package com.commutescout.drive

import android.Manifest
import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import android.app.Activity
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.stadiamaps.ferrostar.composeui.config.NavigationViewComponentBuilder
import com.stadiamaps.ferrostar.composeui.config.VisualNavigationViewConfig
import com.stadiamaps.ferrostar.composeui.config.withCustomOverlayView
import com.stadiamaps.ferrostar.composeui.config.withSpeedLimitStyle
import com.stadiamaps.ferrostar.composeui.runtime.KeepScreenOnDisposableEffect
import com.stadiamaps.ferrostar.composeui.views.components.speedlimit.SignageStyle
import com.stadiamaps.ferrostar.maplibreui.NavigationMapClickResult
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationCameraMode
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState
import com.stadiamaps.ferrostar.maplibreui.runtime.navigationCameraOptions
import com.stadiamaps.ferrostar.maplibreui.runtime.rememberNavigationMapState
import com.stadiamaps.ferrostar.maplibreui.views.DynamicallyOrientingNavigationView
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.compose.expressions.dsl.const
import org.maplibre.compose.expressions.value.LineCap
import org.maplibre.compose.expressions.value.LineJoin
import org.maplibre.compose.layers.CircleLayer
import org.maplibre.compose.layers.LineLayer
import org.maplibre.compose.layers.RasterLayer
import org.maplibre.compose.map.GestureOptions
import org.maplibre.compose.map.MapOptions
import org.maplibre.compose.map.OrnamentOptions
import org.maplibre.compose.sources.GeoJsonData
import org.maplibre.compose.sources.TileSetOptions
import org.maplibre.compose.sources.rememberGeoJsonSource
import org.maplibre.compose.sources.rememberRasterSource
import org.maplibre.compose.style.BaseStyle
import org.maplibre.compose.util.ClickResult
import org.maplibre.compose.util.MaplibreComposable
import org.maplibre.spatialk.geojson.Feature
import org.maplibre.spatialk.geojson.FeatureCollection
import org.maplibre.spatialk.geojson.LineString
import org.maplibre.spatialk.geojson.Point
import org.maplibre.spatialk.geojson.Position
import uniffi.ferrostar.Route
import kotlin.math.abs
import kotlin.math.max

