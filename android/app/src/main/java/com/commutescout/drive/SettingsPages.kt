package com.commutescout.drive

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGField
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.GroupFoot
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.KindChip
import com.commutescout.drive.design.NavDisc
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.Segmented
import com.commutescout.drive.design.SwitchRow
import com.commutescout.drive.design.Tag
import com.commutescout.drive.design.TagLook
import com.commutescout.drive.design.tag
import com.commutescout.drive.design.tint
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.util.Locale

private const val WEB = "https://commutescout.com"

@Composable
private fun openUrl(): (String) -> Unit {
    val context = LocalContext.current
    return { url -> runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
}

/** A choice in a radio group: the label, an optional line, and a blue check when chosen. */
@Composable
fun RadioRow(label: String, selected: Boolean, tag: String, sub: String? = null, onClick: () -> Unit) {
    SRow(label, Modifier.tag(tag).semantics { this.selected = selected }, sub = sub, onClick = onClick) {
        if (selected) DGIcon("check", DG.low, 20.dp, stroke = 2.6f) else Spacer(Modifier.size(20.dp))
    }
}

// MARK: map style

@Composable
fun MapStylePage(model: DriveViewModel) {
    val prefs = model.prefs
    Spacer(Modifier.height(4.dp))
    BaseMapCards(prefs.mapStyle, model.isDark) { prefs.mapStyle = it }
    GroupFoot("The map above shows the style you pick. Alerts, your route and the car look the same in every style.", Modifier.padding(top = 4.dp))
}

// MARK: units and region

@Composable
fun UnitsPage(model: DriveViewModel) {
    val prefs = model.prefs
    val locale = Locale.getDefault()
    val shape = RoundedCornerShape(22.dp)
    Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape)
        .background(Brush.verticalGradient(listOf(DG.low.tint(.10f), DG.low.tint(.05f)))).border(1.dp, DG.low.copy(alpha = .16f), shape)
        .padding(horizontal = 18.dp, vertical = 16.dp).tag("units-preview")) {
        Text("How the app reads", style = PageType.note.copy(fontWeight = FontWeight.SemiBold), color = DG.lowInk)
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
            Stat(Units.distance(644.0, prefs.useMiles), "Next turn")
            Stat(UnitRules.clock(LocalTime.of(8, 42), prefs.use24h), "Arrival")
            Stat(UnitRules.temperature(-0.6, prefs.useFahrenheit), "Pavement")
        }
        Spacer(Modifier.height(10.dp))
        Text("Your phone is set to ${locale.getDisplayLanguage(Locale.US)}, ${locale.getDisplayCountry(Locale.US).ifEmpty { "no region" }}.",
            style = PageType.rowSub, color = Color(0xFF23406F))
    }
    GroupHead("Distance")
    Group {
        DistanceChoice.entries.forEachIndexed { i, c ->
            if (i > 0) RowDivider(18.dp)
            RadioRow(c.label, prefs.distanceUnit == c, "unit-distance-${c.name.lowercase()}",
                sub = if (c == DistanceChoice.AUTO) UnitRules.autoDistance(prefs.phoneMiles) else null) { prefs.distanceUnit = c }
        }
    }
    GroupHead("Clock")
    Group {
        ClockChoice.entries.forEachIndexed { i, c ->
            if (i > 0) RowDivider(18.dp)
            RadioRow(c.label, prefs.clockUnit == c, "unit-clock-${c.name.lowercase()}",
                sub = if (c == ClockChoice.AUTO) UnitRules.autoClock(prefs.phone24) else null) { prefs.clockUnit = c }
        }
    }
    GroupHead("Temperature")
    Group {
        TempChoice.entries.forEachIndexed { i, c ->
            if (i > 0) RowDivider(18.dp)
            RadioRow(c.label, prefs.tempUnit == c, "unit-temp-${c.name.lowercase()}",
                sub = if (c == TempChoice.AUTO) UnitRules.autoTemp(prefs.phoneFahrenheit) else null) { prefs.tempUnit = c }
        }
    }
    GroupFoot("Units are used on the map, in directions and in spoken alerts.")
}

@Composable
private fun Stat(value: String, label: String) {
    Column {
        Text(value, style = PageType.stat, color = DG.ink)
        Text(label, style = PageType.note, color = DG.sub)
    }
}

// MARK: alerts

