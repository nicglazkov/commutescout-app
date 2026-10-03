package com.commutescout.drive

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DownloadForOffline
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
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
import androidx.compose.material3.rememberModalBottomSheetState
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
import kotlinx.coroutines.delay
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.Home
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/** The pages of Settings; null in the sheet's state is the home page. */
private enum class SettingsPage(val title: String) {
    ACCOUNT("Account"), APPEARANCE("Appearance"), UNITS("Units"), NAVIGATION("Navigation"), ALERTS("Alerts"),
    LAYERS("Map layers"), PLUGINS("Plugins"), OFFLINE("Offline maps"), PLACES("Saved places"), HELP("Help"),
    ABOUT("About"), TESTING("Testing"),
}

/**
 * Settings, laid out like a phone's own Settings app: a short home page
 * of categories, each opening a page of its own. A row says what it
 * holds and what it is set to, so most answers are readable without
 * opening anything. Back returns to the home page before it closes the
 * sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(model: DriveViewModel, onClose: () -> Unit) {
    var page by remember { mutableStateOf<SettingsPage?>(null) }
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("settings-sheet")) {
        BackHandler(enabled = page != null) { page = null }
        Column(Modifier.fillMaxHeight(0.94f)) {
            Row(Modifier.fillMaxWidth().padding(start = if (page == null) 20.dp else 6.dp, end = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (page != null) {
                    IconButton({ page = null }, Modifier.testTag("settings-back")) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to Settings") }
                }
                Text(page?.title ?: "Settings", style = MaterialTheme.typography.titleLarge)
            }
            AnimatedContent(page, label = "settings-page",
                transitionSpec = {
                    val forward = targetState != null
                    (slideInHorizontally { if (forward) it / 4 else -it / 4 } + fadeIn()) togetherWith
                        (slideOutHorizontally { if (forward) -it / 4 else it / 4 } + fadeOut())
                }) { current ->
                Column(
                    Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    when (current) {
                        null -> SettingsHome(model) { page = it }
                        SettingsPage.ACCOUNT -> AccountPage(model)
                        SettingsPage.APPEARANCE -> AppearancePage(model)
                        SettingsPage.UNITS -> UnitsPage(model)
                        SettingsPage.NAVIGATION -> NavigationPage(model)
                        SettingsPage.ALERTS -> AlertsPage(model)
                        SettingsPage.LAYERS -> LayersPage(model)
                        SettingsPage.PLUGINS -> PluginsPage(model)
                        SettingsPage.OFFLINE -> OfflinePage(model)
                        SettingsPage.PLACES -> PlacesPage(model)
                        SettingsPage.HELP -> HelpPage()
                        SettingsPage.ABOUT -> AboutPage()
                        SettingsPage.TESTING -> TestingPage(model)
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsHome(model: DriveViewModel, open: (SettingsPage) -> Unit) {
    val prefs = model.prefs
    val user by model.account.user.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val mine by model.sources.mine.collectAsStateWithLifecycle()
    val off by model.sources.hidden.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()
    val mapFiles by MapFiles.files.collectAsStateWithLifecycle()
    val simulating by model.simulating.collectAsStateWithLifecycle()

    // The profile card: who is signed in, or the invitation to.
    SettingsGroup {
        Row(Modifier.fillMaxWidth().clickable { open(SettingsPage.ACCOUNT) }.padding(16.dp).testTag("settings-account"), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(52.dp).background(if (user != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, CircleShape), contentAlignment = Alignment.Center) {
                if (user != null) Text(model.account.displayName.take(1).uppercase(), style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onPrimary)
                else Icon(Icons.Default.Person, null, tint = Color.White)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(if (user != null) model.account.displayName else "Sign in", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (user != null) "Account, sign out" else "Reports, watch areas, sync", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    SettingsGroup {
        SettingsRow(Icons.Default.Palette, Color(0xFF5856D6), "Appearance", prefs.theme.label) { open(SettingsPage.APPEARANCE) }
        SettingsRow(Icons.Default.Straighten, Color(0xFF30B0C7), "Units", if (prefs.useMiles) "Miles" else "Kilometers", last = true) { open(SettingsPage.UNITS) }
    }
    GroupTitle("Driving")
    SettingsGroup {
        val avoid = listOfNotNull("tolls".takeIf { prefs.avoidTolls }, "highways".takeIf { prefs.avoidHighways }, "ferries".takeIf { prefs.avoidFerries })
        SettingsRow(Icons.Default.Navigation, Color(0xFF007AFF), "Navigation",
            if (avoid.isNotEmpty()) "Avoids " + avoid.joinToString(", ") else if (uiState.isMuted == true) "Voice off" else "Voice on") { open(SettingsPage.NAVIGATION) }
        SettingsRow(Icons.Default.NotificationsActive, Color(0xFFFF3B30), "Alerts",
            if (prefs.advancedAlerts) "Per kind" else (if (prefs.spokenAlerts) "Spoken, " else "Silent, ") + Units.distance(prefs.alertAheadMeters) + " ahead", last = true) { open(SettingsPage.ALERTS) }
    }
    GroupTitle("Map")
    SettingsGroup {
        SettingsRow(Icons.Default.Layers, Color(0xFFFF9500), "Map layers", "${Prefs.layerKinds.count { prefs.isChosen(it.key) }} of ${Prefs.layerKinds.size} on") { open(SettingsPage.LAYERS) }
        val pluginsOn = catalog.count { it.id !in off } + mine.size
        SettingsRow(Icons.Default.Extension, Color(0xFFAF52DE), "Plugins", if (catalog.isEmpty() && mine.isEmpty()) "None" else "$pluginsOn on") { open(SettingsPage.PLUGINS) }
        SettingsRow(Icons.Default.DownloadForOffline, Color(0xFF34C759), "Offline maps", if (mapFiles.isEmpty()) "None saved" else Units.bytes(MapFiles.bytesOnDisk)) { open(SettingsPage.OFFLINE) }
        SettingsRow(Icons.Default.Star, Color(0xFFFFCC00), "Saved places", if (places.isEmpty()) "None" else "${places.size}", last = true) { open(SettingsPage.PLACES) }
    }
    SettingsGroup {
        SettingsRow(Icons.AutoMirrored.Filled.HelpOutline, Color(0xFF8E8E93), "Help", null, last = false) { open(SettingsPage.HELP) }
        SettingsRow(Icons.Default.Info, Color(0xFF8E8E93), "About", BuildConfig.VERSION_NAME, last = !BuildConfig.DEBUG) { open(SettingsPage.ABOUT) }
        if (BuildConfig.DEBUG) SettingsRow(Icons.Default.Build, Color(0xFFA2845E), "Testing", if (simulating) "Simulating" else null, last = true) { open(SettingsPage.TESTING) }
    }
}

/** A rounded card that holds a group of rows, as a settings screen does. */
@Composable
fun SettingsGroup(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
        Column(content = content)
    }
}

