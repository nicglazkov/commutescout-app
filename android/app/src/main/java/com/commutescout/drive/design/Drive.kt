package com.commutescout.drive.design

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.commutescout.drive.LaneLayout
import com.commutescout.drive.PluginBadge
import com.commutescout.drive.PluginStyle
import com.commutescout.drive.UnitStyle
import com.commutescout.drive.RoadMarker
import com.commutescout.drive.Units
import com.stadiamaps.ferrostar.core.NavigationUiState
import uniffi.ferrostar.LaneInfo
import uniffi.ferrostar.ManeuverModifier
import uniffi.ferrostar.ManeuverType
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.roundToInt

/*
 * The driving chrome: the maneuver card on top, the alert tucked under
 * it, the speed disc, the trip bar. Ferrostar still drives the camera
 * and the guidance; these draw what it knows in the Day Glass+ style.
 */

/** "0.4 mi" as the number and the unit, for the big maneuver distance. */
fun splitDistance(meters: Double): Pair<String, String> {
    val s = Units.distance(max(0.0, meters))
    val i = s.lastIndexOf(' ')
    return if (i < 0) s to "" else s.substring(0, i) to s.substring(i + 1)
}

/** The arrow for a maneuver, from the icon set's three. */
fun maneuverIcon(type: ManeuverType?, modifier: ManeuverModifier?): String = when {
    type == ManeuverType.ARRIVE -> "arrive"
    modifier == ManeuverModifier.LEFT || modifier == ManeuverModifier.SLIGHT_LEFT || modifier == ManeuverModifier.SHARP_LEFT || modifier == ManeuverModifier.U_TURN -> "left"
    modifier == ManeuverModifier.RIGHT || modifier == ManeuverModifier.SLIGHT_RIGHT || modifier == ManeuverModifier.SHARP_RIGHT -> "right"
    else -> "straight"
}

private fun laneIcon(dir: String?): String {
    val d = (dir ?: "").lowercase()
    return when { "left" in d -> "left"; "right" in d -> "right"; else -> "straight" }
}

/** The next turn: arrow, distance, road, what comes after, and the lanes. */
@Composable
fun ManeuverCard(ui: NavigationUiState, modifier: Modifier = Modifier) {
    val vi = ui.visualInstruction
    val primary = vi?.primaryContent
    val (num, unit) = splitDistance(ui.progress?.distanceToNextManeuver ?: 0.0)
    val then = vi?.secondaryContent?.text?.takeIf { it.isNotBlank() }
        ?: runCatching { ui.remainingSteps?.getOrNull(1)?.visualInstructions?.firstOrNull()?.primaryContent?.text }.getOrNull()?.takeIf { it.isNotBlank() }
    val lanes = (vi?.subContent?.laneInfo ?: primary?.laneInfo).orEmpty()
    Column(modifier.fillMaxWidth().heightIn(min = 112.dp).glass(RoundedCornerShape(DG.rCard), elevation = 20.dp, strong = true)
        .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 14.dp).testTag("maneuver-card")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(56.dp).clip(RoundedCornerShape(18.dp)).background(Brush.linearGradient(listOf(DG.lowTop, DG.low))), contentAlignment = Alignment.Center) {
                DGIcon(maneuverIcon(primary?.maneuverType, primary?.maneuverModifier), Color.White, 32.dp, stroke = 2.4f)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(buildAnnotatedString {
                    append(num)
                    withStyle(SpanStyle(fontSize = DGType.maneuverUnit.fontSize, fontWeight = FontWeight.SemiBold, color = DG.sub)) { append(" $unit") }
                }, style = DGType.maneuverDist, color = DG.ink, maxLines = 1)
                Spacer(Modifier.height(4.dp))
                Text(primary?.text ?: ui.currentStepRoadName ?: "", style = DGType.maneuverRoad, color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (then != null) {
            Spacer(Modifier.height(12.dp))
            Text("Then " + (if (then.substringBefore(" ") in THEN_VERBS) then.replaceFirstChar { it.lowercase() } else then), style = DGType.maneuverThen, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (lanes.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            LanesRow(lanes)
        }
    }
}

/** One cell per lane, the ones to be in lit blue. */
@Composable
fun LanesRow(lanes: List<LaneInfo>) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (l in lanes) {
            val on = l.active
            Box(Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(10.dp)).background(if (on) DG.low.copy(alpha = .12f) else DG.ink.copy(alpha = .04f)),
                contentAlignment = Alignment.Center) {
                DGIcon(laneIcon(if (on) l.activeDirection ?: l.directions.firstOrNull() else l.directions.firstOrNull()), if (on) DG.low else DG.laneOff, 20.dp, stroke = 2.2f)
            }
        }
    }
}

