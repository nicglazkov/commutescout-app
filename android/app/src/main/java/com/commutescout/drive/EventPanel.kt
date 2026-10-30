package com.commutescout.drive

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.HighlightOff
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.border
import com.commutescout.drive.design.AlertLook
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Disc
import com.commutescout.drive.design.GlassRound
import com.commutescout.drive.design.Looks
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.tint
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.ZoneId

/**
 * The event sheet: one panel for every kind of marker, attached to the
 * bottom edge rather than a modal sheet, so it never fights the other
 * sheets and the map above it stays in use.
 *
 * Collapsed it shows what a glance needs: the kind, the status when an
 * alert opened it, the title and the first facts. Expanded it shows
 * everything the website's popup does, scrolling. Drag or tap the
 * grabber to switch; a drag down from collapsed closes it.
 */
@Composable
fun EventPanel(sheet: EventSheet, here: LatLon?, model: DriveViewModel) {
    val marker = sheet.marker
    val sheetKey = marker?.key ?: sheet.alert?.let { "alert:${it.eventId ?: "${it.lat},${it.lon}"}" } ?: ""
    var expanded by remember(sheetKey) { mutableStateOf(false) }
    val drag = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    // Ages ("12 min ago") stay true while the panel sits open.
    val now by produceState(System.currentTimeMillis()) { while (true) { delay(30_000); value = System.currentTimeMillis() } }
    val screen = LocalConfiguration.current.screenHeightDp.dp
    val card = remember(marker, now) { marker?.let { EventCard.of(it, now, ZoneId.systemDefault(), Units.useMiles) } }
    val accent = when {
        marker?.kind == "plugin" -> PluginStyle.color(PluginStyle.sourceId(marker))
        card?.darker == true -> Color(0xFF7F1D1D)
        else -> MarkerIcons.color(marker?.kind ?: sheet.alert?.kind ?: "")
    }

    fun settle(velocity: Float) {
        val dy = drag.value
        scope.launch {
            when {
                dy < -40f || velocity < -800f -> expanded = true
                (dy > 40f || velocity > 800f) && expanded -> expanded = false
                dy > 40f || velocity > 800f -> { model.clearMarker(); return@launch }
            }
            drag.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy))
        }
    }
    val dragState = rememberDraggableState { delta -> scope.launch { drag.snapTo((drag.value + delta).coerceIn(-200f, 400f)) } }
    val dragging = Modifier.draggable(dragState, Orientation.Vertical, onDragStopped = { settle(it) })

    Box(
        Modifier.fillMaxWidth().graphicsLayer { translationY = drag.value.coerceAtLeast(0f) }
            .glass(RoundedCornerShape(topStart = DG.rSheet, topEnd = DG.rSheet), elevation = 26.dp, strong = true)
            .testTag("marker-card"),
    ) {
        // A watch alert whose event is over has its own layout.
        if (sheet.isClearedAlert()) {
            Column(Modifier.navigationBarsPadding().testTag("event-sheet")) {
                Box(Modifier.fillMaxWidth().height(22.dp).then(dragging), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(width = 40.dp, height = 5.dp).clip(CircleShape).background(DG.ink.copy(alpha = 0.16f)))
                }
                ClearedPanel(sheet, now, model)
            }
            return@Box
        }
        // Never taller than its content, never taller than its height
        // allows: the scrolling part takes what the grabber and the
        // action row leave, measured rather than guessed.
        Column(Modifier.navigationBarsPadding().heightIn(max = if (expanded) screen * 0.85f else screen * 0.5f)
            .animateContentSize(spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow))
            .testTag("event-sheet")) {
            // The grabber: tap to switch heights, drag to resize or close.
            Box(Modifier.fillMaxWidth().height(22.dp).then(dragging).clickable { expanded = !expanded }
                .semantics { contentDescription = if (expanded) "Show less" else "Show more" }, contentAlignment = Alignment.Center) {
                Box(Modifier.size(width = 40.dp, height = 5.dp).clip(CircleShape).background(DG.ink.copy(alpha = 0.16f)))
            }
            Column(
                Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp).padding(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Header(card?.chip ?: EventCard.chipFor(sheet.alert?.kind), accent,
                    card?.age ?: sheet.alert?.sentAt?.let { EventText.agoMs(it * 1000, now) }, dragging,
                    look = marker?.let { Looks.of(it) } ?: Looks.ofKind(sheet.alert?.kind ?: "")) { model.clearMarker() }
                sheet.status?.let { StatusBanner(it, sheet.alert, marker?.kind, now) { model.retryStatus() } }
                if (marker != null && card != null) {
                    MarkerBody(marker, card, here, model, expanded) { expanded = true }
                } else sheet.alert?.let { YourAlert(it, now, expanded) }
            }
            // Outside the scrolling part, so a collapsed panel always says
            // there is more and how to get it.
            if (!expanded && marker != null) {
                Row(Modifier.padding(horizontal = 16.dp).padding(bottom = 4.dp).fillMaxWidth().height(48.dp).clip(RoundedCornerShape(24.dp))
                    .background(Color.White.copy(alpha = 0.7f)).border(0.5.dp, DG.hair, RoundedCornerShape(24.dp))
                    .clickable { expanded = true }.testTag("more-details"),
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Text(if ((card?.dispatchCount ?: 0) > 0) "More details and the dispatch log" else "More details",
                        style = DGType.row.copy(fontWeight = FontWeight.SemiBold), color = DG.low)
                    Spacer(Modifier.width(6.dp))
                    DGIcon("chevron", DG.low, 16.dp)
                }
            }
            Actions(sheet, model)
        }
    }
}

