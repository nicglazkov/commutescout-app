package com.commutescout.drive

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
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
class AlertsEngine(context: Context, prefs: Prefs) {
    private val _ahead = MutableStateFlow<List<Upcoming>>(emptyList())
    val ahead = _ahead.asStateFlow()
    /** Alerts the driver swiped away; off the banner until the next trip or free drive. */
    private val _dismissed = MutableStateFlow<Set<String>>(emptySet())
    val dismissed = _dismissed.asStateFlow()
    fun dismiss(id: String) { _dismissed.value = _dismissed.value + id }
    private val _hereAlong = MutableStateFlow(0.0)
    val hereAlong = _hereAlong.asStateFlow()
    /**
     * An event on the route ahead that the server dropped before the
     * driver reached it: the alert says it cleared. Passing an event
     * never sets this; it is only ever about road still ahead.
     */
    private val _cleared = MutableStateFlow<Upcoming?>(null)
    val cleared = _cleared.asStateFlow()
    fun clearedSeen() { _cleared.value = null }

    /** Debug builds: events put on the route by hand, kept through refreshes. */
    private var forced: List<Upcoming> = emptyList()

    /**
     * Debug builds: puts the marker [make] builds [gap] metres ahead on
     * the route, as a refresh would find it, for screenshots.
     */
    fun forceOnRoute(gap: Double, make: (LatLon) -> RoadMarker): Upcoming? {
        if (route.size < 2 || cumulative.size != route.size) return null
        val at = _hereAlong.value + gap
        var i = cumulative.indexOfFirst { it >= at }.takeIf { it > 0 } ?: (route.size - 1)
        val a = route[i - 1]; val b = route[i]
        val seg = (cumulative[i] - cumulative[i - 1]).coerceAtLeast(1e-6)
        val t = ((at - cumulative[i - 1]) / seg).coerceIn(0.0, 1.0)
        val m = make(LatLon(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t))
        val up = Upcoming(m, min(at, cumulative.last()))
        forced = forced + up
        all = forced.sortedBy { it.alongMeters }
        _ahead.value = all.filter { it.alongMeters > _hereAlong.value - 100 }
        return up
    }

    /** Debug builds: the forced event [u] goes away before it is reached, as a clear would. */
    fun forceClear(u: Upcoming) {
        forced = forced - u
        all = all - u
        _ahead.value = _ahead.value - u
        _cleared.value = u
        Log.i(TAG, "debug: forced clear of ${u.id}")
    }
    var spoken = true
    /** The driver's mute: no alert speaks on its own, whatever the per-kind
     *  rules say. A tap to repeat one still does. */
    @Volatile var muted = false
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