@Composable
fun AlertsPage(model: DriveViewModel) {
    val prefs = model.prefs
    val nav = LocalSettingsNav.current
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val hidden by model.sources.hidden.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.sources.loadCatalog() }
    Group(Modifier.padding(top = 4.dp)) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Text("Alerts reach you by", style = PageType.rowLabel, color = DG.ink)
            Spacer(Modifier.height(10.dp))
            Segmented(AlertDelivery.entries.map { it.label }, prefs.alertDelivery.ordinal, {
                prefs.alertDelivery = AlertDelivery.entries[it]; model.applyPrefs()
            }, icons = listOf("speaker", "bell"), tagPrefix = "alert-delivery")
        }
        RowDivider(0.dp)
        Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Warn me ahead by", Modifier.weight(1f), style = PageType.rowLabel, color = DG.ink)
                Text("On your route", style = PageType.note, color = DG.sub)
            }
            Spacer(Modifier.height(10.dp))
            val steps = aheadSteps(prefs.useMiles)
            Segmented(steps.map { it.second }, aheadIndex(prefs.alertAheadMeters, prefs.useMiles), {
                prefs.alertAheadMeters = steps[it].first; model.applyPrefs()
            }, tagPrefix = "alert-ahead")
        }
    }
    GroupHead("Official alerts")
    Group {
        val colors = listOf(DG.high, DG.mid, DG.low)
        AlertChips.tiers.forEachIndexed { t, tier ->
            if (t > 0) RowDivider(0.dp)
            Column(Modifier.padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 14.dp)) {
                Row(Modifier.padding(start = 4.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(colors[t]))
                    Spacer(Modifier.width(8.dp))
                    Text(tier.label, style = PageType.groupHead, color = DG.ink)
                }
                ChipFlow {
                    tier.chips.forEach { chip ->
                        val on = chip.key !in prefs.alertChipsOff
                        KindChip(chip.label, chip.key, colors[t], on, {
                            prefs.alertChipsOff = if (on) prefs.alertChipsOff + chip.key else prefs.alertChipsOff - chip.key
                        }, Modifier.tag("alert-chip-${chip.key}"))
                    }
                }
            }
        }
    }
    GroupFoot("From state DOTs, 511 feeds, CHP, the National Weather Service and fire agencies. A kind you turn off still shows on the map.")
    val plugins = catalog.filter { it.id !in hidden }
    GroupHead("Plugin alerts", trailing = { Tag("Not official", TagLook.PLUGIN, icon = "puzzle") })
    Group(plugin = true) {
        plugins.forEach { p ->
            val on = p.id !in prefs.pluginAlertsOff
            SRow(p.name, Modifier.tag("plugin-alerts-${p.id}"), sub = if (p.kinds.isEmpty()) "Community alerts" else p.kindsLabel.replaceFirstChar { it.uppercase() },
                lead = { PluginBadge(p.id, PluginStyle.oneCategory(p.kinds), 32.dp) },
                onClick = { prefs.pluginAlertsOff = if (on) prefs.pluginAlertsOff + p.id else prefs.pluginAlertsOff - p.id }) {
                com.commutescout.drive.design.DGSwitch(on, { prefs.pluginAlertsOff = if (it) prefs.pluginAlertsOff - p.id else prefs.pluginAlertsOff + p.id })
            }
            RowDivider(58.dp, plugin = true)
        }
        if (plugins.isEmpty()) {
            Text("No plugin is on. Plugins you install appear here.", Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
            RowDivider(0.dp, plugin = true)
        }
        SwitchRow("Speak plugin alerts", prefs.speakPluginAlerts, { prefs.speakPluginAlerts = it }, sub = "Off by default. Plugin alerts chime instead.",
            tag = "switch-Speak plugin alerts")
    }
    GroupFoot("Plugin alerts appear as badges in the plugin’s own color, never in the official colors, so you can always tell them apart.")
    Spacer(Modifier.height(14.dp))
    Group {
        SRow("Set warnings for each kind", Modifier.tag("alerts-per-kind"), icon = "gear", tileColor = DG.faint,
            value = if (prefs.advancedAlerts) "On" else "Off", chevron = true, onClick = { nav?.push(SettingsPage.ALERT_KINDS) })
    }
}

