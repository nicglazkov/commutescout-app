package com.commutescout.drive

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.ferrostar.Route

/*
 * The trip pages in Day Glass+: search, the place sheet, the routes
 * sheet with leave later, finding routes, resume, and the arrive sheet.
 * The report sheet lives in Report.kt.
 */

/** "8:42 AM" in the phone's own clock style. */
internal fun clockOf(ms: Long): String = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(ms))

/** The route's longest road, the one it goes "via". */
internal fun viaOf(route: Route): String? =
    route.steps.maxByOrNull { it.distance }?.roadName?.trim()?.substringBefore(";")?.takeIf { it.isNotEmpty() }

internal fun secondsOf(route: Route): Double = route.steps.sumOf { it.duration }

private val capsule = RoundedCornerShape(28.dp)

// search

/**
 * The capsule over the map. Browsing it is the search field; with a
 * place found it names the place; choosing a route it names the trip.
 */
@Composable
internal fun TripCapsule(model: DriveViewModel, onSettings: () -> Unit, focused: MutableState<Boolean>) {
    val state by model.state.collectAsStateWithLifecycle()
    when (val s = state) {
        is DriveState.Found -> PlaceCapsule(s.place.shortName, onBack = { model.clearFound(); focused.value = true }, onClose = { model.clearFound() })
        is DriveState.Choosing -> RouteCapsule(s.place.shortName) { model.show(s.place) }
        else -> SearchPanel(model, onSettings, focused)
    }
}

