package com.commutescout.drive

import android.content.Context
import android.speech.tts.TextToSpeech
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class LatLon(val lat: Double, val lon: Double)

data class Upcoming(val marker: RoadMarker, val alongMeters: Double) {
    val id: String get() = marker.key
}

/**
 * Live alerts while driving. Every 60 seconds the engine reads the markers
 * inside the route's box, projects each onto the route, keeps those within a
 * corridor, orders them by distance along the route, and announces each one
 * once when it is about a minute ahead. The same list feeds the strip.
 *
 * Projection runs once per location update, searching a window around the
 * last segment first, so a 500-mile route costs the same as a short one.
 */
class AlertsEngine(context: Context) {
    private val _ahead = MutableStateFlow<List<Upcoming>>(emptyList())
    val ahead = _ahead.asStateFlow()
    private val _hereAlong = MutableStateFlow(0.0)
    val hereAlong = _hereAlong.asStateFlow()
    var spoken = true
    var announceAheadMeters = 1500.0
    /** Per-kind rules from Settings; null means the one distance above. */
    var rules: ((RoadMarker) -> Prefs.AlertRule)? = null
    private val repeated = HashSet<String>()

    private var route: List<LatLon> = emptyList()
    private var cumulative: DoubleArray = DoubleArray(0)
    private var all: List<Upcoming> = emptyList()
    private val announced = HashSet<String>()
    private var box: DoubleArray? = null
    private var lastSegment = 0
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var refreshJob: Job? = null
    private var ttsReady = false
    private var tts: TextToSpeech? = null

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) tts?.language = Locale.getDefault()
        }
    }

    companion object {
        private const val TAG = "Alerts"
        const val REFRESH_MS = 60_000L

        fun cumulativeDistances(pts: List<LatLon>): DoubleArray {
            val out = DoubleArray(pts.size)
            for (i in 1 until pts.size) out[i] = out[i - 1] + meters(pts[i - 1], pts[i])
            return out
        }

        fun meters(a: LatLon, b: LatLon): Double {
            val k = cos(Math.toRadians((a.lat + b.lat) / 2))
            val dx = (b.lon - a.lon) * 111_320.0 * k
            val dy = (b.lat - a.lat) * 110_540.0
            return sqrt(dx * dx + dy * dy)
        }

        data class Hit(val along: Double, val offset: Double, val segment: Int)

        /** The direction a marker applies to as a bearing, from `dir` or "(northbound)" / "NB" in the label; null when both or unknown. */
        fun headingOf(m: RoadMarker): Double? {
            // The server's dir field: "North", "NB", "N"... and only that word.
            val d = m.dir?.trim()?.lowercase()
            if (!d.isNullOrEmpty()) {
                if (d.startsWith("both") || '/' in d || '&' in d) return null
                when (d[0]) { 'n' -> return 0.0; 'e' -> return 90.0; 's' -> return 180.0; 'w' -> return 270.0 }
            }
            // Otherwise a "(northbound)" or "NB" in the label; two directions say nothing.
            val text = " " + (m.label ?: "").lowercase()
            val table = listOf("northbound" to 0.0, "eastbound" to 90.0, "southbound" to 180.0, "westbound" to 270.0,
                               " nb" to 0.0, " eb" to 90.0, " sb" to 180.0, " wb" to 270.0)
            val found = table.filter { (k, _) -> text.contains(k) }.map { it.second }
            return if (found.size == 1) found[0] else null
        }

        fun bearing(a: LatLon, b: LatLon): Double {
            val k = Math.cos(Math.toRadians((a.lat + b.lat) / 2))
            val deg = Math.toDegrees(Math.atan2((b.lon - a.lon) * k, b.lat - a.lat))
            return if (deg < 0) deg + 360 else deg
        }

        fun angleBetween(a: Double, b: Double): Double {
            val d = Math.abs(a - b) % 360
            return if (d > 180) 360 - d else d
        }

        /**
         * Nearest point on the polyline. With [near], a window around that
         * segment is tried first; the coarse full pass is the fallback.
         */
        fun along(pts: List<LatLon>, cum: DoubleArray, p: LatLon, near: Int? = null): Hit {
            if (pts.size < 2) return Hit(0.0, Double.MAX_VALUE, 0)
            val k = cos(Math.toRadians(p.lat))
            var best = Hit(0.0, Double.MAX_VALUE, 0)
            fun test(j: Int) {
                val a = pts[j]; val b = pts[j + 1]
                val bx = (b.lon - a.lon) * 111_320.0 * k; val by = (b.lat - a.lat) * 110_540.0
                val px = (p.lon - a.lon) * 111_320.0 * k; val py = (p.lat - a.lat) * 110_540.0
                val len2 = bx * bx + by * by
                val t = if (len2 == 0.0) 0.0 else min(1.0, max(0.0, (px * bx + py * by) / len2))
                val dx = px - t * bx; val dy = py - t * by
                val off = sqrt(dx * dx + dy * dy)
                if (off < best.offset) best = Hit(cum[j] + t * sqrt(len2), off, j)
            }
            if (near != null) {
                for (j in max(0, near - 20) until min(pts.size - 1, near + 60)) test(j)
                if (best.offset < 120.0) return best
            }
            best = Hit(0.0, Double.MAX_VALUE, 0)
            var i = 0
            while (i < pts.size) {
                if (meters(pts[i], p) < 3000.0) {
                    for (j in max(0, i - 8) until min(pts.size - 1, i + 8)) test(j)
                }
                i += 8
            }
            return best
        }
    }

    fun start(coordinates: List<LatLon>) {
        Log.i(TAG, "alerts start: ${coordinates.size} route points")
        stop()
        route = coordinates
        cumulative = cumulativeDistances(coordinates)
        lastSegment = 0
        val lats = coordinates.map { it.lat }; val lons = coordinates.map { it.lon }
        if (lats.isEmpty()) return
        box = doubleArrayOf(lats.min() - 0.05, lons.min() - 0.05, lats.max() + 0.05, lons.max() + 0.05)
        announced.clear(); repeated.clear()
        refreshJob = scope.launch {
            while (isActive) {
                refresh()
                delay(REFRESH_MS)
            }
        }
    }

    fun stop() {
        refreshJob?.cancel(); refreshJob = null
        route = emptyList(); cumulative = DoubleArray(0); all = emptyList(); box = null
        _ahead.value = emptyList()
        _hereAlong.value = 0.0
    }

    /**
     * The route ahead of the driver as a sparse line: a vertex every
     * [every] metres for the next [limit] metres, starting just behind
     * where the driver is. Empty when no route is running.
     *
     * The server keeps this stretch warm for the community plugins and
     * serves alerts along it to this phone alone. It never includes the
     * destination: an hour of road ahead is all anyone needs to know.
     */
    fun stretchAhead(limit: Double = 60_000.0, every: Double = 5_000.0): List<LatLon> {
        if (route.size < 2 || cumulative.size != route.size) return emptyList()
        val here = _hereAlong.value
        val out = ArrayList<LatLon>()
        var lastAt = -every
        for (i in lastSegment until route.size) {
            val d = cumulative[i]
            if (d < here - 500) continue
            if (d - here > limit) break
            if (d - lastAt >= every) {
                out.add(route[i])
                lastAt = d
            }
        }
        return out
    }

    fun update(position: LatLon) {
        if (route.isEmpty()) return
        val hit = along(route, cumulative, position, lastSegment)
        lastSegment = hit.segment
        _hereAlong.value = hit.along
        val upcoming = all.filter { it.alongMeters > hit.along - 100 && (rules?.invoke(it.marker)?.enabled ?: true) }
        if (upcoming != _ahead.value) _ahead.value = upcoming
        for (item in upcoming) {
            val rule = rules?.invoke(item.marker) ?: Prefs.AlertRule(true, spoken, announceAheadMeters, 0.0)
            val gap = item.alongMeters - hit.along
            if (item.id !in announced && gap <= rule.firstMeters && gap > -100) {
                announced.add(item.id)
                if (rule.speak) say(item.marker, gap)
            } else if (item.id in announced && item.id !in repeated && rule.repeatMeters > 0 && gap <= rule.repeatMeters && gap > -100) {
                repeated.add(item.id)
                if (rule.speak) say(item.marker, gap)
            }
        }
    }

    // Identical text is not repeated within 90 s: several markers can share
    // one label (the same ramp closure recorded per lane).
    private val spokenAt = HashMap<String, Long>()

    fun say(marker: RoadMarker, gap: Double = 0.0) {
        if (!ttsReady) return
        val now = System.currentTimeMillis()
        if (gap > 0 && (spokenAt[marker.spokenTitle] ?: 0L) > now - 90_000) return
        spokenAt[marker.spokenTitle] = now
        val text = marker.spokenTitle + if (gap > 200) ", in " + Units.spoken(gap) else ""
        tts?.speak(text, TextToSpeech.QUEUE_ADD, null, marker.key)
    }

    private suspend fun refresh() {
        val b = box ?: return
        val markers = runCatching { LiveData.markers(b[0], b[1], b[2], b[3]) }
            .onFailure { Log.w(TAG, "alerts fetch failed: $it") }.getOrNull() ?: return
        val pts = route; val cum = cumulative
        all = withContext(Dispatchers.Default) {
            markers.mapNotNull { m ->
                if (m.tooMinorToAnnounce) return@mapNotNull null
                val hit = along(pts, cum, LatLon(m.lat, m.lon))
                if (hit.offset > m.corridorMeters) return@mapNotNull null
                // A closure for the other direction of a divided road is not ahead of this driver.
                val h = headingOf(m)
                if (h != null && hit.segment + 1 < pts.size &&
                    angleBetween(h, bearing(pts[hit.segment], pts[hit.segment + 1])) > 110) return@mapNotNull null
                Upcoming(m, hit.along)
            }.sortedBy { it.alongMeters }
        }
        Log.i(TAG, "alerts: ${markers.size} markers in box, ${all.size} on the route")
    }

    fun shutdown() {
        stop()
        tts?.shutdown()
    }
}