/** What an alert says, worked out once for the card, the chip and the catalog. */
data class AlertWords(
    val title: String,
    val line: String?,
    val distance: String?,
    val eta: String?,
    val look: AlertLook,
    val layout: LaneLayout?,
    val miles: Double,
) {
    companion object {
        fun of(m: RoadMarker, gapMeters: Double?, speedMps: Double): AlertWords {
            val look = Looks.of(m)
            val layout = m.laneLayout
            val title = shortTitle(m, look)
            val line = layout?.summary ?: m.lanes?.takeIf { it.isNotBlank() } ?: listOfNotNull(m.route, m.location ?: m.near).filter { it.isNotBlank() }.joinToString(", ").ifBlank { null }
            val gap = gapMeters?.let { max(0.0, it) }
            val pace = if (speedMps > 4) speedMps else 26.0
            val eta = gap?.let { val s = (it / pace).roundToInt().coerceAtLeast(1); if (s < 60) "$s s" else "${(s / 60.0).roundToInt()} min" }
            return AlertWords(title, line, gap?.let { Units.distance(it) }, eta, look, layout, (gap ?: 0.0) / 1609.344)
        }

        /** The cleared capsule's words, and the voice's: "Crash ahead has cleared". */
        fun clearedLine(title: String): String = "${title.removeSuffix(" ahead")} ahead has cleared"

        /** "Crash ahead", not the feed's whole sentence. */
        fun shortTitle(m: RoadMarker, look: AlertLook): String = when {
            m.kind == "incident" && look.icon == "crash" -> "Crash ahead"
            m.kind == "lane_closure" -> m.laneLayout?.let { if (it.closedLanes.size == it.total) "Road closed" else "Lanes closed" } ?: "Lane closure"
            m.kind == "chain_control" -> "Chain control" + (m.status?.let { " $it" } ?: "")
            m.kind == "wildfire" -> m.displayTitle
            m.kind == "plugin" -> when (look.icon) { "police" -> "Police reported"; "crash" -> "Crash reported"; "traffic" -> "Slow traffic"; "camera" -> "Speed camera"; "closure" -> "Road closed"; "hazard" -> "Hazard reported"; else -> m.displayTitle }
            m.kind == "camera" -> "Camera"
            m.kind == "sign" -> "Message sign"
            m.kind == "toll" -> m.displayTitle
            m.kind == "rwis" -> if (look.tone == Tone.MID) "Icy pavement" else m.displayTitle
            else -> m.displayTitle
        }
    }
}

/** The thumbnail for an alert, with the plugin's badge on a community report. */
@Composable
fun AlertThumb(words: AlertWords, marker: RoadMarker?, size: Pair<Dp, Dp> = 76.dp to 64.dp, cleared: Boolean = false, near: Float = 0f) {
    Box(Modifier.size(size.first, size.second).clip(RoundedCornerShape(DG.rThumb)).background(Color.White)
        .border(0.5.dp, DG.edge, RoundedCornerShape(DG.rThumb))) {
        AnimatedContent(cleared, transitionSpec = { fadeIn(tween(700)) togetherWith fadeOut(tween(700)) }, label = "thumb") { c ->
            if (c) LaneThumb(Drawings.cleared(words.layout), DrawKind.CRASH, width = size.first, height = size.second)
            else LaneThumb(Drawings.forAlert(words.look.draw, words.layout, near), words.look.draw, width = size.first, height = size.second, animate = true, key = marker?.key)
        }
        if (words.look.community && marker != null) Box(Modifier.align(Alignment.TopStart).padding(4.dp)) {
            PluginBadge(PluginStyle.sourceId(marker), PluginStyle.category(marker.flare_kind), 16.dp)
        }
    }
}

/**
 * The alert ahead, tucked under the maneuver card: what, the lanes, how
 * far. A tap opens it out (see more); a swipe up puts it away; a swipe
 * down opens it too. [cleared] turns it green and says so.
 */
