package com.commutescout.drive

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
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
 *
 * With no destination there is no route to project onto, so the road
 * ahead is taken to be the direction of travel: a marker counts when it
 * lies ahead inside a narrow cone, and its distance along is its
 * distance straight ahead. The same rules and the same voice apply, so
 * a camera or a crash is called out on the way to the store too.
 */
class AlertsEngine(context: Context) {
    private val _ahead = MutableStateFlow<List<Upcoming>>(emptyList())
    val ahead = _ahead.asStateFlow()
    /** Alerts the driver swiped away; off the banner until the next trip or free drive. */
    private val _dismissed = MutableStateFlow<Set<String>>(emptySet())
    val dismissed = _dismissed.asStateFlow()
    fun dismiss(id: String) { _dismissed.value = _dismissed.value + id }
    private val _hereAlong = MutableStateFlow(0.0)
    val hereAlong = _hereAlong.asStateFlow()
    var spoken = true
    var announceAheadMeters = 1500.0
    /** Per-kind rules from Settings; null means the one distance above. */
    var rules: ((RoadMarker) -> Prefs.AlertRule)? = null
    /**
     * Whether the map shows a marker at all: a layer switched off or a
     * plugin uninstalled is not spoken about and not on the banner.
     */
    var shown: ((RoadMarker) -> Boolean)? = null
    private fun wanted(m: RoadMarker) = (shown?.invoke(m) ?: true) && (rules?.invoke(m)?.enabled ?: true) && !m.tooMinorToAnnounce
    /**
     * What the map is showing and when it was current. Used when the
     * route's own fetch cannot reach the server, so a trip started
     * without a signal still announces what the phone already knows.
     */
    var fallback: (() -> Pair<List<RoadMarker>, Long?>)? = null
    /** When the list in [all] was current. */
    private var allAsOf: Long? = null
    private val repeated = HashSet<String>()

    private var route: List<LatLon> = emptyList()
    private var cumulative: DoubleArray = DoubleArray(0)
    private var all: List<Upcoming> = emptyList()
    private val announced = HashSet<String>()
    private var box: DoubleArray? = null
    /** Free drive: no route, the markers around the car instead. */
    private var freeDrive = false
    private var around: List<RoadMarker> = emptyList()
    private var aroundCenter: LatLon? = null
    private var lastCourse: Pair<Double, Long>? = null
    private var lastSegment = 0
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var refreshJob: Job? = null
    private var ttsReady = false
    private var tts: TextToSpeech? = null