@Composable
private fun GroupTitle(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 16.dp, top = 4.dp))
}

/** One category on the home page: a colored icon tile, its name, what it is set to. */
@Composable
private fun SettingsRow(icon: ImageVector, color: Color, title: String, value: String?, last: Boolean = false, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp)
        .testTag("settings-" + title.lowercase().replace(' ', '-')), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).background(color, RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(19.dp), tint = Color.White)
        }
        Spacer(Modifier.width(14.dp))
        Text(title, style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.width(10.dp))
        Text(value ?: "", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (!last) HorizontalDivider(Modifier.padding(start = 62.dp))
}

/** A page's card of controls, padded like the rows on the home page. */
@Composable
private fun PageGroup(content: @Composable ColumnScope.() -> Unit) {
    SettingsGroup { Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content) }
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun AccountPage(model: DriveViewModel) {
    val user by model.account.user.collectAsStateWithLifecycle()
    val accountError by model.account.error.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var confirmDelete by remember { mutableStateOf(false) }
    if (user != null) {
        PageGroup { Text("Signed in as ${model.account.displayName}") }
        Note("The same account as commutescout.com: your places, plugins and watch areas follow it.")
        PageGroup { TextButton({ model.account.signOut() }) { Text("Sign out") } }
        PageGroup { TextButton({ confirmDelete = true }) { Text("Delete account", color = MaterialTheme.colorScheme.error) } }
        Note("Deleting removes your watches, API keys and reports from commutescout.com.")
    } else {
        PageGroup {
            Button({ scope.launch { (context as? android.app.Activity)?.let { model.account.signInWithGoogle(it) } } }, Modifier.testTag("sign-in")) { Text("Sign in with Google") }
        }
        Note("Sign in to report from the road, keep watch areas, and manage API keys. Same account as the website.")
    }
    accountError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp)) }
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("Delete your account?") },
        text = { Text("This removes your watches, API keys and reports. It cannot be undone.") },
        confirmButton = { TextButton({ confirmDelete = false; scope.launch { model.account.deleteAccount() } }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel") } },
    )
}

