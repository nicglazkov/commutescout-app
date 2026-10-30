package com.commutescout.drive

import android.os.StatFs
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGSheet
import com.commutescout.drive.design.DGSwitch
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Facts
import com.commutescout.drive.design.GhostRound
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.PageTitle
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.StatusBox
import com.commutescout.drive.design.TopBar
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.rememberSheetState
import com.commutescout.drive.design.tag
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.compose.camera.CameraState
import org.maplibre.compose.camera.rememberCameraState
import org.maplibre.compose.expressions.dsl.const
import org.maplibre.compose.layers.FillLayer
import org.maplibre.compose.layers.LineLayer
import org.maplibre.compose.map.MapOptions
import org.maplibre.compose.map.MaplibreMap
import org.maplibre.compose.map.OrnamentOptions
import org.maplibre.compose.map.RenderOptions
import org.maplibre.compose.sources.GeoJsonData
import org.maplibre.compose.sources.rememberGeoJsonSource
import org.maplibre.compose.style.BaseStyle
import org.maplibre.spatialk.geojson.Feature
import org.maplibre.spatialk.geojson.FeatureCollection
import org.maplibre.spatialk.geojson.Polygon
import org.maplibre.spatialk.geojson.Position
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max

private val STATES_BLUE = Color(0xFF2F7CF6)
private val AREAS_BLUE = Color(0xFF7AA9F8)
private val TRIPS_BLUE = Color(0xFFB9C9E6)

/** "today, 6:40 AM", "yesterday, 6:40 AM" or "Oct 12". */
internal fun savedWhen(ms: Long, zone: ZoneId = ZoneId.systemDefault(), today: LocalDate = LocalDate.now(zone)): String {
    val t = Instant.ofEpochMilli(ms).atZone(zone)
    val clock = t.format(DateTimeFormatter.ofPattern("h:mm a", Locale.US))
    return when (t.toLocalDate()) {
        today -> "today, $clock"
        today.minusDays(1) -> "yesterday, $clock"
        else -> t.format(DateTimeFormatter.ofPattern("MMM d", Locale.US))
    }
}

private fun miniOf(f: MapFiles.LocalFile) = when (f.kind) { "state" -> Mini.STATE; "area" -> Mini.AREA; else -> Mini.TRIP }

private val fixtureFiles: List<MapFiles.LocalFile> by lazy {
    val now = System.currentTimeMillis()
    listOf(
        MapFiles.LocalFile("state-CA", "state", "California", 1_640_000_000, 32.4, -124.6, 42.1, -114.0, now - 3 * 86_400_000L, "fixture"),
        MapFiles.LocalFile("area-1", "area", "Home and around", 312_000_000, 37.33, -122.30, 37.56, -121.95, now - 2 * 3600_000L, "fixture"),
        MapFiles.LocalFile("corridor-1", "corridor", "Trip to Work", 38_000_000, 37.38, -122.16, 37.45, -122.02, now - 86_400_000L, "fixture",
            listOf(listOf(37.442, -122.143), listOf(37.43, -122.11), listOf(37.40, -122.08), listOf(37.39, -122.03))),
    )
}

/**
 * Offline maps: what is saved on this phone and how much room it takes,
 * a state or an area to download, and how saved maps stay current. A
 * saved map opens on its own map; Download an area opens a picker.
 * Full screen over Settings, so Settings itself needs no change.
 */
@Composable
fun OfflineMapsSheet(model: DriveViewModel, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        OfflineMapsPage(model, onClose)
    }
}