    // A spoken alert is guidance: music turns down for the sentence and
    // comes back, a podcast pauses and resumes. Focus is taken before
    // each utterance and let go when the voice is done.
    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val voiceAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        .setAudioAttributes(voiceAttributes)
        .setOnAudioFocusChangeListener { }
        .build()
    private var speaking = 0

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.getDefault()
                tts?.setAudioAttributes(voiceAttributes)
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) = letGo()
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) = letGo()
                    override fun onError(utteranceId: String?, errorCode: Int) = letGo()
                })
            }
        }
    }

    private fun letGo() {
        synchronized(this) {
            speaking = max(0, speaking - 1)
            if (speaking == 0) audio.abandonAudioFocusRequest(focus)
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

    /** Alerts with no destination. Runs from launch and again after every trip; a trip's [start] takes over. */
    fun startFreeDrive() {
        stop()
        _dismissed.value = emptySet()
        // A fresh start: what was said on the last drive is said again
        // on this one, and the sets do not grow for the life of the process.
        announced.clear(); repeated.clear(); spokenAt.clear()
        freeDrive = true
        refreshJob = scope.launch {
            while (isActive) {
                delay(REFRESH_MS)
                refreshAround()
            }
        }
    }

    /** A fix with no trip running: the cone ahead of the car. */
    fun update(position: LatLon, course: Double?, speed: Double) {
        if (!freeDrive) return
        val c = aroundCenter
        if (c == null || meters(c, position) > 4000) {
            box = doubleArrayOf(position.lat - 0.12, position.lon - 0.15, position.lat + 0.12, position.lon + 0.15)
            aroundCenter = position
            scope.launch { refreshAround() }
        }
        // At a light the course goes away; the last one holds for a while.
        val now = System.currentTimeMillis()
        if (course != null && speed >= 1) lastCourse = course to now
        val heading = lastCourse?.takeIf { now - it.second < 120_000 } ?: run {
            if (_ahead.value.isNotEmpty()) _ahead.value = emptyList()
            return
        }
        // Once a thing is well behind the car it may be announced again
        // when it comes up ahead on the way back.
        if (announced.isNotEmpty()) {
            val behind = around.filter { it.key in announced && meters(position, LatLon(it.lat, it.lon)) > 5000 }
            for (m in behind) { announced.remove(m.key); repeated.remove(m.key) }
        }
        val upcoming = around.mapNotNull { m ->
            if (!wanted(m)) return@mapNotNull null
            val d = meters(position, LatLon(m.lat, m.lon))
            if (d > 6000 || d <= 20) return@mapNotNull null
            val off = angleBetween(heading.first, bearing(position, LatLon(m.lat, m.lon)))
            // Straight ahead, or close and roughly ahead: a road bends.
            if (!(off <= 22 || (d < 400 && off <= 55))) return@mapNotNull null
            val along = d * Math.cos(Math.toRadians(off))
            val offset = d * Math.sin(Math.toRadians(off))
            if (offset > maxOf(m.corridorMeters, 120.0)) return@mapNotNull null
            // A closure for the other direction of a divided road is not ahead of this driver.
            val h = headingOf(m)
            if (h != null && angleBetween(h, heading.first) > 110) return@mapNotNull null
            Upcoming(m, along)
        }.sortedBy { it.alongMeters }
        _hereAlong.value = 0.0
        if (upcoming != _ahead.value) _ahead.value = upcoming
        announce(upcoming, 0.0)
    }

    /** What is around the car, for the cone. Without a signal the map's own markers stand in, as on a trip. */
    private suspend fun refreshAround() {
        if (!freeDrive) return
        val b = box ?: return
        around = runCatching { LiveData.markers(b[0], b[1], b[2], b[3]) }.getOrNull() ?: run {
            val saved = fallback?.invoke() ?: return
            ShelfLife.prune(saved.first, saved.second).filter { it.lat >= b[0] && it.lat <= b[2] && it.lon >= b[1] && it.lon <= b[3] }
        }
    }

    fun start(coordinates: List<LatLon>) {
        Log.i(TAG, "alerts start: ${coordinates.size} route points")
        stop()
        route = coordinates
        cumulative = cumulativeDistances(coordinates)
        lastSegment = 0
        _dismissed.value = emptySet()
        val lats = coordinates.map { it.lat }; val lons = coordinates.map { it.lon }
        if (lats.isEmpty()) return
        box = doubleArrayOf(lats.min() - 0.05, lons.min() - 0.05, lats.max() + 0.05, lons.max() + 0.05)
        announced.clear(); repeated.clear()
        allAsOf = null
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
        freeDrive = false; around = emptyList(); aroundCenter = null
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
        val upcoming = all.filter { it.alongMeters > hit.along - 100 && wanted(it.marker) }
        if (upcoming != _ahead.value) _ahead.value = upcoming
        announce(upcoming, hit.along)
    }

    /** Each marker once when it comes within its first distance, and once more within its second, by the per-kind rules. */
    private fun announce(upcoming: List<Upcoming>, along: Double) {
        for (item in upcoming) {
            val rule = rules?.invoke(item.marker) ?: Prefs.AlertRule(true, spoken, announceAheadMeters, 0.0)
            val gap = item.alongMeters - along
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
        synchronized(this) {
            if (speaking == 0) audio.requestAudioFocus(focus)
            speaking += 1
        }
        if (tts?.speak(text, TextToSpeech.QUEUE_ADD, null, marker.key) != TextToSpeech.SUCCESS) letGo()
    }

    /** Fetch again now: the signal came back. */
    fun refreshNow() {
        if (box != null) scope.launch { refresh() }
    }

    private suspend fun refresh() {
        val b = box ?: return
        var asOf = System.currentTimeMillis()
        val markers = runCatching { LiveData.markers(b[0], b[1], b[2], b[3]) }
            .onFailure { Log.w(TAG, "alerts fetch failed: $it") }.getOrNull() ?: run {
                // No answer. A list fetched earlier on this trip covers the
                // whole route, so it is kept, less whatever has gone stale
                // for its kind since. With none, because the trip began
                // without a signal, the map's own markers stand in.
                val was = allAsOf
                if (was != null && all.isNotEmpty()) {
                    val age = System.currentTimeMillis() - was
                    if (age > 15 * 60_000L) {
                        val kept = all.filter { ShelfLife.keep(it.marker.kind, age) }
                        if (kept.size != all.size) { Log.i(TAG, "offline: ${all.size - kept.size} gone stale on the route"); all = kept }
                    }
                    return
                }
                val saved = fallback?.invoke() ?: return
                if (saved.first.isEmpty()) return
                asOf = saved.second ?: System.currentTimeMillis()
                Log.i(TAG, "no answer from the server, using ${saved.first.size} markers the map already had")
                ShelfLife.prune(saved.first, saved.second)
            }
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
        allAsOf = asOf
        Log.i(TAG, "alerts: ${markers.size} markers in box, ${all.size} on the route")
    }

    fun shutdown() {
        stop()
        tts?.shutdown()
    }
}
