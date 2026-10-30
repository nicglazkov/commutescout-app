package com.commutescout.drive

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGField
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGSwitch
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.GhostRound
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.GroupFoot
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.SheetLayer
import com.commutescout.drive.design.SheetScope
import com.commutescout.drive.design.tag
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState

enum class Tool { MARKETPLACE, LAYERS, ALERTS, DIRECTIONS, WATCHES, ASK, SOURCES }

/** A tool sheet's head: its title on the left, a round close on the right. */
@Composable
internal fun SheetHead(title: String, scope: SheetScope, sub: String? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 14.dp, top = 2.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = DGType.sheetTitle, color = DG.ink)
            if (sub != null) Text(sub, style = PageType.intro, color = DG.sub, modifier = Modifier.padding(top = 3.dp))
        }
        GhostRound("close", "Close", { scope.close(null) }, Modifier.tag("sheet-close"))
    }
}

/** A plain link row in a group: blue words and an out-arrow. */
@Composable
internal fun LinkSRow(label: String, icon: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    SRow(label, modifier, icon = icon, tileColor = DG.faint, labelColor = DG.lowInk, onClick = onClick) {
        DGIcon("next", DG.chev, 18.dp, stroke = 2.4f)
    }
}

/** The website's rail, on the phone: everything that is not the search bar or Settings. */
@Composable
fun ToolsSheet(onPick: (Tool) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    SheetLayer(onClose, snaps = listOf(.86f), maxHeight = 640.dp, modifier = Modifier.tag("tools-sheet")) { sheet ->
        SheetHead("Tools", sheet)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 16.dp)) {
            fun pick(t: Tool) = sheet.close { onPick(t) }
            Group {
                SRow("Layers and base map", Modifier.tag("tool-layers"), icon = "layers", tileColor = DG.low, chevron = true, onClick = { pick(Tool.LAYERS) })
                RowDivider()
                SRow("Alerts nearby", Modifier.tag("tool-alerts"), icon = "bell", tileColor = DG.high, chevron = true, onClick = { pick(Tool.ALERTS) })
                RowDivider()
                SRow("Directions from another place", Modifier.tag("tool-directions"), icon = "route", tileColor = DG.low, chevron = true, onClick = { pick(Tool.DIRECTIONS) })
            }
            Spacer(Modifier.height(12.dp))
            Group {
                SRow("Watch areas", Modifier.tag("tool-watches"), icon = "eye", tileColor = DG.good, chevron = true, onClick = { pick(Tool.WATCHES) })
                RowDivider()
                SRow("Ask about the roads", Modifier.tag("tool-ask"), icon = "help", tileColor = DG.mid, chevron = true, onClick = { pick(Tool.ASK) })
            }
            GroupHead("Plugins")
            Group {
                SRow("Plugin marketplace", Modifier.tag("tool-marketplace"), icon = "store", tileColor = DG.plug, chevron = true, onClick = { pick(Tool.MARKETPLACE) })
                RowDivider()
                SRow("My plugins and private sources", Modifier.tag("tool-sources"), icon = "piece", tileColor = DG.plug, chevron = true, onClick = { pick(Tool.SOURCES) })
            }
            Spacer(Modifier.height(12.dp))
            Group {
                LinkSRow("Open the full map on the web", "globe", { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/map"))) })
            }
        }
    }
}

