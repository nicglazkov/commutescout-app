package com.commutescout.drive

import android.content.Context
import android.speech.tts.TextToSpeech
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.abs
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
 * once when it is about a minute ahead. The same list feeds the strip above
 * the trip bar.
 */
class AlertsEngine(context: Context) {
    private val _ahead = MutableStateFlow<List<Upcoming>>(emptyList())
    val ahead = _ahead.asStateFlow()
    var spoken = true

    private var route: List<LatLon> = emptyList()
    private var cumulative: DoubleArray = DoubleArray(0)
    private var all: List<Upcoming> = emptyList()
    private val announced = HashSet<String>()
    private var box: DoubleArray? = null
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
        const val ANNOUNCE_AHEAD_METERS = 1500.0
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

        /** Nearest point on the polyline: distance along it and offset from it. */
        fun along(pts: List<LatLon>, cum: DoubleArray, p: LatLon): Pair<Double, Double> {
            if (pts.size < 2) return 0.0 to Double.MAX_VALUE
            var bestAlong = 0.0
            var bestOff = Double.MAX_VALUE
            val k = cos(Math.toRadians(p.lat))
            for (i in 0 until pts.size - 1) {
                val a = pts[i]; val b = pts[i + 1]
                if (abs(a.lat - p.lat) > 0.05 && abs(b.lat - p.lat) > 0.05) continue
                if (abs(a.lon - p.lon) > 0.06 && abs(b.lon - p.lon) > 0.06) continue
                val ax = 0.0; val ay = 0.0
                val bx = (b.lon - a.lon) * 111_320.0 * k; val by = (b.lat - a.lat) * 110_540.0
                val px = (p.lon - a.lon) * 111_320.0 * k; val py = (p.lat - a.lat) * 110_540.0
                val len2 = bx * bx + by * by
                val t = if (len2 == 0.0) 0.0 else min(1.0, max(0.0, ((px - ax) * bx + (py - ay) * by) / len2))
                val dx = px - t * bx; val dy = py - t * by
                val off = sqrt(dx * dx + dy * dy)
                if (off < bestOff) {
                    bestOff = off
                    bestAlong = cum[i] + t * sqrt(len2)
                }
            }
            return bestAlong to bestOff
        }
    }

    fun start(coordinates: List<LatLon>) {
        stop()
        route = coordinates
        cumulative = cumulativeDistances(coordinates)
        val lats = coordinates.map { it.lat }; val lons = coordinates.map { it.lon }
        if (lats.isEmpty()) return
        box = doubleArrayOf(lats.min() - 0.05, lons.min() - 0.05, lats.max() + 0.05, lons.max() + 0.05)
        announced.clear()
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
    }

    fun update(position: LatLon) {
        if (route.isEmpty()) return
        val here = along(route, cumulative, position).first
        val upcoming = all.filter { it.alongMeters > here - 100 }
        _ahead.value = upcoming
        for (item in upcoming) {
            if (item.id in announced) continue
            val gap = item.alongMeters - here
            if (gap <= ANNOUNCE_AHEAD_METERS && gap > -100) {
                announced.add(item.id)
                if (spoken) say(item.marker)
            }
        }
    }

    fun say(marker: RoadMarker) {
        if (!ttsReady) return
        tts?.speak(marker.spokenTitle, TextToSpeech.QUEUE_ADD, null, marker.key)
    }

    private suspend fun refresh() {
        val b = box ?: return
        val markers = runCatching { LiveData.markers(b[0], b[1], b[2], b[3]) }.getOrNull() ?: return
        val pts = route; val cum = cumulative
        all = markers.mapNotNull { m ->
            val (along, off) = along(pts, cum, LatLon(m.lat, m.lon))
            if (off <= m.corridorMeters) Upcoming(m, along) else null
        }.sortedBy { it.alongMeters }
    }

    fun shutdown() {
        stop()
        tts?.shutdown()
    }
}