@Composable
fun AlertTuck(words: AlertWords, marker: RoadMarker, cleared: Boolean, onOpen: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val tone = if (cleared) Tone.GOOD else words.look.tone
    Box(modifier.fillMaxWidth()
        .glass(RoundedCornerShape(bottomStart = 26.dp, bottomEnd = 26.dp), tone = tone, elevation = 16.dp)
        .pointerInput(marker.key) { detectVerticalDragGestures { _, dy -> if (dy < -12) onDismiss() else if (dy > 14) onOpen() } }
        .clickable(onClick = onOpen).testTag("alert-banner")) {
        Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 18.dp, top = DG.tuck + 10.dp, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            AlertThumb(words, marker, cleared = cleared)
            Spacer(Modifier.width(12.dp))
            AnimatedContent(cleared, transitionSpec = { (fadeIn(tween(380, 90)) togetherWith fadeOut(tween(170)))
            }, modifier = Modifier.weight(1f), label = "words") { c ->
                Column {
                    Text(if (c) AlertWords.clearedLine(words.title) else words.title,
                        style = DGType.alertTitle, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val line = if (c) "All lanes are open again" else words.line
                    line?.let { Spacer(Modifier.height(3.dp)); Text(it, style = DGType.alertBody, color = tone.ink, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
            }
            if (!cleared && words.distance != null) {
                Spacer(Modifier.width(8.dp))
                Column(horizontalAlignment = Alignment.End) {
                    Text(words.distance, style = DGType.alertDist, color = DG.ink, maxLines = 1)
                    words.eta?.let { Text(it, style = DGType.small.copy(fontSize = 13.sp), color = DG.sub) }
                }
            }
        }
        Grab(Modifier.align(Alignment.BottomCenter).padding(bottom = 7.dp), width = 32.dp, color = tone.color.copy(alpha = .35f))
    }
}

/**
 * The alert opened out: the big lane drawing, what to do, where and
 * when it was reported, and the answers today's rules allow.
 */
@Composable
fun AlertMore(
    words: AlertWords, marker: RoadMarker, reported: String?, where: String?, canConfirm: Boolean,
    onVote: (String) -> Unit, onDismiss: () -> Unit, onLess: () -> Unit, onDetails: () -> Unit, modifier: Modifier = Modifier,
) {
    val tone = words.look.tone
    var thanked by remember(marker.key) { mutableStateOf(false) }
    LaunchedEffect(thanked) { if (thanked) { kotlinx.coroutines.delay(900); onDismiss() } }
    Column(modifier.fillMaxWidth().glass(RoundedCornerShape(bottomStart = 28.dp, bottomEnd = 28.dp), tone = tone, elevation = 22.dp)
        .padding(start = 16.dp, end = 16.dp, top = DG.tuck + 12.dp, bottom = 14.dp).testTag("alert-more")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Disc(words.look.icon, tone)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f).clickable(onClick = onDetails)) {
                Text(words.title, style = DGType.cardTitle, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                words.line?.let { Text(it, style = DGType.body, color = tone.ink, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            words.distance?.let { Text(it, style = DGType.bigDist, color = DG.ink) }
        }
        val draw = words.look.draw
        if (draw != DrawKind.FIRE && draw != DrawKind.SIGN) {
            val ticks = listOf(RoadSpec.Tick(.02f, "You", true), RoadSpec.Tick(.02f + (.28f + .46f * minOf(1f, words.miles.toFloat() / .8f) - .02f) / 2, Units.distance(words.miles * 1609.344 / 2)),
                RoadSpec.Tick(.28f + .46f * minOf(1f, words.miles.toFloat() / .8f), words.distance ?: "", true))
            Box(Modifier.padding(top = 14.dp).fillMaxWidth().height(150.dp).clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = .7f))) {
                LaneDrawing(Drawings.large(draw, words.layout, words.miles, ticks), draw, Modifier.fillMaxWidth().height(150.dp), animate = true, key = marker.key)
            }
        } else {
            Box(Modifier.padding(top = 14.dp).fillMaxWidth().height(120.dp).clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = .7f))) {
                LaneDrawing(RoadSpec(), draw, Modifier.fillMaxWidth().height(120.dp))
            }
        }
        val advice = words.layout?.advice
        val detail = marker.detail ?: marker.description?.takeIf { marker.kind != "plugin" }
        if (advice != null || detail != null) {
            Spacer(Modifier.height(12.dp))
            Text(buildAnnotatedString {
                advice?.let { withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = DG.ink)) { append(it) }; append(" ") }
                detail?.let { append(it) }
            }, style = DGType.body.copy(fontSize = 15.5.sp), color = DG.sub, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(10.dp))
        where?.let { Fact("Where", it) }
        reported?.let { Fact("Reported", it) }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            when {
                thanked -> DGButton("Thanks", {}, Modifier.weight(1f), BtnStyle.DONE, icon = "check")
                canConfirm -> {
                    DGButton("Still there", { onVote("up"); thanked = true }, Modifier.weight(1f).testTag("alert-confirm-up"), icon = "thumb")
                    DGButton("It's gone", { onVote("gone"); thanked = true }, Modifier.weight(1f).testTag("alert-confirm-gone"), icon = "gone")
                }
                else -> DGButton("Hide alert", onDismiss, Modifier.weight(1f).testTag("alert-dismiss"), icon = "close")
            }
            GhostRound("up", "Show less", onLess, size = 48.dp, tint = DG.ink)
        }
    }
}