@Composable
private fun OfflineMapsPage(model: DriveViewModel, onClose: () -> Unit) {
    val fixtures = BuildConfig.DEBUG && MorePages.fixtures
    val real by MapFiles.files.collectAsStateWithLifecycle()
    val files = if (fixtures) fixtureFiles.filter { f -> real.none { it.id == f.id } } + real else real
    val manifest by MapFiles.manifest.collectAsStateWithLifecycle()
    val progress by MapFiles.progress.collectAsStateWithLifecycle()
    val wifiUpdates by MapFiles.wifiUpdates.collectAsStateWithLifecycle()
    val online by Connectivity.online.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var picking by remember { mutableStateOf(MorePages.wanted == "picker") }
    var opened by remember { mutableStateOf(if (MorePages.wanted == "savedmap") files.firstOrNull { it.kind == "area" } ?: files.firstOrNull() else null) }
    var confirming by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { MorePages.wanted = null; MapFiles.refreshManifest() }
    BackHandler { when { opened != null -> opened = null; picking -> picking = false; else -> onClose() } }

    Box(Modifier.fillMaxSize().background(Color(0xFFEFF3F7)).tag("offline-maps-sheet")) {
        val open = opened
        when {
            picking -> AreaPicker(model, manifest, onCancel = { picking = false }) { s, w, n, e, name ->
                picking = false
                scope.launch { MapFiles.saveArea(s, w, n, e, name) }
            }
            open != null -> SavedMapPage(model, open, fixtures, onClose = { opened = null })
            else -> MapPage("Offline maps", onClose, dock = {
                DGButton("Download an area", { picking = true }, Modifier.weight(1f).tag("offline-download-area"), style = BtnStyle.PRIMARY,
                    icon = "download", enabled = online)
            }) {
                PageTitle("Offline maps", "With no signal, the map comes from maps saved here, and alerts from the last ones you loaded. Guidance works either way.")
                StorageCard(files)
                GroupHead("Saved maps")
                val downloading = progress.keys.filter { id -> files.none { it.id == id } }
                Group {
                    if (files.isEmpty() && downloading.isEmpty()) Text("None yet. Download an area you drive in, or a whole state.",
                        Modifier.padding(18.dp), style = PageType.foot, color = DG.sub)
                    val order = files.sortedWith(compareBy({ listOf("state", "area", "corridor").indexOf(it.kind) }, { -it.savedAt }))
                    order.forEachIndexed { i, f ->
                        if (i > 0) RowDivider(78.dp)
                        val p = progress[f.id]
                        SRow(f.name, Modifier.tag("saved-${f.id}"),
                            lead = { MiniMap(miniOf(f), size = 52.dp, radius = 14.dp, path = f.path?.map { LatLon(it[0], it[1]) }.orEmpty()) },
                            sub = if (p != null) "Updating, ${(p * 100).toInt()}%" else "${f.sizeText}, updated ${savedWhen(f.savedAt)}",
                            chevron = p == null, onClick = { opened = f }) {
                            if (p != null) StopButton(f.id)
                        }
                        if (p != null) Bar(p, Modifier.padding(start = 78.dp, end = 18.dp, bottom = 12.dp))
                    }
                    downloading.forEachIndexed { i, id ->
                        if (files.isNotEmpty() || i > 0) RowDivider(78.dp)
                        val p = progress[id] ?: 0f
                        val state = manifest?.states?.firstOrNull { "state-${it.code}" == id }
                        val kind = if (state != null) Mini.STATE else if (id.startsWith("area")) Mini.AREA else Mini.TRIP
                        SRow(state?.name ?: if (kind == Mini.AREA) "New area" else "Trip map", Modifier.tag("downloading-$id"),
                            lead = { MiniMap(kind, size = 52.dp, radius = 14.dp, dashed = true) },
                            sub = "Downloading, ${(p * 100).toInt()}%") { StopButton(id) }
                        Bar(p, Modifier.padding(start = 78.dp, end = 18.dp, bottom = 12.dp))
                    }
                }
                GroupHead("Whole states")
                Group {
                    val states = manifest?.states.orEmpty().filter { s -> files.none { it.id == "state-${s.code}" } && "state-${s.code}" !in progress }
                    if (manifest == null) Text(if (online) "The list of states is loading." else "The list of states needs a signal.",
                        Modifier.padding(18.dp), style = PageType.foot, color = DG.sub)
                    states.forEachIndexed { i, s ->
                        if (i > 0) RowDivider(18.dp)
                        val size = s.bytes?.let(Units::bytes) ?: "Size unknown"
                        SRow(s.name, sub = size, onClick = { confirming = if (confirming == s.code) null else s.code }) {
                            GhostRound("download", "Download ${s.name}", { confirming = s.code }, Modifier.tag("download-${s.code}"), tint = DG.low)
                        }
                        AnimatedVisibility(confirming == s.code) {
                            Row(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                DGButton("Cancel", { confirming = null }, Modifier.weight(1f))
                                DGButton("Download $size", { confirming = null; scope.launch { MapFiles.downloadState(s) } },
                                    Modifier.weight(1f).tag("download-yes-${s.code}"), style = BtnStyle.BLUE, enabled = online)
                            }
                        }
                    }
                }
                GroupHead("Keep them current")
                Group {
                    SRow("Update on Wi-Fi", Modifier.tag("offline-wifi-update"), sub = "When a newer map is out, never on mobile data", lead = { RowTile("wifi") },
                        onClick = { MapFiles.setWifiUpdates(!wifiUpdates) }) { DGSwitch(wifiUpdates, { MapFiles.setWifiUpdates(it) }) }
                    RowDivider()
                    SRow("Save each trip's map", Modifier.tag("offline-autosave"), sub = "When a trip starts on Wi-Fi", lead = { RowTile("route") },
                        onClick = { model.prefs.mapAutoSave = !model.prefs.mapAutoSave }) { DGSwitch(model.prefs.mapAutoSave, { model.prefs.mapAutoSave = it }) }
                }
                Text("A whole state can take a few gigabytes. Download the areas you drive in.",
                    Modifier.padding(start = 24.dp, end = 24.dp, top = 10.dp), style = PageType.note, color = DG.faint)
            }
        }
    }
}