@Composable
private fun AppearancePage(model: DriveViewModel) {
    val prefs = model.prefs
    PageGroup { Choice("Theme", Prefs.Theme.entries.map { it.label }, prefs.theme.ordinal) { prefs.theme = Prefs.Theme.entries[it] } }
    GroupTitle("Base map")
    PageGroup {
        // The map as it will look, in the chosen style, with the styles
        // as pictures: no need to close Settings to see the choice.
        BaseMapPreview(model)
        BaseMapCards(prefs.mapStyle, model.isDark) { prefs.mapStyle = it }
    }
    Note("Match theme follows the Theme setting above: Light by day, Dark at night.")
    PageGroup { ToggleRow("3D perspective", prefs.is3D) { model.toggle3D() } }
    Note("Tilts the map while you drive, so more of the road ahead is in view.")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UnitsPage(model: DriveViewModel) {
    val prefs = model.prefs
    PageGroup {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SegmentedButton(prefs.useMiles, { prefs.useMiles = true }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Miles") }
            SegmentedButton(!prefs.useMiles, { prefs.useMiles = false }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Kilometers") }
        }
    }
    Note("Used for distances on the map, in guidance and in spoken alerts.")
}

@Composable
private fun NavigationPage(model: DriveViewModel) {
    val prefs = model.prefs
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    GroupTitle("Route options")
    PageGroup {
        ToggleRow("Avoid tolls", prefs.avoidTolls) { prefs.avoidTolls = it }
        ToggleRow("Avoid highways", prefs.avoidHighways) { prefs.avoidHighways = it }
        ToggleRow("Avoid ferries", prefs.avoidFerries) { prefs.avoidFerries = it }
    }
    Note("Full road closures are always avoided. Changes apply to the next route.")
    GroupTitle("While driving")
    PageGroup {
        ToggleRow("Voice guidance", uiState.isMuted != true) { model.toggleMute() }
        ToggleRow("Show speed limit", prefs.showSpeedLimit) { prefs.showSpeedLimit = it }
        ToggleRow("Keep the screen on", prefs.keepAwake) { prefs.keepAwake = it }
    }
}

@Composable
private fun AlertsPage(model: DriveViewModel) {
    val prefs = model.prefs
    var showAdvanced by remember { mutableStateOf(false) }
    if (showAdvanced) AdvancedAlertsSheet(model) { showAdvanced = false }
    PageGroup {
        ToggleRow("Speak road alerts", prefs.spokenAlerts) { prefs.spokenAlerts = it }
        val aheadLabels = if (prefs.useMiles) listOf("0.5 mi ahead", "1 mi ahead", "2 mi ahead") else listOf("800 m ahead", "1.5 km ahead", "3 km ahead")
        val aheadValues = listOf(800.0, 1500.0, 3000.0)
        Choice("Warn about alerts", aheadLabels, aheadValues.indexOf(prefs.alertAheadMeters).coerceAtLeast(0)) { prefs.alertAheadMeters = aheadValues[it] }
    }
    Note("How far before an alert on your route the app warns you.")
    PageGroup {
        val stripLabels = if (prefs.useMiles) listOf("5 mi", "10 mi", "25 mi", "Whole route") else listOf("8 km", "16 km", "40 km", "Whole route")
        val stripValues = listOf(8047.0, 16093.0, 40234.0, 1e9)
        Choice("Show the next alert within", stripLabels, stripValues.indexOf(prefs.stripAheadMeters).coerceAtLeast(0)) { prefs.stripAheadMeters = stripValues[it] }
    }
    Note("The card under the next turn shows the nearest alert inside this distance.")
    PageGroup { LinkRow("Advanced alerts: ${if (prefs.advancedAlerts) "on" else "off"}") { showAdvanced = true } }
    Note("A warning distance, a second warning and a voice for each kind of alert.")
}

@Composable
private fun LayersPage(model: DriveViewModel) {
    val prefs = model.prefs
    PageGroup {
        Choice("Show", Prefs.SourceFilter.entries.map { it.label }, prefs.sourceFilter.ordinal) {
            prefs.sourceFilter = Prefs.SourceFilter.entries[it]; model.layersChanged()
        }
    }
    Note(when (prefs.sourceFilter) {
        Prefs.SourceFilter.ALL -> "Everything the map can show: agency data and the plugins you installed."
        Prefs.SourceFilter.OFFICIAL -> "Agency data only: state DOT and 511 feeds, cameras, signs and weather stations."
        Prefs.SourceFilter.PLUGINS -> "Plugin alerts only, with what each plugin loads."
    })
    if (prefs.sourceFilter != Prefs.SourceFilter.PLUGINS) {
        GroupTitle("Official sources")
        PageGroup {
            ToggleRow("Traffic", prefs.traffic) { prefs.traffic = it }
            Prefs.layerKinds.filter { it.key != "plugin" }.forEach { k ->
                ToggleRow(k.label, prefs.isChosen(k.key)) { prefs.setShown(k.key, it); model.layersChanged() }
            }
        }
    }
    if (prefs.sourceFilter != Prefs.SourceFilter.OFFICIAL) {
        val catalog by model.sources.catalog.collectAsStateWithLifecycle()
        val off by model.sources.hidden.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { model.sources.loadCatalog() }
        GroupTitle("Plugins")
        PageGroup {
            ToggleRow("Show plugin alerts", prefs.isChosen("plugin")) { prefs.setShown("plugin", it); model.layersChanged() }
            if (catalog.isEmpty()) Text("No plugin is installed. Find one in the marketplace.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            catalog.forEach { p ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    PluginBadge(p.id, PluginStyle.oneCategory(p.kinds), 22.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(p.name, maxLines = 2)
                        Text(if (p.kinds.isEmpty()) "Alerts" else "Loads " + p.kindsLabel,
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(p.id !in off, { model.sources.setOn(p.id, it); model.layersChanged() }, Modifier.testTag("switch-${p.name}"))
                }
            }
        }
        Note("A plugin's alerts are badges in its own color, and this says what each one puts on the map.")
    }
}

@Composable
private fun PluginsPage(model: DriveViewModel) {
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val off by model.sources.hidden.collectAsStateWithLifecycle()
    var showMarket by remember { mutableStateOf(false) }
    var showMine by remember { mutableStateOf(false) }
    if (showMarket) MarketplaceSheet(model) { showMarket = false }
    if (showMine) SourcesSheet(model) { showMine = false }
    LaunchedEffect(Unit) { model.sources.loadCatalog() }
    GroupTitle("Installed")
    PageGroup {
        if (catalog.isEmpty()) Text("No plugin is listed right now.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        catalog.forEach { p ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                PluginBadge(p.id, PluginStyle.oneCategory(p.kinds), 22.dp)
                Spacer(Modifier.width(10.dp))
                Text(p.name, Modifier.weight(1f), maxLines = 2)
                Switch(p.id !in off, { on -> model.sources.setOn(p.id, on); model.markers.refresh(true) }, Modifier.testTag("plugin-switch-${p.id}"))
            }
        }
    }
    Note("Plugins add alerts to the map. A plugin's alerts are badges in its own color.")
    PageGroup {
        LinkRow("Browse the marketplace") { showMarket = true }
        LinkRow("My plugins and private sources") { showMine = true }
    }
}

@Composable
private fun OfflinePage(model: DriveViewModel) {
    val prefs = model.prefs
    val mapFiles by MapFiles.files.collectAsStateWithLifecycle()
    var showOfflineMaps by remember { mutableStateOf(false) }
    if (showOfflineMaps) OfflineMapsSheet(model) { showOfflineMaps = false }
    PageGroup { ToggleRow("Save the map for each trip on Wi-Fi", prefs.mapAutoSave) { prefs.mapAutoSave = it } }
    Note("When a trip starts on Wi-Fi, the map along the route is saved, so it draws with no signal.")
    PageGroup {
        LinkRow(if (mapFiles.isEmpty()) "Maps saved on this phone: none yet"
                else "Maps saved on this phone: ${mapFiles.size}, ${Units.bytes(MapFiles.bytesOnDisk)}") { showOfflineMaps = true }
    }
    Note("Trip maps the app saved, and whole states you choose to download. Each one can be opened to see where it covers and whether the file is really there.")
}

@Composable
private fun PlacesPage(model: DriveViewModel) {
    val places by model.places.places.collectAsStateWithLifecycle()
    val user by model.account.user.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf<PlaceKind?>(null) }
    picking?.let { kind -> PlacePickerSheet(model, kind) { picking = null } }
    PageGroup {
        PlaceSlot("Home", Icons.Default.Home, model.places.home, { picking = PlaceKind.home }) { model.places.remove(it) }
        PlaceSlot("Work", Icons.Default.Work, model.places.work, { picking = PlaceKind.work }) { model.places.remove(it) }
    }
    Note("Home and Work are one each; setting a new one replaces the old.")
    GroupTitle("Favorites")
    PageGroup {
        model.places.saved.forEach { PlaceRow(it.name, Icons.Default.Star, it, model) }
        LinkRow("Add a favorite") { picking = PlaceKind.saved }
    }
    if (model.places.recents.isNotEmpty()) {
        GroupTitle("Recent destinations")
        PageGroup { model.places.recents.forEach { PlaceRow(it.name, Icons.Default.History, it, model) } }
        Note("The last ten places you navigated to.")
    }
    Note(if (user == null) "Sign in and these follow your account to the website and your other phone."
         else "Signed in: these follow your account to the website and your other phone.")
}