@Composable
private fun Fact(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp)) {
        Text(label, style = DGType.meta.copy(fontSize = 14.5.sp), color = DG.sub, modifier = Modifier.width(92.dp))
        Text(value, style = DGType.meta.copy(fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold), color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(DG.hair))
}

/** Speed in a glass disc, the posted limit as a small sign on its shoulder. */
@Composable
fun SpeedDisc(speedMps: Double, limitKmh: Double?, modifier: Modifier = Modifier) {
    val miles = Units.useMiles
    val speed = if (speedMps < 0) 0 else (if (miles) speedMps * 2.236936 else speedMps * 3.6).roundToInt()
    val limit = limitKmh?.let { (if (miles) it / 1.609344 else it).roundToInt() }
    val over = limit != null && speed > limit + 1
    Box(modifier.size(80.dp).testTag("speedometer")) {
        Column(Modifier.align(Alignment.BottomStart).size(72.dp).glass(CircleShape, tone = if (over) Tone.HIGH else null, elevation = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("$speed", style = DGType.speed, color = if (over) DG.highInk else DG.ink)
            Text(if (miles) "mph" else "km/h", style = DGType.tiny, color = DG.sub)
        }
        if (limit != null) Box(Modifier.align(Alignment.TopEnd).size(32.dp).clip(CircleShape).background(Color.White).border(2.5.dp, DG.high, CircleShape),
            contentAlignment = Alignment.Center) { Text("$limit", style = DGType.label.copy(fontSize = 12.5.sp, fontWeight = FontWeight.ExtraBold), color = DG.ink) }
    }
}

/** Arrival time, what is left, and the one way to end the trip. */
@Composable
fun TripBar(ui: NavigationUiState, onEnd: () -> Unit, modifier: Modifier = Modifier) {
    val p = ui.progress
    val eta = p?.let { LocalTime.now().plusSeconds(it.durationRemaining.toLong()).format(DateTimeFormatter.ofPattern(UnitStyle.clockPattern, java.util.Locale.US)) } ?: "--"
    Row(modifier.fillMaxWidth().height(76.dp).glass(RoundedCornerShape(30.dp), elevation = 20.dp, strong = true)
        .padding(start = 20.dp, end = 12.dp).testTag("trip-bar"), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(eta, style = DGType.eta, color = DG.ink)
            Spacer(Modifier.height(4.dp))
            p?.let { Text("${Units.duration(it.durationRemaining)}   ${Units.distance(it.distanceRemaining)}", style = DGType.meta, color = DG.sub, maxLines = 1) }
        }
        Box(Modifier.size(52.dp).clip(CircleShape).background(DG.high.tint(.12f)).border(0.5.dp, DG.high.copy(alpha = .25f), CircleShape)
            .clickable(onClick = onEnd).testTag("end-trip"), contentAlignment = Alignment.Center) {
            DGIcon("close", DG.high, 22.dp, stroke = 2.4f, contentDescription = "End trip")
        }
    }
}

/**
 * The 3D view's marker: a glass chip standing on the event's spot, its
 * stem and a glow at its foot. Tapping it opens the alert.
 */