@Composable
private fun PlaceCapsule(name: String, onBack: () -> Unit, onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(54.dp).glass(capsule, elevation = 18.dp, strong = true).padding(start = 5.dp, end = 7.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BackDisc("Search again", onBack)
        Spacer(Modifier.width(6.dp))
        Text(name, Modifier.weight(1f).tag("search"), style = DGType.search, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        GhostRound("close", "Close", onClose, Modifier.tag("place-close"), size = 40.dp)
    }
}

@Composable
private fun RouteCapsule(name: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(62.dp).glass(RoundedCornerShape(31.dp), elevation = 18.dp, strong = true).padding(start = 9.dp, end = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BackDisc("Back to the place", onBack, Modifier.tag("routes-close"))
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text("From your location", style = DGType.small.copy(fontSize = DGType.label.fontSize), color = DG.sub, maxLines = 1)
            Text(name, Modifier.tag("search"), style = DGType.row.copy(fontSize = DGType.search.fontSize), color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun BackDisc(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val src = remember { MutableInteractionSource() }
    Box(modifier.press(src).size(44.dp).clip(CircleShape).clickable(src, null, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center) { DGIcon("back", DG.ink, 22.dp) }
}

/** What a search result row shows. */
private data class Hit(val icon: String, val tone: Tone, val name: String, val sub: String?, val lat: Double, val lon: Double, val full: String, val place: Place? = null)

/**
 * Find anything: an address, a place, or coordinates typed as
 * "37.35, -121.94". Saved and recent places match instantly; the server
 * is asked after a short pause and older answers never replace newer ones.
 */
@Composable
private fun SearchPanel(model: DriveViewModel, onSettings: () -> Unit, focusedState: MutableState<Boolean>) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var focused by focusedState
    var searching by remember { mutableStateOf(false) }
    var seq by remember { mutableStateOf(0) }
    var job by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val requester = remember { FocusRequester() }
    val here by model.here.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()
    // Back from a place card lands here with the field ready to type.
    LaunchedEffect(Unit) { if (focused) runCatching { requester.requestFocus() } }

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
        if (t.length < 2) { results = emptyList(); searching = false; return }
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
        if (t.isEmpty()) return
        val result = runCatching { Search.geocode(t) }
        val found = result.getOrNull()?.firstOrNull()
        // No answer is not the same as no match, so they read differently.
        if (found != null) pick(found.name, found.lat, found.lon)
        else model.showError(when {
            result.isSuccess -> "Nothing found for \"$t\". Try adding a city."
            !Connectivity.online.value || Connectivity.isOffline(result.exceptionOrNull()) -> OfflineText.SEARCH
            else -> "Search is not answering right now. Try again in a moment."
        })
    }

    val veil by animateFloatAsState(if (focused) 1f else 0f, tween(260), label = "veil")
    Column(Modifier.fillMaxWidth().drawBehind {
        // The map steps back while the list is open.
        if (veil > 0f) drawRect(Color(0xFFECF1F6).copy(alpha = .72f * veil), topLeft = androidx.compose.ui.geometry.Offset(-2000f, -2000f),
            size = androidx.compose.ui.geometry.Size(size.width + 4000f, 8000f))
    }) {
        Row(Modifier.fillMaxWidth().height(54.dp).glass(capsule, elevation = 18.dp, strong = true)
            .padding(start = if (focused) 5.dp else 18.dp, end = 7.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (focused) BackDisc("Close search", { text = ""; results = emptyList(); focus.clearFocus() })
            else DGIcon("search", DG.ink, 22.dp)
            Spacer(Modifier.width(if (focused) 6.dp else 12.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty()) Text(if (focused) "Search places" else "Where to?", style = DGType.search, color = DG.sub, maxLines = 1)
                BasicTextField(
                    value = text, onValueChange = { text = it; schedule(it) },
                    modifier = Modifier.fillMaxWidth().focusRequester(requester).onFocusChanged { focused = it.isFocused }.tag("search"),
                    textStyle = DGType.search.copy(color = DG.ink), singleLine = true, cursorBrush = SolidColor(DG.low),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { scope.launch { submit() } }),
                )
            }
            when {
                searching -> CircularProgressIndicator(Modifier.padding(horizontal = 11.dp).size(18.dp), color = DG.low, strokeWidth = 2.dp)
                text.isNotEmpty() -> GhostRound("close", "Clear", { text = ""; results = emptyList() }, size = 40.dp)
                !focused -> GhostRound("gear", "Settings", onSettings, Modifier.tag("settings"), size = 40.dp, tint = DG.ink)
            }
        }
        AnimatedVisibility(focused, enter = fadeIn(tween(220)) + expandVertically(DG.snap(), expandFrom = Alignment.Top),
            exit = fadeOut(tween(160)) + shrinkVertically(tween(220, easing = DG.hideEase), shrinkTowards = Alignment.Top)) {
            Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState())) {
                QuickTiles(model, here) { p -> pick(p.name, p.lat, p.lon) }
                if (text.isEmpty()) {
                    // Up to 5 favorites, then the last 10 destinations, as on the web map. Any can be removed.
                    val rows = model.places.saved.take(5).map { Hit("star", Tone.MID, it.shortName, it.name.substringAfter(",", "").trim().ifEmpty { null }, it.lat, it.lon, it.name, it) } +
                        model.places.recents.take(10).map { Hit("recent", Tone.CLEAR, it.shortName, it.name.substringAfter(",", "").trim().ifEmpty { null }, it.lat, it.lon, it.name, it) }
                    if (rows.isNotEmpty()) ResultList(rows, "", here, onRemove = { model.places.remove(it) }) { pick(it.full, it.lat, it.lon) }
                } else {
                    val rows = local.map { p ->
                        val (icon, tone) = when (p.kind) { PlaceKind.home -> "home" to Tone.LOW; PlaceKind.work -> "work" to Tone.LOW; PlaceKind.saved -> "star" to Tone.MID; else -> "recent" to Tone.CLEAR }
                        Hit(icon, tone, if (p.kind == PlaceKind.home) "Home" else if (p.kind == PlaceKind.work) "Work" else p.shortName, p.name, p.lat, p.lon, p.name)
                    } + results.map { s -> Hit("pin", Tone.LOW, s.name.substringBefore(","), s.name.substringAfter(",", "").trim().ifEmpty { null }, s.lat, s.lon, s.name) }
                    if (rows.isNotEmpty()) ResultList(rows, text, here) { pick(it.full, it.lat, it.lon) }
                    else if (!searching && text.trim().length >= 2) Box(Modifier.padding(top = 8.dp).fillMaxWidth().glass(capsule, elevation = 18.dp, strong = true)) {
                        Text("Nothing yet. Keep typing, or add a city.", Modifier.padding(horizontal = 20.dp, vertical = 18.dp), style = DGType.body, color = DG.sub)
                    }
                }
                Hint(exampleCoordsNear(here))
            }
        }
    }
}

/** Home and Work, side by side, one tap each. Each has a small remove. */
@Composable
private fun QuickTiles(model: DriveViewModel, here: LatLon?, onPick: (Place) -> Unit) {
    val tiles = listOfNotNull(model.places.home?.let { Triple("home", "Home", it) }, model.places.work?.let { Triple("work", "Work", it) })
    if (tiles.isEmpty()) return
    Row(Modifier.padding(top = 10.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        tiles.forEach { (icon, label, p) ->
            val src = remember { MutableInteractionSource() }
            Row(Modifier.weight(1f).press(src).height(58.dp).glass(RoundedCornerShape(29.dp), elevation = 16.dp, strong = true)
                .clickable(src, null, role = Role.Button) { onPick(p) }.padding(start = 9.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(CircleShape).background(DG.low.tint(.12f)), contentAlignment = Alignment.Center) { DGIcon(icon, DG.low, 20.dp) }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(label, style = DGType.row, color = DG.ink, maxLines = 1)
                    val sub = here?.let { Units.distance(AlertsEngine.meters(it, LatLon(p.lat, p.lon))) } ?: p.shortName
                    Text(sub, style = DGType.small, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                RemoveX(label) { model.places.remove(p) }
            }
        }
    }
}

@Composable
private fun RemoveX(title: String, onRemove: () -> Unit) {
    Box(Modifier.size(36.dp).clip(CircleShape).clickable(role = Role.Button, onClick = onRemove).tag("remove-place")
        .semantics { contentDescription = "Remove $title" }, contentAlignment = Alignment.Center) {
        DGIcon("close", DG.faint, 15.dp)
    }
}

/** Search results in glass: the typed part of each name in bold, how far on the right. */
@Composable
private fun ResultList(rows: List<Hit>, typed: String, here: LatLon?, onRemove: ((Place) -> Unit)? = null, onPick: (Hit) -> Unit) {
    Column(Modifier.padding(top = 8.dp).fillMaxWidth().glass(capsule, elevation = 18.dp, strong = true).padding(vertical = 6.dp)) {
        rows.forEachIndexed { i, h ->
            if (i > 0) Box(Modifier.padding(start = 70.dp, end = 16.dp).fillMaxWidth().height(0.5.dp).background(DG.hair))
            Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable { onPick(h) }.padding(start = 14.dp, end = if (h.place != null && onRemove != null) 4.dp else 16.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(CircleShape).background(if (h.tone == Tone.CLEAR) DG.wash else h.tone.color.tint(.12f)), contentAlignment = Alignment.Center) {
                    DGIcon(h.icon, if (h.tone == Tone.CLEAR) DG.sub else h.tone.color, 20.dp)
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    val n = TripText.boldPrefix(h.name, typed)
                    Text(buildAnnotatedString {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(h.name.take(n)) }
                        append(h.name.drop(n))
                    }, style = DGType.row.copy(fontWeight = FontWeight.Medium), color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    h.sub?.takeIf { it != h.name }?.let { Text(it, style = PageType.rowSub, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
                here?.let {
                    Spacer(Modifier.width(8.dp))
                    Text(Units.distance(AlertsEngine.meters(it, LatLon(h.lat, h.lon))),
                        style = DGType.row.copy(fontSize = DGType.alertBody.fontSize.times(15.5f / 14.5f), fontWeight = FontWeight.Bold), color = DG.ink, maxLines = 1)
                }
                if (h.place != null && onRemove != null) RemoveX(h.name) { onRemove(h.place) }
            }
        }
    }
}

@Composable
private fun Hint(coords: String) {
    Text(buildAnnotatedString {
        append("Search a place, an address, or coordinates like ")
        withStyle(SpanStyle(fontFamily = DGType.mono.fontFamily, color = DG.sub)) { append(coords) }
        append(".")
    }, Modifier.padding(start = 18.dp, end = 18.dp, top = 12.dp, bottom = 8.dp), style = DGType.small.copy(fontSize = DGType.label.fontSize), color = DG.faint)
}

/** Coordinates near the driver for the search hint, so an example reads as local anywhere in the country. */
internal fun exampleCoordsNear(here: LatLon?): String {
    val p = here ?: LatLon(39.74, -104.99)
    return String.format(java.util.Locale.US, "%.2f, %.2f", Math.round(p.lat * 100) / 100.0 + 0.01, Math.round(p.lon * 100) / 100.0 - 0.01)
}

// place

/**
 * The place sheet: what and where, how long the drive is and when you
 * would get there, what is on the way, Save, Watch this area, Share, and
 * the two ways on: the routes, or Go on the first one.
 */
@Composable
internal fun PlaceSheet(place: Place, here: LatLon?, model: DriveViewModel, onWatch: () -> Unit) {
    val context = LocalContext.current
    val preview by model.preview.collectAsStateWithLifecycle()
    val way by model.onTheWay.collectAsStateWithLifecycle()
    val mine = preview?.takeIf { Math.abs(it.lat - place.lat) < 1e-5 && Math.abs(it.lon - place.lon) < 1e-5 }
    val route = mine?.routes?.firstOrNull()
    var saving by remember(place) { mutableStateOf(false) }
    FitSheet(Modifier.tag("place-card"), onDismiss = { model.clearFound() }) {
        SheetHead(place.shortName, place.name.substringAfter(",", "").trim().ifEmpty { null },
            lead = { Disc("pin", Tone.LOW) })
        // The drive: minutes, via, arrive at. Only what the route says.
        Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 22.dp, top = 14.dp), verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f)) {
                if (route != null) {
                    val min = routeMinutes(secondsOf(route)).coerceAtLeast(1)
                    Row(verticalAlignment = Alignment.Bottom) {
                        if (min >= 60) {
                            Text("${min / 60}", style = DGType.maneuverDist, color = DG.ink)
                            Text(" h ", Modifier.padding(bottom = 3.dp), style = DGType.maneuverUnit, color = DG.ink)
                            if (min % 60 > 0) { Text("${min % 60}", style = DGType.maneuverDist, color = DG.ink); Text(" min", Modifier.padding(bottom = 3.dp), style = DGType.maneuverUnit, color = DG.ink) }
                        } else {
                            Text("$min", style = DGType.maneuverDist, color = DG.ink)
                            Text(" min", Modifier.padding(bottom = 3.dp), style = DGType.maneuverUnit, color = DG.ink)
                        }
                    }
                    Text(listOfNotNull(Units.distance(route.distance), viaOf(route)?.let { "via $it" }).joinToString(" · "),
                        Modifier.padding(top = 4.dp), style = DGType.alertBody, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
                } else {
                    val away = here?.let { Units.distance(AlertsEngine.meters(it, LatLon(place.lat, place.lon))) + " away" }
                    if (away != null) Text(away, style = DGType.alertTitle, color = DG.ink)
                    Text(if (mine == null) "Checking the drive" else "Drive time is not available right now",
                        Modifier.padding(top = 4.dp), style = DGType.alertBody, color = DG.faint)
                }
            }
            if (route != null) Text("Arrive " + clockOf(System.currentTimeMillis() + (secondsOf(route) * 1000).toLong()),
                Modifier.padding(bottom = 2.dp), style = DGType.alertBody.copy(fontWeight = FontWeight.SemiBold), color = DG.ink)
        }
        // On the way: real events near the first route, nearest first.
        val events = way.firstOrNull().orEmpty().take(2)
        if (events.isNotEmpty()) {
            SheetLabel("On the way", dot = events.first().let { Looks.of(it.marker).tone.color })
            Column(Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                events.forEach { u -> WayRow(u) { model.showMarker(u.marker) } }
            }
        }
        // Save, Watch this area, Share.
        Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            DGButton("Save", { saving = !saving }, Modifier.weight(1f).tag("save-menu"), icon = "star")
            DGButton("Watch this area", onWatch, Modifier.weight(1.6f).tag("watch-area"), icon = "watch")
            ShareRound { share(context, Backend.mapUrl(place.lat, place.lon)) }
        }
        AnimatedVisibility(saving, enter = fadeIn(tween(200)) + expandVertically(DG.snap()), exit = fadeOut(tween(140)) + shrinkVertically(tween(200))) {
            SaveChoices(place) { kind -> model.places.set(kind, place.name, place.lat, place.lon); saving = false
                model.toast(when (kind) { PlaceKind.home -> "Saved as Home."; PlaceKind.work -> "Saved as Work."; else -> "Saved to favorites." }) }
        }
        Spacer(Modifier.height(14.dp))
        SheetActions {
            DGButton(TripText.routesLabel(mine?.routes?.size), { model.routes(place) }, Modifier.weight(1f).tag("navigate"), icon = "reroute")
            DGButton("Go", { model.go(place) }, Modifier.weight(1.6f).tag("go"), style = BtnStyle.PRIMARY, icon = "nav")
        }
    }
}

/** Where a saved place goes: Home, Work or the favorites. */
@Composable
private fun SaveChoices(place: Place, onSave: (PlaceKind) -> Unit) {
    Column(Modifier.padding(start = 14.dp, end = 14.dp, top = 8.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp))
        .background(Color.White.copy(alpha = .82f)).border(1.dp, DG.hair, RoundedCornerShape(22.dp))) {
        listOf(Triple("home", "Save as Home", PlaceKind.home), Triple("work", "Save as Work", PlaceKind.work), Triple("star", "Save to favorites", PlaceKind.saved))
            .forEachIndexed { i, (icon, label, kind) ->
                if (i > 0) Box(Modifier.padding(start = 54.dp).fillMaxWidth().height(0.5.dp).background(DG.hair))
                Row(Modifier.fillMaxWidth().height(50.dp).clickable { onSave(kind) }.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    DGIcon(icon, if (kind == PlaceKind.saved) DG.mid else DG.low, 20.dp)
                    Spacer(Modifier.width(18.dp))
                    Text(label, style = PageType.rowLabel, color = DG.ink)
                }
            }
    }
}