/** Chips that wrap onto as many lines as they need. */
@Composable
private fun ChipFlow(content: @Composable () -> Unit) {
    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

/** Per-kind warnings: a first distance, an optional second one closer in, and a voice for each kind. */
@Composable
fun AlertKindsPage(model: DriveViewModel) {
    val prefs = model.prefs
    val steps = if (prefs.useMiles) listOf(402.0, 805.0, 1609.0, 2414.0, 3219.0, 4828.0, 8047.0) else listOf(300.0, 500.0, 1000.0, 1500.0, 2000.0, 3000.0, 5000.0, 8000.0)
    fun nearest(m: Double) = steps.minByOrNull { kotlin.math.abs(it - m) } ?: m
    Column(Modifier.tag("advanced-alerts")) {
        Group(Modifier.padding(top = 4.dp)) {
            SwitchRow("Set alerts per kind", prefs.advancedAlerts, { prefs.advancedAlerts = it }, tag = "switch-Set alerts per kind",
                sub = "Each kind gets its own distance, a second warning and its own voice.")
        }
        GroupFoot("Off: every alert uses the distance on the Alerts page.")
        GroupHead("Next alert card")
        Group {
            val stripLabels = if (prefs.useMiles) listOf("5 mi", "10 mi", "25 mi", "Route") else listOf("8 km", "16 km", "40 km", "Route")
            val stripValues = listOf(8047.0, 16093.0, 40234.0, 1e9)
            Column(Modifier.padding(16.dp)) {
                Text("Show the next alert within", style = PageType.rowLabel, color = DG.ink)
                Spacer(Modifier.height(10.dp))
                Segmented(stripLabels, stripValues.indexOf(prefs.stripAheadMeters).coerceAtLeast(0), { prefs.stripAheadMeters = stripValues[it] }, tagPrefix = "strip-ahead")
            }
        }
        GroupFoot("The card under the next turn shows the nearest alert inside this distance.")
        if (prefs.advancedAlerts) {
            val rules = prefs.alertRules
            prefs.alertKinds.forEach { (key, label) ->
                val rule = rules[key] ?: Prefs.AlertRule()
                GroupHead(label)
                Group {
                    SwitchRow("Warn", rule.enabled, { prefs.setRule(key, rule.copy(enabled = it)) }, tag = "switch-warn-$key")
                    if (rule.enabled) {
                        RowDivider(18.dp)
                        Column(Modifier.padding(16.dp)) {
                            Text("First warning", style = PageType.rowSub, color = DG.sub)
                            Spacer(Modifier.height(8.dp))
                            val first = steps.indexOf(nearest(rule.firstMeters)).coerceAtLeast(0)
                            ChipFlow {
                                steps.forEachIndexed { i, m ->
                                    Pill(Units.distance(m), i == first) {
                                        prefs.setRule(key, rule.copy(firstMeters = m, repeatMeters = if (rule.repeatMeters >= m) 0.0 else rule.repeatMeters))
                                    }
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                            Text("Second warning", style = PageType.rowSub, color = DG.sub)
                            Spacer(Modifier.height(8.dp))
                            val second = listOf(0.0) + steps.filter { it < nearest(rule.firstMeters) }
                            val sel = second.indexOf(if (rule.repeatMeters == 0.0) 0.0 else nearest(rule.repeatMeters)).coerceAtLeast(0)
                            ChipFlow { second.forEachIndexed { i, m -> Pill(if (m == 0.0) "None" else Units.distance(m), i == sel) { prefs.setRule(key, rule.copy(repeatMeters = m)) } } }
                        }
                        RowDivider(18.dp)
                        SwitchRow("Speak it", rule.speak, { prefs.setRule(key, rule.copy(speak = it)) }, tag = "switch-speak-$key")
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            DGButton("Reset to defaults", { prefs.alertRules = emptyMap() }, Modifier.padding(horizontal = 14.dp).fillMaxWidth(), style = BtnStyle.QUIET)
        }
    }
}

@Composable
private fun Pill(label: String, on: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Box(Modifier.height(36.dp).clip(shape).background(if (on) DG.low else DG.ink.copy(alpha = .05f)).clickable(role = Role.RadioButton, onClick = onClick)
        .semantics { selected = on }.padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
        Text(label, style = PageType.chip, color = if (on) Color.White else DG.ink)
    }
}

// MARK: route options

@Composable
fun RoutePage(model: DriveViewModel) {
    val prefs = model.prefs
    Group(Modifier.padding(top = 4.dp)) {
        SwitchRow("Avoid tolls", prefs.avoidTolls, { prefs.avoidTolls = it }, icon = "toll", tileColor = DG.good, tag = "switch-Avoid tolls")
        RowDivider()
        SwitchRow("Avoid highways", prefs.avoidHighways, { prefs.avoidHighways = it }, icon = "route", tileColor = DG.good, tag = "switch-Avoid highways")
        RowDivider()
        SwitchRow("Avoid ferries", prefs.avoidFerries, { prefs.avoidFerries = it }, icon = "nav", tileColor = DG.good, tag = "switch-Avoid ferries")
    }
    GroupFoot("Full road closures are always avoided. Changes apply to the next route.")
    GroupHead("While driving")
    Group {
        SwitchRow("Show speed limit", prefs.showSpeedLimit, { prefs.showSpeedLimit = it }, icon = "speed", tileColor = DG.low, tag = "switch-Show speed limit")
        RowDivider()
        SwitchRow("Keep the screen on", prefs.keepAwake, { prefs.keepAwake = it }, icon = "light", tileColor = DG.mid, tag = "switch-Keep the screen on")
    }
}

// MARK: data sources

@Composable
fun DataSourcesPage() {
    val report by DataSources.report.collectAsStateWithLifecycle()
    val busy by DataSources.busy.collectAsStateWithLifecycle()
    val failed by DataSources.failed.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var justChecked by remember { mutableStateOf(false) }
    LaunchedEffect(busy) { if (!busy && justChecked) { delay(4000); justChecked = false } }
    val r = report
    Group(Modifier.padding(top = 4.dp).tag("sources-health")) {
        Row(Modifier.padding(start = 14.dp, end = 10.dp, top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(DG.good.tint(.82f), DG.good))), contentAlignment = Alignment.Center) {
                DGIcon("globe", Color.White, 22.dp)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(r?.coverage ?: if (failed) "Could not reach the server" else "Checking every feed", style = PageType.section, color = DG.ink)
                Text(when {
                    busy -> "Checking every feed"
                    justChecked -> "Checked just now"
                    r?.checkedAtMs != null -> "Checked at ${Units.clock(r.checkedAtMs)}"
                    failed -> "Try again when you have a signal"
                    else -> ""
                }, style = PageType.rowSub, color = DG.sub)
            }
            Box(Modifier.size(44.dp).clip(CircleShape).background(DG.low.copy(alpha = .1f))
                .clickable(role = Role.Button) { justChecked = true; scope.launch { DataSources.refresh() } }
                .semantics { contentDescription = "Check again" }.tag("sources-refresh"), contentAlignment = Alignment.Center) {
                if (busy) {
                    // Composed only while it turns: an endless animation on a still page keeps the screen drawing.
                    val spin by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart), label = "spin")
                    DGIcon("refresh", DG.low, 20.dp, Modifier.rotate(spin), stroke = 2.4f)
                } else DGIcon("refresh", DG.low, 20.dp, stroke = 2.4f)
            }
        }
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CountTile(r?.fresh, "Fresh", DG.good, DG.goodInk, Modifier.weight(1f))
            CountTile(r?.stale, "Stale", DG.mid, DG.midInk, Modifier.weight(1f))
            CountTile(r?.down, "Down", DG.high, DG.highInk, Modifier.weight(1f))
        }
    }
    if (r != null) {
        if (r.national.isNotEmpty()) {
            GroupHead("National")
            Group { r.national.forEachIndexed { i, f -> if (i > 0) RowDivider(62.dp); FeedLine(f) } }
        }
        if (r.stateRows.isNotEmpty()) {
            GroupHead("States")
            Group { r.stateRows.forEachIndexed { i, f -> if (i > 0) RowDivider(62.dp); FeedLine(f) } }
        }
    }
    GroupFoot("Fresh means updated within the feed’s normal interval. Stale means late. Down means the agency is not answering, so the map keeps its last data and marks it.")
}

@Composable
private fun CountTile(n: Int?, label: String, color: Color, ink: Color, modifier: Modifier) {
    val shape = RoundedCornerShape(16.dp)
    Column(modifier.clip(shape).background(color.copy(alpha = .08f)).border(1.dp, color.copy(alpha = .2f), shape).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(n?.toString() ?: "–", style = PageType.stat, color = ink)
        Text(label, style = PageType.rowSub, color = DG.sub)
    }
}

@Composable
private fun FeedLine(f: FeedRow) {
    val (dot, ink) = when (f.status) {
        FeedStatus.DOWN -> DG.high to DG.highInk
        FeedStatus.STALE -> DG.mid to DG.midInk
        else -> DG.good to DG.goodInk
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp).tag("feed-${f.code}-${f.title}"), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(DG.ink.copy(alpha = .05f)).border(1.dp, DG.hair, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center) { Text(f.code, style = PageType.tag.copy(fontWeight = FontWeight.Bold), color = DG.sub) }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(f.title, style = PageType.rowLabel, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (f.by.isNotEmpty()) Text(f.by, style = PageType.rowSub, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(8.dp))
        Column(horizontalAlignment = Alignment.End) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(dot))
                Spacer(Modifier.width(5.dp))
                Text(if (f.status == FeedStatus.LIVE) "Fresh" else f.status.word, style = PageType.tag, color = ink)
            }
            Text(SourcesHealth.ageText(f), style = PageType.note, color = DG.sub, maxLines = 1)
        }
    }
}

