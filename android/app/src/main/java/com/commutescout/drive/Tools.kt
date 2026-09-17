package com.commutescout.drive

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.QuestionAnswer
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.spatialk.geojson.Position
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationCameraMode
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState

enum class Tool { LAYERS, ALERTS, DIRECTIONS, WATCHES, ASK, SOURCES }

/** The website's rail, on the phone: everything that is not the search bar or Settings. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolsSheet(onPick: (Tool) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("tools-sheet")) {
        Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 32.dp)) {
            Text("Tools", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(8.dp))
            ToolRow(Icons.Default.Layers, "Layers and base map", "tool-layers") { onPick(Tool.LAYERS) }
            ToolRow(Icons.Default.Warning, "Alerts nearby", "tool-alerts") { onPick(Tool.ALERTS) }
            ToolRow(Icons.Default.SwapVert, "Directions from another place", "tool-directions") { onPick(Tool.DIRECTIONS) }
            ToolRow(Icons.Default.Visibility, "Watch areas", "tool-watches") { onPick(Tool.WATCHES) }
            ToolRow(Icons.Default.QuestionAnswer, "Ask about the roads", "tool-ask") { onPick(Tool.ASK) }
            ToolRow(Icons.Default.Sensors, "Community sources (Flare)", "tool-sources") { onPick(Tool.SOURCES) }
            LinkRow("Open the full map on the web") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/map"))) }
        }
    }
}

@Composable
private fun ToolRow(icon: ImageVector, label: String, tag: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp).testTag(tag), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(14.dp)); Text(label)
    }
}

/** The website's Alerts tool: what is on the map, closest first. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlertsListSheet(model: DriveViewModel, mapState: NavigationMapState, onClose: () -> Unit) {
    val markers by model.markers.markers.collectAsStateWithLifecycle()
    val direct by model.sources.directMarkers.collectAsStateWithLifecycle()
    val here by model.here.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val sorted = (markers + direct).filter { model.prefs.isShown(it.kind) }.sortedBy { m -> here?.let { AlertsEngine.meters(it, LatLon(m.lat, m.lon)) } ?: 0.0 }
    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("alerts-sheet")) {
        Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 24.dp)) {
            Text("Alerts nearby", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(8.dp))
            if (sorted.isEmpty()) Text("Nothing reported in the area on screen. Zoom out or move the map to see more.", Modifier.padding(8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyColumn(Modifier.height(420.dp)) {
                items(sorted, key = { it.key }) { m ->
                    Row(Modifier.fillMaxWidth().clickable {
                        model.showMarker(m.key)
                        scope.launch {
                            mapState.cameraMode = NavigationCameraMode.FREE
                            mapState.cameraState.animateTo(CameraPosition(target = Position(m.lon, m.lat), zoom = 14.0))
                        }
                        onClose()
                    }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(MarkerIcons.icon(m.kind), null, tint = MarkerIcons.color(m.kind))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(m.displayTitle, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            m.detailLines.firstOrNull()?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
                        }
                        here?.let { Text(Units.distance(AlertsEngine.meters(it, LatLon(m.lat, m.lon))), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
            }
        }
    }
}

/** The website's From/To planner: pick a start other than where you are. */
@OptIn(ExperimentalMaterial3Api::class)
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

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("directions-sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Directions", style = MaterialTheme.typography.titleLarge)
            Heading("From")
            TextButton({ from = null; fromText = "" }) { Text(from?.shortName ?: "My location") }
            OutlinedTextField(fromText, { fromText = it; suggest(it) { r -> fromResults = r } }, Modifier.fillMaxWidth(), placeholder = { Text("Or search a start") }, singleLine = true)
            fromResults.forEach { s -> TextButton({ from = Place(name = s.name, lat = s.lat, lon = s.lon, kind = PlaceKind.recent); fromText = s.name.substringBefore(","); fromResults = emptyList() }) { Text(s.name, maxLines = 1) } }
            Heading("To")
            to?.let { Text(it.shortName, color = MaterialTheme.colorScheme.primary) }
            OutlinedTextField(toText, { toText = it; suggest(it) { r -> toResults = r } }, Modifier.fillMaxWidth(), placeholder = { Text("Search a destination") }, singleLine = true)
            toResults.forEach { s -> TextButton({ to = Place(name = s.name, lat = s.lat, lon = s.lon, kind = PlaceKind.recent); toText = s.name.substringBefore(","); toResults = emptyList() }) { Text(s.name, maxLines = 1) } }
            Button({ to?.let { model.origin = from; onClose(); model.routes(it) } }, Modifier.fillMaxWidth(), enabled = to != null) { Text("Show routes") }
            Text("Route options (tolls, highways, ferries) are in Settings. Full closures are always avoided.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Serializable data class Watch(val id: String, val name: String? = null, val type: String? = null, val center: Center? = null,
                               val radius_km: Double? = null, val kinds: List<String>? = null, val active: Boolean? = null) {
    @Serializable data class Center(val lat: Double, val lon: Double)
}
@Serializable private data class MeResponse(val email: String? = null, val watches: List<Watch> = emptyList())