@Composable
private fun ShareRound(onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    Box(Modifier.press(src).size(DG.btnH).clip(CircleShape).background(Color.White.copy(alpha = .75f)).border(0.5.dp, DG.edge, CircleShape)
        .clickable(src, null, role = Role.Button, onClick = onClick).semantics { contentDescription = "Share" }.tag("share-place"),
        contentAlignment = Alignment.Center) { DGIcon("share", DG.ink, 20.dp) }
}

/** One event on the way, tinted by how much it matters, with its lane drawing. */
@Composable
private fun WayRow(u: Upcoming, onClick: () -> Unit) {
    val words = AlertWords.of(u.marker, u.alongMeters, 0.0)
    val tone = words.look.tone
    val shape = RoundedCornerShape(26.dp)
    Row(Modifier.fillMaxWidth().clip(shape).background(tone.color.tint(.07f)).border(1.dp, tone.color.copy(alpha = .18f), shape)
        .clickable(onClick = onClick).padding(start = 8.dp, end = 16.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        AlertThumb(words, u.marker, 60.dp to 42.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(TripText.eventTitle(u.marker), style = DGType.row.copy(fontSize = DGType.alertBody.fontSize.times(15.5f / 14.5f)), color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            words.line?.takeIf { it != u.marker.route }?.let { Text(it, style = PageType.note, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        Spacer(Modifier.width(8.dp))
        val delay = u.marker.delay_min?.takeIf { it >= 1 }?.let { Math.round(it).toInt() }
        Column(horizontalAlignment = Alignment.End) {
            if (delay != null) {
                Text("+$delay", style = DGType.row.copy(fontWeight = FontWeight.Bold), color = tone.ink)
                Text("min", style = PageType.note, color = DG.sub)
            } else {
                val d = Units.distance(u.alongMeters)
                Text(d.substringBefore(" "), style = DGType.row.copy(fontWeight = FontWeight.Bold), color = tone.ink)
                Text(d.substringAfter(" ", ""), style = PageType.note, color = DG.sub)
            }
        }
    }
}

// routes

/** The alternatives, fastest first, a highlight that slides to the one chosen, leave later, and Start. */
@Composable
internal fun RoutesSheet(routes: List<Route>, place: Place, model: DriveViewModel, onChosen: (Route) -> Unit) {
    var chosen by remember(routes) { mutableStateOf(0) }
    LaunchedEffect(chosen, routes) { routes.getOrNull(chosen)?.let(onChosen) }
    LaunchedEffect(place) { model.loadLeaveLater(place) }
    val leave by model.leaveLater.collectAsStateWithLifecycle()
    val events = remember(routes) { routes.map { model.eventsOn(it) } }
    FitSheet(Modifier.tag("routes-card"), onDismiss = { model.show(place) }) {
        Text("Routes to ${place.shortName}", Modifier.padding(horizontal = 22.dp).padding(bottom = 6.dp), style = PageType.groupHead, color = DG.sub)
        val step = 78.dp
        val y by animateDpAsState(step * chosen, DG.snap(), label = "routeHi")
        Box(Modifier.fillMaxWidth().padding(horizontal = 14.dp)) {
            Box(Modifier.offset(y = y).fillMaxWidth().height(74.dp).clip(RoundedCornerShape(22.dp)).background(DG.low.copy(alpha = .08f))
                .border(1.5.dp, DG.low.copy(alpha = .45f), RoundedCornerShape(22.dp)))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                routes.forEachIndexed { i, r -> RouteRow(r, i, i == chosen, events.getOrNull(i).orEmpty()) { chosen = i } }
            }
        }
        val answer = leave?.takeIf { it.first.lat == place.lat && it.first.lon == place.lon }?.second
        AnimatedVisibility(answer != null, enter = fadeIn(tween(240)) + expandVertically(DG.snap()), exit = fadeOut()) {
            answer?.let { LeaveLaterRow(it) }
        }
        Spacer(Modifier.height(14.dp))
        // The map along the route, for a drive through a dead zone. Saved
        // on its own on Wi-Fi when the trip starts; this is the tap for
        // mobile data, and it says so.
        val online by Connectivity.online.collectAsStateWithLifecycle()
        val wifi by Connectivity.onWifi.collectAsStateWithLifecycle()
        val saving by MapFiles.progress.collectAsStateWithLifecycle()
        SheetActions {
            val route = routes.getOrNull(chosen)
            if (online && saving.isNotEmpty()) SaveMapRound(saving.values.first(), "Saving the map for this trip") {}
            else if (online && !(wifi && model.prefs.mapAutoSave) && route != null)
                SaveMapRound(null, if (wifi) "Save the map for this trip" else "Save the map for this trip (mobile data)") { model.saveTripMap(route, place, manual = true) }
            StartButton(route?.let { "Arrive " + clockOf(System.currentTimeMillis() + (secondsOf(it) * 1000).toLong()) }, Modifier.weight(1f)) {
                route?.let { model.start(it, place) }
            }
        }
    }
}

@Composable
private fun RouteRow(r: Route, i: Int, selected: Boolean, events: List<Upcoming>, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(74.dp).clip(RoundedCornerShape(22.dp)).clickable(onClick = onClick).tag("route-$i")
        .padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(viaOf(r)?.let { "via $it" } ?: "Route ${i + 1}",
                    Modifier.weight(1f, fill = false), style = DGType.row, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (i == 0) {
                    Spacer(Modifier.width(8.dp))
                    Text("Fastest", Modifier.clip(RoundedCornerShape(8.dp)).background(DG.good.copy(alpha = .1f)).padding(horizontal = 7.dp, vertical = 2.dp),
                        style = PageType.tag, color = DG.goodInk)
                }
            }
            Spacer(Modifier.height(6.dp))
            if (events.isEmpty()) Text("Nothing reported on the way", style = DGType.small, color = DG.faint, maxLines = 1)
            else Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // One chip per kind of event, with how many there are.
                val kinds = events.groupBy { TripText.eventNoun(it.marker) }.entries.toList()
                kinds.take(2).forEach { (noun, list) ->
                    val u = list.first()
                    val look = Looks.of(u.marker)
                    Row(Modifier.height(26.dp).clip(RoundedCornerShape(13.dp)).background(look.tone.color.tint(.09f)).padding(start = 4.dp, end = 9.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Disc(look.icon, look.tone, 18.dp)
                        Spacer(Modifier.width(5.dp))
                        Text(if (list.size > 1) "$noun ×${list.size}" else noun, style = PageType.tag, color = look.tone.ink, maxLines = 1)
                    }
                }
                if (kinds.size > 2) Text("+${kinds.drop(2).sumOf { it.value.size }}", Modifier.align(Alignment.CenterVertically), style = PageType.tag, color = DG.sub)
            }
        }
        Spacer(Modifier.width(10.dp))
        Column(horizontalAlignment = Alignment.End) {
            Text(Units.duration(secondsOf(r)), style = DGType.cardTitle, color = if (selected) DG.lowInk else DG.ink, maxLines = 1)
            Text(Units.distance(r.distance), style = DGType.small.copy(fontSize = DGType.label.fontSize), color = DG.sub)
        }
    }
}

/** Leave later: the best time to go within the hour, and, opened, the drive time for each. */
@Composable
private fun LeaveLaterRow(a: LeaveLaterAnswer) {
    var open by remember { mutableStateOf(false) }
    val turn by animateFloatAsState(if (open) 180f else 0f, DG.snap(), label = "llChev")
    val h24 = android.text.format.DateFormat.is24HourFormat(LocalContext.current)
    val saves = (a.best?.saving_min ?: 0) > 0
    Column {
        SheetLabel("Leave later")
        val shape = RoundedCornerShape(20.dp)
        Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape)
            .background(if (saves) DG.good.copy(alpha = .07f) else DG.wash)
            .border(1.dp, if (saves) DG.good.copy(alpha = .2f) else DG.hair, shape)
            .clickable { open = !open }.tag("leave-later").padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Disc("recent", if (saves) Tone.GOOD else Tone.CLEAR, DG.discSm)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(LeaveLater.title(a, h24 = h24), style = DGType.row.copy(fontSize = DGType.alertBody.fontSize.times(15.5f / 14.5f)),
                        color = if (saves) DG.goodInk else DG.ink)
                    val sub = if (open) "Drive time by when you leave" else a.reason ?: "Drive time by when you leave"
                    Text(sub, style = DGType.small.copy(fontSize = DGType.label.fontSize, fontWeight = FontWeight.Medium), color = DG.sub)
                }
                DGIcon("chevron", DG.chev, 20.dp, Modifier.rotate(turn))
            }
            AnimatedVisibility(open, enter = fadeIn(tween(200)) + expandVertically(DG.snap()), exit = fadeOut(tween(140)) + shrinkVertically(tween(220))) {
                LeaveBars(LeaveLater.bars(a, h24 = h24))
            }
        }
    }
}