// MARK: account

@Composable
fun AccountPage(model: DriveViewModel) {
    val user by model.account.user.collectAsStateWithLifecycle()
    val busy by model.account.busy.collectAsStateWithLifecycle()
    val accountError by model.account.error.collectAsStateWithLifecycle()
    val nav = LocalSettingsNav.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val open = openUrl()
    var usage by remember { mutableStateOf<ApiUsage?>(null) }
    var usageAsked by remember { mutableStateOf(false) }
    LaunchedEffect(user) {
        usageAsked = false
        usage = if (user != null) model.account.apiUsage() else null
        usageAsked = true
    }
    val signedIn = user != null

    Group(Modifier.padding(top = 4.dp)) {
        AccountCard(model, signedIn)
        RowDivider(0.dp)
        if (signedIn) {
            SRow("Sign out", Modifier.tag("sign-out"), icon = "logout", tileColor = DG.faint, chevron = true, onClick = {
                nav?.confirm(ConfirmRequest("Sign out on this phone?",
                    "Your places, watch areas and plugin data are cleared from this phone. They stay in your account.",
                    listOf(ConfirmAction("Cancel"), ConfirmAction("Sign out", BtnStyle.PRIMARY, "sign-out-yes") { model.account.signOut() })))
            })
        } else {
            Box(Modifier.padding(14.dp)) {
                DGButton(if (busy) "Signing in" else "Sign in with Google", {
                    scope.launch { (context as? android.app.Activity)?.let { model.account.signInWithGoogle(it) } }
                }, Modifier.fillMaxWidth().tag("sign-in"), style = BtnStyle.BLUE, enabled = !busy)
            }
        }
    }
    accountError?.let { Text(it, Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = PageType.foot, color = DG.highInk) }
    GroupFoot(if (signedIn) "Signing out clears your places, watch areas and plugin data from this phone. They stay in your account. You can always drive without signing in."
        else "The same account as commutescout.com. You can always drive without signing in.")
    GroupHead("Your account adds")
    Group {
        val perks = listOf(
            Triple("report", "Reports from the road", "Tell other drivers what you see"),
            Triple("devices", "Watch areas on every device", "Synced with the website and your other phones"),
            Triple("puzzle", "Plugins", "Install them once, use them anywhere"),
            Triple("key", "API keys", "For your own apps and scripts"),
        )
        val tiles = listOf(DG.low, Color(0xFF12A39A), DG.plug, DG.mid)
        perks.forEachIndexed { i, (icon, label, sub) ->
            if (i > 0) RowDivider()
            SRow(label, icon = icon, tileColor = tiles[i], sub = sub) {
                if (signedIn) DGIcon("check", DG.good, 20.dp, stroke = 2.6f)
            }
        }
    }
    if (signedIn) {
        GroupHead("API use today")
        Group {
            val u = usage
            Column(Modifier.padding(16.dp).tag("api-meter")) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("Requests", Modifier.weight(1f), style = PageType.rowLabel, color = DG.ink)
                    Text(u?.usedText ?: if (usageAsked) ApiUsage.UNAVAILABLE else "–", style = PageType.rowLabel.copy(fontWeight = FontWeight.Bold), color = if (u?.full == true) DG.highInk else DG.ink)
                    Text(u?.limitText?.takeIf { it.isNotEmpty() }?.let { " $it" } ?: "", style = PageType.rowSub, color = DG.sub)
                }
                Spacer(Modifier.height(10.dp))
                Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(DG.ink.copy(alpha = .07f))) {
                    Box(Modifier.fillMaxWidth(u?.fraction ?: 0f).fillMaxHeight().clip(CircleShape)
                        .background(Brush.horizontalGradient(listOf(DG.lowTop, if (u?.full == true) DG.high else DG.low))))
                }
            }
            RowDivider(0.dp)
            Row(Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
                Limit(u?.keylessDaily?.let { ApiUsage.n(it) } ?: "–", "a day per address, no key", false, Modifier.weight(1f))
                Box(Modifier.width(1.dp).fillMaxHeight().background(DG.hair))
                Limit(u?.let { ApiUsage.n(it.limit) } ?: "–", u?.tierText ?: "a day with a free key", true, Modifier.weight(1f))
            }
            RowDivider(0.dp)
            SRow("Manage API keys", Modifier.tag("manage-keys"), value = u?.keysText, chevron = true, onClick = { open("$WEB/watch") })
        }
        GroupFoot("A free key allows ${ApiUsage.n(ApiUsage.FREE_DAILY)} requests a day and a pro key 10,000. The count starts over at midnight UTC.")
        Spacer(Modifier.height(18.dp))
        DGButton("Delete account", {
            nav?.confirm(ConfirmRequest("Delete your account?", "This removes your watch areas, API keys and reports for good. It cannot be undone.",
                listOf(ConfirmAction("Cancel"), ConfirmAction("Delete", BtnStyle.DANGER_SOLID, "delete-yes") { scope.launch { model.account.deleteAccount() } })))
        }, Modifier.padding(horizontal = 14.dp).fillMaxWidth().tag("delete-account"), style = BtnStyle.WARN, icon = "trash")
        GroupFoot("Deleting removes your watch areas, API keys and reports for good.")
    }
}