@OptIn(kotlinx.coroutines.FlowPreview::class)
@Composable
fun DriveScreen(model: DriveViewModel) {
    val prefs = model.prefs
    if (prefs.keepAwake) KeepScreenOnDisposableEffect()
    val state by model.state.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    val here by model.here.collectAsStateWithLifecycle()
    val hasPermission by model.hasPermission.collectAsStateWithLifecycle()
    val selected by model.selectedMarker.collectAsStateWithLifecycle()
    val siteMarkers by model.markers.markers.collectAsStateWithLifecycle()
    val directMarkers by model.sources.directMarkers.collectAsStateWithLifecycle()
    val hiddenSources by model.sources.hidden.collectAsStateWithLifecycle()
    val allMarkers = (siteMarkers + directMarkers).filter { (it.source ?: "") !in hiddenSources }
    var tool by remember { mutableStateOf<Tool?>(null) }
    var showTools by remember { mutableStateOf(false) }
    val mapState = rememberNavigationMapState()
    val scope = rememberCoroutineScope()
    var showSettings by remember { mutableStateOf(false) }
    var showLayers by remember { mutableStateOf(false) }
    var reportAt by remember { mutableStateOf<LatLon?>(null) }
    var stripCollapsed by remember { mutableStateOf(false) }
    val toastText by model.toast.collectAsStateWithLifecycle()
    val isNavigating = uiState.isNavigating()

    val permissions = if (Build.VERSION.SDK_INT >= 34) arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.FOREGROUND_SERVICE_LOCATION,
    ) else if (Build.VERSION.SDK_INT >= 33) arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.POST_NOTIFICATIONS,
    ) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        model.setLocationPermission(granted[Manifest.permission.ACCESS_FINE_LOCATION] == true)
    }
    LaunchedEffect(Unit) { if (!hasPermission) launcher.launch(permissions) }

    // Ferrostar follows the driver while browsing; a pin or a route
    // preview takes the camera over, and Browsing hands it back.
    LaunchedEffect(state) {
        when (val s = state) {
            is DriveState.Found -> {
                mapState.cameraMode = NavigationCameraMode.FREE
                delay(350)   // let the keyboard finish closing; a resize cancels camera animations
                runCatching {
                    mapState.cameraState.animateTo(CameraPosition(
                        target = Position(s.place.lon, s.place.lat), zoom = max(mapState.cameraState.position.zoom, 14.5),
                        tilt = if (prefs.is3D) 45.0 else 0.0, padding = PaddingValues(bottom = 220.dp)))
                }
            }
            is DriveState.Choosing -> s.routes.firstOrNull()?.let { r ->
                mapState.cameraMode = NavigationCameraMode.FREE
                mapState.cameraState.animateTo(CameraPosition(
                    target = Position((r.bbox.sw.lng + r.bbox.ne.lng) / 2, (r.bbox.sw.lat + r.bbox.ne.lat) / 2),
                    zoom = zoomFor(r.bbox.ne.lat - r.bbox.sw.lat, r.bbox.ne.lng - r.bbox.sw.lng),
                    padding = PaddingValues(top = 120.dp, bottom = 340.dp)))
            }
            is DriveState.Browsing -> mapState.recenter(isNavigating = false)
            else -> {}
        }
    }
    // 2D or 3D, applied to whatever the camera is doing now.
    LaunchedEffect(prefs.is3D) {
        val p = mapState.cameraState.position
        mapState.cameraState.position = p.copy(tilt = if (prefs.is3D) 45.0 else 0.0)
    }
    var chosenRoute by remember { mutableStateOf<Route?>(null) }
    var bearing by remember { mutableStateOf(0.0) }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth; val h = maxHeight
        // The visible area, for loading markers, and the heading for the compass.
        LaunchedEffect(mapState, prefs.apiKinds) {
            snapshotFlow { mapState.cameraState.position }.debounce(400).collect { pos ->
                bearing = pos.bearing
                val proj = mapState.cameraState.projection ?: return@collect
                val a = proj.positionFromScreenLocation(DpOffset(0.dp, 0.dp))
                val b = proj.positionFromScreenLocation(DpOffset(w, h))
                val c = proj.positionFromScreenLocation(DpOffset(w, 0.dp))
                val d = proj.positionFromScreenLocation(DpOffset(0.dp, h))
                val lats = listOf(a, b, c, d).map { it.latitude }; val lons = listOf(a, b, c, d).map { it.longitude }
                model.markers.view(lats.min(), lons.min(), lats.max(), lons.max(), pos.zoom, prefs.apiKinds)
                model.viewCenter = LatLon(pos.target.latitude, pos.target.longitude)
                model.sources.view(LatLon(pos.target.latitude, pos.target.longitude))
            }
        }

        DynamicallyOrientingNavigationView(
            modifier = Modifier.fillMaxSize(),
            baseStyle = BaseStyle.Uri(model.styleUrl),
            navigationMapState = mapState,
            navigationCameraOptions = navigationCameraOptions().copy(browsingZoom = 14.0, navigationTilt = if (prefs.is3D) 45.0 else 0.0),
            viewModel = model,
            config = VisualNavigationViewConfig.Default().withSpeedLimitStyle(SignageStyle.MUTCD),
            views = NavigationViewComponentBuilder.Default().withCustomOverlayView { modifier ->
                if (!uiState.isNavigating()) {
                    BrowsingOverlay(modifier, model, onSettings = { showSettings = true }, onLayers = { showTools = true })
                }
            },
            onTapExit = { model.stopNavigation() },
            onMapClick = { _, _ -> if (selected != null) { model.clearMarker(); NavigationMapClickResult.Consume } else NavigationMapClickResult.Pass },
            onMapLongClick = { position, _ ->
                if (!uiState.isNavigating()) { model.dropPin(position.lat, position.lng); NavigationMapClickResult.Consume } else NavigationMapClickResult.Pass
            },
            mapOptions = MapOptions(
                gestureOptions = GestureOptions(isTiltEnabled = true, isRotateEnabled = true, isQuickZoomEnabled = true),
                ornamentOptions = OrnamentOptions(isCompassEnabled = false, isScaleBarEnabled = false),
            ),
        ) {
            if (prefs.traffic) TrafficLayer()
            MarkerLayers(allMarkers.filter { prefs.isShown(it.kind) }) { key -> model.showMarker(key) }
            (state as? DriveState.Found)?.let { PinLayer(it.place) }
            if (state is DriveState.Choosing) chosenRoute?.let { RouteLine(it) }
        }

        // Map controls: 2D/3D, compass when turned, my location. While
        // navigating Ferrostar draws its own zoom and recenter buttons.
        Column(Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(end = 12.dp,
            bottom = if (isNavigating) 118.dp else bottomCardHeight(state, selected) + 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!isNavigating && abs(bearing) > 1.0) {
                RoundIcon(Icons.Default.Navigation, "Face north", tint = Color(0xFFD32F2F), rotate = -bearing.toFloat(), tag = "compass") {
                    scope.launch { mapState.cameraState.animateTo(mapState.cameraState.position.copy(bearing = 0.0)) }
                }
            }
            RoundText(if (prefs.is3D) "2D" else "3D", tag = "perspective") { model.toggle3D() }
            if (!isNavigating) RoundIcon(Icons.Default.MyLocation, "My location", tag = "locate") { mapState.recenter(isNavigating = false) }
            // Report, like Waze: one tap from anywhere.
            Box(Modifier.shadow(4.dp, CircleShape).background(Color(0xFFF57C00), CircleShape).size(52.dp)
                .clickable { model.reportLatLon?.let { reportAt = it } }.testTag("report"), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Campaign, "Report", tint = Color.White)
            }
        }
        toastText?.let {
            Box(Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = 70.dp)) {
                Text(it, Modifier.background(MaterialTheme.colorScheme.surface, RoundedCornerShape(20.dp)).padding(horizontal = 14.dp, vertical = 10.dp),
                    style = MaterialTheme.typography.bodyMedium)
            }
        }

        // Under the maneuver card and its side controls, clear of the
        // puck, the road name and the trip bar.
        if (isNavigating) {
            val ahead by model.alerts.ahead.collectAsStateWithLifecycle()
            val along by model.alerts.hereAlong.collectAsStateWithLifecycle()
            ahead.firstOrNull()?.takeIf { it.alongMeters - along <= prefs.stripAheadMeters }?.let { next ->
                if (stripCollapsed) {
                    // Tucked away: a pill with the icon and distance; tap to bring it back.
                    Row(Modifier.align(Alignment.TopEnd).safeDrawingPadding().padding(top = 300.dp, end = 12.dp)
                        .shadow(4.dp, RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(20.dp))
                        .clickable { stripCollapsed = false }.padding(horizontal = 10.dp, vertical = 8.dp).testTag("alert-pill"),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(MarkerIcons.icon(next.marker.kind), null, Modifier.size(18.dp), tint = MarkerIcons.color(next.marker.kind))
                        Spacer(Modifier.width(6.dp))
                        Text(Units.distance(max(0.0, next.alongMeters - along)), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                        if (ahead.size > 1) Text(" +${ahead.size - 1}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    Box(Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = 300.dp)) {
                        AlertStrip(next, along, ahead.size - 1, onCollapse = { stripCollapsed = true }) { model.alerts.say(next.marker) }
                    }
                }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            if (isNavigating) {
                // Ferrostar's trip bar owns the bottom while navigating.
            } else if (selected != null) {
                MarkerCard(selected!!, here, model)
            } else when (val s = state) {
                is DriveState.Found -> PlaceCard(s.place, here, model)
                is DriveState.Routing -> Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding()) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp)); Text("Finding routes")
                    }
                }
                is DriveState.Choosing -> RoutesCard(s.routes, s.place, model) { chosenRoute = it }
                else -> {}
            }
        }
    }

    if (showSettings) SettingsSheet(model) { showSettings = false; model.applyPrefs() }
    if (showLayers) LayersSheet(model) { showLayers = false }
    if (showTools) ToolsSheet(onPick = { showTools = false; if (it == Tool.LAYERS) showLayers = true else tool = it }) { showTools = false }
    when (tool) {
        Tool.ALERTS -> AlertsListSheet(model, mapState) { tool = null }
        Tool.DIRECTIONS -> DirectionsSheet(model) { tool = null }
        Tool.WATCHES -> WatchesSheet(model) { tool = null }
        Tool.ASK -> AskSheet(model) { tool = null }
        Tool.SOURCES -> SourcesSheet(model) { tool = null }
        Tool.MARKETPLACE -> MarketplaceSheet(model) { tool = null }
        else -> {}
    }
    reportAt?.let { at -> ReportSheet(model, at.lat, at.lon) { reportAt = null } }
    error?.let {
        AlertDialog(onDismissRequest = { model.clearError() }, confirmButton = { TextButton({ model.clearError() }) { Text("OK") } },
            title = { Text("Something went wrong") }, text = { Text(it) })
    }
}