/** The website's Alerts tool: what is on the map, closest first. */
@Composable
fun AlertsListSheet(model: DriveViewModel, mapState: NavigationMapState, onClose: () -> Unit) {
    val markers by model.markers.markers.collectAsStateWithLifecycle()
    val direct by model.sources.directMarkers.collectAsStateWithLifecycle()
    val here by model.here.collectAsStateWithLifecycle()
    // The nearest hundred events, ranked off the main thread: the whole
    // country's markers are held now, and sorting them all on every
    // redraw froze the sheet for a second. One row per thing.
    var sorted by remember { mutableStateOf<List<RoadMarker>?>(null) }
    LaunchedEffect(markers, direct, here) {
        val hidden = Engine.sources.hidden.value
        val shown = (markers + direct).filter {
            model.prefs.isShown(it.kind) && it.kind != "camera" && it.kind != "rwis" &&
                (it.kind != "plugin" || PluginStyle.sourceId(it) !in hidden)
        }
        val h = here
        sorted = withContext(Dispatchers.Default) {
            if (h == null) shown.take(100) else {
                val seen = HashSet<String>()
                shown.map { it to AlertsEngine.meters(h, LatLon(it.lat, it.lon)) }.filter { it.second <= 160_000 }
                    .sortedBy { it.second }
                    .filter { seen.add(it.first.kind + "|" + it.first.displayTitle + "|" + (it.second / 300).toInt()) }
                    .take(100).map { it.first }
            }
        }
    }
    SheetLayer(onClose, snaps = listOf(.56f, .92f), modifier = Modifier.tag("alerts-sheet")) { sheet ->
        val list = sorted
        SheetHead("Alerts nearby", sheet, sub = when {
            list == null -> "Looking around you"
            list.isEmpty() -> "Nothing reported within ${Units.distance(160_000.0)} of you."
            else -> "Closest first"
        })
        if (!list.isNullOrEmpty()) LazyColumn(Modifier.weight(1f).padding(bottom = 8.dp)) {
            itemsIndexed(list, key = { _, m -> m.key }) { i, m ->
                val plugin = m.kind == "plugin"
                val shape = RoundedCornerShape(
                    topStart = if (i == 0) 22.dp else 0.dp, topEnd = if (i == 0) 22.dp else 0.dp,
                    bottomStart = if (i == list.lastIndex) 22.dp else 0.dp, bottomEnd = if (i == list.lastIndex) 22.dp else 0.dp)
                Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape)
                    .background(if (plugin) DG.plug.copy(alpha = .06f) else Color(0xD6FFFFFF))) {
                    if (i > 0) RowDivider(inset = 58.dp)
                    SRow(m.displayTitle, sub = m.detailLines.firstOrNull(), labelColor = if (plugin) DG.plugInk else DG.ink,
                        lead = { Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { MarkerGlyph(m, 26.dp) } },
                        value = here?.let { Units.distance(AlertsEngine.meters(it, LatLon(m.lat, m.lon))) },
                        onClick = {
                            sheet.close {
                                model.showMarker(m.key)
                                // The same camera as a tapped alert: the event above the sheet.
                                model.focusOn(m.lat, m.lon)
                                onClose()
                            }
                        })
                }
            }
            item { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(12.dp)) }
        }
    }
}

/** The website's From/To planner: pick a start other than where you are. */
@Composable
fun DirectionsSheet(model: DriveViewModel, onClose: () -> Unit) {
    var fromText by remember { mutableStateOf("") }
    var toText by remember { mutableStateOf("") }
    var fromResults by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var toResults by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var from by remember { mutableStateOf<Place?>(null) }
    var to by remember { mutableStateOf<Place?>(null) }
    val here by model.here.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    fun suggest(q: String, set: (List<Suggestion>) -> Unit) {
        val t = q.trim()
        parseCoordinates(t)?.let { set(listOf(Suggestion("%.5f, %.5f".format(it.lat, it.lon), it.lat, it.lon))); return }
        if (t.length < 2) { set(emptyList()); return }
        scope.launch { delay(150); runCatching { Search.suggest(t, here?.let { it.lat to it.lon }) }.getOrNull()?.let(set) }
    }

    @Composable
    fun Suggestions(list: List<Suggestion>, onPick: (Suggestion) -> Unit) {
        if (list.isEmpty()) return
        Spacer(Modifier.height(8.dp))
        Group {
            list.forEachIndexed { i, s ->
                if (i > 0) RowDivider(inset = 58.dp)
                SRow(s.name.substringBefore(","), sub = s.name.substringAfter(", ", "").ifEmpty { null }, icon = "pinl", tileColor = DG.faint, onClick = { onPick(s) })
            }
        }
    }

    SheetLayer(onClose, snaps = listOf(.92f), modifier = Modifier.tag("directions-sheet")) { sheet ->
        SheetHead("Directions", sheet)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
            GroupHead("From")
            Group {
                SRow(from?.shortName ?: "My location", icon = if (from == null) "locate" else "pinl", tileColor = DG.low,
                    sub = if (from == null) "Where you are now" else "Tap to start from where you are",
                    onClick = { from = null; fromText = ""; fromResults = emptyList() })
            }
            Spacer(Modifier.height(8.dp))
            DGField("Or start somewhere else", fromText, { fromText = it; suggest(it) { r -> fromResults = r } }, placeholder = "Search a start", tag = "from-field")
            Suggestions(fromResults) { s -> from = Place(name = s.name, lat = s.lat, lon = s.lon, kind = PlaceKind.recent); fromText = s.name.substringBefore(","); fromResults = emptyList() }
            GroupHead("To")
            DGField(to?.let { "Going to ${it.shortName}" } ?: "Destination", toText, { toText = it; suggest(it) { r -> toResults = r } }, placeholder = "Search a destination", tag = "to-field")
            Suggestions(toResults) { s -> to = Place(name = s.name, lat = s.lat, lon = s.lon, kind = PlaceKind.recent); toText = s.name.substringBefore(","); toResults = emptyList() }
            Spacer(Modifier.height(16.dp))
            DGButton("Show routes", { to?.let { t -> sheet.close { model.origin = from; onClose(); model.routes(t) } } },
                Modifier.padding(horizontal = 14.dp).fillMaxWidth(), style = BtnStyle.BLUE, icon = "route", enabled = to != null)
            GroupFoot("Route options (tolls, highways, ferries) are in Settings. Full closures are always avoided.")
        }
    }
}

