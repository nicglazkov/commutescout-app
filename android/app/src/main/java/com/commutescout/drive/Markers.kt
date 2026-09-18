package com.commutescout.drive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.AcUnit
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
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The road markers the website draws, for the area on screen. Loaded when
 * the view settles, kept fresh every minute, filtered by the Layers sheet.
 * Nothing is fetched while zoomed out past a state.
 */
class MarkerStore {
    private val _markers = MutableStateFlow<List<RoadMarker>>(emptyList())
    val markers = _markers.asStateFlow()
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

    init {
        scope.launch { while (isActive) { delay(60_000); if (System.currentTimeMillis() >= holdUntil) refresh(force = true) } }
    }

    fun marker(key: String): RoadMarker? = byKey[key]

    /** The visible area changed: fetch when it left the last box or the layers changed. */
    fun view(south: Double, west: Double, north: Double, east: Double, zoom: Double, kinds: String) {
        if (zoom < 5.5 || kinds.isEmpty()) {
            if (kinds.isEmpty()) { _markers.value = emptyList(); byKey = emptyMap() }
            return
        }
        val latPad = (north - south) * 0.5; val lonPad = (east - west) * 0.5
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
                _markers.value = found
                byKey = found.associateBy { it.key }
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
    val kinds = listOf("incident", "lane_closure", "chain_control", "wildfire", "plugin")

    fun color(kind: String): Color = when (kind) {
        "incident" -> Color(0xFFF29E1A)
        "lane_closure" -> Color(0xFFD63030)
        "chain_control" -> Color(0xFF2973D9)
        "wildfire" -> Color(0xFFE6591A)
        "plugin" -> Color(0xFF734DCC)
        else -> Color.Gray
    }

    fun icon(kind: String): ImageVector = when (kind) {
        "incident" -> Icons.Default.Warning
        "lane_closure" -> Icons.Default.Block
        "chain_control" -> Icons.Default.AcUnit
        "wildfire" -> Icons.Default.LocalFireDepartment
        "plugin" -> Icons.Default.Groups
        else -> Icons.Default.Place
    }
}