@Composable
private fun LeaveBars(bars: List<LeaveLater.Bar>) {
    Row(Modifier.padding(top = 14.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
        bars.forEachIndexed { i, b ->
            // Bars grow from the floor one after another.
            val grow = remember { Animatable(0f) }
            LaunchedEffect(Unit) { delay(40L * i); grow.animateTo(1f, DG.springy()) }
            val color = when { b.best -> DG.good; b.now -> DG.low.copy(alpha = .45f); else -> DG.ink.copy(alpha = .1f) }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${b.minutes}", style = DGType.tiny, color = if (b.best) DG.goodInk else DG.sub)
                Spacer(Modifier.height(3.dp))
                Box(Modifier.height(64.dp), contentAlignment = Alignment.BottomCenter) {
                    Box(Modifier.width(18.dp).fillMaxHeight(b.height)
                        .graphicsLayer { scaleY = grow.value; transformOrigin = TransformOrigin(.5f, 1f) }
                        .clip(RoundedCornerShape(topStart = 9.dp, topEnd = 9.dp, bottomStart = 4.dp, bottomEnd = 4.dp)).background(color))
                }
                Spacer(Modifier.height(5.dp))
                Text(b.label, style = DGType.tiny.copy(fontWeight = if (b.best) FontWeight.Bold else FontWeight.Medium), color = if (b.best) DG.goodInk else DG.sub, maxLines = 1)
            }
        }
    }
}