@Composable
fun HorizonChip(words: AlertWords, onTap: () -> Unit, modifier: Modifier = Modifier) {
    val tone = words.look.tone
    Column(modifier.testTag("horizon-chip"), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.height(50.dp).glass(RoundedCornerShape(25.dp), elevation = 14.dp).clickable(onClick = onTap).padding(start = 7.dp, end = 16.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Disc(words.look.icon, tone, DG.discSm)
            Spacer(Modifier.width(9.dp))
            Text(words.title.removeSuffix(" ahead"), style = DGType.title, color = DG.ink, maxLines = 1)
        }
        Box(Modifier.size(2.dp, 24.dp).background(Brush.verticalGradient(listOf(tone.color.copy(alpha = .9f), tone.color.copy(alpha = .2f)))))
        Box(Modifier.size(26.dp, 9.dp).clip(RoundedCornerShape(50)).background(Brush.radialGradient(listOf(tone.color.copy(alpha = .55f), Color.Transparent))))
    }
}

/**
 * An app message, the design's note: a disc, a title, a line, and up to
 * two answers. [inline] puts one short answer beside the words.
 */
@Composable
fun Note(
    icon: String, tone: Tone, title: String, body: String?, modifier: Modifier = Modifier,
    action: String? = null, onAction: (() -> Unit)? = null, secondary: String? = null, onSecondary: (() -> Unit)? = null,
    inline: Boolean = false, tag: String = "note",
) {
    Column(modifier.glass(RoundedCornerShape(26.dp), tone = tone, elevation = 16.dp).padding(start = 12.dp, end = 18.dp, top = 12.dp, bottom = 12.dp).testTag(tag)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Disc(icon, tone, DG.discSm)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f, fill = !inline || action == null)) {
                Text(title, style = DGType.row, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                body?.let { Text(it, style = DGType.small, color = DG.sub, maxLines = 3, overflow = TextOverflow.Ellipsis) }
            }
            if (inline && action != null) {
                Spacer(Modifier.width(10.dp))
                DGButton(action, { onAction?.invoke() }, Modifier.height(44.dp), BtnStyle.PRIMARY)
            }
        }
        if (!inline && (action != null || secondary != null)) {
            Spacer(Modifier.height(10.dp))
            Row(Modifier.padding(start = 48.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                action?.let { DGButton(it, { onAction?.invoke() }, Modifier.weight(1f).height(44.dp), BtnStyle.PRIMARY) }
                secondary?.let { DGButton(it, { onSecondary?.invoke() }, Modifier.weight(1f).height(44.dp)) }
            }
        }
    }
}

/** A row in the catalog of every alert: thumb, title, line, distance. */
@Composable
fun AlertRow(words: AlertWords, marker: RoadMarker?, modifier: Modifier = Modifier, mono: String? = null, onClick: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 8.dp, horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(60.dp, 42.dp).clip(RoundedCornerShape(topStart = 21.dp, bottomStart = 21.dp, topEnd = 11.dp, bottomEnd = 11.dp))
            .background(Color.White).border(0.5.dp, DG.edge, RoundedCornerShape(topStart = 21.dp, bottomStart = 21.dp, topEnd = 11.dp, bottomEnd = 11.dp))) {
            LaneDrawing(Drawings.forAlert(words.look.draw, words.layout).copy(padT = 3f, padB = 4f, padL = 6f, padR = 6f), words.look.draw, Modifier.size(60.dp, 42.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(words.title, style = DGType.row.copy(fontSize = 15.5.sp), color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (mono != null) Text(mono, style = DGType.mono.copy(fontSize = 11.5.sp), color = DG.midInk, maxLines = 1)
            else words.line?.let { Text(it, style = DGType.small.copy(fontSize = 12.5.sp), color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        words.distance?.let { d ->
            Column(horizontalAlignment = Alignment.End) {
                Text(d, style = DGType.row.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold), color = DG.ink)
                words.eta?.let { Text(it, style = DGType.small.copy(fontSize = 12.5.sp), color = DG.sub) }
            }
        }
        if (words.look.community && marker != null) {
            Spacer(Modifier.width(8.dp)); PluginBadge(PluginStyle.sourceId(marker), PluginStyle.category(marker.flare_kind), 18.dp)
        }
    }
}

/** A struck-through line: what a spent alert said. */
fun struck(text: String) = buildAnnotatedString { withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(text) } }

/** Instruction verbs that read lowercase after "Then"; road names keep their capitals. */
private val THEN_VERBS = setOf("Turn", "Keep", "Continue", "Take", "Merge", "Exit", "Make", "Bear", "Head", "Go", "Enter", "Stay")
