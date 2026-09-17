package com.commutescout.drive

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.stadiamaps.ferrostar.composeui.config.NavigationViewComponentBuilder
import com.stadiamaps.ferrostar.composeui.config.VisualNavigationViewConfig
import com.stadiamaps.ferrostar.composeui.config.withCustomOverlayView
import com.stadiamaps.ferrostar.composeui.config.withSpeedLimitStyle
import com.stadiamaps.ferrostar.composeui.runtime.KeepScreenOnDisposableEffect
import com.stadiamaps.ferrostar.composeui.views.components.speedlimit.SignageStyle
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationCameraMode
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState
import com.stadiamaps.ferrostar.maplibreui.runtime.rememberNavigationMapState
import com.stadiamaps.ferrostar.maplibreui.views.DynamicallyOrientingNavigationView
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.compose.expressions.dsl.const
import org.maplibre.compose.layers.CircleLayer
import org.maplibre.compose.layers.LineLayer
import org.maplibre.compose.expressions.value.LineCap
import org.maplibre.compose.expressions.value.LineJoin
import org.maplibre.spatialk.geojson.LineString
import androidx.compose.foundation.layout.PaddingValues
import com.stadiamaps.ferrostar.maplibreui.runtime.navigationCameraOptions
import org.maplibre.compose.map.MapOptions
import org.maplibre.compose.map.OrnamentOptions
import org.maplibre.compose.sources.GeoJsonData
import org.maplibre.compose.sources.rememberGeoJsonSource
import org.maplibre.compose.style.BaseStyle
import org.maplibre.compose.util.MaplibreComposable
import org.maplibre.spatialk.geojson.Feature
import org.maplibre.spatialk.geojson.FeatureCollection
import org.maplibre.spatialk.geojson.Point
import org.maplibre.spatialk.geojson.Position
import uniffi.ferrostar.Route
import kotlin.math.max

@Composable
fun DriveScreen(model: DriveViewModel) {
    KeepScreenOnDisposableEffect()
    val state by model.state.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    val here by model.here.collectAsStateWithLifecycle()
    val hasPermission by model.hasPermission.collectAsStateWithLifecycle()
    val mapState = rememberNavigationMapState()
    val scope = rememberCoroutineScope()
    var showSettings by remember { mutableStateOf(false) }

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
                try {
                    mapState.cameraState.animateTo(CameraPosition(
                        target = Position(s.place.lon, s.place.lat), zoom = 14.5,
                        padding = PaddingValues(bottom = 220.dp)))
                } catch (e: Exception) {
                    android.util.Log.w("DriveScreen", "pin camera move failed: $e")
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
    var chosenRoute by remember { mutableStateOf<Route?>(null) }

    Box(Modifier.fillMaxSize()) {
        DynamicallyOrientingNavigationView(
            modifier = Modifier.fillMaxSize(),
            baseStyle = BaseStyle.Uri(Backend.STYLE_URL),
            navigationMapState = mapState,
            navigationCameraOptions = navigationCameraOptions().copy(browsingZoom = 14.0),
            viewModel = model,
            config = VisualNavigationViewConfig.Default().withSpeedLimitStyle(SignageStyle.MUTCD),
            views = NavigationViewComponentBuilder.Default().withCustomOverlayView { modifier ->
                if (!uiState.isNavigating()) {
                    BrowsingOverlay(modifier, model, mapState, onSettings = { showSettings = true })
                }
            },
            onTapExit = { model.stopNavigation() },
            mapOptions = MapOptions(ornamentOptions = OrnamentOptions(isCompassEnabled = false, isScaleBarEnabled = false)),
        ) {
            (state as? DriveState.Found)?.let { PinLayer(it.place) }
            if (state is DriveState.Choosing) chosenRoute?.let { RouteLine(it) }
        }

        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            if (uiState.isNavigating()) {
                val ahead by model.alerts.ahead.collectAsStateWithLifecycle()
                val along = remember(uiState.location, uiState.routeGeometry) {
                    val geometry = uiState.routeGeometry ?: return@remember 0.0
                    val loc = uiState.location ?: return@remember 0.0
                    val pts = geometry.map { LatLon(it.lat, it.lng) }
                    AlertsEngine.along(pts, AlertsEngine.cumulativeDistances(pts), LatLon(loc.coordinates.lat, loc.coordinates.lng)).first
                }
                ahead.firstOrNull()?.let { next ->
                    AlertStrip(next, along, ahead.size - 1) { model.alerts.say(next.marker) }
                    Spacer(Modifier.height(96.dp))
                }
            } else when (val s = state) {
                is DriveState.Found -> PlaceCard(s.place, here, model)
                is DriveState.Routing -> Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding()) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.material3.CircularProgressIndicator(Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp)); Text("Finding routes")
                    }
                }
                is DriveState.Choosing -> RoutesCard(s.routes, s.place, model) { chosenRoute = it }
                else -> {}
            }
        }
    }

    if (showSettings) SettingsSheet(model) { showSettings = false }
    error?.let {
        AlertDialog(onDismissRequest = { model.clearError() }, confirmButton = { TextButton({ model.clearError() }) { Text("OK") } },
            title = { Text("Something went wrong") }, text = { Text(it) })
    }
}