@Composable
private fun Limit(value: String, label: String, mine: Boolean, modifier: Modifier) {
    Column(modifier.padding(16.dp)) {
        Text(value, style = PageType.section.copy(fontSize = 19.sp), color = if (mine) DG.lowInk else DG.ink)
        Text(label, style = PageType.rowSub, color = DG.sub)
    }
}

// MARK: map layers

/**
 * The map's layers: which sources show, each official kind, and each
 * plugin. The same content is Settings > Map layers and the Layers
 * sheet on the map, so a switch means the same thing in both.
 */
@Composable
fun LayersContent(model: DriveViewModel, withStyles: Boolean = false) {
    val prefs = model.prefs
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val off by model.sources.hidden.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.sources.loadCatalog() }
    if (withStyles) {
        GroupHead("Map style")
        BaseMapCards(prefs.mapStyle, model.isDark) { prefs.mapStyle = it }
    }
    GroupHead("Show")
    Box(Modifier.padding(horizontal = 14.dp)) {
        Segmented(Prefs.SourceFilter.entries.map { it.label }, prefs.sourceFilter.ordinal, {
            prefs.sourceFilter = Prefs.SourceFilter.entries[it]; model.layersChanged()
        }, tagPrefix = "source-filter")
    }
    GroupFoot(when (prefs.sourceFilter) {
        Prefs.SourceFilter.ALL -> "Everything the map can show: agency data and the plugins you installed."
        Prefs.SourceFilter.OFFICIAL -> "Agency data only: state DOT and 511 feeds, cameras, signs and weather stations."
        Prefs.SourceFilter.PLUGINS -> "Plugin alerts only, with what each plugin loads."
    })
    if (prefs.sourceFilter != Prefs.SourceFilter.PLUGINS) {
        GroupHead("Official sources")
        Group {
            SwitchRow("Traffic", prefs.traffic, { prefs.traffic = it }, icon = "traffic", tileColor = DG.mid, tag = "switch-Traffic")
            Prefs.layerKinds.filter { it.key != "plugin" }.forEach { k ->
                RowDivider()
                SwitchRow(k.label, prefs.isChosen(k.key), { prefs.setShown(k.key, it); model.layersChanged() },
                    icon = layerIcon(k.key), tileColor = DG.low, tag = "switch-${k.label}")
            }
        }
    }
    if (prefs.sourceFilter != Prefs.SourceFilter.OFFICIAL) {
        GroupHead("Plugins", trailing = { Tag("Not official", TagLook.PLUGIN, icon = "puzzle") })
        Group(plugin = true) {
            val label = Prefs.layerKinds.firstOrNull { it.key == "plugin" }?.label ?: "Show plugin alerts"
            SwitchRow(label, prefs.isChosen("plugin"), { prefs.setShown("plugin", it); model.layersChanged() }, icon = "puzzle", tileColor = DG.plug,
                tag = "switch-$label")
            catalog.forEach { p ->
                RowDivider(58.dp, plugin = true)
                val on = p.id !in off
                SRow(p.name, Modifier.tag("plugin-switch-${p.id}"), sub = if (p.kinds.isEmpty()) "Alerts" else "Loads " + p.kindsLabel,
                    lead = { PluginBadge(p.id, PluginStyle.oneCategory(p.kinds), 32.dp) },
                    onClick = { model.sources.setOn(p.id, !on); model.layersChanged(); model.markers.refresh(true) }) {
                    com.commutescout.drive.design.DGSwitch(on, { model.sources.setOn(p.id, it); model.layersChanged(); model.markers.refresh(true) },
                        Modifier.tag("switch-${p.name}"))
                }
            }
            if (catalog.isEmpty()) Text("No plugin is installed. Find one in the marketplace.", Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
        }
        GroupFoot("A plugin’s alerts are badges in its own color, and this says what each one puts on the map.")
    }
}

