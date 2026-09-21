package com.commutescout.drive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Announcement
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Place
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The road markers the website draws, for the area on screen.
 *
 * Two sources feed it. [Snapshot] holds the nationwide dots fetched at
 * launch, which is what the map paints the instant it knows where it is
 * looking. /api/mapdata is then asked for the viewport, as before, and
 * its answer takes over: it is the only source of the closure stretch
 * and toll corridor lines, which the snapshot drops. Both keep running;
 * neither replaces the other.
 */
class MarkerStore {
    private val _live = MutableStateFlow<List<RoadMarker>>(emptyList())
    private val _view = MutableStateFlow<DoubleArray?>(null)
    private val _loading = MutableStateFlow(false)
    val loading = _loading.asStateFlow()
    private var byKey: Map<String, RoadMarker> = emptyMap()
    private var box: DoubleArray? = null     // s, w, n, e with margin
    private var kinds = ""
    private var fetchedAt = 0L
    private var job: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    // After a failed fetch, a 429 or a 5xx the timed refresh waits: two
    // minutes, then double each time up to ten; a success resets it.
    private var backoffMs = 0L
    private var holdUntil = 0L

    /** Everything to draw: the viewport answer, topped up from the snapshot. */
    val markers: StateFlow<List<RoadMarker>> =
        combine(_live, Snapshot.markers, _view) { live, snap, view -> merge(live, snap, view) }
            .stateIn(scope, SharingStarted.Eagerly, emptyList())

    init {
        scope.launch { while (isActive) { delay(60_000); if (System.currentTimeMillis() >= holdUntil) refresh(force = true) } }
        scope.launch { markers.collect { byKey = it.associateBy { m -> m.key } } }
    }

    fun marker(key: String): RoadMarker? = byKey[key]

    /**
     * Merge the two sources.
     *
     * Where the viewport has answered it wins outright, carrying the
     * geometry the snapshot lacks. The snapshot then adds the kinds the
     * viewport call never asks for, and stands in for all of them
     * before the first answer lands or after one fails.
     */
    private fun merge(live: List<RoadMarker>, snap: List<RoadMarker>, view: DoubleArray?): List<RoadMarker> {
        val near = if (view == null) snap else snap.filter {
            it.lat >= view[0] && it.lon >= view[1] && it.lat <= view[2] && it.lon <= view[3]
        }
        if (live.isEmpty()) return near
        val seen = live.mapTo(HashSet()) { it.key }
        return live + near.filter { it.key !in seen && it.kind in Prefs.snapshotOnlyKinds }
    }

    /** The visible area changed: fetch when it left the last box or the layers changed. */
    fun view(south: Double, west: Double, north: Double, east: Double, zoom: Double, kinds: String) {
        val latPad = (north - south) * 0.5; val lonPad = (east - west) * 0.5
        // The drawing window is wider than the screen so a short pan has
        // something to show before the next fetch settles.
        _view.value = doubleArrayOf(south - latPad, west - lonPad, north + latPad, east + lonPad)
        if (zoom < 5.5 || kinds.isEmpty()) {
            if (kinds.isEmpty()) { _live.value = emptyList() }
            return
        }
        val b = box
        val inside = b != null && south >= b[0] && west >= b[1] && north <= b[2] && east <= b[3]
        if (inside && kinds == this.kinds && System.currentTimeMillis() - fetchedAt < 60_000) return
        box = doubleArrayOf(south - latPad, west - lonPad, north + latPad, east + lonPad)
        this.kinds = kinds
        refresh(force = false)
    }

    fun refresh(force: Boolean) {
        val b = box ?: return
        if (kinds.isEmpty()) return
        job?.cancel()
        val k = kinds
        job = scope.launch {
            if (!force) delay(350)   // let the pan settle
            _loading.value = true
            try {
                val found = runCatching { LiveData.markers(b[0], b[1], b[2], b[3], k) }.getOrElse { e ->
                    if (e is CancellationException) throw e
                    val code = (e as? BackendError)?.code ?: 0
                    if (e is BackendError && code != 429 && code < 500) return@launch   // not a server problem
                    backoffMs = minOf(600_000L, if (backoffMs == 0L) 120_000L else backoffMs * 2)
                    holdUntil = System.currentTimeMillis() + backoffMs
                    Log.i("Markers", "fetch failed (${e.message}), next timed refresh in ${backoffMs / 1000} s")
                    return@launch
                }
                _live.value = found
                fetchedAt = System.currentTimeMillis()
                backoffMs = 0L; holdUntil = 0L
            } finally {
                _loading.value = false
            }
        }
    }
}

/** One color and glyph per marker kind, the website's palette. */
object MarkerIcons {
    /** Draw order: the quiet roadside kinds sit under the urgent ones. */
    val kinds = listOf("camera", "sign", "rwis", "toll", "wildfire", "chain_control", "lane_closure", "incident", "plugin")

    fun color(kind: String): Color = when (kind) {
        "incident" -> Color(0xFFF29E1A)
        "lane_closure" -> Color(0xFFD63030)
        "chain_control" -> Color(0xFF2973D9)
        "wildfire" -> Color(0xFFE6591A)
        "plugin" -> Color(0xFF734DCC)
        "camera" -> Color(0xFF2F81F7)
        "sign" -> Color(0xFFA16207)
        "rwis" -> Color(0xFF2F9E6E)
        "toll" -> Color(0xFF7C3AED)
        else -> Color.Gray
    }

    fun icon(kind: String): ImageVector = when (kind) {
        "incident" -> Icons.Default.Warning
        "lane_closure" -> Icons.Default.Block
        "chain_control" -> Icons.Default.AcUnit
        "wildfire" -> Icons.Default.LocalFireDepartment
        "plugin" -> Icons.Default.Groups
        "camera" -> Icons.Default.Videocam
        "sign" -> Icons.Default.Announcement
        "rwis" -> Icons.Default.Thermostat
        "toll" -> Icons.Default.Paid
        else -> Icons.Default.Place
    }

    /** The word over a marker card, as the website labels its popups. */
    fun label(kind: String): String = when (kind) {
        "incident" -> "INCIDENT"
        "lane_closure" -> "LANE CLOSURE"
        "chain_control" -> "CHAIN CONTROL"
        "wildfire" -> "WILDFIRE"
        "plugin" -> "COMMUNITY REPORT"
        "camera" -> "LIVE CAMERA"
        "sign" -> "MESSAGE SIGN"
        "rwis" -> "ROAD WEATHER"
        "toll" -> "TOLL PRICE"
        else -> kind.replace('_', ' ').uppercase()
    }
}