@Composable
private fun StopButton(id: String) {
    Box(Modifier.size(34.dp).clip(CircleShape).background(DG.ink.copy(alpha = .06f)).clickable { MapFiles.stop(id) }.tag("stop-$id")
        .semantics { contentDescription = "Stop" }, contentAlignment = Alignment.Center) { DGIcon("close", DG.sub, 15.dp, stroke = 2.6f) }
}

@Composable
private fun Bar(p: Float, modifier: Modifier = Modifier) {
    val a by animateFloatAsState(p.coerceIn(0f, 1f), tween(400), label = "bar")
    Box(modifier.fillMaxWidth().height(5.dp).clip(CircleShape).background(DG.low.copy(alpha = .14f))) {
        Box(Modifier.fillMaxWidth(a).height(5.dp).clip(CircleShape).background(DG.low))
    }
}

/** How much the saved maps take, how much room is left, and the split by kind. */
@Composable
private fun StorageCard(files: List<MapFiles.LocalFile>) {
    val states = files.filter { it.kind == "state" }.sumOf { it.bytes }
    val areas = files.filter { it.kind == "area" }.sumOf { it.bytes }
    val trips = files.filter { it.kind == "corridor" }.sumOf { it.bytes }
    val free = remember { runCatching { StatFs(Engine.app.filesDir.path).availableBytes }.getOrNull() }
    val split = StorageSplit.of(states, areas, trips)
    Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().glass(RoundedCornerShape(24.dp), elevation = 14.dp).padding(18.dp).tag("offline-storage")) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(Units.bytes(states + areas + trips), style = PageType.navTitle.copy(fontSize = 30.sp, fontWeight = FontWeight.Bold), color = DG.ink)
            Spacer(Modifier.width(8.dp))
            Text("on this phone", Modifier.padding(bottom = 5.dp).weight(1f), style = PageType.rowSub, color = DG.sub)
            free?.let { Text("${Units.bytes(it)} free", Modifier.padding(bottom = 5.dp), style = PageType.rowSub, color = DG.sub) }
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(DG.ink.copy(alpha = .06f)), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            if (split.states > 0) Box(Modifier.weight(split.states).height(10.dp).background(STATES_BLUE))
            if (split.areas > 0) Box(Modifier.weight(split.areas).height(10.dp).background(AREAS_BLUE))
            if (split.trips > 0) Box(Modifier.weight(split.trips).height(10.dp).background(TRIPS_BLUE))
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            listOf("States" to STATES_BLUE, "Areas" to AREAS_BLUE, "Trips" to TRIPS_BLUE).forEach { (label, c) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(c)); Spacer(Modifier.width(6.dp))
                    Text(label, style = PageType.rowSub.copy(fontSize = 13.sp), color = DG.sub)
                }
            }
        }
    }
}

/** A map of its own for the picker and a saved map, in the driver's style; [area] is drawn on it. */
@Composable
private fun OwnMap(model: DriveViewModel, camera: CameraState, area: List<LatLon>? = null, alpha: Float = 1f) {
    MaplibreMap(
        modifier = Modifier.fillMaxSize(),
        baseStyle = BaseStyle.Json(model.styleJson),
        cameraState = camera,
        // A TextureView: a SurfaceView draws nothing inside a dialog's window.
        options = MapOptions(renderOptions = RenderOptions(renderMode = RenderOptions.RenderMode.TextureView),
            ornamentOptions = OrnamentOptions.AllDisabled),
    ) {
        area?.let { ring ->
            val src = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
                Feature(geometry = Polygon(listOf((ring + ring.first()).map { Position(it.lon, it.lat) })), properties = kotlinx.serialization.json.buildJsonObject {}))))
            FillLayer(id = "cs-saved-fill", source = src, color = const(DG.low.copy(alpha = .13f * alpha)))
            LineLayer(id = "cs-saved-edge", source = src, color = const(DG.low.copy(alpha = alpha)), width = const(2.5.dp))
        }
    }
}