/** The round download button; while saving, a ring shows how far along it is. */
@Composable
private fun SaveMapRound(progress: Float?, label: String, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    Box(Modifier.press(src).size(DG.btnH).clip(CircleShape).background(Color.White.copy(alpha = .75f)).border(0.5.dp, DG.edge, CircleShape)
        .clickable(src, null, enabled = progress == null, role = Role.Button, onClick = onClick).semantics { contentDescription = label }.tag("save-trip-map"),
        contentAlignment = Alignment.Center) {
        if (progress != null) CircularProgressIndicator(progress = { progress }, modifier = Modifier.size(40.dp), color = DG.low, strokeWidth = 2.5.dp, trackColor = DG.hair)
        DGIcon("download", if (progress != null) DG.low else DG.ink, 20.dp)
    }
}

/** Start, with when you would arrive under it. */
@Composable
private fun StartButton(arrive: String?, modifier: Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    Row(modifier.press(src).height(DG.btnH).clip(RoundedCornerShape(24.dp)).background(DG.ink)
        .clickable(src, null, role = Role.Button, onClick = onClick).tag("start").padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        DGIcon("nav", Color.White, 19.dp)
        Spacer(Modifier.width(7.dp))
        Text("Start", style = DGType.button, color = Color.White)
        if (arrive != null) Text("  $arrive", style = DGType.small, color = Color.White.copy(alpha = .7f), maxLines = 1)
    }
}