/** The website's Watch tool: areas that alert you when something happens inside them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchesSheet(model: DriveViewModel, onClose: () -> Unit) {
    val user by model.account.user.collectAsStateWithLifecycle()
    var watches by remember { mutableStateOf<List<Watch>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("") }
    var radius by remember { mutableStateOf(8.0) }
    var kinds by remember { mutableStateOf(setOf("incident", "closure", "chain", "fire")) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val state by model.state.collectAsStateWithLifecycle()
    val here by model.here.collectAsStateWithLifecycle()
    val anchor = (state as? DriveState.Found)?.place?.let { LatLon(it.lat, it.lon) } ?: here
    val anchorName = (state as? DriveState.Found)?.place?.shortName ?: "you"

    suspend fun load() {
        val token = model.account.token() ?: return
        loading = true
        try {
            val (status, text) = Backend.send("GET", "/api/watch/me", token)
            if (status == 200) watches = Backend.json.decodeFromString<MeResponse>(text).watches
        } catch (_: Exception) {} finally { loading = false }
    }
    LaunchedEffect(user) { load() }

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("watches-sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Watch areas", style = MaterialTheme.typography.titleLarge)
            if (user == null) {
                Text("Watch areas need an account, the same one as the website.")
                Button({ scope.launch { (context as? Activity)?.let { model.account.signInWithGoogle(it) } } }) { Text("Sign in with Google") }
            } else {
                Heading("Your watch areas")
                if (loading) CircularProgressIndicator()
                if (!loading && watches.isEmpty()) Text("None yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                watches.forEach { w ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(w.name ?: "Watch area")
                            Text(listOfNotNull(w.type, w.radius_km?.let { Units.distance(it * 1000) + " radius" }, w.kinds?.joinToString(", ")).joinToString(" · "),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton({ scope.launch { model.account.token()?.let { Backend.send("DELETE", "/api/watch/${w.id}", it) }; load() } }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.error) }
                    }
                }
                Heading("New watch around $anchorName")
                OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), placeholder = { Text("Name") }, singleLine = true)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Radius ${Units.distance(radius * 1000)}", Modifier.weight(1f))
                    OutlinedButton({ radius = (radius - 1).coerceAtLeast(1.0) }) { Text("-") }
                    Spacer(Modifier.width(6.dp))
                    OutlinedButton({ radius = (radius + 1).coerceAtMost(40.0) }) { Text("+") }
                }
                listOf("incident" to "Incidents", "closure" to "Closures", "chain" to "Chain controls", "fire" to "Fires").forEach { (k, label) ->
                    ToggleRow(label, k in kinds) { kinds = if (it) kinds + k else kinds - k }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                Button({
                    val c = anchor ?: return@Button
                    scope.launch {
                        val token = model.account.token() ?: return@launch
                        val body = """{"type":"circle","name":${JsonPrimitive(name.ifBlank { "Around $anchorName" })},"center":{"lat":${c.lat},"lon":${c.lon}},"radius_km":$radius,"kinds":[${kinds.joinToString(",") { "\"$it\"" }}],"channels":{"push":false,"email":true}}"""
                        val (status, text) = runCatching { Backend.send("POST", "/api/watch/create", token, body) }.getOrElse { 0 to "" }
                        if (status in 200..299) { name = ""; load() }
                        else error = runCatching { Backend.json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull() ?: "The server refused the watch ($status)."
                    }
                }, Modifier.fillMaxWidth(), enabled = kinds.isNotEmpty() && anchor != null) { Text("Create watch") }
                Text("Push and email delivery, polygons and route watches are set up on commutescout.com.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            LinkRow("Manage on the website") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/watch"))) }
        }
    }
}

/** The website's Ask tool: a question about the roads, streamed as it is written. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AskSheet(model: DriveViewModel, onClose: () -> Unit) {
    var question by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var prior by remember { mutableStateOf<Pair<String, String>?>(null) }
    val here by model.here.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    fun ask() {
        val q = question.trim(); if (q.isEmpty()) return
        running = true; answer = ""; status = ""
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val body = buildString {
                        append("""{"question":${JsonPrimitive(q)},"tz":${JsonPrimitive(java.util.TimeZone.getDefault().id)}""")
                        here?.let { append(""","location":{"lat":${it.lat},"lon":${it.lon}}""") }
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

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("ask-sheet")) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Ask", style = MaterialTheme.typography.titleLarge)
            Column(Modifier.height(300.dp).verticalScroll(rememberScrollState())) {
                if (answer.isEmpty() && !running) Text("Ask about closures, chain controls, fires or traffic, for example \"Is 80 over Donner open?\" or \"Anything between here and Tahoe?\"", color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (status.isNotEmpty()) Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (answer.isNotEmpty()) Text(answer.replace("**", "").replace(Regex("(?m)^#+ "), ""))
                if (running) CircularProgressIndicator(Modifier.padding(8.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(question, { question = it }, Modifier.weight(1f).testTag("ask-field"), placeholder = { Text("Ask about the roads") }, maxLines = 3)
                Spacer(Modifier.width(8.dp))
                Button({ ask() }, enabled = question.isNotBlank() && !running) { Icon(Icons.Default.Send, "Ask") }
            }
        }
    }
}

/** The Sources screen: what feeds the community layer, and the driver's own plugins. */
@OptIn(ExperimentalMaterial3Api::class)
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
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("sources-sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Sources", style = MaterialTheme.typography.titleLarge)
            Text("Community reports come from Flare plugins. Public ones are checked by CommuteScout; private ones you add here are read straight from your phone.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            LinkRow("How to write a plugin") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/plugins"))) }
            Heading("Public plugins")
            if (catalog.isEmpty()) Text("No public plugins are listed right now.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            catalog.forEach { s ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.name)
                        Text(listOfNotNull(s.attribution, s.trust, "${s.count} alerts", if (s.ok == false) "not answering" else null).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(s.id !in hidden, { model.sources.setOn(s.id, it); model.markers.refresh(true) })
                }
            }
            Heading("My plugins")
            mine.forEach { s ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.name)
                        Text(listOfNotNull(s.base, if (s.canReport) "accepts reports" else null, "every ${s.refreshS} s").joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                    }
                    Switch(s.id !in hidden, { model.sources.setOn(s.id, it) })
                    IconButton({ model.sources.remove(s) }) { Icon(Icons.Default.Delete, "Remove", tint = MaterialTheme.colorScheme.error) }
                }
            }
            if (!adding) TextButton({ adding = true }, Modifier.testTag("add-source")) { Text("Add a private or unlisted plugin") }
            else {
                OutlinedTextField(base, { base = it }, Modifier.fillMaxWidth().testTag("source-url"), placeholder = { Text("https://example.com") }, singleLine = true)
                OutlinedTextField(token, { token = it }, Modifier.fillMaxWidth(), placeholder = { Text("Token (private plugins only)") }, singleLine = true)
                Text("The app asks the plugin who it is (its handshake), then reads its alerts around where you are looking. Only you see them unless the plugin is public.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button({ scope.launch { busy = true; model.sources.clearError(); if (model.sources.add(base, token)) { adding = false; base = ""; token = "" }; busy = false } },
                        enabled = base.isNotBlank() && !busy) { Text(if (busy) "Checking" else "Add") }
                    TextButton({ adding = false; model.sources.clearError() }) { Text("Cancel") }
                }
            }
        }
    }
}