private fun bottomCardHeight(state: DriveState, selected: RoadMarker?) = when {
    selected != null -> 170.dp
    state is DriveState.Found -> 150.dp
    state is DriveState.Routing -> 80.dp
    state is DriveState.Choosing -> 330.dp
    else -> 0.dp
}

private fun zoomFor(dlat: Double, dlon: Double): Double {
    val span = max(dlat, dlon * 0.8).coerceAtLeast(0.001)
    return (Math.log(360.0 / span) / Math.log(2.0) - 1.6).coerceIn(9.0, 15.0)
}

/** The traffic raster from the site, above the base map. */
@Composable
@MaplibreComposable
private fun TrafficLayer() {
    val source = rememberRasterSource(tiles = listOf(Backend.TRAFFIC_TILES), options = TileSetOptions(maxZoom = 16), tileSize = 256)
    RasterLayer(id = "cs-traffic", source = source, opacity = const(0.75f))
}

/** Live road markers: one source and layer per kind, colored like the website. */
@Composable
@MaplibreComposable
private fun MarkerLayers(markers: List<RoadMarker>, onTap: (String) -> Unit) {
    for (kind in MarkerIcons.kinds) {
        val ofKind = markers.filter { it.kind == kind }
        val source = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(ofKind.map { m ->
            Feature(geometry = Point(Position(m.lon, m.lat)), properties = buildJsonObject { put("key", JsonPrimitive(m.key)) })
        })))
        CircleLayer(
            id = "cs-m-$kind", source = source, color = const(MarkerIcons.color(kind)), radius = const(8.dp),
            strokeColor = const(Color.White), strokeWidth = const(2.dp),
            onClick = { features ->
                val key = features.firstOrNull()?.properties?.get("key")?.let { (it as? JsonPrimitive)?.content }
                if (key != null) { onTap(key); ClickResult.Consume } else ClickResult.Pass
            },
        )
    }
}