// finding routes, resume

@Composable
internal fun FindingRoutesCard(onCancel: () -> Unit) {
    Row(Modifier.padding(horizontal = DG.gutter).padding(bottom = 6.dp).fillMaxWidth().navigationBarsPadding()
        .glass(RoundedCornerShape(DG.rCard), elevation = 22.dp, strong = true).padding(start = 18.dp, end = 8.dp, top = 8.dp, bottom = 8.dp).tag("finding-routes"),
        verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(22.dp), color = DG.low, strokeWidth = 2.5.dp, trackColor = DG.low.tint(.14f))
        Spacer(Modifier.width(14.dp))
        Text("Finding routes", Modifier.weight(1f), style = DGType.row, color = DG.ink)
        DGButton("Cancel", onCancel, style = BtnStyle.QUIET)
    }
}

/** A trip that was running when the app closed: pick it up again, with or without a signal. */
@Composable
internal fun ResumeTripCard(trip: SavedTrip, model: DriveViewModel) {
    Column(Modifier.padding(horizontal = DG.gutter).padding(bottom = 6.dp).fillMaxWidth().navigationBarsPadding()
        .glass(RoundedCornerShape(DG.rCard), elevation = 22.dp, strong = true).padding(16.dp).tag("resume-card")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Disc("route", Tone.LOW)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("Resume your trip to ${trip.place.shortName}?", style = DGType.title, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("Started at ${OfflineText.time(trip.startedAt)}. Works without a signal.", style = DGType.small, color = DG.sub)
            }
        }
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DGButton("Not now", { model.dismissResume() }, Modifier.weight(1f).tag("dismiss-trip"))
            DGButton("Resume", { model.resume() }, Modifier.weight(1.4f).tag("resume-trip"), style = BtnStyle.PRIMARY, icon = "nav")
        }
    }
}