/** The kind chip, the age, and close. */
@Composable
private fun Header(chip: String, accent: Color, age: String?, dragging: Modifier, look: AlertLook, onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth().then(dragging), verticalAlignment = Alignment.CenterVertically) {
        // A community report keeps its plugin colour; official kinds take the design's tone.
        if (look.community) Box(Modifier.size(DG.disc).clip(CircleShape).background(accent), contentAlignment = Alignment.Center) {
            DGIcon(look.icon, Color.White, 22.dp)
        } else Disc(look.icon, look.tone, DG.disc)
        Spacer(Modifier.width(12.dp))
        Text(chip, style = DGType.label, color = if (look.community) accent else look.tone.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f))
        age?.let {
            Spacer(Modifier.width(8.dp))
            Text(it, style = DGType.small, color = DG.sub)
            Spacer(Modifier.width(8.dp))
        }
        Box(Modifier.size(36.dp).clip(CircleShape).background(DG.ink.copy(alpha = 0.06f)).clickable(onClick = onClose)
            .testTag("marker-close").semantics { contentDescription = "Close" }, contentAlignment = Alignment.Center) {
            DGIcon("close", DG.sub, 18.dp)
        }
    }
}

/** What became of the alerted event, over everything else. */
@Composable
private fun StatusBanner(status: EventStatus, alert: AlertTap?, kind: String?, now: Long, onRetry: () -> Unit) {
    val text = EventBanner.text(status, alert, kind, now, ZoneId.systemDefault())
    val gray = MaterialTheme.colorScheme.onSurfaceVariant
    val (tint, icon) = when (status.state) {
        EventState.LOADING -> gray to null
        EventState.ACTIVE -> Color(0xFF1E8E3E) to Icons.Default.CheckCircle
        EventState.CHANGED -> Color(0xFF1F6FD1) to Icons.Default.Sync
        EventState.CLEARED -> gray to Icons.Default.Verified
        EventState.GONE -> gray to Icons.Default.HighlightOff
        EventState.UNKNOWN -> Color(0xFFB26A00) to Icons.Default.WifiOff
    }
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(tint.copy(alpha = 0.10f))
        .border(0.5.dp, tint.copy(alpha = 0.28f), RoundedCornerShape(18.dp)).padding(14.dp)
        .testTag("event-status"), verticalAlignment = Alignment.Top) {
        if (icon == null) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = tint)
        else Icon(icon, null, Modifier.size(20.dp), tint = tint)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(text.headline, style = DGType.row.copy(fontWeight = FontWeight.Bold), color = if (status.state == EventState.LOADING) DG.ink else tint)
            text.detail?.let { Text(it, style = DGType.small, color = DG.sub) }
            if (text.retry) TextButton(onRetry, Modifier.testTag("event-retry")) { Text("Try again") }
        }
    }
}