private fun boxRing(f: MapFiles.LocalFile) = listOf(LatLon(f.south, f.west), LatLon(f.south, f.east), LatLon(f.north, f.east), LatLon(f.north, f.west))

/**
 * Choose an area: a frame over the map with a corner to drag. Under it,
 * what the area would take on the phone and how big it is on the ground.
 */
@Composable
private fun AreaPicker(model: DriveViewModel, manifest: MapFiles.Manifest?, onCancel: () -> Unit,
                       onDownload: (Double, Double, Double, Double, String) -> Unit) {
    val home = Engine.places.home?.let { LatLon(it.lat, it.lon) }
    val start = (if (BuildConfig.DEBUG && MorePages.fixtures) LatLon(37.442, -122.143) else null)
        ?: model.here.value ?: home ?: model.viewCenter ?: LatLon(39.5, -98.35)
    val camera = rememberCameraState(firstPosition = CameraPosition(target = Position(start.lon, start.lat), zoom = 10.2))
    val online by Connectivity.online.collectAsStateWithLifecycle()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth; val h = maxHeight
        val top = 140.dp; val left = 30.dp
        var fw by remember { mutableStateOf(w - 60.dp) }
        var fh by remember { mutableStateOf(h - top - 300.dp) }
        // Put the frame's centre over the spot the map opened on.
        LaunchedEffect(Unit) {
            camera.awaitProjection()
            val off = camera.projection?.positionFromScreenLocation(DpOffset(left + fw / 2, top + fh / 2)) ?: return@LaunchedEffect
            val c = camera.position.target
            camera.position = CameraPosition(target = Position(2 * c.longitude - off.longitude, 2 * c.latitude - off.latitude), zoom = camera.position.zoom)
        }
        OwnMap(model, camera)
        camera.position.zoom   // read, so the numbers follow the map
        val proj = camera.projection
        val nw = proj?.positionFromScreenLocation(DpOffset(left, top))
        val se = proj?.positionFromScreenLocation(DpOffset(left + fw, top + fh))
        val box = if (nw != null && se != null) doubleArrayOf(se.latitude, nw.longitude, nw.latitude, se.longitude) else null
        val wKm = box?.let { AreaMath.widthKm(it[0], it[1], it[2], it[3]) } ?: 0.0
        val hKm = box?.let { AreaMath.heightKm(it[0], it[2]) } ?: 0.0
        val density = box?.let { b ->
            val lat = (b[0] + b[2]) / 2; val lon = (b[1] + b[3]) / 2
            StateBounds.within(doubleArrayOf(lat, lon, lat, lon)).firstNotNullOfOrNull { code ->
                AreaMath.density(manifest?.states?.firstOrNull { it.code == code }?.bytes, StateBounds.of(code))
            }
        }
        val bytes = AreaMath.estimateBytes(wKm, hKm, density)
        val fits = box != null && AreaMath.fits(box[0], box[1], box[2], box[3])

        // The frame: the map outside it dimmed, a dashed inner line, and the corner handle.
        Canvas(Modifier.fillMaxSize()) {
            val r = 22.dp.toPx()
            val frame = Path().apply { addRoundRect(RoundRect(left.toPx(), top.toPx(), (left + fw).toPx(), (top + fh).toPx(), CornerRadius(r))) }
            clipPath(frame, ClipOp.Difference) { drawRect(Color(0xFF0E1726).copy(alpha = .28f)) }
            drawPath(frame, DG.low, style = Stroke(2.dp.toPx()))
            val i = 8.dp.toPx()
            drawRoundRect(Color.White.copy(alpha = .8f), Offset(left.toPx() + i, top.toPx() + i), Size(fw.toPx() - 2 * i, fh.toPx() - 2 * i), CornerRadius(r - i),
                style = Stroke(1.2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))))
        }
        val d = LocalDensity.current
        Box(Modifier.offset(x = left + fw - 22.dp, y = top + fh - 22.dp).size(44.dp).semantics { contentDescription = "Resize the area" }
            .pointerInput(Unit) {
                detectDragGestures { change, amount ->
                    change.consume()
                    with(d) {
                        fw = (fw + amount.x.toDp()).coerceIn(90.dp, w - left - 14.dp)
                        fh = (fh + amount.y.toDp()).coerceIn(90.dp, h - top - 250.dp)
                    }
                }
            }.tag("picker-corner"), contentAlignment = Alignment.Center) {
            Box(Modifier.size(26.dp).shadow(6.dp, CircleShape).clip(CircleShape).background(Color.White).border(3.dp, DG.low, CircleShape))
        }

        // The capsule.
        Row(Modifier.windowInsetsPadding(WindowInsets.statusBars).padding(start = 14.dp, end = 14.dp, top = 6.dp).fillMaxWidth().height(54.dp)
            .glass(RoundedCornerShape(27.dp), elevation = 16.dp).padding(horizontal = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(DG.ink.copy(alpha = .05f)).clickable(onClick = onCancel).tag("picker-close")
                .semantics { contentDescription = "Cancel" }, contentAlignment = Alignment.Center) { DGIcon("close", DG.ink, 20.dp, stroke = 2.4f) }
            Text("Choose an area", Modifier.weight(1f), style = DGType.title.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold), color = DG.ink,
                textAlign = TextAlign.Center)
            Spacer(Modifier.width(44.dp))
        }

        // The pick card.
        Column(Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(start = 10.dp, end = 10.dp, bottom = 6.dp)
            .fillMaxWidth().glass(RoundedCornerShape(30.dp), elevation = 24.dp, strong = true)
            .padding(start = 20.dp, end = 14.dp, top = 18.dp, bottom = 12.dp).tag("picker-card")) {
            Text(if (fits) AreaMath.aboutText(bytes) else "Too big to save at once", Modifier.tag("picker-size"),
                style = PageType.confirmTitle, color = if (fits) DG.ink else DG.highInk)
            Text(AreaMath.spanText(wKm, hKm) + if (fits) ". Drag the corner to change it." else ". Drag the corner in, or zoom in.",
                Modifier.padding(top = 4.dp), style = PageType.confirmBody, color = DG.sub)
            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DGButton("Cancel", onCancel, Modifier.weight(1f))
                DGButton("Download", {
                    val b = box ?: return@DGButton
                    val inside = { p: LatLon? -> p != null && p.lat in b[0]..b[2] && p.lon in b[1]..b[3] }
                    val name = when {
                        inside(home) -> "Home and around"
                        inside(Engine.places.work?.let { LatLon(it.lat, it.lon) }) -> "Work and around"
                        else -> "Area saved " + LocalDate.now().format(DateTimeFormatter.ofPattern("MMM d", Locale.US))
                    }
                    onDownload(b[0], b[1], b[2], b[3], name)
                }, Modifier.weight(1f).tag("picker-download"), style = BtnStyle.PRIMARY, enabled = fits && online)
            }
        }
    }
}