/** Home or Work: the place with Change and Remove, or the way to set it. */
@Composable
private fun PlaceSlot(label: String, icon: ImageVector, p: Place?, onSet: () -> Unit, onRemove: (Place) -> Unit) {
    if (p == null) {
        Row(Modifier.fillMaxWidth().clickable(onClick = onSet).padding(vertical = 6.dp).testTag("set-${label.lowercase()}"), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(10.dp))
            Text("Set $label", color = MaterialTheme.colorScheme.primary)
        }
    } else {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(label)
                Text(p.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            TextButton(onSet) { Text("Change") }
            IconButton({ onRemove(p) }) { Icon(Icons.Default.Delete, "Remove", tint = MaterialTheme.colorScheme.error) }
        }
    }
}

/**
 * Find a place and save it as Home, Work or a favorite, from Settings:
 * the same lookup the search bar uses.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlacePickerSheet(model: DriveViewModel, kind: PlaceKind, onClose: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    val here by model.here.collectAsStateWithLifecycle()
    val title = when (kind) { PlaceKind.home -> "Set Home"; PlaceKind.work -> "Set Work"; else -> "Add a favorite" }
    fun pick(name: String, lat: Double, lon: Double) { model.places.set(kind, name, lat, lon); onClose() }
    LaunchedEffect(text) {
        val q = text.trim()
        if (q.length < 2) { results = emptyList(); return@LaunchedEffect }
        delay(150)
        searching = true
        results = runCatching { Search.suggest(q, here?.let { it.lat to it.lon }) }.getOrDefault(emptyList())
        searching = false
    }
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("place-picker")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().testTag("place-search"), placeholder = { Text("Search a place or address") }, singleLine = true)
            if (kind != PlaceKind.saved) here?.let { h ->
                LinkRow("Use my current location") { pick("%.5f, %.5f".format(h.lat, h.lon), h.lat, h.lon) }
            }
            if (searching) Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("Searching") }
            results.forEach { r ->
                Column(Modifier.fillMaxWidth().clickable { pick(r.name, r.lat, r.lon) }.padding(vertical = 6.dp)) {
                    Text(r.name.substringBefore(","))
                    Text(r.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (results.isEmpty()) {
                val recents = model.places.recents.filter { text.isBlank() || it.name.contains(text, ignoreCase = true) }
                if (recents.isNotEmpty()) {
                    Heading("Recent destinations")
                    recents.forEach { p ->
                        Row(Modifier.fillMaxWidth().clickable { pick(p.name, p.lat, p.lon) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.History, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(10.dp)); Text(p.name, maxLines = 2)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HelpPage() {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    PageGroup {
        LinkRow("Contact") { open("https://commutescout.com/contact") }
        LinkRow("Data sources") { open("https://commutescout.com/data-sources") }
        LinkRow("Live map on the web") { open("https://commutescout.com/map") }
    }
    PageGroup {
        LinkRow("Developers and API") { open("https://commutescout.com/developers") }
        LinkRow("About CommuteScout") { open("https://commutescout.com/about") }
        LinkRow("Privacy") { open("https://commutescout.com/privacy") }
    }
}

@Composable
private fun AboutPage() {
    PageGroup { Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})") }
    Note("Routing and address lookup by Stadia Maps. Map data (c) OpenStreetMap contributors, drawn from files CommuteScout hosts. Road data from the agencies listed on commutescout.com. Verify before you drive.")
}

@Composable
private fun TestingPage(model: DriveViewModel) {
    val simulating by model.simulating.collectAsStateWithLifecycle()
    PageGroup { ToggleRow("Simulate driving the route", simulating) { model.simulating.value = it } }
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
private fun PlaceRow(label: String, icon: ImageVector, p: Place, model: DriveViewModel) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(10.dp))
        Text(label, Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
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
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("advanced-alerts")) {
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
