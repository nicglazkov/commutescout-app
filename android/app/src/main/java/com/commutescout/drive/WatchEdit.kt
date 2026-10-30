package com.commutescout.drive

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGField
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGSheet
import com.commutescout.drive.design.DGSwitch
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.Segmented
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.rememberSheetState
import com.commutescout.drive.design.tag
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationCameraMode
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.spatialk.geojson.Position
import uniffi.ferrostar.GeographicCoordinate
import uniffi.ferrostar.UserLocation
import uniffi.ferrostar.Waypoint
import uniffi.ferrostar.WaypointKind
import java.time.Instant
import kotlin.math.hypot
import kotlin.math.max
import kotlin.time.Duration.Companion.milliseconds

private val SHAPES = listOf("circle", "route", "polygon")

/** Where the drive between Home and Work stands while the editor finds it. */
private sealed interface Drive {
    data object Loading : Drive
    data object NoPlaces : Drive
    data object Failed : Drive
    data class Ready(val path: List<LatLon>) : Drive
}

/**
 * A new or existing watch area, drawn on the main map: a circle with a
 * radius handle (past 12 mi the map zooms out instead), the drive from
 * Home to Work with its corridor, or a shape with corners to drag.
 * The sheet holds the name, the kinds, quiet hours and Save.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WatchEditor(model: DriveViewModel, mapState: NavigationMapState, existing: Watch?, prefs: WatchPrefs, push: Boolean, email: Boolean,
                fixtures: Boolean, onSaved: () -> Unit, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val home = Engine.places.home; val work = Engine.places.work
    val here = model.here.value
    val camera = mapState.cameraState
    val start = existing?.center?.let { LatLon(it.lat, it.lon) } ?: home?.let { LatLon(it.lat, it.lon) }
        ?: (if (fixtures) LatLon(37.442, -122.143) else null) ?: here
        ?: camera.position.target.takeIf { kotlin.math.abs(it.latitude) > 0.5 }?.let { LatLon(it.latitude, it.longitude) }
        ?: LatLon(39.5, -98.35)   // no place and no map yet: the middle of the US

    var shape by remember { mutableIntStateOf(SHAPES.indexOf(existing?.shape ?: "circle").coerceAtLeast(0)) }
    var name by remember { mutableStateOf(existing?.name ?: "Home area") }
    var typed by remember { mutableStateOf(existing != null) }
    var center by remember { mutableStateOf(start) }
    var radius by remember { mutableIntStateOf(existing?.takeIf { it.shape == "circle" }?.let { WatchGeo.radiusMi(it.radius_km) } ?: 8) }
    var poly by remember { mutableStateOf(existing?.takeIf { it.shape == "polygon" }?.path?.takeIf { it.size >= 3 } ?: WatchGeo.startPolygon(start)) }
    var drive by remember { mutableStateOf<Drive>(existing?.takeIf { it.shape == "route" }?.path?.takeIf { it.size >= 2 }?.let { Drive.Ready(it) } ?: Drive.Loading) }
    var kinds by remember { mutableStateOf(existing?.kinds?.toSet() ?: setOf("incident", "closure", "fire")) }
    var quiet by remember { mutableStateOf(existing?.quiet_hours ?: true) }
    var saving by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth; val h = maxHeight
        val scale = (w.value / 390f)
        val sheetLow = h * (468f / 844f); val sheetHigh = h * (640f / 844f)
        val sheet = rememberSheetState(listOf(sheetLow, sheetHigh))
        // The shape sits in the open map above the sheet, at the mockup's 252 of 844.
        val focusY = h * (252f / 844f)
        val shiftDp = h / 2 - focusY

        /** The camera for a circle of [r] miles (or a shape at the 12 mi scale) around [c], the shape up in the open map. */
        fun cameraAt(mpd: Double, c: LatLon): CameraPosition {
            val target = WatchGeo.offset(c, -shiftDp.value * mpd, 0.0)
            return CameraPosition(target = Position(target.lon, target.lat), zoom = WatchGeo.zoomForMpd(mpd, c.lat).coerceIn(3.0, 17.0), bearing = 0.0, tilt = 0.0)
        }
        fun cameraFor(r: Int, c: LatLon): CameraPosition = cameraAt(WatchGeo.metersPerDp(r, scale), c)
        suspend fun frame(animate: Boolean) {
            mapState.cameraMode = NavigationCameraMode.FREE
            camera.awaitProjection()
            val target = when (SHAPES[shape]) {
                "route" -> (drive as? Drive.Ready)?.path?.let { p ->
                    val s = p.minOf { it.lat }; val n = p.maxOf { it.lat }; val west = p.minOf { it.lon }; val e = p.maxOf { it.lon }
                    val wide = AreaMath.widthKm(s, west, n, e) * 1000 + 2 * WatchGeo.ROUTE_BUFFER_KM * 1000; val tall = (n - s) * 110_540 + 2 * WatchGeo.ROUTE_BUFFER_KM * 1000
                    cameraAt(max(wide / (w.value * .72), tall / ((h - sheetLow).value - 150)).coerceAtLeast(5.0), LatLon((s + n) / 2, (west + e) / 2))
                }
                "polygon" -> cameraAt(WatchGeo.MI_M / (WatchGeo.SHAPE_DP_PER_MI * scale), LatLon(poly.sumOf { it.lat } / poly.size, poly.sumOf { it.lon } / poly.size))
                else -> cameraFor(radius, center)
            } ?: return
            if (animate) runCatching { camera.animateTo(target, 800.milliseconds) }.onFailure { camera.position = target }
            else camera.position = target
        }
        LaunchedEffect(shape, drive is Drive.Ready) { frame(true) }

        // The drive from Home to Work, once, when Route is picked.
        LaunchedEffect(shape) {
            if (SHAPES[shape] != "route" || drive is Drive.Ready) return@LaunchedEffect
            if (fixtures) { drive = Drive.Ready(MorePages.fixtureWatches[1].path); return@LaunchedEffect }
            if (home == null || work == null) { drive = Drive.NoPlaces; return@LaunchedEffect }
            drive = runCatching {
                withContext(Dispatchers.IO) {
                    Engine.core.getRoutes(UserLocation(GeographicCoordinate(home.lat, home.lon), 6.0, null, Instant.now(), null),
                        listOf(Waypoint(GeographicCoordinate(work.lat, work.lon), WaypointKind.BREAK)))
                }.firstOrNull()?.geometry?.map { LatLon(it.lat, it.lng) }
            }.getOrNull()?.takeIf { it.size >= 2 }?.let { Drive.Ready(it) } ?: Drive.Failed
        }

        // What the map draws.
        camera.position.zoom   // read, so the handles follow the map as it moves
        val proj = camera.projection
        SideEffect {
            when (SHAPES[shape]) {
                "circle" -> { MapDrawing.area = WatchGeo.circleRing(center, radius * WatchGeo.MI_M); MapDrawing.line = null }
                "polygon" -> { MapDrawing.area = poly; MapDrawing.line = null }
                else -> {
                    MapDrawing.area = null
                    MapDrawing.line = (drive as? Drive.Ready)?.path
                    MapDrawing.bandDp = (2 * WatchGeo.ROUTE_BUFFER_KM * 1000 / WatchGeo.mpdAt(camera.position.zoom, camera.position.target.latitude)).toFloat().coerceAtMost(600f)
                }
            }
        }
        DisposableEffect(Unit) { MapDrawing.cover = true; onDispose { MapDrawing.clear() } }
        fun screen(p: LatLon): DpOffset? = proj?.screenLocationFromPosition(Position(p.lon, p.lat))
        fun geo(o: DpOffset): LatLon? = proj?.positionFromScreenLocation(o)?.let { LatLon(it.latitude, it.longitude) }

        when (SHAPES[shape]) {
            "circle" -> screen(center)?.let { c ->
                val edge = screen(WatchGeo.offset(center, 0.0, radius * WatchGeo.MI_M)) ?: return@let
                // The dashed radius and its label.
                Canvas(Modifier.fillMaxSize()) {
                    drawLine(DG.low, Offset(c.x.toPx(), c.y.toPx()), Offset(edge.x.toPx(), edge.y.toPx()), 1.6.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
                }
                Box(Modifier.offset(x = (c.x + edge.x) / 2 - 100.dp, y = c.y - 44.dp).width(200.dp).height(34.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.height(34.dp).glass(RoundedCornerShape(17.dp), elevation = 10.dp).padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                        Text(WatchGeo.radiusLabel(radius), Modifier.tag("watch-radius-label"), style = DGType.row.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold), color = DG.ink, maxLines = 1)
                    }
                }
                // The centre: drag it to move the circle.
                Handle(c, 14.dp, "Center", Modifier.tag("watch-center"), dot = true,
                    onDrag = { o -> geo(o)?.let { center = it } }, onStart = { dragging = true }, onEnd = { dragging = false })
                // The radius handle.
                var startD by remember { mutableStateOf(0f) }
                Handle(edge, 26.dp, "Radius, ${WatchGeo.radiusLabel(radius)}", Modifier.tag("watch-radius"), grow = dragging,
                    onStart = {
                        dragging = true
                        // Line the map up with the drag's own scale first.
                        camera.position = cameraFor(radius, center)
                        startD = WatchGeo.handleDp(radius, scale)
                    },
                    onDelta = { d ->
                        startD = (startD + d.x.value).coerceAtLeast(0f)
                        val r = WatchGeo.radiusFromDrag(startD, scale)
                        if (r != radius) { radius = r; camera.position = cameraFor(r, center) }
                    },
                    onEnd = { dragging = false })
            }
            "polygon" -> poly.forEachIndexed { i, p ->
                screen(p)?.let { o ->
                    Handle(o, 18.dp, "Corner ${i + 1}", Modifier.tag("watch-corner-$i"),
                        onDrag = { at -> geo(DpOffset(at.x.coerceIn(16.dp, w - 16.dp), at.y.coerceIn(118.dp, h - sheetLow - 20.dp)))?.let { g ->
                            poly = poly.toMutableList().also { it[i] = g } } },
                        onStart = { dragging = true }, onEnd = { dragging = false })
                }
            }
            else -> (drive as? Drive.Ready)?.path?.let { p ->
                screen(p.first())?.let { EndLabel(it, "home", "Home", -58.dp) }
                screen(p.last())?.let { EndLabel(it, "work", "Work", 44.dp) }
            }
        }

        // The capsule.
        Row(Modifier.windowInsetsPadding(WindowInsets.statusBars).padding(start = 14.dp, end = 14.dp, top = 6.dp).fillMaxWidth().height(54.dp)
            .glass(RoundedCornerShape(27.dp), elevation = 16.dp).padding(horizontal = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            CapsuleButton("close", "Cancel", onClose, Modifier.tag("watch-cancel"))
            Text(if (existing == null) "New watch area" else "Edit watch area", Modifier.weight(1f), style = DGType.title.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
                color = DG.ink, textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 1)
            if (existing != null) CapsuleButton("trash", "Delete", { confirmDelete = true }, Modifier.tag("watch-delete"), tint = DG.highInk)
            else Spacer(Modifier.width(44.dp))
        }

        // The sheet.
        val area = when (SHAPES[shape]) {
            "polygon" -> WatchGeo.polygonSqKm(poly)
            else -> 0.0
        }
        val driveKm = (drive as? Drive.Ready)?.path?.let(WatchGeo::lengthKm) ?: 0.0
        val geometryOk = when (SHAPES[shape]) {
            "polygon" -> area in 0.5..WatchGeo.FREE_POLYGON_SQ_KM
            "route" -> drive is Drive.Ready && driveKm <= WatchGeo.FREE_ROUTE_KM
            else -> true
        }
        val help = when (SHAPES[shape]) {
            "circle" -> "Drag the handle to resize, up to 25 mi. This circle covers about ${WatchGeo.grouped(WatchGeo.circleSqMi(radius))} sq mi."
            "polygon" -> if (area > WatchGeo.FREE_POLYGON_SQ_KM) "That's about ${WatchGeo.grouped(WatchGeo.polygonSqMi(poly))} sq mi. Drag a corner in: a shape can cover up to 2,000 sq mi."
                else "Drag the corners to draw your own area, up to 2,000 sq mi. This one covers about ${WatchGeo.grouped(WatchGeo.polygonSqMi(poly))} sq mi."
            else -> when (drive) {
                Drive.Loading -> "Finding your drive from Home to Work."
                Drive.NoPlaces -> "Save Home and Work in your places to watch the drive between them."
                Drive.Failed -> "Could not find the drive from Home to Work. Check your signal and try again."
                is Drive.Ready -> if (driveKm > WatchGeo.FREE_ROUTE_KM) "This drive is ${WatchGeo.miles(driveKm)} mi. A watch can follow up to 250 mi."
                    else if (existing != null) "Follows this drive, 2 mi on each side."
                    else "Follows your usual drive from Home to Work, 2 mi on each side."
            }
        }
        DGSheet(sheet, Modifier.align(Alignment.BottomCenter).tag("watch-edit-sheet")) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 2.dp, bottom = 24.dp)) {
                DGField("Name", name, { name = it.take(60); typed = true }, tag = "watch-name")
                if (existing == null) {
                    Spacer(Modifier.height(12.dp))
                    Segmented(listOf("Circle", "Route", "Shape"), shape, { i ->
                        shape = i
                        if (!typed) name = listOf("Home area", "Work commute", "Downtown")[i]
                    }, Modifier.padding(horizontal = 14.dp), icons = listOf("ring", "route", "shape"), tagPrefix = "watch-shape")
                }
                AnimatedContent(help, transitionSpec = { fadeIn(tween(360)) togetherWith fadeOut(tween(160)) }, label = "help") { t ->
                    Text(t, Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp).heightIn(min = 38.dp).tag("watch-help"),
                        style = PageType.foot, color = DG.sub)
                }
                Text("What to watch", Modifier.padding(start = 18.dp, top = 14.dp, bottom = 8.dp), style = PageType.section, color = DG.ink)
                FlowRow(Modifier.padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    WatchKind.entries.forEach { k ->
                        CheckChip(k.label, k.icon, k.tone.color, k.id in kinds, { kinds = if (k.id in kinds) kinds - k.id else kinds + k.id },
                            Modifier.tag("watch-kind-${k.id}"))
                    }
                }
                Spacer(Modifier.height(14.dp))
                val q = prefs.quiet_hours
                Group {
                    SRow("Quiet hours", Modifier.tag("watch-edit-quiet"), sub = if (q?.enabled == true) "${WatchText.time(q.start)} to ${WatchText.time(q.end)}" else "Off for your account",
                        lead = { RowTile("moon") }, onClick = { quiet = !quiet }) { DGSwitch(quiet, { quiet = it }) }
                }
                Text(when {
                    q?.enabled != true -> "Turn on quiet hours in Watch areas, and this area follows them."
                    !quiet -> "This area alerts at any hour, even during quiet hours."
                    q.summary -> "During quiet hours, alerts wait and arrive as one summary at ${WatchText.time(q.end)}."
                    else -> "During quiet hours, this area stays silent."
                }, Modifier.padding(start = 24.dp, end = 24.dp, top = 10.dp), style = PageType.note, color = DG.faint)
                error?.let { Text(it, Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp).tag("watch-error"), style = PageType.note, color = DG.highInk) }
            }
            Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = .6f)).windowInsetsPadding(WindowInsets.navigationBars)
                .padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (confirmDelete && existing != null) {
                    DGButton("Keep it", { confirmDelete = false }, Modifier.weight(1f))
                    DGButton("Delete", {
                        scope.launch {
                            saving = true
                            val (status, text) = if (fixtures) 200 to "" else WatchApi.call(model, "DELETE", "/api/watch/${existing.id}")
                            saving = false
                            if (status in 200..299 || status == 404) { onSaved(); onClose() } else { error = WatchBodies.error(status, text); confirmDelete = false }
                        }
                    }, Modifier.weight(1f).tag("watch-delete-yes"), style = BtnStyle.DANGER, enabled = !saving)
                } else {
                    val none = kinds.isEmpty()
                    val label = saved?.let { "Saved. Watching $it" } ?: if (none) "Pick at least one kind" else if (saving) "Saving" else "Save watch area"
                    DGButton(label, {
                        if (saved != null) return@DGButton
                        val draft = WatchDraft(name.trim().ifEmpty { "Watch area" }, SHAPES[shape], center, radius,
                            if (SHAPES[shape] == "polygon") poly else (drive as? Drive.Ready)?.path.orEmpty(), kinds, quiet, push, email)
                        scope.launch {
                            saving = true; error = null
                            val (status, text) = when {
                                fixtures -> 200 to ""
                                existing == null -> WatchApi.call(model, "POST", "/api/watch/create", WatchBodies.create(draft))
                                existing.shape == "circle" && (existing.center?.let { LatLon(it.lat, it.lon) } != center || WatchGeo.radiusMi(existing.radius_km) != radius) ->
                                    replaceCircle(model, existing, draft)
                                else -> WatchApi.call(model, "PATCH", "/api/watch/${existing.id}", WatchBodies.update(draft))
                            }
                            saving = false
                            if (status in 200..299) { saved = draft.name; delay(1100); onSaved(); onClose() }
                            else error = WatchBodies.error(status, text)
                        }
                    }, Modifier.weight(1f).tag("watch-save"), style = if (saved != null) BtnStyle.DONE else BtnStyle.PRIMARY,
                        icon = if (saved != null) "check" else null, enabled = !none && geometryOk && !saving)
                }
            }
        }
    }
}