/**
 * One saved map, on a map of the ground it covers: whether it is here
 * and current, its facts, what is in it, and Update now and Delete.
 */
@Composable
private fun SavedMapPage(model: DriveViewModel, f: MapFiles.LocalFile, fixtures: Boolean, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val progress by MapFiles.progress.collectAsStateWithLifecycle()
    val online by Connectivity.online.collectAsStateWithLifecycle()
    var check by remember { mutableStateOf<MapFileCheck?>(null) }
    var phase by remember { mutableStateOf("idle") }   // idle, updating, updated, confirm, deleted
    var current by remember { mutableStateOf(f) }
    LaunchedEffect(current.id, current.savedAt) { check = if (fixtures) null else MapFiles.check(current) }
    val here = fixtures || check?.exists == true
    val alerts = remember { runCatching { File(Engine.app.cacheDir, "offline").listFiles()?.sumOf { it.length() } }.getOrNull() ?: 0L }
    val fade by animateFloatAsState(if (phase == "deleted") 0f else 1f, tween(500), label = "fade")
    val center = LatLon((f.south + f.north) / 2, (f.west + f.east) / 2)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight
        val sheet = rememberSheetState(listOf(h * (500f / 844f), h * (756f / 844f)))
        val wKm = AreaMath.widthKm(f.south, f.west, f.north, f.east); val hKm = AreaMath.heightKm(f.south, f.north)
        // The ground fits in the open map above the sheet.
        val mpd = max(wKm * 1000 / (maxWidth.value * .8), hKm * 1000 / ((h * (344f / 844f)).value * .75))
        val target = WatchGeo.offset(center, -(h / 2 - h * (200f / 844f)).value * mpd, 0.0)
        val camera = rememberCameraState(firstPosition = CameraPosition(target = Position(target.lon, target.lat),
            zoom = WatchGeo.zoomForMpd(mpd, center.lat).coerceIn(3.0, 15.0)))
        OwnMap(model, camera, area = boxRing(f), alpha = fade)
        TopBar(onClose, Modifier.align(Alignment.TopStart))
        DGSheet(sheet, Modifier.align(Alignment.BottomCenter).tag("saved-map-sheet")) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(bottom = 16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(48.dp).clip(CircleShape).background(DG.low.copy(alpha = .1f)), contentAlignment = Alignment.Center) { DGIcon("map", DG.low, 24.dp) }
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(f.name, style = PageType.confirmTitle, color = DG.ink, maxLines = 1)
                        val day = savedWhen(f.savedAt).let { if (it.startsWith("today") || it.startsWith("yesterday")) it.substringBefore(",") else it }
                        Text(when (f.kind) { "state" -> "A whole state"; "area" -> "An area you chose"; else -> "A trip's map" } + ", saved $day",
                            style = PageType.rowSub, color = DG.sub)
                    }
                }
                Spacer(Modifier.height(14.dp))
                if (phase != "deleted") {
                    val stale = !fixtures && MapFiles.stale().any { it.id == f.id }
                    when {
                        !here -> StatusBox("Not on this phone", "The map needs a signal here now.", good = false)
                        phase == "updated" -> StatusBox("Up to date", "Updated just now, ${current.sizeText} in all.", good = true)
                        stale -> StatusBox("A newer map is out", "Update now, or it updates on its own on Wi-Fi.", good = false)
                        else -> StatusBox("Up to date", "Updated ${savedWhen(current.savedAt)}.", good = true)
                    }
                    progress[f.id]?.let { Bar(it, Modifier.padding(top = 10.dp)) }
                }
                Spacer(Modifier.height(12.dp))
                val detail = check?.header?.maxZoom?.let { if (it >= 14) "Every street and address" else "Main roads and towns" } ?: "Every street and address"
                Facts(listOf("Size" to current.sizeText, "Covers" to "About ${AreaMath.spanText(wKm, hKm)}", "Detail" to detail,
                    "Next update" to when {
                        f.kind == "corridor" -> "Saved again on your next trip"
                        MapFiles.wifiUpdates.value -> "When a newer map is out, on Wi-Fi"
                        else -> "When you update it"
                    }))
                Text("What's included", Modifier.padding(top = 16.dp, bottom = 8.dp), style = PageType.section, color = DG.ink)
                Group {
                    SRow("Roads and the map", sub = "Streets, names and places", value = current.sizeText, lead = { RowTile("map") })
                    RowDivider()
                    SRow("Last road alerts", sub = "From the last time you had a signal", value = Units.bytes(alerts), lead = { RowTile("hazard") })
                }
                Text("Offline, alerts can be out of date. Live alerts come back as soon as you have a signal.",
                    Modifier.padding(top = 10.dp, start = 6.dp, end = 6.dp), style = PageType.note, color = DG.faint)
            }
            Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (phase) {
                    "confirm" -> {
                        DGButton("Keep it", { phase = "idle" }, Modifier.weight(1f).tag("saved-keep"))
                        DGButton("Delete ${current.sizeText}", {
                            if (!fixtures) MapFiles.delete(current)
                            phase = "deleted"
                            scope.launch { delay(900); onClose() }
                        }, Modifier.weight(1f).tag("saved-delete-yes"), style = BtnStyle.DANGER)
                    }
                    "deleted" -> DGButton("Deleted", {}, Modifier.weight(1f), style = BtnStyle.DONE, icon = "check")
                    else -> {
                        val busy = phase == "updating"
                        DGButton(when (phase) { "updating" -> "Checking for changes"; "updated" -> "Updated"; else -> "Update now" }, {
                            if (phase != "idle") return@DGButton
                            phase = "updating"
                            scope.launch {
                                val done = if (fixtures) { delay(1600); current.copy(savedAt = System.currentTimeMillis()) } else MapFiles.update(current)
                                if (done != null) { current = done; phase = "updated" } else phase = "idle"
                            }
                        }, Modifier.weight(1f).tag("saved-update"), style = if (phase == "updated") BtnStyle.DONE else BtnStyle.PLAIN,
                            icon = if (phase == "updated") "check" else "refresh", enabled = (online || fixtures) && !busy)
                        DGButton("Delete", { phase = "confirm" }, Modifier.weight(1f).tag("saved-delete"), style = BtnStyle.WARN, icon = "trash", enabled = !busy)
                    }
                }
            }
        }
    }
}