    // A spoken alert is guidance: music turns down for the sentence and
    // comes back, a podcast pauses and resumes. Focus is taken before
    // each utterance and let go when the voice is done.
    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build())
        .setOnAudioFocusChangeListener { }
        .build()
    private var speaking = 0

    /** The driver's voice, as for turn instructions. Settings lists its voices and plays its previews. */
    val speaker = Speaker(context, prefs, onDone = { letGo() }, onError = { letGo() }).also { it.start() }

    private fun letGo() {
        synchronized(this) {
            speaking = max(0, speaking - 1)
            if (speaking == 0) audio.abandonAudioFocusRequest(focus)
        }
    }

    companion object {
        private const val TAG = "Alerts"
        const val REFRESH_MS = 60_000L

        /** Kinds an agency clears; a camera or a sign going missing is a feed hiccup, not news. */
        val CLEARABLE = setOf("incident", "lane_closure", "chain_control", "plugin")

        /**
         * Events that were on the route [minGap] to [maxGap] ahead of
         * [along] in [old] and are missing from [new]: they cleared before
         * the driver got there. Anything already passed, or about to be,
         * says nothing.
         */
        fun clearedAhead(old: List<Upcoming>, new: List<Upcoming>, along: Double, minGap: Double = 150.0, maxGap: Double = 8047.0): List<Upcoming> {
            if (old.isEmpty()) return emptyList()
            val still = new.mapTo(HashSet()) { it.id }
            return old.filter { it.marker.kind in CLEARABLE && it.id !in still && it.alongMeters - along in minGap..maxGap }
        }

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

        /** What is said for an alert [gap] metres ahead. */
        fun sentence(title: String, gap: Double, spoken: (Double) -> String = Units::spoken): String =
            title + if (gap > 200) ", in " + spoken(gap) else ""

        /**
         * The sentences an alert will most likely be spoken with, so a
         * neural voice can render them ahead: at its first distance and,
         * when set, its second. A fix comes about once a second, so the
         * gap lands up to 40 m inside each distance; both ends are kept
         * where the spoken distance changes between them.
         */
        fun likelySentences(title: String, rule: Prefs.AlertRule, spoken: (Double) -> String = Units::spoken): List<Pair<String, Double>> {
            val out = LinkedHashMap<String, Double>()
            for (d in listOf(rule.firstMeters, rule.repeatMeters)) {
                if (d <= 0) continue
                for (g in listOf(d, d - 40)) if (g > 0) out.putIfAbsent(sentence(title, g, spoken), d)
            }
            return out.map { it.key to it.value }
        }

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
        announced.clear(); repeated.clear(); spokenAt.clear(); prerendered.clear()
        freeDrive = true
        refreshJob = scope.launch {
            while (isActive) {
                delay(REFRESH_MS)
                if (Engine.awake()) refreshAround()
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
        announced.clear(); repeated.clear(); prerendered.clear()
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
        _cleared.value = null
        forced = emptyList()
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

    /** Alerts whose sentences were handed to the neural voice already, this trip or free drive. */
    private val prerendered = HashSet<String>()

    /**
     * A neural voice renders each alert's sentence when the alert first
     * becomes known, well before its announce distance. With a system
     * voice this does nothing.
     */
    private fun prerender(upcoming: List<Upcoming>, along: Double) {
        if (muted) return
        val fresh = upcoming.filter { it.id !in prerendered }
        if (fresh.isEmpty()) return
        val sentences = ArrayList<Pair<String, Double>>()
        for (item in fresh) {
            prerendered.add(item.id)
            val rule = rules?.invoke(item.marker) ?: Prefs.AlertRule(true, spoken, announceAheadMeters, 0.0)
            if (!rule.speak) continue
            // Already inside its first distance: it speaks now, too soon to render.
            if (item.alongMeters - along <= rule.firstMeters) continue
            for ((text, at) in likelySentences(item.marker.spokenTitle, rule)) sentences.add(text to item.alongMeters - at)
        }
        if (sentences.isNotEmpty()) Neural.prerenderAlerts(sentences, Engine.prefs)
    }

    /** Each marker once when it comes within its first distance, and once more within its second, by the per-kind rules. */
    private fun announce(upcoming: List<Upcoming>, along: Double) {
        runCatching { prerender(upcoming, along) }.onFailure { Log.w(TAG, "prerender: $it") }
        for (item in upcoming) {
            val rule = rules?.invoke(item.marker) ?: Prefs.AlertRule(true, spoken, announceAheadMeters, 0.0)
            val gap = item.alongMeters - along
            if (item.id !in announced && gap <= rule.firstMeters && gap > -100) {
                announced.add(item.id)
                if (rule.speak && !muted) say(item.marker, gap)
            } else if (item.id in announced && item.id !in repeated && rule.repeatMeters > 0 && gap <= rule.repeatMeters && gap > -100) {
                repeated.add(item.id)
                if (rule.speak && !muted) say(item.marker, gap)
            }
        }
    }

    // Identical text is not repeated within 90 s: several markers can share
    // one label (the same ramp closure recorded per lane).
    private val spokenAt = HashMap<String, Long>()

    fun say(marker: RoadMarker, gap: Double = 0.0) {
        if (!speaker.ready.value) return
        val now = System.currentTimeMillis()
        if (gap > 0 && (spokenAt[marker.spokenTitle] ?: 0L) > now - 90_000) return
        spokenAt[marker.spokenTitle] = now
        speakWithFocus(sentence(marker.spokenTitle, gap), marker.key, flush = false)
    }

    /** A sample from Settings, in place of anything still queued. It speaks even when muted: the driver asked. */
    fun preview(text: String) = speakWithFocus(text, "preview", flush = true)

    private fun speakWithFocus(text: String, id: String, flush: Boolean) {
        synchronized(this) {
            if (speaking == 0) audio.requestAudioFocus(focus)
            speaking += 1
        }
        if (!speaker.speak(text, id, flush)) letGo()
    }

    /** Fetch again now: the signal came back. */
    fun refreshNow() {
        if (box != null) scope.launch { refresh() }
    }

    private suspend fun refresh() {
        val b = box ?: return
        var asOf = System.currentTimeMillis()
        val fetched = runCatching { LiveData.markers(b[0], b[1], b[2], b[3]) }
            .onFailure { Log.w(TAG, "alerts fetch failed: $it") }.getOrNull()
        val markers = fetched ?: run {
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
        val before = all
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
        if (forced.isNotEmpty()) all = forced.sortedBy { it.alongMeters }
        allAsOf = asOf
        // Only a real answer from the server can say an event is gone, and
        // only on a trip: free drive has no route to be ahead on.
        if (fetched != null && !freeDrive && route.isNotEmpty()) {
            clearedAhead(before, all, _hereAlong.value).firstOrNull { wanted(it.marker) && it.id !in _dismissed.value }?.let {
                Log.i(TAG, "cleared ahead: ${it.id}")
                _cleared.value = it
            }
        }
        Log.i(TAG, "alerts: ${markers.size} markers in box, ${all.size} on the route")
    }

    fun shutdown() {
        stop()
        speaker.shutdown()
    }
}