/** The website's Ask tool: a question about the roads, streamed as it is written. */
@Composable
fun AskSheet(model: DriveViewModel, onClose: () -> Unit) {
    var question by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var prior by remember { mutableStateOf<Pair<String, String>?>(null) }
    var asked by remember { mutableStateOf<String?>(null) }
    val here by model.here.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    fun ask() {
        val q = question.trim(); if (q.isEmpty()) return
        running = true; answer = ""; status = ""; asked = q
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val body = buildString {
                        append("""{"question":${JsonPrimitive(q)},"tz":${JsonPrimitive(java.util.TimeZone.getDefault().id)}""")
                        // Three decimals (about 100 m), the same as every other request.
                        here?.let { append(""","location":{"lat":%.3f,"lon":%.3f}""".format(java.util.Locale.US, it.lat, it.lon)) }
                        prior?.let { append(""","prior":{"question":${JsonPrimitive(it.first)},"answer":${JsonPrimitive(it.second)}}""") }
                        append("}")
                    }
                    val req = Request.Builder().url("${Backend.BASE}/api/ask").post(body.toRequestBody("application/json".toMediaType())).build()
                    Backend.http.newCall(req).execute().use { r ->
                        if (!r.isSuccessful) { answer = "The assistant is not available right now."; return@use }
                        r.body.source().let { src ->
                            while (!src.exhausted()) {
                                val line = src.readUtf8Line() ?: break
                                if (!line.startsWith("data: ")) continue
                                val msg = runCatching { Backend.json.parseToJsonElement(line.substring(6)).jsonObject }.getOrNull() ?: continue
                                msg["text"]?.jsonPrimitive?.content?.let { t -> withContext(Dispatchers.Main) { answer += t; status = "" } }
                                msg["tool"]?.jsonPrimitive?.content?.let { t -> withContext(Dispatchers.Main) { status = "Looking up " + t.replace('_', ' ') } }
                            }
                        }
                    }
                }
                prior = q to answer; question = ""
            } catch (e: Exception) { answer = "Could not reach the assistant: ${e.message}" } finally { running = false }
        }
    }

    SheetLayer(onClose, snaps = listOf(.62f, .92f), modifier = Modifier.tag("ask-sheet")) { sheet ->
        SheetHead("Ask", sheet)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp)) {
            if (answer.isEmpty() && !running) Text("Ask about closures, chain controls, fires or traffic anywhere in the country, for example \"Is I-70 open through the Eisenhower Tunnel?\", \"Any crashes on I-95 near Richmond?\" or \"Chains on US-2 over Stevens Pass?\"",
                style = DGType.body, color = DG.sub)
            asked?.let { Text(it, style = DGType.row, color = DG.ink, modifier = Modifier.padding(bottom = 8.dp)) }
            if (status.isNotEmpty()) Text(status, style = DGType.small, color = DG.sub)
            if (answer.isNotEmpty()) Text(answer.replace("**", "").replace(Regex("(?m)^#+ "), ""), style = DGType.body, color = DG.ink)
            if (running) CircularProgressIndicator(Modifier.padding(8.dp).size(22.dp), color = DG.low, strokeWidth = 2.5.dp)
            Spacer(Modifier.height(12.dp))
        }
        // The question box and its send button, above the keyboard.
        val shape = RoundedCornerShape(26.dp)
        Row(Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(start = 14.dp, end = 14.dp, top = 6.dp, bottom = 10.dp).fillMaxWidth()
            .heightIn(min = 52.dp).clip(shape).background(Color.White.copy(alpha = .85f)).border(1.dp, DG.hair, shape)
            .padding(start = 18.dp, end = 6.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                if (question.isEmpty()) Text("Ask about the roads", style = DGType.search, color = DG.faint)
                BasicTextField(question, { question = it }, Modifier.fillMaxWidth().testTag("ask-field"), textStyle = DGType.search.copy(color = DG.ink),
                    maxLines = 3, cursorBrush = SolidColor(DG.low))
            }
            Spacer(Modifier.width(8.dp))
            val can = question.isNotBlank() && !running
            Box(Modifier.size(40.dp).clip(CircleShape).background(if (can) Brush.verticalGradient(listOf(DG.lowTop, DG.low)) else SolidColor(DG.wash))
                .clickable(enabled = can, role = Role.Button) { ask() }.semantics { contentDescription = "Ask" }.testTag("ask-send"),
                contentAlignment = Alignment.Center) { DGIcon("up", if (can) Color.White else DG.faint, 20.dp, stroke = 2.4f) }
        }
    }
}