private fun zoomFor(dlat: Double, dlon: Double): Double {
    val span = max(dlat, dlon * 0.8).coerceAtLeast(0.001)
    return (Math.log(360.0 / span) / Math.log(2.0) - 1.6).coerceIn(9.0, 15.0)
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

/** Search, settings and locate, floating over the map while browsing. */
@Composable
private fun BrowsingOverlay(modifier: Modifier, model: DriveViewModel, mapState: NavigationMapState, onSettings: () -> Unit) {
    val here by model.here.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    Column(modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.weight(1f)) { SearchBar(model) }
            Spacer(Modifier.width(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RoundIcon(Icons.Default.Settings, "Settings", onSettings)
                RoundIcon(Icons.Default.MyLocation, "My location") { mapState.recenter(isNavigating = false) }
            }
        }
    }
}

@Composable
private fun RoundIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    IconButton(onClick, Modifier.shadow(4.dp, CircleShape).background(MaterialTheme.colorScheme.surface, CircleShape).size(44.dp)) {
        Icon(icon, label, tint = MaterialTheme.colorScheme.primary)
    }
}

/**
 * Find anything: an address, a place, or coordinates typed as
 * "37.35, -121.94". A result becomes a pin with Navigate and Save.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchBar(model: DriveViewModel) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var focused by remember { mutableStateOf(false) }
    var job by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val here by model.here.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()

    fun pick(name: String, lat: Double, lon: Double) {
        focus.clearFocus(); text = ""; results = emptyList()
        model.show(Place(name = name, lat = lat, lon = lon, kind = PlaceKind.recent))
    }

    fun schedule(q: String) {
        job?.cancel(); results = emptyList()
        parseCoordinates(q)?.let { c -> results = listOf(Suggestion("%.5f, %.5f".format(c.lat, c.lon), c.lat, c.lon)); return }
        if (q.length < 2) return
        job = scope.launch {
            delay(250)
            runCatching { Search.suggest(q, here?.let { it.lat to it.lon }) }.getOrNull()?.let { results = it }
        }
    }

    suspend fun submit() {
        parseCoordinates(text)?.let { pick("%.5f, %.5f".format(it.lat, it.lon), it.lat, it.lon); return }
        results.firstOrNull()?.let { pick(it.name, it.lat, it.lon); return }
        val found = runCatching { Search.geocode(text) }.getOrNull()?.firstOrNull()
        if (found != null) pick(found.name, found.lat, found.lon) else model.run { }
    }

    Column {
        TextField(
            value = text, onValueChange = { text = it; schedule(it) },
            modifier = Modifier.fillMaxWidth().shadow(4.dp, RoundedCornerShape(12.dp)).onFocusChanged { focused = it.isFocused },
            placeholder = { Text("Search a place or address", maxLines = 1, overflow = TextOverflow.Ellipsis) },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = { if (text.isNotEmpty()) IconButton({ text = ""; results = emptyList() }) { Icon(Icons.Default.Close, "Clear") } },
            singleLine = true, shape = RoundedCornerShape(12.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { scope.launch { submit() } }),
            colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
        )
        if (focused && text.isEmpty()) {
            Card(Modifier.padding(top = 6.dp).fillMaxWidth()) {
                Column {
                    model.places.recents.take(5).forEach { p -> RowItem(Icons.Default.History, p.shortName, p.name) { pick(p.name, p.lat, p.lon) } }
                    model.places.home?.let { p -> RowItem(Icons.Default.Home, "Home", p.shortName) { pick(p.name, p.lat, p.lon) } }
                    model.places.work?.let { p -> RowItem(Icons.Default.Work, "Work", p.shortName) { pick(p.name, p.lat, p.lon) } }
                    model.places.saved.take(6).forEach { p -> RowItem(Icons.Default.Star, p.shortName, p.name) { pick(p.name, p.lat, p.lon) } }
                    if (places.isEmpty()) Text("Type a place, an address, or coordinates like 37.35, -121.94.",
                        Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else if (focused && results.isNotEmpty()) {
            Card(Modifier.padding(top = 6.dp).fillMaxWidth()) {
                Column { results.forEach { s -> RowItem(Icons.Default.Place, s.name.substringBefore(","), s.name) { pick(s.name, s.lat, s.lon) } } }
            }
        }
    }
}

@Composable
private fun RowItem(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, sub: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != title) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
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

/** The pin's card: what it is, how far, Navigate, Save as Home, Work or a star. */
@Composable
private fun PlaceCard(place: Place, here: LatLon?, model: DriveViewModel) {
    var menu by remember { mutableStateOf(false) }
    Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding(), elevation = CardDefaults.cardElevation(6.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(place.shortName, style = MaterialTheme.typography.titleMedium)
                    Text(place.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                    here?.let { Text(Units.distance(AlertsEngine.meters(it, LatLon(place.lat, place.lon))) + " away",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                IconButton({ model.clearFound() }) { Icon(Icons.Default.Close, "Close") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({ model.routes(place) }, Modifier.weight(1f)) {
                    Icon(Icons.Default.Navigation, null); Spacer(Modifier.width(6.dp)); Text("Navigate")
                }
                Box {
                    OutlinedButton({ menu = true }) { Icon(Icons.Default.Star, "Save") }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem({ Text("Save as Home") }, { model.places.set(PlaceKind.home, place.name, place.lat, place.lon); menu = false })
                        DropdownMenuItem({ Text("Save as Work") }, { model.places.set(PlaceKind.work, place.name, place.lat, place.lon); menu = false })
                        DropdownMenuItem({ Text("Save to favorites") }, { model.places.set(PlaceKind.saved, place.name, place.lat, place.lon); menu = false })
                    }
                }
            }
        }
    }
}

/** The alternatives, fastest first, one tap to go. */
@Composable
private fun RoutesCard(routes: List<Route>, place: Place, model: DriveViewModel, onChosen: (Route) -> Unit) {
    var chosen by remember { mutableStateOf(0) }
    LaunchedEffect(chosen, routes) { routes.getOrNull(chosen)?.let(onChosen) }
    Card(Modifier.padding(12.dp).fillMaxWidth().safeDrawingPadding(), elevation = CardDefaults.cardElevation(6.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("To ${place.shortName}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton({ model.show(place) }) { Icon(Icons.Default.Close, "Close") }
            }
            routes.forEachIndexed { i, route ->
                val seconds = route.steps.sumOf { it.duration }
                val via = route.steps.maxByOrNull { it.distance }?.roadName?.trim()?.substringBefore(";")?.takeIf { it.isNotEmpty() }
                Row(
                    Modifier.fillMaxWidth().clickable { chosen = i }
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
            Button({ model.start(routes[chosen], place) }, Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Navigation, null); Spacer(Modifier.width(6.dp)); Text("Start")
            }
        }
    }
}

/** The next road event on the route, above the trip bar. Tap to hear it again. */
@Composable
private fun AlertStrip(item: Upcoming, along: Double, more: Int, onTap: () -> Unit) {
    val tint = when (item.marker.kind) { "lane_closure" -> Color(0xFFD32F2F); "chain_control" -> Color(0xFF1976D2); "wildfire" -> Color(0xFFF57C00); else -> Color(0xFFF9A825) }
    Card(Modifier.padding(horizontal = 12.dp).fillMaxWidth().clickable(onClick = onTap), elevation = CardDefaults.cardElevation(6.dp)) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Warning, null, tint = tint)
            Spacer(Modifier.width(10.dp))
            Column {
                Text(item.marker.displayTitle, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("in ${Units.distance(max(0.0, item.alongMeters - along))}" + (if (more > 0) ", $more more ahead" else ""),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(model: DriveViewModel, onClose: () -> Unit) {
    var miles by remember { mutableStateOf(Units.useMiles) }
    var spoken by remember { mutableStateOf(model.alerts.spoken) }
    val simulating by model.simulating.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()
    ModalBottomSheet(onDismissRequest = onClose) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Settings", style = MaterialTheme.typography.titleLarge)
            Text("Distances", style = MaterialTheme.typography.labelLarge)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(miles, { miles = true; Units.useMiles = true }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Miles") }
                SegmentedButton(!miles, { miles = false; Units.useMiles = false }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Kilometers") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Speak alerts along the route", Modifier.weight(1f))
                Switch(spoken, { spoken = it; model.alerts.spoken = it })
            }
            Text("Places", style = MaterialTheme.typography.labelLarge)
            if (places.isEmpty()) Text("Search a place, then save it as Home, Work or a favorite.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            model.places.home?.let { PlaceRow("Home", it, model) }
            model.places.work?.let { PlaceRow("Work", it, model) }
            model.places.saved.forEach { PlaceRow("Saved", it, model) }
            if (BuildConfig.DEBUG) Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Simulate driving the route", Modifier.weight(1f))
                Switch(simulating, { model.simulating.value = it })
            }
            Text("About", style = MaterialTheme.typography.labelLarge)
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = MaterialTheme.typography.bodySmall)
            Text("Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PlaceRow(label: String, p: Place, model: DriveViewModel) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(60.dp))
        Text(p.shortName, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        IconButton({ model.places.remove(p) }) { Icon(Icons.Default.Delete, "Remove", tint = MaterialTheme.colorScheme.error) }
    }
}

/** Scripted drive for automated testing: `-e csAutoDrive true` on launch (debug only). */
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
