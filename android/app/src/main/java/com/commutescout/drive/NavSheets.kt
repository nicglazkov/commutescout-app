package com.commutescout.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.FitSheet
import com.commutescout.drive.design.GhostRound
import com.commutescout.drive.design.ModeToggle
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.SheetHead
import com.commutescout.drive.design.SheetLabel
import com.commutescout.drive.design.StopDisc
import com.commutescout.drive.design.tint
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/*
 * The sheets a driver opens mid-trip: pick a place (a stop on the way,
 * or a new destination) and "Your trip", which shows where the trip
 * goes and lets it change. Rows are large on purpose: these are used
 * at a red light.
 */

/** A search to start with one tap. The words are what the search is sent. */
private val QUICK = listOf(Triple("fuel", "Gas", "gas station"), Triple("bolt", "Charging", "ev charging"),
    Triple("store", "Coffee", "coffee"), Triple("store", "Food", "restaurant"))

private data class Pick(val icon: String, val name: String, val sub: String?, val place: Place)

/**
 * Pick a place while driving. With nothing typed it lists Home, Work,
 * favorites and recent places; the quick searches look near the driver.
 */
@Composable
internal fun PlacePickSheet(
    title: String, sub: String, model: DriveViewModel, quick: Boolean, exclude: List<Place>,
    onPick: (Place) -> Unit, onClose: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var asked by remember { mutableStateOf(false) }
    var seq by remember { mutableIntStateOf(0) }
    var job by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val here by model.here.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()
    val busy by model.tripChanging.collectAsStateWithLifecycle()

    fun search(raw: String, wait: Long = 160) {
        job?.cancel()
        val t = raw.trim()
        parseCoordinates(t)?.let { c -> results = listOf(Suggestion("%.5f, %.5f".format(c.lat, c.lon), c.lat, c.lon)); asked = true; return }
        if (t.length < 2) { results = emptyList(); searching = false; asked = false; return }
        val mine = ++seq
        job = scope.launch {
            delay(wait)
            searching = true
            try {
                val found = runCatching { Search.suggest(t, here?.let { it.lat to it.lon }) }.getOrNull()
                if (mine == seq) { results = found ?: emptyList(); asked = true }
            } finally { if (mine == seq) searching = false }
        }
    }

    fun gone(p: Place) = exclude.any { AlertsEngine.meters(LatLon(it.lat, it.lon), LatLon(p.lat, p.lon)) < 30 }
    val rows: List<Pick> = if (text.isBlank()) {
        (places.filter { it.kind == PlaceKind.home }.map { Pick("home", "Home", it.name, it) } +
            places.filter { it.kind == PlaceKind.work }.map { Pick("work", "Work", it.name, it) } +
            places.filter { it.kind == PlaceKind.saved }.take(3).map { Pick("star", it.shortName, it.name.substringAfter(",", "").trim().ifEmpty { null }, it) } +
            places.filter { it.kind == PlaceKind.recent }.sortedByDescending { it.savedAt }.take(5).map { Pick("recent", it.shortName, it.name.substringAfter(",", "").trim().ifEmpty { null }, it) })
            .filterNot { gone(it.place) }.take(6)
    } else results.map { s ->
        Pick("pin", s.name.substringBefore(","), s.name.substringAfter(",", "").trim().ifEmpty { null }, Place(name = s.name, lat = s.lat, lon = s.lon, kind = PlaceKind.recent))
    }.filterNot { gone(it.place) }

    FitSheet(Modifier.testTag("place-pick"), onDismiss = onClose) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding()) {
            SheetHead(title, sub, onClose = onClose)
            Row(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp).fillMaxWidth().height(52.dp).clip(RoundedCornerShape(26.dp)).background(DG.wash)
                .padding(start = 16.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                DGIcon("search", DG.sub, 20.dp)
                Spacer(Modifier.width(10.dp))
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text("Search a place or address", style = DGType.search, color = DG.sub, maxLines = 1)
                    BasicTextField(
                        value = text, onValueChange = { text = it; search(it) },
                        modifier = Modifier.fillMaxWidth().testTag("place-pick-search"),
                        textStyle = DGType.search.copy(color = DG.ink), singleLine = true, cursorBrush = SolidColor(DG.low),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { focus.clearFocus(); search(text, 0) }),
                    )
                }
                when {
                    searching || busy -> CircularProgressIndicator(Modifier.padding(horizontal = 11.dp).size(18.dp), color = DG.low, strokeWidth = 2.dp)
                    text.isNotEmpty() -> GhostRound("close", "Clear", { text = ""; results = emptyList(); asked = false }, size = 40.dp)
                }
            }
            if (quick) Row(Modifier.padding(top = 12.dp).fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                QUICK.forEach { (icon, label, words) ->
                    val on = text == words
                    Row(Modifier.height(40.dp).clip(RoundedCornerShape(20.dp)).background(if (on) DG.low.tint(.14f) else DG.wash)
                        .clickable(role = Role.Button) { focus.clearFocus(); text = words; search(words, 0) }.padding(start = 12.dp, end = 14.dp)
                        .testTag("quick-$label"), verticalAlignment = Alignment.CenterVertically) {
                        DGIcon(icon, if (on) DG.lowInk else DG.ink, 18.dp)
                        Spacer(Modifier.width(7.dp))
                        Text(label, style = DGType.label.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = if (on) DG.lowInk else DG.ink)
                    }
                }
            }
            Column(Modifier.padding(top = 8.dp).fillMaxWidth().heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                rows.forEachIndexed { i, r ->
                    if (i > 0) Box(Modifier.padding(start = 74.dp, end = 18.dp).fillMaxWidth().height(0.5.dp).background(DG.hair))
                    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clickable(enabled = !busy) { focus.clearFocus(); onPick(r.place) }
                        .padding(horizontal = 18.dp, vertical = 9.dp).testTag("place-pick-row"), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(42.dp).clip(CircleShape).background(DG.low.tint(.12f)), contentAlignment = Alignment.Center) { DGIcon(r.icon, DG.low, 20.dp) }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(r.name, style = DGType.row, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            r.sub?.takeIf { it != r.name }?.let { Text(it, style = PageType.rowSub, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                        here?.let {
                            Spacer(Modifier.width(8.dp))
                            Text(Units.distance(AlertsEngine.meters(it, LatLon(r.place.lat, r.place.lon))), style = DGType.row, color = DG.ink, maxLines = 1)
                        }
                    }
                }
                val note = when {
                    rows.isNotEmpty() -> if (text.isNotBlank()) "The trip is not changed until you confirm." else null
                    text.isBlank() -> "Search for a place, or tap one of the quick searches."
                    searching || !asked -> null
                    !Connectivity.online.value -> OfflineText.SEARCH
                    else -> "Nothing found for that. Try other words, or add a city."
                }
                if (note != null) Text(note, Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp), style = DGType.small, color = DG.faint)
                Spacer(Modifier.height(14.dp))
            }
        }
    }
}