/**
 * The server keeps a circle's geometry fixed after it is made, so a
 * moved or resized circle is a new watch: the old one goes, the new
 * one is made, and if that fails the old one is put back.
 */
private suspend fun replaceCircle(model: DriveViewModel, old: Watch, draft: WatchDraft): Pair<Int, String> {
    val gone = WatchApi.call(model, "DELETE", "/api/watch/${old.id}")
    if (gone.first !in 200..299 && gone.first != 404) return gone
    val made = WatchApi.call(model, "POST", "/api/watch/create", WatchBodies.create(draft))
    if (made.first !in 200..299) {
        WatchApi.call(model, "POST", "/api/watch/create", WatchBodies.create(draft.copy(
            name = old.name ?: draft.name, center = old.center?.let { LatLon(it.lat, it.lon) }, radiusMi = WatchGeo.radiusMi(old.radius_km),
            kinds = old.kinds?.toSet() ?: draft.kinds)))
    }
    return made
}

/** A round white handle with a blue ring that grows while held. [onDrag] gets the finger's spot on the screen. */
@Composable
private fun Handle(at: DpOffset, size: Dp, label: String, modifier: Modifier = Modifier, dot: Boolean = false, grow: Boolean = false,
                   onStart: () -> Unit = {}, onEnd: () -> Unit = {}, onDelta: ((DpOffset) -> Unit)? = null, onDrag: ((DpOffset) -> Unit)? = null) {
    var held by remember { mutableStateOf(false) }
    val s by animateFloatAsState(if (held || grow) 1.2f else 1f, DG.springy(), label = "hdl")
    val d = LocalDensity.current
    var finger by remember { mutableStateOf(at) }
    // The gesture outlives recompositions (the label and spot change as it drags), so it reads the latest of each.
    val atNow by rememberUpdatedState(at)
    val startNow by rememberUpdatedState(onStart); val endNow by rememberUpdatedState(onEnd)
    val deltaNow by rememberUpdatedState(onDelta); val dragNow by rememberUpdatedState(onDrag)
    Box(modifier.offset(x = at.x - 22.dp, y = at.y - 22.dp).size(44.dp)
        .semantics { contentDescription = label }
        .pointerInput(Unit) {
            detectDragGestures(
                onDragStart = { held = true; finger = atNow; startNow() },
                onDragEnd = { held = false; endNow() }, onDragCancel = { held = false; endNow() },
            ) { change, amount ->
                change.consume()
                val dd = with(d) { DpOffset(amount.x.toDp(), amount.y.toDp()) }
                finger = DpOffset(finger.x + dd.x, finger.y + dd.y)
                deltaNow?.invoke(dd)
                dragNow?.invoke(finger)
            }
        }, contentAlignment = Alignment.Center) {
        if (dot) Box(Modifier.size(size).shadow(4.dp, CircleShape).clip(CircleShape).background(Color.White).padding(3.dp).clip(CircleShape).background(DG.low))
        else Box(Modifier.scale(s).size(size).shadow(6.dp, CircleShape).clip(CircleShape).background(Color.White)
            .border(if (size > 20.dp) 3.dp else 2.5.dp, DG.low, CircleShape))
    }
}