@Composable
@MaplibreComposable
private fun PinLayer(place: Place) {
    val source = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
        Feature(geometry = Point(Position(place.lon, place.lat)), properties = buildJsonObject {})
    )))
    CircleLayer(id = "cs-pin-ring", source = source, color = const(Color(0x402E80F7)), radius = const(14.dp))
    CircleLayer(id = "cs-pin", source = source, color = const(Color(0xFF2E80F7)), radius = const(7.dp),
        strokeColor = const(Color.White), strokeWidth = const(2.dp))
}

/** The alternative under consideration, drawn like the navigation route. */
@Composable
@MaplibreComposable
private fun RouteLine(route: Route) {
    val source = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
        Feature(geometry = LineString(route.geometry.map { Position(it.lng, it.lat) }), properties = buildJsonObject {})
    )))
    LineLayer(id = "cs-route-border", source = source, color = const(Color(0xFF1B4FA8)), width = const(9.dp),
        cap = const(LineCap.Round), join = const(LineJoin.Round))
    LineLayer(id = "cs-route", source = source, color = const(Color(0xFF3B82F6)), width = const(6.dp),
        cap = const(LineCap.Round), join = const(LineJoin.Round))
}

/** Search, settings and layers, floating over the map while browsing. */
@Composable
private fun BrowsingOverlay(modifier: Modifier, model: DriveViewModel, onSettings: () -> Unit, onLayers: () -> Unit) {
    Column(modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.weight(1f)) { SearchBar(model) }
            Spacer(Modifier.width(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RoundIcon(Icons.Default.Settings, "Settings", tag = "settings", onClick = onSettings)
                RoundIcon(Icons.Default.Menu, "Tools", tag = "tools", onClick = onLayers)
            }
        }
    }
}

