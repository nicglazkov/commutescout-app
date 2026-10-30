package com.commutescout.drive

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.ConfirmCard
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.GroupFoot
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.PageNav
import com.commutescout.drive.design.PageSheet
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.tag
import kotlinx.coroutines.launch

/** The pages of Settings; the home page is the empty stack. */
enum class SettingsPage(val title: String) {
    ACCOUNT("Account"), MAP_STYLE("Map style"), UNITS("Units and region"), VOICE("Voice"), ALERTS("Alerts"),
    ALERT_KINDS("Set warnings for each kind"), ROUTE("Route options"), SOURCES("Data sources"), LAYERS("Map layers"),
    PLUGINS("Plugins"), OFFLINE("Offline maps"), PLACES("Saved places"), PLACE_PICKER("Find a place"),
    HELP("Help and feedback"), ABOUT("About and privacy"), VOICE_LICENSES("Voice licenses"), TESTING("Testing");

    companion object {
        /** A page from a debug extra: its name in any case, dashes for underscores. */
        fun of(s: String?): SettingsPage? = entries.firstOrNull { it.name.equals(s?.replace('-', '_'), ignoreCase = true) }
    }
}

/** One button on a confirm card. */
data class ConfirmAction(val label: String, val style: BtnStyle = BtnStyle.PLAIN, val tag: String? = null, val run: () -> Unit = {})

/** A question the sheet asks on its confirm card; a tap on the veil is [onDismiss]. */
data class ConfirmRequest(val title: String, val body: String?, val actions: List<ConfirmAction>, val onDismiss: () -> Unit = {})

/** What a settings page can ask of the sheet it is in. */
class SettingsNav(val push: (SettingsPage) -> Unit, val back: () -> Unit, val confirm: (ConfirmRequest) -> Unit, val close: () -> Unit)

val LocalSettingsNav = staticCompositionLocalOf<SettingsNav?> { null }

/**
 * Settings: one tall frosted sheet over the map. The home page lists
 * the categories with what each is set to; a page pushes in from the
 * side with a back arrow, and Back returns to the page before it, then
 * closes the sheet. Map style drops the sheet's top so the live map
 * above shows the style being picked. Confirm questions rise as a card
 * inside the sheet, not a system dialog.
 */
@Composable
fun SettingsSheet(model: DriveViewModel, start: SettingsPage? = null, onClose: () -> Unit) {
    var stack by remember { mutableStateOf(listOfNotNull(start)) }
    var forward by remember { mutableStateOf(true) }
    var confirm by remember { mutableStateOf<ConfirmRequest?>(null) }
    var shown by remember { mutableStateOf<ConfirmRequest?>(null) }
    val rise = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    var leaving by remember { mutableStateOf(false) }
    fun close() {
        if (leaving) return
        leaving = true
        scope.launch { rise.animateTo(1f, tween(260, easing = DG.hideEase)); onClose() }
    }
    fun push(p: SettingsPage) { forward = true; stack = stack + p }
    fun back() { if (stack.isEmpty()) close() else { forward = false; stack = stack.dropLast(1) } }
    val nav = remember { SettingsNav({ push(it) }, { back() }, { confirm = it; shown = it }, { close() }) }
    LaunchedEffect(Unit) {
        rise.animateTo(0f, DG.slide())
        DataSources.refresh()
    }
    BackHandler(enabled = !leaving) { if (confirm != null) { confirm?.onDismiss?.invoke(); confirm = null } else back() }
    val page = stack.lastOrNull()

    CompositionLocalProvider(LocalSettingsNav provides nav) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val height = with(LocalDensity.current) { maxHeight.toPx() }
            // Above the sheet: a tap closes it, except over the live map of Map style.
            Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) { if (page != SettingsPage.MAP_STYLE) close() })
            val top by animateDpAsState(if (page == SettingsPage.MAP_STYLE) maxHeight * .38f else 0.dp, DG.snap(), label = "sheet-top")
            // The spring overshoots on its way back to 0; padding must never go below it.
            PageSheet(Modifier.padding(top = top.coerceAtLeast(0.dp)).graphicsLayer { translationY = rise.value * height }.testTag("settings-sheet")) {
                AnimatedContent(page, Modifier.fillMaxSize(), label = "settings-page", transitionSpec = {
                    val d = if (forward) 1 else -1
                    (slideInHorizontally(tween(420, 120, DG.easeOut)) { d * 90 } + fadeIn(tween(420, 120, DG.easeOut))) togetherWith
                        (slideOutHorizontally(tween(200)) { -d * 90 } + fadeOut(tween(200)))
                }) { current ->
                    Column(Modifier.fillMaxSize()) {
                        if (current == null) PageNav("Settings", onClose = { close() }, home = true, closeTag = "settings-close")
                        else PageNav(current.title, onBack = { back() }, backTag = "settings-back")
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)
                            .padding(bottom = 28.dp)) {
                            when (current) {
                                null -> SettingsHome(model) { push(it) }
                                SettingsPage.ACCOUNT -> AccountPage(model)
                                SettingsPage.MAP_STYLE -> MapStylePage(model)
                                SettingsPage.UNITS -> UnitsPage(model)
                                SettingsPage.VOICE -> VoicePage(model) { push(SettingsPage.VOICE_LICENSES) }
                                SettingsPage.ALERTS -> AlertsPage(model)
                                SettingsPage.ALERT_KINDS -> AlertKindsPage(model)
                                SettingsPage.ROUTE -> RoutePage(model)
                                SettingsPage.SOURCES -> DataSourcesPage()
                                SettingsPage.LAYERS -> LayersContent(model)
                                SettingsPage.PLUGINS -> PluginsPage(model)
                                SettingsPage.OFFLINE -> OfflinePage(model)
                                SettingsPage.PLACES -> PlacesPage(model)
                                SettingsPage.PLACE_PICKER -> PlacePickerPage(model)
                                SettingsPage.HELP -> HelpPage()
                                SettingsPage.ABOUT -> AboutPage { push(SettingsPage.VOICE_LICENSES) }
                                SettingsPage.VOICE_LICENSES -> VoiceLicensesPage()
                                SettingsPage.TESTING -> TestingPage(model)
                            }
                        }
                    }
                }
            }
            val c = shown
            if (c != null) ConfirmCard(confirm != null, c.title, c.body, { c.onDismiss(); confirm = null }) {
                c.actions.forEach { a ->
                    DGButton(a.label, { confirm = null; a.run() }, Modifier.weight(1f).then(if (a.tag != null) Modifier.tag(a.tag) else Modifier), style = a.style)
                }
            }
        }
    }
}