private fun layerIcon(kind: String): String = when (kind) {
    "incident" -> "crash"; "lane_closure" -> "closure"; "chain_control" -> "chain"; "wildfire" -> "fire"
    "camera" -> "camera"; "sign" -> "sign"; "toll" -> "toll"; "weather", "rwis" -> "thermo"; "police" -> "police"
    else -> "layers"
}

// MARK: plugins, offline maps

@Composable
fun PluginsPage(model: DriveViewModel) {
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val off by model.sources.hidden.collectAsStateWithLifecycle()
    var showMarket by remember { mutableStateOf(false) }
    var showMine by remember { mutableStateOf(false) }
    var statusOf by remember { mutableStateOf<String?>(null) }
    if (showMarket) MarketplaceSheet(model) { showMarket = false }
    if (showMine) SourcesSheet(model) { showMine = false }
    statusOf?.let { PluginStatusSheet(model, it) { statusOf = null } }
    LaunchedEffect(Unit) { model.sources.loadCatalog() }
    GroupHead("Plugins", Modifier.padding(top = 0.dp), trailing = { Tag("Not official", TagLook.PLUGIN, icon = "puzzle") })
    Group(plugin = true) {
        if (catalog.isEmpty()) Text("No plugin is listed right now.", Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
        catalog.forEachIndexed { i, p ->
            if (i > 0) RowDivider(58.dp, plugin = true)
            SRow(p.name, Modifier.tag("plugin-row-${p.id}"), sub = if (p.ok == false) "Not answering" else "${p.count} alerts",
                value = if (p.id !in off) "Installed" else "Off", chevron = true,
                lead = { PluginBadge(p.id, PluginStyle.oneCategory(p.kinds), 32.dp) }, onClick = { statusOf = p.id })
        }
    }
    GroupFoot("Open one to see whether it is answering, what it loads, and to install or uninstall it. Plugin data follows you and no one else.")
    Spacer(Modifier.height(14.dp))
    Group {
        SRow("Browse the marketplace", icon = "store", tileColor = DG.plug, chevron = true, onClick = { showMarket = true })
        RowDivider()
        SRow("My plugins and private sources", icon = "key", tileColor = DG.faint, chevron = true, onClick = { showMine = true })
    }
}

@Composable
fun OfflinePage(model: DriveViewModel) {
    val mapFiles by MapFiles.files.collectAsStateWithLifecycle()
    var showOfflineMaps by remember { mutableStateOf(false) }
    if (showOfflineMaps) OfflineMapsSheet(model) { showOfflineMaps = false }
    Group(Modifier.padding(top = 4.dp)) {
        SRow("Maps on this phone", Modifier.tag("offline-maps-open"), icon = "download", tileColor = Color(0xFF0F9F8F),
            value = if (mapFiles.isEmpty()) "None yet" else "${mapFiles.size}, ${Units.bytes(MapFiles.bytesOnDisk)}", chevron = true,
            onClick = { showOfflineMaps = true })
    }
    GroupFoot("Trip maps the app saved, and whole states you choose to download. Saving and updates are set there.")
}

// MARK: saved places

/** Which slot the place search fills. */
object PlacePick { var kind by mutableStateOf(PlaceKind.saved) }

@Composable
fun PlacesPage(model: DriveViewModel) {
    val places by model.places.places.collectAsStateWithLifecycle()
    val user by model.account.user.collectAsStateWithLifecycle()
    val nav = LocalSettingsNav.current
    fun pick(kind: PlaceKind) { PlacePick.kind = kind; nav?.push(SettingsPage.PLACE_PICKER) }
    places.size // read so the page follows changes
    Group(Modifier.padding(top = 4.dp)) {
        PlaceSlot("Home", "home", model.places.home, { pick(PlaceKind.home) }) { model.places.remove(it) }
        RowDivider()
        PlaceSlot("Work", "work", model.places.work, { pick(PlaceKind.work) }) { model.places.remove(it) }
    }
    GroupFoot("Home and Work are one each; setting a new one replaces the old.")
    GroupHead("Favorites")
    Group {
        model.places.saved.forEach { p -> PlaceLine(p, "star") { model.places.remove(p) }; RowDivider() }
        SRow("Add a favorite", Modifier.tag("add-favorite"), icon = "plus", tileColor = DG.low, labelColor = DG.lowInk, onClick = { pick(PlaceKind.saved) })
    }
    if (model.places.recents.isNotEmpty()) {
        GroupHead("Recent destinations")
        Group { model.places.recents.forEachIndexed { i, p -> if (i > 0) RowDivider(); PlaceLine(p, "recent") { model.places.remove(p) } } }
        GroupFoot("The last ten places you navigated to.")
    }
    GroupFoot(if (user == null) "Sign in and these follow your account to the website and your other phones."
        else "Signed in: these follow your account to the website and your other phones.")
}

@Composable
private fun PlaceSlot(label: String, icon: String, p: Place?, onSet: () -> Unit, onRemove: (Place) -> Unit) {
    if (p == null) {
        SRow("Set $label", Modifier.tag("set-${label.lowercase()}"), icon = icon, tileColor = DG.low, labelColor = DG.lowInk, onClick = onSet)
    } else {
        SRow(label, icon = icon, tileColor = DG.low, sub = p.name, onClick = onSet) {
            Text("Change", style = PageType.rowValue, color = DG.lowInk)
            NavDisc("trash", "Remove", { onRemove(p) })
        }
    }
}

@Composable
private fun PlaceLine(p: Place, icon: String, onRemove: () -> Unit) {
    SRow(p.name, icon = icon, tileColor = if (icon == "star") Color(0xFFE8A70C) else DG.faint) { NavDisc("trash", "Remove", onRemove) }
}

/** Find a place and save it as Home, Work or a favorite: the same lookup the search bar uses. */
@Composable
fun PlacePickerPage(model: DriveViewModel) {
    val nav = LocalSettingsNav.current
    val kind = PlacePick.kind
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Suggestion>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    val here by model.here.collectAsStateWithLifecycle()
    fun pick(name: String, lat: Double, lon: Double) { model.places.set(kind, name, lat, lon); nav?.back() }
    LaunchedEffect(text) {
        val q = text.trim()
        if (q.length < 2) { results = emptyList(); return@LaunchedEffect }
        delay(150)
        searching = true
        results = runCatching { Search.suggest(q, here?.let { it.lat to it.lon }) }.getOrDefault(emptyList())
        searching = false
    }
    Column(Modifier.tag("place-picker")) {
        Text(when (kind) { PlaceKind.home -> "Set Home"; PlaceKind.work -> "Set Work"; else -> "Add a favorite" },
            Modifier.padding(start = 24.dp, bottom = 10.dp), style = PageType.section, color = DG.ink)
        DGField("Search", text, { text = it }, placeholder = "A place or address", tag = "place-search")
        Spacer(Modifier.height(12.dp))
        Group {
            if (kind != PlaceKind.saved) here?.let { h ->
                SRow("Use my current location", icon = "locate", tileColor = DG.low, onClick = { pick("%.5f, %.5f".format(h.lat, h.lon), h.lat, h.lon) })
                RowDivider()
            }
            if (searching) SRow("Searching", sub = null)
            results.forEachIndexed { i, r ->
                if (i > 0) RowDivider(18.dp)
                SRow(r.name.substringBefore(","), sub = r.name, onClick = { pick(r.name, r.lat, r.lon) })
            }
            if (results.isEmpty() && !searching) {
                val recents = model.places.recents.filter { text.isBlank() || it.name.contains(text, ignoreCase = true) }
                recents.forEachIndexed { i, p ->
                    if (i > 0) RowDivider()
                    SRow(p.name, icon = "recent", tileColor = DG.faint, onClick = { pick(p.name, p.lat, p.lon) })
                }
                if (recents.isEmpty()) Text("Type at least two letters.", Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
            }
        }
    }
}

// MARK: help, about, testing

@Composable
fun HelpPage() {
    val open = openUrl()
    Group(Modifier.padding(top = 4.dp)) {
        SRow("Contact", icon = "mail", tileColor = DG.low, chevron = true, onClick = { open("$WEB/contact") })
        RowDivider()
        SRow("Data sources", icon = "antenna", tileColor = Color(0xFF253047), chevron = true, onClick = { open("$WEB/data-sources") })
        RowDivider()
        SRow("Live map on the web", icon = "map", tileColor = Color(0xFF5B6CF0), chevron = true, onClick = { open("$WEB/map") })
        RowDivider()
        SRow("Developers and API", icon = "key", tileColor = DG.mid, chevron = true, onClick = { open("$WEB/developers") })
    }
    GroupFoot("Tell us what is wrong or missing. Each page opens on commutescout.com.")
}

@Composable
fun AboutPage(openVoiceLicenses: () -> Unit) {
    val open = openUrl()
    Group(Modifier.padding(top = 4.dp)) {
        SRow("Version", value = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        RowDivider(18.dp)
        SRow("About CommuteScout", chevron = true, onClick = { open("$WEB/about") })
        RowDivider(18.dp)
        SRow("Privacy", chevron = true, onClick = { open("$WEB/privacy") })
        RowDivider(18.dp)
        SRow("Voice licenses", Modifier.tag("about-voice-licenses"), chevron = true, onClick = openVoiceLicenses)
    }
    GroupFoot("Routing and address lookup by Stadia Maps. Map data © OpenStreetMap contributors, drawn from files CommuteScout hosts. " +
        "Road data from the agencies listed on commutescout.com. Verify before you drive.")
}

@Composable
fun TestingPage(model: DriveViewModel) {
    val simulating by model.simulating.collectAsStateWithLifecycle()
    val prefs = model.prefs
    Group(Modifier.padding(top = 4.dp)) {
        SwitchRow("Simulate driving the route", simulating, { model.simulating.value = it }, tag = "switch-Simulate driving the route")
        RowDivider(18.dp)
        SRow("Show the first-run screen", sub = "Opens the next time the app starts", onClick = { prefs.welcomeDone = false })
    }
    Text("Debug builds only.", Modifier.padding(start = 24.dp, top = 8.dp), style = DGType.meta, color = DG.sub)
}