/** "Home" and "Work" at the ends of a drive. */
@Composable
private fun EndLabel(at: DpOffset, icon: String, text: String, dx: Dp) {
    Row(Modifier.offset(x = at.x + dx - 36.dp, y = at.y - 15.dp).height(30.dp).glass(RoundedCornerShape(15.dp), elevation = 10.dp)
        .padding(start = 6.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(20.dp).clip(CircleShape).background(DG.low), contentAlignment = Alignment.Center) { DGIcon(icon, Color.White, 12.dp, stroke = 2.6f) }
        Spacer(Modifier.width(6.dp))
        Text(text, style = DGType.small.copy(fontWeight = FontWeight.SemiBold), color = DG.ink)
    }
}

@Composable
private fun CapsuleButton(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, tint: Color = DG.ink) {
    Box(modifier.size(44.dp).clip(CircleShape).background(DG.ink.copy(alpha = .05f)).clickable(role = Role.Button, onClick = onClick)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) { DGIcon(icon, tint, 20.dp, stroke = 2.4f) }
}

/**
 * A kind chip as the watch editor draws it: the kind's icon in its
 * color, the label, and a blue check that springs in when it is on.
 */
@Composable
fun CheckChip(label: String, icon: String, color: Color, on: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val bg by animateColorAsState(if (on) DG.low.copy(alpha = .08f) else Color.White.copy(alpha = .75f), tween(300), label = "cc")
    val edge by animateColorAsState(if (on) DG.low.copy(alpha = .4f) else DG.hair, tween(300), label = "cce")
    val fg by animateColorAsState(if (on) DG.ink else DG.sub, tween(300), label = "ccf")
    val ck by animateDpAsState(if (on) 22.dp else 0.dp, DG.springy(), label = "cck")
    val shape = RoundedCornerShape(23.dp)
    Row(modifier.height(46.dp).clip(shape).background(bg).border(if (on) 1.5.dp else 1.dp, edge, shape)
        .clickable(role = Role.Checkbox, onClick = onToggle).semantics { stateDescription = if (on) "On" else "Off" }
        .padding(start = 14.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        DGIcon(icon, color, 20.dp, stroke = 2.1f)
        Spacer(Modifier.width(8.dp))
        Text(label, style = PageType.chip.copy(fontSize = 15.sp), color = fg, maxLines = 1)
        Spacer(Modifier.width(if (ck > 1.dp) 6.dp else 4.dp))
        if (ck > 0.5.dp) Box(Modifier.size(ck).clip(CircleShape).background(DG.low), contentAlignment = Alignment.Center) {
            DGIcon("check", Color.White, (ck.value * 13f / 22f).dp, stroke = 3f)
        }
    }
}