/**
 * Map layers on its own, from the map's tools: the same frosted sheet as
 * Settings and the same switches as Settings > Map layers, with the map
 * styles on top.
 */
@Composable
fun LayersOverlay(model: DriveViewModel, onClose: () -> Unit) {
    val rise = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    var leaving by remember { mutableStateOf(false) }
    fun close() {
        if (leaving) return
        leaving = true
        scope.launch { rise.animateTo(1f, tween(260, easing = DG.hideEase)); onClose() }
    }
    LaunchedEffect(Unit) { rise.animateTo(0f, DG.slide()) }
    BackHandler(enabled = !leaving) { close() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val height = with(LocalDensity.current) { maxHeight.toPx() }
        Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) { close() })
        PageSheet(Modifier.padding(top = maxHeight * .12f).graphicsLayer { translationY = rise.value * height }.testTag("layers-sheet")) {
            PageNav("Layers", onClose = { close() }, home = true, closeTag = "layers-close")
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 28.dp)) {
                LayersContent(model, withStyles = true)
            }
        }
    }
}

@Composable
private fun SettingsHome(model: DriveViewModel, open: (SettingsPage) -> Unit) {
    val prefs = model.prefs
    val user by model.account.user.collectAsStateWithLifecycle()
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val mine by model.sources.mine.collectAsStateWithLifecycle()
    val off by model.sources.hidden.collectAsStateWithLifecycle()
    val places by model.places.places.collectAsStateWithLifecycle()
    val mapFiles by MapFiles.files.collectAsStateWithLifecycle()
    val simulating by model.simulating.collectAsStateWithLifecycle()
    val report by DataSources.report.collectAsStateWithLifecycle()
    val voiceReady by Engine.alerts.speaker.ready.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()

    Group(Modifier.padding(top = 4.dp)) {
        AccountCard(model, user != null, Modifier.tag("settings-account").clickable { open(SettingsPage.ACCOUNT) }, chevron = true)
    }
    GroupHead("Map and display")
    Group {
        HomeRow("Map style", "map-style", "map", Color(0xFF5B6CF0), MapStyles.name(prefs.mapStyle, model.isDark)) { open(SettingsPage.MAP_STYLE) }
        RowDivider()
        HomeRow("Units and region", "units", "ruler", Color(0xFF12A39A), UnitRules.summary(prefs.useMiles, prefs.use24h)) { open(SettingsPage.UNITS) }
    }
    GroupHead("Driving")
    Group {
        val voice = remember(voiceReady, prefs.voiceName) { voiceSummary(prefs, if (voiceReady) Engine.alerts.speaker.voices().map(VoiceInfo::of) else emptyList()) }
        HomeRow("Voice", "voice", "speaker", DG.low, if (uiState.isMuted == true) "Off" else voice) { open(SettingsPage.VOICE) }
        RowDivider()
        HomeRow("Alerts", "alerts", "bell", DG.high, alertsSummary(prefs)) { open(SettingsPage.ALERTS) }
        RowDivider()
        val avoid = listOfNotNull("tolls".takeIf { prefs.avoidTolls }, "highways".takeIf { prefs.avoidHighways }, "ferries".takeIf { prefs.avoidFerries })
        HomeRow("Route options", "navigation", "route", DG.good, if (avoid.isEmpty()) "Fastest" else "Avoids " + avoid.joinToString(", ")) { open(SettingsPage.ROUTE) }
    }
    GroupHead("Map data")
    Group {
        SRow("Data sources", Modifier.tag("settings-data-sources"), icon = "antenna", tileColor = Color(0xFF253047), chevron = true,
            onClick = { open(SettingsPage.SOURCES) }) {
            report?.let { r ->
                if (r.worst != FeedStatus.FRESH) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(if (r.worst == FeedStatus.DOWN) DG.high else DG.mid))
                    Spacer(Modifier.width(6.dp))
                }
                val color = when (r.worst) { FeedStatus.DOWN -> DG.highInk; FeedStatus.STALE -> DG.midInk; else -> DG.sub }
                Text(r.headline, style = PageType.rowValue, color = color, maxLines = 1)
            }
        }
        RowDivider()
        HomeRow("Map layers", "map-layers", "layers", DG.mid, "${Prefs.layerKinds.count { prefs.isChosen(it.key) }} of ${Prefs.layerKinds.size}") { open(SettingsPage.LAYERS) }
        RowDivider()
        val pluginsOn = catalog.count { it.id !in off } + mine.size
        HomeRow("Plugins", "plugins", "puzzle", DG.plug, if (catalog.isEmpty() && mine.isEmpty()) "None" else "$pluginsOn on") { open(SettingsPage.PLUGINS) }
        RowDivider()
        HomeRow("Offline maps", "offline-maps", "download", Color(0xFF0F9F8F), if (mapFiles.isEmpty()) "None" else Units.bytes(MapFiles.bytesOnDisk)) { open(SettingsPage.OFFLINE) }
        RowDivider()
        val saved = places.count { it.kind != PlaceKind.recent }
        HomeRow("Saved places", "saved-places", "star", Color(0xFFE8A70C), if (saved == 0) "None" else "$saved") { open(SettingsPage.PLACES) }
    }
    GroupHead("Help")
    Group {
        HomeRow("Help and feedback", "help", "help", DG.faint, null) { open(SettingsPage.HELP) }
        RowDivider()
        HomeRow("About and privacy", "about", "shield", DG.faint, "Version ${BuildConfig.VERSION_NAME}") { open(SettingsPage.ABOUT) }
        if (BuildConfig.DEBUG) {
            RowDivider()
            HomeRow("Testing", "testing", "gear", Color(0xFFA2845E), if (simulating) "Simulating" else null) { open(SettingsPage.TESTING) }
        }
    }
    GroupFoot("Not affiliated with any government agency. Check 511 or your state DOT before you drive.", Modifier.padding(top = 6.dp))
}

