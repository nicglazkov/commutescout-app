package com.commutescout.drive

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.AlertMore
import com.commutescout.drive.design.AlertTuck
import com.commutescout.drive.design.AlertWords
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.GlassRound
import com.commutescout.drive.design.HorizonChip
import com.commutescout.drive.design.ManeuverCard
import com.commutescout.drive.design.ModeToggle
import com.commutescout.drive.design.Note
import com.commutescout.drive.design.ReportButton
import com.commutescout.drive.design.SpeedDisc
import com.commutescout.drive.design.Tone
import com.commutescout.drive.design.TripBar
import com.commutescout.drive.design.veil
import com.stadiamaps.ferrostar.core.NavigationUiState
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState
import kotlinx.coroutines.delay
import org.maplibre.spatialk.geojson.Position
import java.time.ZoneId
import kotlin.math.roundToInt

/** An app message for the slot under the maneuver card, or the browse capsule. */
data class SysNote(
    val id: String, val icon: String, val tone: Tone, val title: String, val body: String?,
    val action: String? = null, val onAction: (() -> Unit)? = null,
    val secondary: String? = null, val onSecondary: (() -> Unit)? = null, val inline: Boolean = false,
)

/** Where and when, for the see-more card's facts. */
internal fun whereOf(m: RoadMarker): String? =
    listOfNotNull(m.route?.takeIf { it.isNotBlank() }, (m.location ?: m.near ?: m.road)?.takeIf { it.isNotBlank() })
        .distinct().joinToString(", ").ifBlank { null }

internal fun reportedOf(m: RoadMarker): String? = runCatching {
    EventCard.of(m, System.currentTimeMillis(), ZoneId.systemDefault(), Units.useMiles).age
}.getOrNull()

/**
 * Everything over the map on a trip: the maneuver card, the alert
 * tucked under it (or the app's own message), the side buttons, the
 * speed disc and the trip bar. [open] is the see-more state, hoisted so
 * the map camera can make room for it.
 */