@Composable
private fun RoundIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tint: Color = MaterialTheme.colorScheme.primary,
                      rotate: Float = 0f, tag: String, onClick: () -> Unit) {
    IconButton(onClick, Modifier.shadow(4.dp, CircleShape).background(MaterialTheme.colorScheme.surface, CircleShape).size(44.dp).testTag(tag)) {
        Icon(icon, label, Modifier.rotate(rotate), tint = tint)
    }
}

@Composable
private fun RoundText(text: String, tag: String, onClick: () -> Unit) {
    Box(Modifier.shadow(4.dp, CircleShape).background(MaterialTheme.colorScheme.surface, CircleShape).size(44.dp)
        .clickable(onClick = onClick).testTag(tag), contentAlignment = Alignment.Center) {
        Text(text, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * Find anything: an address, a place, or coordinates typed as
 * "37.35, -121.94". Saved and recent places match instantly; the server
 * is asked after a short pause and older answers never replace newer ones.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchBar(model: DriveViewModel) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var focused by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    var seq by remember { mutableStateOf(0) }
    var job by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val here by model.here.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()

    val q = text.trim().lowercase()
    val local = if (q.isEmpty()) emptyList() else places.filter {
        it.name.lowercase().startsWith(q) || it.shortName.lowercase().startsWith(q) ||
            (it.kind == PlaceKind.home && "home".startsWith(q)) || (it.kind == PlaceKind.work && "work".startsWith(q))
    }.take(3)

    fun pick(name: String, lat: Double, lon: Double) {
        focus.clearFocus(); text = ""; results = emptyList()
        model.show(Place(name = name, lat = lat, lon = lon, kind = PlaceKind.recent))
    }

    fun schedule(raw: String) {
        job?.cancel()
        val t = raw.trim()
        parseCoordinates(t)?.let { c -> results = listOf(Suggestion("%.5f, %.5f".format(c.lat, c.lon), c.lat, c.lon)); return }
        if (t.length < 2) { results = emptyList(); return }
        val mine = ++seq
        job = scope.launch {
            delay(120)
            searching = true
            try {
                val found = runCatching { Search.suggest(t, here?.let { it.lat to it.lon }) }.getOrNull()
                if (found != null && mine == seq) results = found
            } finally { if (mine == seq) searching = false }
        }
    }

    suspend fun submit() {
        val t = text.trim()
        parseCoordinates(t)?.let { pick("%.5f, %.5f".format(it.lat, it.lon), it.lat, it.lon); return }
        local.firstOrNull()?.let { pick(it.name, it.lat, it.lon); return }
        results.firstOrNull()?.let { pick(it.name, it.lat, it.lon); return }
        val found = runCatching { Search.geocode(t) }.getOrNull()?.firstOrNull()
        if (found != null) pick(found.name, found.lat, found.lon)
    }

    Column {
        TextField(
            value = text, onValueChange = { text = it; schedule(it) },
            modifier = Modifier.fillMaxWidth().shadow(4.dp, RoundedCornerShape(12.dp)).onFocusChanged { focused = it.isFocused }.testTag("search"),
            placeholder = { Text("Search a place or address", maxLines = 1, overflow = TextOverflow.Ellipsis) },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = {
                if (searching) CircularProgressIndicator(Modifier.size(18.dp))
                else if (text.isNotEmpty()) IconButton({ text = ""; results = emptyList() }) { Icon(Icons.Default.Close, "Clear") }
            },
            singleLine = true, shape = RoundedCornerShape(12.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { scope.launch { submit() } }),
            colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
        )
        if (focused && text.isEmpty()) {
            // Quick picks in the order the web map uses: Home, Work, up to 5
            // favorites, then the last 10 destinations. Any of them can be removed.
            Card(Modifier.padding(top = 6.dp).fillMaxWidth()) {
                Column(Modifier.heightIn(max = 380.dp).verticalScroll(rememberScrollState())) {
                    model.places.home?.let { p -> RowItem(Icons.Default.Home, "Home", p.shortName, onRemove = { model.places.remove(p) }) { pick(p.name, p.lat, p.lon) } }
                    model.places.work?.let { p -> RowItem(Icons.Default.Work, "Work", p.shortName, onRemove = { model.places.remove(p) }) { pick(p.name, p.lat, p.lon) } }
                    model.places.saved.take(5).forEach { p -> RowItem(Icons.Default.Star, p.shortName, p.name, onRemove = { model.places.remove(p) }) { pick(p.name, p.lat, p.lon) } }
                    model.places.recents.take(10).forEach { p -> RowItem(Icons.Default.History, p.shortName, p.name, onRemove = { model.places.remove(p) }) { pick(p.name, p.lat, p.lon) } }
                    if (places.isEmpty()) Text("Type a place, an address, or coordinates like 37.35, -121.94.",
                        Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else if (focused && text.isNotEmpty()) {
            Card(Modifier.padding(top = 6.dp).fillMaxWidth()) {
                Column {
                    local.forEach { p ->
                        val icon = when (p.kind) { PlaceKind.home -> Icons.Default.Home; PlaceKind.work -> Icons.Default.Work; PlaceKind.saved -> Icons.Default.Star; else -> Icons.Default.History }
                        RowItem(icon, if (p.kind == PlaceKind.home) "Home" else if (p.kind == PlaceKind.work) "Work" else p.shortName, p.name) { pick(p.name, p.lat, p.lon) }
                    }
                    results.forEach { s -> RowItem(Icons.Default.Place, s.name.substringBefore(","), s.name) { pick(s.name, s.lat, s.lon) } }
                    if (results.isEmpty() && local.isEmpty() && !searching && text.length >= 2)
                        Text("Nothing yet. Keep typing, or add a city.", Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun RowItem(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, sub: String, onRemove: (() -> Unit)? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 12.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != title) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onRemove != null) IconButton(onRemove, Modifier.size(36.dp).testTag("remove-place")) {
            Icon(Icons.Default.Close, "Remove $title", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** "37.35, -121.94", "37.35 -121.94", or with N/S/E/W letters. */
fun parseCoordinates(s: String): LatLon? {
    val m = Regex("""^\s*(-?\d{1,2}(?:\.\d+)?)\s*([NS])?\s*[,\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*([EW])?\s*$""")
        .find(s.uppercase().replace("°", " ")) ?: return null
    var lat = m.groupValues[1].toDoubleOrNull() ?: return null
    var lon = m.groupValues[3].toDoubleOrNull() ?: return null
    if (m.groupValues[2] == "S") lat = -Math.abs(lat)
    if (m.groupValues[4] == "W") lon = -Math.abs(lon)
    if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
    return LatLon(lat, lon)
}

private fun share(context: android.content.Context, url: String) {
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, url) }, null))
}

/** The pin's card: what it is, how far, Navigate, Save as Home, Work or a star. */
@Composable
private fun PlaceCard(place: Place, here: LatLon?, model: DriveViewModel) {
    var menu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding().testTag("place-card"), elevation = CardDefaults.cardElevation(6.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(place.shortName, style = MaterialTheme.typography.titleMedium)
                    Text(place.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                    here?.let { Text(Units.distance(AlertsEngine.meters(it, LatLon(place.lat, place.lon))) + " away",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                IconButton({ model.clearFound() }, Modifier.testTag("place-close")) { Icon(Icons.Default.Close, "Close") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({ model.routes(place) }, Modifier.weight(1f).testTag("navigate")) {
                    Icon(Icons.Default.Navigation, null); Spacer(Modifier.width(6.dp)); Text("Navigate")
                }
                Box {
                    OutlinedButton({ menu = true }, Modifier.testTag("save-menu")) { Icon(Icons.Default.Star, "Save") }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem({ Text("Save as Home") }, { model.places.set(PlaceKind.home, place.name, place.lat, place.lon); menu = false })
                        DropdownMenuItem({ Text("Save as Work") }, { model.places.set(PlaceKind.work, place.name, place.lat, place.lon); menu = false })
                        DropdownMenuItem({ Text("Save to favorites") }, { model.places.set(PlaceKind.saved, place.name, place.lat, place.lon); menu = false })
                        DropdownMenuItem({ Text("Share") }, { share(context, Backend.mapUrl(place.lat, place.lon)); menu = false })
                    }
                }
            }
        }
    }
}

/** What a tapped marker says: the website's popup, on the phone. */
@Composable
private fun MarkerCard(marker: RoadMarker, here: LatLon?, model: DriveViewModel) {
    val context = LocalContext.current
    Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding().testTag("marker-card"), elevation = CardDefaults.cardElevation(6.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(MarkerIcons.icon(marker.kind), null, tint = MarkerIcons.color(marker.kind))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(marker.displayTitle, style = MaterialTheme.typography.titleMedium, maxLines = 3)
                    marker.detailLines.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    here?.let { Text(Units.distance(AlertsEngine.meters(it, LatLon(marker.lat, marker.lon))) + " from you",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                IconButton({ model.clearMarker() }) { Icon(Icons.Default.Close, "Close") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({ model.show(Place(name = marker.displayTitle, lat = marker.lat, lon = marker.lon, kind = PlaceKind.recent)) }, Modifier.weight(1f)) {
                    Icon(Icons.Default.Navigation, null); Spacer(Modifier.width(6.dp)); Text("Navigate here")
                }
                OutlinedButton({ share(context, marker.webUrl) }) { Icon(Icons.Default.Share, "Share") }
            }
            if (marker.kind == "plugin") marker.id?.let { ConfirmRow(it, model) }
        }
    }
}

/** Confirm a plugin report or mark it gone, as on the website; sign-in is asked for first. */
@Composable
private fun ConfirmRow(alertId: String, model: DriveViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var voted by remember(alertId) { mutableStateOf<String?>(null) }
    fun vote(v: String) {
        scope.launch {
            val token = model.account.token()
            if (token == null) { (context as? Activity)?.let { model.account.signInWithGoogle(it) }; return@launch }
            runCatching { Reporter.confirm(alertId, v, token) }
                .onSuccess { voted = v; model.toast(if (v == "up") "Thanks, confirmed." else "Thanks, marked as gone.") }
                .onFailure { model.toast(it.message ?: "Could not record that.") }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton({ vote("up") }, Modifier.weight(1f).testTag("confirm-up"), enabled = voted == null) {
            Icon(Icons.Default.ThumbUp, null); Spacer(Modifier.width(6.dp)); Text(if (voted == "up") "Confirmed" else "Still there")
        }
        OutlinedButton({ vote("gone") }, Modifier.weight(1f).testTag("confirm-gone"), enabled = voted == null) {
            Icon(Icons.Default.Clear, null); Spacer(Modifier.width(6.dp)); Text(if (voted == "gone") "Marked gone" else "Gone")
        }
    }
}

/** The alternatives, fastest first, one tap to go. */
@Composable
private fun RoutesCard(routes: List<Route>, place: Place, model: DriveViewModel, onChosen: (Route) -> Unit) {
    var chosen by remember { mutableStateOf(0) }
    LaunchedEffect(chosen, routes) { routes.getOrNull(chosen)?.let(onChosen) }
    Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding().testTag("routes-card"), elevation = CardDefaults.cardElevation(6.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("To ${place.shortName}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton({ model.show(place) }, Modifier.testTag("routes-close")) { Icon(Icons.Default.Close, "Close") }
            }
            routes.forEachIndexed { i, route ->
                val seconds = route.steps.sumOf { it.duration }
                val via = route.steps.maxByOrNull { it.distance }?.roadName?.trim()?.substringBefore(";")?.takeIf { it.isNotEmpty() }
                Row(
                    Modifier.fillMaxWidth().clickable { chosen = i }.testTag("route-$i")
                        .background(if (i == chosen) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent, RoundedCornerShape(10.dp))
                        .padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(if (i == 0) "Fastest" else "Alternate $i", fontWeight = FontWeight.SemiBold)
                        Text("${Units.duration(seconds)}, ${Units.distance(route.distance)}" + (via?.let { ", via $it" } ?: ""),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (i == chosen) Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                }
            }
            Button({ model.start(routes[chosen], place) }, Modifier.fillMaxWidth().testTag("start")) {
                Icon(Icons.Default.Navigation, null); Spacer(Modifier.width(6.dp)); Text("Start")
            }
        }
    }
}

/** The next road event on the route, above the trip bar. Tap to hear it again. */
@Composable
private fun AlertStrip(item: Upcoming, along: Double, more: Int, onCollapse: (() -> Unit)? = null, onTap: () -> Unit) {
    Card(Modifier.padding(horizontal = 12.dp).fillMaxWidth().clickable(onClick = onTap).testTag("alert-strip"), elevation = CardDefaults.cardElevation(6.dp)) {
        Row(Modifier.padding(start = 14.dp, end = 6.dp, top = 10.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(MarkerIcons.icon(item.marker.kind), null, tint = MarkerIcons.color(item.marker.kind))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(item.marker.displayTitle, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("in ${Units.distance(max(0.0, item.alongMeters - along))}" + (if (more > 0) ", $more more ahead" else ""),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (onCollapse != null) IconButton(onCollapse, Modifier.size(32.dp).testTag("alert-collapse")) {
                Icon(Icons.Default.KeyboardArrowUp, "Hide", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** What the map shows: the same layers as the website's Layers tool. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LayersSheet(model: DriveViewModel, onClose: () -> Unit) {
    val prefs = model.prefs
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("layers-sheet")) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Layers", style = MaterialTheme.typography.titleLarge)
            Heading("Base map")
            Choice("Style", Prefs.MapStyle.entries.map { it.label }, prefs.mapStyle.ordinal) { prefs.mapStyle = Prefs.MapStyle.entries[it] }
            ToggleRow("Traffic", prefs.traffic) { prefs.traffic = it }
            ToggleRow("3D perspective", prefs.is3D) { model.toggle3D() }
            Heading("On the road")
            Prefs.layerKinds.forEach { k -> ToggleRow(k.label, prefs.isShown(k.key)) { prefs.setShown(k.key, it); model.markers.refresh(true) } }
            LinkRow("Where this data comes from") { context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://commutescout.com/data-sources"))) }
        }
    }
}

/** Scripted drive for automated testing: `--ez csAutoDrive true` on launch (debug only). */
object AutoDrive {
    fun run(model: DriveViewModel) {
        android.util.Log.i("AutoDrive", "scripted drive requested")
        model.simulating.value = true
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            delay(3000)
            val place = Place(name = "Los Altos, CA", lat = 37.372, lon = -122.110, kind = PlaceKind.recent)
            model.show(place)
            delay(1500)
            model.routes(place)
            var tries = 0
            while (model.state.value !is DriveState.Choosing && tries++ < 40) delay(500)
            android.util.Log.i("AutoDrive", "state after routing: ${model.state.value::class.simpleName}")
            (model.state.value as? DriveState.Choosing)?.let { c -> model.start(c.routes.first(), c.place) }
        }
    }
}