/** The Alerts row on the home page: "Voice, 1 mi ahead", or "Voice, per kind". */
fun alertsSummary(prefs: Prefs): String =
    if (prefs.advancedAlerts) prefs.alertDelivery.label + ", per kind"
    else prefs.alertDelivery.label + ", " + aheadLabel(prefs.alertAheadMeters, prefs.useMiles) + " ahead"

/** The warning distances, in the driver's unit: 0.5, 1 and 2 miles, or 800 m, 1.5 and 3 km. */
fun aheadSteps(miles: Boolean): List<Pair<Double, String>> =
    if (miles) listOf(805.0 to "0.5 mi", 1609.0 to "1 mi", 3219.0 to "2 mi") else listOf(800.0 to "800 m", 1500.0 to "1.5 km", 3000.0 to "3 km")

fun aheadIndex(meters: Double, miles: Boolean): Int = aheadSteps(miles).withIndex().minBy { kotlin.math.abs(it.value.first - meters) }.index
fun aheadLabel(meters: Double, miles: Boolean): String = aheadSteps(miles)[aheadIndex(meters, miles)].second

@Composable
private fun HomeRow(label: String, tag: String, icon: String, color: Color, value: String?, onClick: () -> Unit) {
    SRow(label, Modifier.tag("settings-$tag"), icon = icon, tileColor = color, value = value, chevron = true, onClick = onClick)
}

/** Who is signed in: a round avatar with the initial, the name and the email. Signed out, the way in. */
@Composable
fun AccountCard(model: DriveViewModel, signedIn: Boolean, modifier: Modifier = Modifier, chevron: Boolean = false) {
    Row(modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(56.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(DG.lowTop, DG.low))), contentAlignment = Alignment.Center) {
            if (signedIn) Text(model.account.initial, style = PageType.stat, color = Color.White)
            else DGIcon("people", Color.White, 26.dp)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(if (signedIn) model.account.displayName else "Sign in", style = PageType.section, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (signedIn) model.account.email ?: "Signed in" else "Reports, watch areas and sync", style = PageType.rowSub, color = DG.sub,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (chevron) DGIcon("chevR", DG.ink, 20.dp, stroke = 2.4f)
    }
}

// The parts below are the older Material settings controls. Sheets that
// other screens still draw use them; Settings itself does not.

@Composable
fun GroupTitle(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 16.dp, top = 4.dp))
}

@Composable
fun PageGroup(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh)
        .padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
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