@Composable
fun BoxScope.NavChrome(
    model: DriveViewModel, ui: NavigationUiState, mapState: NavigationMapState,
    item: Upcoming?, cleared: Upcoming?, along: Double, speedMps: Double, note: SysNote?,
    is3D: Boolean, open: Boolean, onOpen: (Boolean) -> Unit, onReport: () -> Unit,
) {
    val density = LocalDensity.current
    // What the slot shows: a cleared event first, then the next alert.
    val shown = cleared ?: item
    val isCleared = cleared != null
    LaunchedEffect(cleared?.id) {
        val c = cleared ?: return@LaunchedEffect
        onOpen(false)
        delay(DebugScenes.clearedHoldMs)
        model.alerts.dismiss(c.id)
        model.alerts.clearedSeen()
    }
    LaunchedEffect(shown?.id) { if (shown == null) onOpen(false) }

    // The veil behind an opened alert; a tap on it closes the alert.
    AnimatedVisibility(open && shown != null, Modifier.fillMaxSize(), enter = fadeIn(tween(300)), exit = fadeOut(tween(300))) {
        Box(Modifier.fillMaxSize().veil(is3D).clickable(remember { MutableInteractionSource() }, null) { onOpen(false) })
    }

    // In 3D the event gets a chip standing on its spot in the scene.
    if (is3D && shown != null && !isCleared && !open) {
        val m = shown.marker
        val spot by produceState<DpOffset?>(null, m.key) {
            snapshotFlow { mapState.cameraState.position }.collect {
                value = runCatching { mapState.cameraState.projection?.screenLocationFromPosition(Position(m.lon, m.lat)) }.getOrNull()
            }
        }
        var chipW by remember { mutableIntStateOf(0) }
        var chipH by remember { mutableIntStateOf(0) }
        val conf = androidx.compose.ui.platform.LocalConfiguration.current
        // Only a spot that is on screen, below the cards, gets a chip.
        spot?.takeIf { it.x.value in 0f..conf.screenWidthDp.toFloat() && it.y.value in 300f..(conf.screenHeightDp - 160f) }?.let { s ->
            val words = AlertWords.of(m, shown.alongMeters - along, speedMps)
            Box(Modifier.offset {
                val maxX = (conf.screenWidthDp.dp.toPx() - chipW - DG.gutter.toPx()).coerceAtLeast(0f)
                IntOffset((s.x.toPx() - chipW / 2f).coerceIn(DG.gutter.toPx().coerceAtMost(maxX), maxX).roundToInt(), (s.y.toPx() - chipH).roundToInt())
            }
                .onSizeChanged { chipW = it.width; chipH = it.height }) {
                HorizonChip(words, onTap = { onOpen(true) })
            }
        }
    }

    Column(Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = 6.dp, start = DG.gutter, end = DG.gutter).widthIn(max = 520.dp).fillMaxWidth()) {
        var cardH by remember { mutableIntStateOf(with(density) { DG.manH.roundToPx() }) }
        Box(Modifier.fillMaxWidth()) {
            val under = with(density) { cardH.toDp() } - DG.tuck
            androidx.compose.animation.AnimatedVisibility(shown != null, Modifier.padding(top = under).padding(horizontal = 6.dp),
                enter = slideInVertically(DG.slide()) { -it } + fadeIn(tween(220)),
                exit = slideOutVertically(tween(560, easing = DG.hideEase)) { -it } + fadeOut(tween(420, 140))) {
                // The last alert stays drawn while it tucks away.
                val last = remember { mutableStateOf(shown) }
                if (shown != null) last.value = shown
                val u = last.value ?: return@AnimatedVisibility
                key(u.id) {
                    val words = AlertWords.of(u.marker, u.alongMeters - along, speedMps)
                    if (open && !isCleared) AlertMore(words, u.marker, reportedOf(u.marker), whereOf(u.marker), model.canConfirm(u.marker),
                        onVote = { v -> model.vote(u.marker, v) }, onDismiss = { onOpen(false); model.alerts.dismiss(u.id) },
                        onLess = { onOpen(false) }, onDetails = { onOpen(false); model.showMarker(u.marker) })
                    else AlertTuck(words, u.marker, isCleared, onOpen = { if (!isCleared) { model.alerts.say(u.marker); onOpen(true) } },
                        onDismiss = { onOpen(false); model.alerts.dismiss(u.id) })
                }
            }
            // An app message takes the slot when no alert has it.
            androidx.compose.animation.AnimatedVisibility(shown == null && note != null, Modifier.padding(top = with(density) { cardH.toDp() } + 8.dp),
                enter = slideInVertically(DG.slide()) { -it / 2 } + fadeIn(), exit = fadeOut(tween(220))) {
                val last = remember { mutableStateOf(note) }
                if (note != null) last.value = note
                last.value?.let { n -> Note(n.icon, n.tone, n.title, n.body, Modifier.fillMaxWidth(), n.action, n.onAction, n.secondary, n.onSecondary, n.inline, tag = "note-${n.id}") }
            }
            ManeuverCard(ui, Modifier.onSizeChanged { cardH = it.height })
        }
    }

    // The side column: 2D and 3D, recenter when the map was moved, report.
    Column(Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(end = DG.gutter, bottom = 102.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // An opened alert reaches down here: the small buttons step aside.
        if (!mapState.isTrackingUser && !open) GlassRound("locate", "Recenter", { mapState.recenter(isNavigating = true) }, Modifier.taggedAs("recenter"))
        val muted = ui.isMuted == true
        if (!open) GlassRound("mute", if (muted) "Unmute" else "Mute", { model.toggleMute() }, Modifier.taggedAs("mute"),
            tint = if (muted) DG.faint else DG.ink, size = 44.dp, iconSize = 20.dp)
        ModeToggle(is3D, { model.toggle3D() }, Modifier.taggedAs("perspective"))
        ReportButton(onReport, Modifier.taggedAs("report"))
    }
    if (model.prefs.showSpeedLimit && speedMps >= 0) {
        Box(Modifier.align(Alignment.BottomStart).safeDrawingPadding().padding(start = DG.gutter, bottom = 92.dp)) {
            SpeedDisc(speedMps, model.limitKmh(ui))
        }
    }
    Box(Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(start = 10.dp, end = 10.dp, bottom = 6.dp)) {
        TripBar(ui, onEnd = { model.stopNavigation() })
    }
}

internal fun Modifier.taggedAs(t: String): Modifier = testTag(t)
