package com.commutescout.drive

import android.app.Activity
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.LocalPolice
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Traffic
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Water
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.CarCrash
import androidx.compose.material.icons.filled.RemoveRoad
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** What a driver can report, the website's list. Kinds are the Flare vocabulary. */
object ReportKinds {
    data class Kind(val kind: String, val label: String, val icon: ImageVector)
    val all = listOf(
        Kind("POLICE_VISIBLE", "Police", Icons.Default.LocalPolice),
        Kind("CRASH_MAJOR", "Crash", Icons.Default.CarCrash),
        Kind("HAZARD_ON_ROAD", "Hazard on road", Icons.Default.Warning),
        Kind("HAZARD_SHOULDER_CAR", "Car on shoulder", Icons.Default.DirectionsCar),
        Kind("ROAD_CLOSED", "Road closed", Icons.Default.Block),
        Kind("LANE_CLOSED", "Lane closed", Icons.Default.RemoveRoad),
        Kind("JAM_HEAVY", "Traffic jam", Icons.Default.Traffic),
        Kind("WEATHER_FOG", "Fog or weather", Icons.Default.Cloud),
        Kind("WEATHER_FLOOD", "Flooding", Icons.Default.Water),
        Kind("WEATHER_ICE", "Ice or snow", Icons.Default.AcUnit),
        Kind("CHAINS_REQUIRED", "Chains required", Icons.Default.Link),
        Kind("CHAINS_NOT_REQUIRED", "Chains not needed", Icons.Default.LinkOff),
        Kind("CAMERA_ISSUE", "Camera issue", Icons.Default.CameraAlt),
        Kind("MAP_ISSUE", "Map issue", Icons.Default.Map),
    )
}

/** Sends a report to commutescout.com, which fans it out to plugins. */
object Reporter {
    suspend fun send(kind: String, lat: Double, lon: Double, heading: Double?, description: String, token: String) {
        val body = buildString {
            append("""{"kind":"$kind","lat":$lat,"lon":$lon,"client":"commutescout-android/${BuildConfig.VERSION_NAME}"""")
            if (heading != null && heading >= 0) append(""","heading_deg":$heading""")
            if (description.isNotBlank()) append(""","description":${JsonPrimitive(description)}""")
            append("}")
        }
        val (status, text) = Backend.send("POST", "/api/flare/report", token, body)
        if (status != 201 && status != 202) {
            val msg = runCatching { Backend.json.parseToJsonElement(text).jsonObject["error"] }.getOrNull()
            val detail = (msg as? JsonPrimitive)?.content ?: (msg as? JsonObject)?.get("message")?.jsonPrimitive?.content
            throw BackendError(if (status == 429) "Too many reports for now. Try again in a minute." else detail ?: "The server refused the report.")
        }
    }

    suspend fun confirm(alertId: String, vote: String, token: String) {
        val (status, _) = Backend.send("POST", "/api/flare/confirm", token, """{"alert_id":${JsonPrimitive(alertId)},"vote":"$vote"}""")
        if (status != 200) throw BackendError("Could not record that.")
    }
}

/** The Waze-style report sheet: one tap on a kind, an optional note, send. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportSheet(model: DriveViewModel, lat: Double, lon: Double, onClose: () -> Unit) {
    var kind by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val user by model.account.user.collectAsStateWithLifecycle()
    val busy by model.account.busy.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("report-sheet")) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Report", style = MaterialTheme.typography.titleLarge)
            if (user == null) {
                Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp)).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("Reports need an account, the same one as the website.", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    TextButton({ scope.launch { (context as? Activity)?.let { model.account.signInWithGoogle(it) } } }, enabled = !busy) { Text("Sign in") }
                }
            }
            LazyVerticalGrid(GridCells.Adaptive(100.dp), Modifier.height(330.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(ReportKinds.all, key = { it.kind }) { k ->
                    val on = kind == k.kind
                    Column(
                        Modifier.fillMaxWidth().height(84.dp)
                            .background(if (on) MaterialTheme.colorScheme.primary.copy(alpha = 0.18f) else MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp))
                            .border(2.dp, if (on) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(12.dp))
                            .clickable { kind = k.kind }.padding(8.dp).testTag("report-${k.kind}"),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(k.icon, null)
                        Spacer(Modifier.height(6.dp))
                        Text(k.label, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, maxLines = 2)
                    }
                }
            }
            OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth(), placeholder = { Text("Add a note (optional)") }, maxLines = 3)
            Text("Reported at %.5f, %.5f. Reports show on the map for everyone and go to the plugins you use, under a pseudonym.".format(lat, lon),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            Button(
                onClick = {
                    val k = kind ?: return@Button
                    scope.launch {
                        val token = model.account.token()
                        if (token == null) { (context as? Activity)?.let { model.account.signInWithGoogle(it) }; return@launch }
                        sending = true
                        try {
                            Reporter.send(k, lat, lon, model.courseDegrees, note, token)
                            model.markers.refresh(true)
                            model.toast("Thanks. Your report is on the map.")
                            onClose()
                        } catch (e: Exception) {
                            error = e.message
                        } finally { sending = false }
                    }
                },
                enabled = kind != null && !sending, modifier = Modifier.fillMaxWidth().testTag("report-send"),
            ) { Icon(Icons.Default.Send, null); Spacer(Modifier.width(6.dp)); Text(if (sending) "Sending" else "Send report") }
        }
    }
}
