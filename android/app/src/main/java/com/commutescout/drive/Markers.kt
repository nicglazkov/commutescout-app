package com.commutescout.drive

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CarCrash
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.DoNotDisturbOn
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Traffic
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
    /** When the viewport answer was fetched, and a minute tick so expiry is re-checked without a signal. */
    private val _liveAt = MutableStateFlow<Long?>(null)
    private val _tick = MutableStateFlow(0L)

    /** How new the markers on screen are: shown in the offline banner. */
    val asOf: StateFlow<Long?> = combine(_liveAt, Snapshot.asOf) { a, b -> listOfNotNull(a, b).maxOrNull() }
        .stateIn(scope, SharingStarted.Eagerly, null)

    /**
     * Everything to draw: the viewport answer, topped up from the
     * snapshot. Without a signal nothing gets newer, so each source is
     * cut by age for its kind: a police report goes after half an hour,
     * a roadwork closure lasts the day. Online, both are minutes old and
     * nothing is cut.
     */
    val markers: StateFlow<List<RoadMarker>> =
        combine(_live, Snapshot.markers, _view, _tick, Snapshot.asOf) { live, snap, view, _, snapAt ->
            merge(ShelfLife.prune(live, _liveAt.value), ShelfLife.prune(snap, snapAt), view)
        }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    init {
        scope.launch {
            while (isActive) {
                delay(60_000)
                _tick.value += 1
                if (Connectivity.online.value && System.currentTimeMillis() >= holdUntil) refresh(force = true)
            }
        }
        scope.launch { markers.collect { byKey = it.associateBy { m -> m.key } } }
        // The signal is back: catch up at once rather than at the next tick.
        Connectivity.onReconnect { backoffMs = 0L; holdUntil = 0L; refresh(force = true) }
    }

    fun marker(key: String): RoadMarker? = byKey[key]

    /**
     * Everything held, not cut to the view: the last viewport answer and
     * the whole snapshot area, each less what has gone stale. What the
     * spoken alerts fall back on when their own fetch gets no answer; the
     * route runs well past the edge of the screen.
     */
    fun held(): List<RoadMarker> {
        val live = ShelfLife.prune(_live.value, _liveAt.value)
        val seen = live.mapTo(HashSet()) { it.key }
        return live + ShelfLife.prune(Snapshot.markers.value, Snapshot.asOf.value).filter { it.key !in seen }
    }

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
        // Zoomed out past a state the viewport call would be the whole
        // snapshot again, so only the snapshot runs; nothing is dropped.
        if (zoom < 5.5 || kinds.isEmpty()) return
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
                _liveAt.value = fetchedAt
                backoffMs = 0L; holdUntil = 0L
            } finally {
                _loading.value = false
            }
        }
    }
}

/**
 * How a plugin's alerts look, everywhere they show.
 *
 * Official agency data is a dot. A plugin alert is a rounded square
 * badge instead: the picture says what the alert is, the color says
 * which plugin it came from. The website and the iPhone app draw the
 * same thing, with the same colors and categories.
 */
object PluginStyle {
    // The plugins CommuteScout runs get fixed colors; any other plugin
    // gets one from its id, so it is the same on every launch.
    private val known = mapOf("wz-flare" to Color(0xFF1D4ED8), "osm-cameras" to Color(0xFFEA580C))
    private val palette = listOf(Color(0xFF7C3AED), Color(0xFF0F766E), Color(0xFFBE123C),
        Color(0xFF4D7C0F), Color(0xFFA16207), Color(0xFF0369A1))

    fun color(sourceId: String): Color {
        known[sourceId]?.let { return it }
        var h = 0L
        for (c in sourceId) h = (h * 31 + c.code) and 0xFFFFFFFFL
        return palette[(h % palette.size).toInt()]
    }

    /** The plugin a marker came from: the part of its id before the colon. */
    fun sourceId(m: RoadMarker): String = m.id?.substringBefore(':', "")?.takeIf { it.isNotEmpty() } ?: m.source ?: "plugin"

    fun category(flareKind: String?): String {
        val k = (flareKind ?: "").uppercase()
        return when {
            k.startsWith("POLICE") -> "police"
            k.startsWith("CRASH") -> "crash"
            k.startsWith("CAMERA") -> "camera"
            k.startsWith("JAM") -> "jam"
            k.startsWith("WEATHER") -> "weather"
            k.startsWith("ROAD_CLOSED") || k.startsWith("LANE_CLOSED") || k.startsWith("RAMP_CLOSED") -> "closed"
            k.startsWith("CHAINS") -> "chains"
            k.startsWith("HAZARD") -> "hazard"
            else -> "other"
        }
    }

    fun icon(category: String): ImageVector = when (category) {
        "police" -> Icons.Default.Shield
        "crash" -> Icons.Default.CarCrash
        "camera" -> Icons.Default.CameraAlt
        "jam" -> Icons.Default.Traffic
        "weather" -> Icons.Default.Cloud
        "closed" -> Icons.Default.DoNotDisturbOn
        "chains" -> Icons.Default.Link
        "hazard" -> Icons.Default.Warning
        else -> Icons.Default.Circle
    }

    /** What names a badge: the plugin and the category, safe inside a layer id. */
    fun key(m: RoadMarker): String =
        sourceId(m).map { if (it.isLetterOrDigit()) it else '-' }.joinToString("") + "_" + category(m.flare_kind)

    /** The one category a plugin shows, when it only ever shows one. */
    fun oneCategory(kinds: List<String>): String? = kinds.map { category(it) }.toSet().singleOrNull()
}

/** The badge itself: a white edge, the plugin's color, the kind's picture. */
class BadgePainter(private val color: Color, private val glyph: Painter?) : Painter() {
    override val intrinsicSize: Size = Size.Unspecified
    override fun DrawScope.onDraw() {
        val edge = size.minDimension * 0.085f
        drawRoundRect(Color.White, cornerRadius = CornerRadius(size.minDimension * 0.3f))
        drawRoundRect(color, topLeft = Offset(edge, edge), size = Size(size.width - 2 * edge, size.height - 2 * edge),
            cornerRadius = CornerRadius(size.minDimension * 0.23f))
        glyph?.let { g ->
            val pad = size.minDimension * 0.24f
            translate(pad, pad) {
                with(g) { draw(Size(size.width - 2 * pad, size.height - 2 * pad), colorFilter = ColorFilter.tint(Color.White)) }
            }
        }
    }
}

/** A plugin's badge in a list or a card: the same picture as on the map. */
@Composable
fun PluginBadge(sourceId: String, category: String?, size: Dp = 24.dp) {
    val glyph = category?.let { rememberVectorPainter(PluginStyle.icon(it)) }
    val color = PluginStyle.color(sourceId)
    Canvas(Modifier.size(size)) { with(BadgePainter(color, glyph)) { draw(this@Canvas.size) } }
}

/** The icon beside a marker in a list or a card: a plugin badge for a
 *  plugin alert, the kind's own icon for everything else. */
@Composable
fun MarkerGlyph(marker: RoadMarker, size: Dp = 24.dp) {
    if (marker.kind == "plugin") PluginBadge(PluginStyle.sourceId(marker), PluginStyle.category(marker.flare_kind), size)
    else Icon(MarkerIcons.icon(marker.kind), null, Modifier.size(size), tint = MarkerIcons.color(marker.kind))
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