/** What the alert said, when there is no marker to show instead. */
@Composable
private fun YourAlert(alert: AlertTap, now: Long, expanded: Boolean) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        .padding(12.dp).testTag("your-alert"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Your alert", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            alert.watch?.let {
                Spacer(Modifier.width(8.dp))
                Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 8.dp, vertical = 2.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        // Collapsed, long alerts are cut at a few lines rather than
        // pushing the time sent out of sight.
        alert.title?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f),
            maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis) }
        alert.body?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = if (expanded) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis) }
        alert.sentAt?.let {
            Text("Sent " + EventText.clock(it * 1000, now, ZoneId.systemDefault()), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Title, warning, prose, facts, the kind's own panel and the footer. */
@Composable
private fun MarkerBody(marker: RoadMarker, card: EventCard, here: LatLon?, model: DriveViewModel, expanded: Boolean, onExpand: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(card.title, style = DGType.sheetTitle, color = DG.ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
        card.subtitle?.let { Text(it, style = DGType.body, color = DG.sub, maxLines = 2, overflow = TextOverflow.Ellipsis) }
    }
    card.warning?.let { Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = Color(0xFFD32F2F)) }
    // A picture or a board is what a camera or a sign is: it shows at
    // either height, since those kinds have no facts to lead with.
    when (marker.kind) {
        "camera" -> CameraShot(marker)
        "sign" -> if (marker.signLines.isEmpty()) Gloss("This sign is blank right now.") else SignBoard(marker)
    }
    if (expanded) {
        card.body.forEach { Text(it, style = DGType.lede, color = DG.ink) }
        card.gloss?.let { Gloss(it) }
    }
    val facts = if (expanded) card.facts else card.facts.take(3)
    if (facts.isNotEmpty()) Facts(facts)
    if (!expanded) return
    card.schedule?.let { SchedulePanel(it) }
    card.chain?.let { ChainLegend(it) }
    if (marker.kind == "toll") TollPrices(marker)
    if (card.dispatchCount > 0) marker.id?.let { DispatchLog(it, card.dispatchCount, onExpand) }
    card.link?.let { url ->
        val uri = LocalUriHandler.current
        TextButton({ runCatching { uri.openUri(url) } }) { Text("More") }
    }
    val lines = listOfNotNull(here?.let { Units.distance(AlertsEngine.meters(it, LatLon(marker.lat, marker.lon))) + " from you" }) + card.footer
    if (lines.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        lines.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun Gloss(text: String) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(DG.low.tint(.08f))
        .border(0.5.dp, DG.low.copy(alpha = 0.22f), RoundedCornerShape(18.dp)).padding(14.dp).testTag("plain-words"),
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text("In plain words", style = DGType.label, color = DG.low)
        Text(text, style = DGType.body, color = DG.ink.copy(alpha = 0.8f))
    }
}

/** The facts as a grouped list: label on the left, value on the right. */
@Composable
private fun Facts(facts: List<Pair<String, String>>) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = 0.72f))
        .border(0.5.dp, DG.hair, RoundedCornerShape(18.dp))) {
        facts.forEachIndexed { i, (label, value) ->
            if (i > 0) HorizontalDivider(thickness = 0.5.dp, color = DG.hair)
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.Top) {
                Text(label, style = DGType.body, color = DG.sub)
                Spacer(Modifier.width(12.dp))
                Text(value, Modifier.weight(1f), style = DGType.body.copy(fontWeight = FontWeight.SemiBold), color = DG.ink,
                    textAlign = androidx.compose.ui.text.style.TextAlign.End)
            }
        }
    }
}