// arrive

/** The trip is over: how long, how far, when, and what the driver was warned about on the way. */
@Composable
internal fun ArriveSheet(model: DriveViewModel, place: Place?, onDone: () -> Unit) {
    val trip by model.trip.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.arrived() }
    val r = trip
    val target = r?.place ?: place
    FitSheet(Modifier.tag("arrive-sheet"), onDismiss = onDone) {
        SheetHead("You have arrived", target?.name, lead = { Disc("arrive", Tone.GOOD) })
        if (r != null) {
            val s = ArriveStats.of(r, System.currentTimeMillis(), Units.useMiles) { clockOf(it) }
            Row(Modifier.padding(start = 14.dp, end = 14.dp, top = 16.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp))
                .background(Color.White.copy(alpha = .84f)).border(1.dp, DG.hair, RoundedCornerShape(22.dp)).padding(vertical = 14.dp)) {
                listOf(s.driveTime to "Drive time", s.distance to "Distance", s.arrived to "Arrived").forEachIndexed { i, (v, l) ->
                    if (i > 0) Box(Modifier.width(0.5.dp).height(40.dp).background(DG.hair).align(Alignment.CenterVertically))
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(v, style = DGType.cardTitle, color = DG.ink, maxLines = 1)
                        Text(l, style = DGType.small.copy(fontSize = DGType.label.fontSize, fontWeight = FontWeight.Medium), color = DG.sub)
                    }
                }
            }
            val avoided = ArriveStats.avoided(r)
            if (avoided.isNotEmpty()) {
                SheetLabel("What you avoided")
                Group(radius = 22.dp) {
                    avoided.forEachIndexed { i, m ->
                        if (i > 0) RowDivider(inset = 64.dp)
                        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Disc(Looks.of(m).icon, Tone.CLEAR, DG.discSm)
                            Spacer(Modifier.width(14.dp))
                            Column(Modifier.weight(1f)) {
                                Text(TripText.eventTitle(m), style = DGType.row.copy(fontSize = DGType.alertBody.fontSize.times(15.5f / 14.5f)), color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("You had a heads-up before you reached it", style = DGType.small, color = DG.sub)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        SheetActions {
            val saved = target != null && model.places.places.value.any { it.kind != PlaceKind.recent && Math.abs(it.lat - target.lat) < 1e-4 && Math.abs(it.lon - target.lon) < 1e-4 }
            if (target != null && !saved) DGButton("Save place", {
                model.places.set(PlaceKind.saved, target.name, target.lat, target.lon); model.toast("Saved to favorites.")
            }, Modifier.weight(1f).tag("arrive-save"), icon = "star")
            DGButton("Done", onDone, Modifier.weight(1.4f).tag("arrive-done"), style = BtnStyle.PRIMARY)
        }
    }
}

/** A gap between capsule-sized things. */
internal val TripGap: Dp = 8.dp
