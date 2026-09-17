package com.commutescout.drive

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/** Every setting, grouped the way a driver looks for them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(model: DriveViewModel, onClose: () -> Unit) {
    val prefs = model.prefs
    val places by model.places.places.collectAsStateWithLifecycle()
    val simulating by model.simulating.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("settings-sheet")) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Settings", style = MaterialTheme.typography.titleLarge)

            Heading("Account")
            val user by model.account.user.collectAsStateWithLifecycle()
            val accountError by model.account.error.collectAsStateWithLifecycle()
            val scope = rememberCoroutineScope()
            var confirmDelete by remember { mutableStateOf(false) }
            if (user != null) {
                Text("Signed in as ${model.account.displayName}")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton({ model.account.signOut() }) { Text("Sign out") }
                    TextButton({ confirmDelete = true }) { Text("Delete account", color = MaterialTheme.colorScheme.error) }
                }
                Text("Deleting removes your watches, API keys and reports from commutescout.com.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Button({ scope.launch { (context as? android.app.Activity)?.let { model.account.signInWithGoogle(it) } } }, Modifier.testTag("sign-in")) { Text("Sign in with Google") }
                Text("Sign in to report from the road, keep watch areas, and manage API keys. Same account as the website.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            accountError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            if (confirmDelete) AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text("Delete your account?") },
                text = { Text("This removes your watches, API keys and reports. It cannot be undone.") },
                confirmButton = { TextButton({ confirmDelete = false; scope.launch { model.account.deleteAccount() } }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
                dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel") } },
            )

            Heading("Appearance")
            Choice("Theme", Prefs.Theme.entries.map { it.label }, prefs.theme.ordinal) { prefs.theme = Prefs.Theme.entries[it] }
            Choice("Base map", Prefs.MapStyle.entries.map { it.label }, prefs.mapStyle.ordinal) { prefs.mapStyle = Prefs.MapStyle.entries[it] }
            ToggleRow("3D perspective", prefs.is3D) { model.toggle3D() }

            Heading("Distances")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(prefs.useMiles, { prefs.useMiles = true }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Miles") }
                SegmentedButton(!prefs.useMiles, { prefs.useMiles = false }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Kilometers") }
            }

            Heading("Route options")
            ToggleRow("Avoid tolls", prefs.avoidTolls) { prefs.avoidTolls = it }
            ToggleRow("Avoid highways", prefs.avoidHighways) { prefs.avoidHighways = it }
            ToggleRow("Avoid ferries", prefs.avoidFerries) { prefs.avoidFerries = it }
            Text("Full road closures are always avoided. Changes apply to the next route.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Heading("While driving")
            ToggleRow("Voice guidance", uiState.isMuted != true) { model.toggleMute() }
            ToggleRow("Speak road alerts", prefs.spokenAlerts) { prefs.spokenAlerts = it }
            val aheadLabels = if (prefs.useMiles) listOf("0.5 mi ahead", "1 mi ahead", "2 mi ahead") else listOf("800 m ahead", "1.5 km ahead", "3 km ahead")
            val aheadValues = listOf(800.0, 1500.0, 3000.0)
            Choice("Warn about alerts", aheadLabels, aheadValues.indexOf(prefs.alertAheadMeters).coerceAtLeast(0)) { prefs.alertAheadMeters = aheadValues[it] }
            var showAdvanced by remember { mutableStateOf(false) }
            LinkRow("Advanced alerts: ${if (prefs.advancedAlerts) "on" else "off"}") { showAdvanced = true }
            if (showAdvanced) AdvancedAlertsSheet(model) { showAdvanced = false }
            ToggleRow("Show speed limit", prefs.showSpeedLimit) { prefs.showSpeedLimit = it }
            ToggleRow("Keep the screen on", prefs.keepAwake) { prefs.keepAwake = it }

            Heading("Layers")
            ToggleRow("Traffic", prefs.traffic) { prefs.traffic = it }
            Prefs.layerKinds.forEach { k -> ToggleRow(k.label, prefs.isShown(k.key)) { prefs.setShown(k.key, it); model.markers.refresh(true) } }

            Heading("Places")
            if (places.isEmpty()) Text("Search a place, then save it as Home, Work or a favorite.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            model.places.home?.let { PlaceRow("Home", it, model) }
            model.places.work?.let { PlaceRow("Work", it, model) }
            model.places.saved.forEach { PlaceRow("Saved", it, model) }

            if (BuildConfig.DEBUG) {
                Heading("Testing")
                ToggleRow("Simulate driving the route", simulating) { model.simulating.value = it }
            }

            Heading("Help and docs")
            LinkRow("Live map on the web") { open("https://commutescout.com/map") }
            LinkRow("Data sources") { open("https://commutescout.com/data-sources") }
            LinkRow("Developers and API") { open("https://commutescout.com/developers") }
            LinkRow("About CommuteScout") { open("https://commutescout.com/about") }
            LinkRow("Contact") { open("https://commutescout.com/contact") }
            LinkRow("Privacy") { open("https://commutescout.com/privacy") }

            Heading("About")
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = MaterialTheme.typography.bodySmall)
            Text("Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun Heading(text: String) {
    HorizontalDivider(Modifier.padding(top = 6.dp))
    Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
}

@Composable
fun ToggleRow(label: String, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(on, onChange, Modifier.testTag("switch-$label"))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Choice(label: String, options: List<String>, selected: Int, onPick: (Int) -> Unit) {
    Text(label, style = MaterialTheme.typography.bodyMedium)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { i, o ->
            SegmentedButton(i == selected, { onPick(i) }, SegmentedButtonDefaults.itemShape(i, options.size)) {
                Text(o, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun LinkRow(label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = MaterialTheme.colorScheme.primary)
        Icon(Icons.Default.OpenInNew, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
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

/** Highway Radar-style control: per kind, first warning distance, optional second warning, voice. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdvancedAlertsSheet(model: DriveViewModel, onClose: () -> Unit) {
    val prefs = model.prefs
    val steps = if (prefs.useMiles) listOf(402.0, 805.0, 1609.0, 2414.0, 3219.0, 4828.0, 8047.0) else listOf(300.0, 500.0, 1000.0, 1500.0, 2000.0, 3000.0, 5000.0, 8000.0)
    fun nearest(m: Double) = steps.minByOrNull { kotlin.math.abs(it - m) } ?: m
    ModalBottomSheet(onDismissRequest = onClose, modifier = Modifier.testTag("advanced-alerts")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Advanced alerts", style = MaterialTheme.typography.titleLarge)
            ToggleRow("Set alerts per kind", prefs.advancedAlerts) { prefs.advancedAlerts = it }
            Text("Off: every alert uses the one distance in While driving. On: each kind has its own first warning, an optional second warning closer in, and its own voice.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (prefs.advancedAlerts) {
                val rules = prefs.alertRules
                prefs.alertKinds.forEach { (key, label) ->
                    val rule = rules[key] ?: Prefs.AlertRule()
                    Heading(label)
                    ToggleRow("Warn", rule.enabled) { prefs.setRule(key, rule.copy(enabled = it)) }
                    if (rule.enabled) {
                        val labels = steps.map { Units.distance(it) + " ahead" }
                        Choice("First warning", labels, steps.indexOf(nearest(rule.firstMeters)).coerceAtLeast(0)) { i ->
                            prefs.setRule(key, rule.copy(firstMeters = steps[i], repeatMeters = if (rule.repeatMeters >= steps[i]) 0.0 else rule.repeatMeters))
                        }
                        val second = listOf(0.0) + steps.filter { it < nearest(rule.firstMeters) }
                        Choice("Second warning", second.map { if (it == 0.0) "None" else Units.distance(it) }, second.indexOf(if (rule.repeatMeters == 0.0) 0.0 else nearest(rule.repeatMeters)).coerceAtLeast(0)) { i ->
                            prefs.setRule(key, rule.copy(repeatMeters = second[i]))
                        }
                        ToggleRow("Speak it", rule.speak) { prefs.setRule(key, rule.copy(speak = it)) }
                    }
                }
                TextButton({ prefs.alertRules = emptyMap() }) { Text("Reset to defaults") }
            }
        }
    }
}