/** When a closure is scheduled to end, in the road's time and, when it differs, the viewer's. */
@Composable
private fun SchedulePanel(s: Schedule) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        .padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(s.head, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        Text(s.tail, style = MaterialTheme.typography.bodyMedium)
        if (s.zoneLines.isNotEmpty()) Text(s.zoneLines.joinToString("\n"), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The level that applies now, then the others for reference. */
@Composable
private fun ChainLegend(c: ChainPanel) {
    if (c.head != null) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            .padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(c.head, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
            c.text?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        }
        Text("The other chain control levels:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        c.legend.forEach { (level, text) ->
            Row {
                Text(level, Modifier.widthIn(min = 36.dp), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(8.dp))
                Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private sealed class LogState {
    data object Idle : LogState()
    data object Loading : LogState()
    data class Loaded(val dispatch: Dispatch) : LogState()
    data object Failed : LogState()
    /** CHP cleared the call: its log is gone with it. */
    data object Ended : LogState()
}

/**
 * The CHP call's log, fetched only when asked for, as on the website:
 * newest first, each line with a rough plain-English reading, then one
 * line per unit on the call.
 */
@Composable
private fun DispatchLog(id: String, count: Int, onOpen: () -> Unit) {
    var state by remember(id) { mutableStateOf<LogState>(LogState.Idle) }
    var asked by remember(id) { mutableStateOf(0) }
    LaunchedEffect(id, asked) {
        if (asked == 0) return@LaunchedEffect
        state = LogState.Loading
        state = runCatching { EventApi.incident(id) }.fold(
            onSuccess = { LogState.Loaded(it.dispatch ?: Dispatch()) },
            onFailure = { if ((it as? BackendError)?.code == 404) LogState.Ended else LogState.Failed },
        )
    }
    when (val s = state) {
        LogState.Idle -> OutlinedButton({ onOpen(); asked++ }, Modifier.testTag("dispatch-log")) { Text("Show dispatch log ($count)") }
        LogState.Loading -> OutlinedButton({}, enabled = false) { Text("Loading…") }
        LogState.Failed -> OutlinedButton({ asked++ }, Modifier.testTag("dispatch-log")) { Text("Log not available. Try again") }
        LogState.Ended -> Gloss("The dispatch log ends when CHP clears the call.")
        is LogState.Loaded -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val d = s.dispatch
            if (d.log.isEmpty() && d.units.isEmpty()) Gloss("No shared entries yet.")
            if (d.log.isNotEmpty()) {
                Text("Dispatch log (newest first)", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Gloss("Blue text is a rough translation of the CHP shorthand.")
                d.log.forEach { line ->
                    Row {
                        Text(line.time ?: "", Modifier.widthIn(min = 64.dp), fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                        Column(Modifier.weight(1f)) {
                            Text(line.text ?: "", style = MaterialTheme.typography.bodyMedium)
                            line.plain?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = Color(0xFF1F6FD1)) }
                        }
                    }
                }
            }
            if (d.units.isNotEmpty()) {
                Text("CHP units on this call (${d.units.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Gloss("One line per unit. \"Cleared to leave\" means the unit finished its part and left the scene. CHP does not name units in the public feed.")
                d.units.forEachIndexed { i, u -> Text(EventText.unitLine(u, i), style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

/**
 * The row pinned to the bottom: Navigate and Share for a marker, the
 * plugin's vote where it takes one; for an alert with no marker, the
 * spot on the map and any newer event of the same kind there.
 */
@Composable
private fun Actions(sheet: EventSheet, model: DriveViewModel) {
    val context = LocalContext.current
    val marker = sheet.marker
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (marker != null) {
            if (marker.kind == "plugin") marker.id?.let { ConfirmRow(it, model) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DGButton("Navigate here", { model.show(Place(name = marker.displayTitle, lat = marker.lat, lon = marker.lon, kind = PlaceKind.recent)) },
                    Modifier.weight(1f).testTag("navigate-here"), style = BtnStyle.PRIMARY, icon = "nav")
                GlassRound("share", "Share", { share(context, marker.webUrl) }, size = DG.btnH)
            }
        } else sheet.alert?.let { alert ->
            DGButton("Show on map", { model.focusOn(alert.lat, alert.lon) }, Modifier.fillMaxWidth().testTag("show-on-map"),
                style = BtnStyle.PRIMARY, icon = "locate")
            sheet.status?.nearby?.let { other ->
                OutlinedButton({ model.showMarker(other); model.focusOn(other.lat, other.lon) }, Modifier.fillMaxWidth().testTag("show-nearby")) {
                    Text("Another ${EventKinds.noun(other.kind)} is reported here")
                }
            }
        }
    }
}