/** The driver's plugins: the listed ones with a switch each, and private ones added by URL. */
@Composable
fun SourcesSheet(model: DriveViewModel, onClose: () -> Unit) {
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val mine by model.sources.mine.collectAsStateWithLifecycle()
    val hidden by model.sources.hidden.collectAsStateWithLifecycle()
    val error by model.sources.error.collectAsStateWithLifecycle()
    var adding by remember { mutableStateOf(false) }
    var base by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var details by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    details?.let { PluginStatusSheet(model, it) { details = null } }

    @Composable
    fun PluginRow(s: FlareSource, mineToo: Boolean) {
        val on = s.id !in hidden
        SRow(s.name, Modifier.tag("source-${s.id}"), lead = { PluginTile(s, 32.dp) },
            sub = listOfNotNull(if (mineToo) s.base?.removePrefix("https://") else Market.maker(s), if (s.ok == false) "not answering" else null).joinToString(" · "),
            onClick = { details = s.id }) {
            DGSwitch(on, { v -> model.sources.setShown(s.id, v); model.markers.refresh(true) })
        }
    }

    SheetLayer(onClose, snaps = listOf(.92f), modifier = Modifier.tag("sources-sheet")) { sheet ->
        SheetHead("My plugins", sheet, sub = "What each plugin shows follows your account and no one else's.")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 24.dp)) {
            val approved = catalog.filter { it.tier == "approved" }
            val public = catalog.filter { it.tier != "approved" }
            GroupHead("Approved plugins")
            Group {
                if (approved.isEmpty()) SRow("No approved plugin is listed right now.", labelColor = DG.sub)
                approved.forEachIndexed { i, s -> if (i > 0) RowDivider(); PluginRow(s, false) }
            }
            GroupFoot("Reviewed by CommuteScout. Drawn by default and may speak.")
            GroupHead("Public plugins, not reviewed")
            Group(plugin = true) {
                if (public.isEmpty()) SRow("None listed right now.", labelColor = DG.sub)
                public.forEachIndexed { i, s -> if (i > 0) RowDivider(plugin = true); PluginRow(s, false) }
            }
            GroupFoot("Anyone who passes the conformance check can be listed. Drawn and labeled; spoken only if you turn that on in Settings > Alerts.")
            GroupHead("Private plugins")
            Group(plugin = true) {
                mine.forEachIndexed { i, s -> if (i > 0) RowDivider(plugin = true); PluginRow(s, true) }
                if (mine.isNotEmpty()) RowDivider(inset = 0.dp, plugin = true)
                if (!adding) SRow("Add a private or unlisted plugin", Modifier.tag("add-source"), icon = "plus", tileColor = DG.plug, labelColor = DG.plugInk,
                    onClick = { adding = true })
                else Column(Modifier.padding(vertical = 12.dp)) {
                    DGField("Plugin address", base, { base = it }, placeholder = "https://example.com", tag = "source-url")
                    Spacer(Modifier.height(8.dp))
                    DGField("Token (private plugins only)", token, { token = it }, placeholder = "Optional", tag = "source-token")
                    Text("The app asks the plugin who it is (its handshake), then reads its alerts around where you are looking. Only you see them.",
                        Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = PageType.note, color = DG.sub)
                    error?.let { Text(it, Modifier.padding(start = 24.dp, end = 24.dp, top = 6.dp), style = PageType.note, color = DG.highInk) }
                    Row(Modifier.padding(start = 14.dp, end = 14.dp, top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DGButton("Cancel", { adding = false; model.sources.clearError() }, Modifier.weight(1f))
                        DGButton(if (busy) "Checking" else "Add", {
                            scope.launch { busy = true; model.sources.clearError(); if (model.sources.add(base, token)) { adding = false; base = ""; token = "" }; busy = false }
                        }, Modifier.weight(1f), style = BtnStyle.BLUE, enabled = base.isNotBlank() && !busy)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Group {
                LinkSRow("How to write a plugin", "help", { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/plugins"))) })
            }
        }
    }
}