/** Where this trip goes: from here, through any stops, to the destination. Each part can change. */
@Composable
internal fun TripSheet(
    model: DriveViewModel, destination: Place, arrive: String?, is3D: Boolean,
    onChangeDestination: () -> Unit, onAddStop: () -> Unit, onReport: () -> Unit, onClose: () -> Unit,
) {
    val stops by model.stops.collectAsStateWithLifecycle()
    val busy by model.tripChanging.collectAsStateWithLifecycle()
    FitSheet(Modifier.testTag("trip-sheet"), onDismiss = onClose) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            SheetHead("Your trip", "Change where you are going", onClose = onClose)
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(DG.wash)) {
                TripRow(lead = { Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { Box(Modifier.size(14.dp).clip(CircleShape).background(DG.low)) } },
                    title = "From here", sub = null)
                stops.forEachIndexed { i, s ->
                    Divider()
                    TripRow(lead = { StopDisc(i + 1) }, title = s.shortName, sub = s.name.substringAfter(",", "").trim().ifEmpty { null }) {
                        if (busy) CircularProgressIndicator(Modifier.padding(horizontal = 9.dp).size(18.dp), color = DG.low, strokeWidth = 2.dp)
                        else GhostRound("close", "Remove ${s.shortName}", { model.removeStop(s) }, Modifier.testTag("remove-stop"), size = 40.dp)
                    }
                }
                Divider()
                TripRow(lead = { Box(Modifier.size(32.dp).clip(RoundedCornerShape(10.dp)).background(DG.solid), contentAlignment = Alignment.Center) { DGIcon("pin", Color.White, 17.dp, stroke = 2.2f) } },
                    title = destination.shortName, sub = arrive?.let { "Arrive $it" }) {
                    Box(Modifier.height(40.dp).clip(RoundedCornerShape(20.dp)).background(DG.low.tint(.14f)).clickable(role = Role.Button, onClick = onChangeDestination)
                        .padding(horizontal = 16.dp).testTag("change-destination"), contentAlignment = Alignment.Center) {
                        Text("Change", style = DGType.label.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = DG.lowInk)
                    }
                }
            }
            DGButton("Add a stop", onAddStop, Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp).fillMaxWidth().height(52.dp).testTag("trip-add-stop"), icon = "pinl")
            SheetLabel("On the road")
            Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(DG.wash)
                .clickable(role = Role.Button, onClick = onReport).heightIn(min = 60.dp).padding(start = 14.dp, end = 16.dp, top = 8.dp, bottom = 8.dp).testTag("trip-report"),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { DGIcon("report", DG.low, 22.dp, stroke = 2f) }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text("Report something", style = DGType.row, color = DG.ink)
                    Text("A crash, a hazard or a slowdown where you are", style = PageType.rowSub, color = DG.sub)
                }
            }
            SheetLabel("Map")
            Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(DG.wash).padding(start = 16.dp, end = 10.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("View", style = DGType.row, color = DG.ink)
                    Text(if (is3D) "3D, tilted toward the road ahead" else "2D, straight down", style = PageType.rowSub, color = DG.sub)
                }
                ModeToggle(is3D, { model.toggle3D() }, Modifier.testTag("perspective"))
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun Divider() = Box(Modifier.padding(start = 62.dp).fillMaxWidth().height(0.5.dp).background(DG.hair))

@Composable
private fun TripRow(lead: @Composable () -> Unit, title: String, sub: String?, trail: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(start = 14.dp, end = 10.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        lead()
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = DGType.row, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, style = PageType.rowSub, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (trail != null) { Spacer(Modifier.width(8.dp)); trail() }
    }
}
