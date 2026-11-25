package com.commutescout.drive.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.commutescout.drive.Rail
import com.commutescout.drive.UnitStyle
import com.commutescout.drive.Units
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/*
 * Clear Glass: the trip screen's own parts. The ahead line is the rail
 * down the left that strings what is on the route between the driver
 * and the destination; the trip bar holds the arrival time and the four
 * things a driver does mid-trip.
 */

/** One mark on the ahead line. */
data class RailMark(val id: String, val icon: String, val tone: Tone, val distance: String, val title: String, val gapMeters: Double)

private val railW = 34.dp
private val railTop = 26.dp      // the destination's centre, from the rail's top
private val railBottom = 24.dp   // the driver's centre, from the rail's bottom

/**
 * The ahead line. [marks] are nearest first; [destination] and
 * [toDestination] label the top end. The rail takes the height it is
 * given and places up to three marks on it by distance.
 */
@Composable
fun AheadRail(
    marks: List<RailMark>, destination: String, toDestination: String?, totalMeters: Double,
    onMark: (RailMark) -> Unit, modifier: Modifier = Modifier, stops: Int = 0,
) {
    BoxWithConstraints(modifier.testTag("ahead-line")) {
        val span = maxHeight - railTop - railBottom
        val slots = remember(marks.map { it.id to (it.gapMeters / 50).toInt() }, (totalMeters / 50).toInt(), span) {
            Rail.slots(marks.map { it.gapMeters }, totalMeters, span.value)
        }
        // The rail itself: a glass capsule with the track down its middle.
        Box(Modifier.width(railW).fillMaxHeight().glass(RoundedCornerShape(17.dp), elevation = 14.dp)) {
            Box(Modifier.align(Alignment.TopCenter).padding(top = railTop, bottom = railBottom).width(3.dp).fillMaxHeight()
                .clip(CircleShape).background(DG.laneFill))
            // The driver, at the foot.
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = railBottom - 8.dp).size(16.dp)
                .shadow(3.dp, CircleShape).clip(CircleShape).background(Color.White).padding(3.dp).clip(CircleShape).background(DG.low))
            // The destination, at the head.
            Box(Modifier.align(Alignment.TopCenter).padding(top = railTop - 12.dp).size(24.dp).clip(RoundedCornerShape(8.dp)).background(DG.ink),
                contentAlignment = Alignment.Center) { DGIcon("pin", Color.White, 14.dp, stroke = 2.2f) }
        }
        RailTag(toDestination ?: "", if (stops > 0) "$destination, $stops ${if (stops == 1) "stop" else "stops"}" else destination, null,
            Modifier.offset(x = railW + 10.dp, y = railTop - 22.dp).testTag("ahead-destination"))
        slots.forEach { s ->
            val m = marks[s.index]
            val y = railTop + s.y.dp
            Box(Modifier.offset(x = (railW - 26.dp) / 2, y = y - 13.dp).size(26.dp).shadow(3.dp, CircleShape).clip(CircleShape)
                .background(if (m.tone == Tone.CLEAR || m.tone == Tone.LOW) DG.sub else m.tone.color), contentAlignment = Alignment.Center) {
                DGIcon(m.icon, Color.White, 15.dp, stroke = 2.2f)
            }
            RailTag(m.distance, m.title, m.tone.takeIf { it == Tone.HIGH || it == Tone.MID },
                Modifier.offset(x = railW + 10.dp, y = y - 22.dp).clickable(remember { MutableInteractionSource() }, null, role = Role.Button) { onMark(m) }
                    .testTag("ahead-mark"))
        }
    }
}

@Composable
private fun RailTag(distance: String, title: String, tone: Tone?, modifier: Modifier = Modifier) {
    Column(modifier.widthIn(max = 168.dp).glass(RoundedCornerShape(13.dp), tone = tone, elevation = 10.dp).padding(horizontal = 10.dp, vertical = 5.dp)) {
        if (distance.isNotEmpty()) Text(distance, style = DGType.row.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = DG.ink, maxLines = 1)
        Text(title, style = DGType.small, color = tone?.ink ?: DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun clock(secondsFromNow: Double): String =
    LocalTime.now().plusSeconds(secondsFromNow.toLong()).format(DateTimeFormatter.ofPattern(UnitStyle.clockPattern, java.util.Locale.US))

private val barShape = RoundedCornerShape(30.dp)

/** Arrival time, what is left, and the four things to do mid-trip. */
@Composable
fun TripBar(
    secondsLeft: Double?, metersLeft: Double?,
    onEnd: () -> Unit, onAddStop: () -> Unit, onRoute: () -> Unit, onReport: () -> Unit, modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth().background(Color.White.copy(alpha = .55f), barShape).glass(barShape, elevation = 20.dp, strong = true)
        .padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 12.dp).testTag("trip-bar")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.Bottom) {
            Text(secondsLeft?.let { clock(it) } ?: "--", style = DGType.eta, color = DG.ink, modifier = Modifier.testTag("trip-eta"))
            Text("arrive", Modifier.padding(start = 8.dp, bottom = 2.dp).weight(1f), style = DGType.meta, color = DG.sub)
            if (secondsLeft != null && metersLeft != null)
                Text("${Units.duration(secondsLeft)} · ${Units.distance(metersLeft)}", Modifier.padding(bottom = 2.dp), style = DGType.meta, color = DG.sub, maxLines = 1)
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TripButton("stop", "End", onEnd, Modifier.weight(1f).testTag("end-trip"), danger = true)
            TripButton("pinl", "Add stop", onAddStop, Modifier.weight(1f).testTag("add-stop"))
            TripButton("route", "Route", onRoute, Modifier.weight(1f).testTag("trip-route"))
            TripButton("report", "Report", onReport, Modifier.weight(1f).testTag("report"), iconTint = DG.low)
        }
    }
}

@Composable
private fun TripButton(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, danger: Boolean = false, iconTint: Color = DG.ink) {
    val src = remember { MutableInteractionSource() }
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier.press(src).height(64.dp).clip(shape).background(if (danger) DG.high.copy(alpha = .10f) else DG.wash)
            .then(if (danger) Modifier.border(0.5.dp, DG.high.copy(alpha = .22f), shape) else Modifier)
            .clickable(src, null, role = Role.Button, onClick = onClick).semantics(mergeDescendants = true) { contentDescription = if (danger) "End trip" else label },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        DGIcon(icon, if (danger) DG.highInk else iconTint, 22.dp, stroke = 2.1f)
        Spacer(Modifier.height(5.dp))
        Text(label, style = DGType.small.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = if (danger) DG.highInk else DG.ink, maxLines = 1)
    }
}

/**
 * The bar that offers a changed trip: the new arrival time, what the
 * change costs, where the trip now goes, and the two answers.
 */
@Composable
fun TripChangeBar(
    seconds: Double, cost: String?, line: String, confirm: String,
    onCancel: () -> Unit, onConfirm: () -> Unit, modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth().background(Color.White.copy(alpha = .55f), barShape).glass(barShape, elevation = 20.dp, strong = true)
        .padding(12.dp).testTag("trip-change")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.Bottom) {
            Text(clock(seconds), style = DGType.eta, color = DG.ink)
            Text("arrive", Modifier.padding(start = 8.dp, bottom = 2.dp).weight(1f), style = DGType.meta, color = DG.sub)
            if (cost != null) Text(cost, Modifier.padding(bottom = 2.dp), style = DGType.meta.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = DG.ink, maxLines = 1)
        }
        Text(line, Modifier.padding(start = 8.dp, end = 8.dp, top = 4.dp), style = DGType.small, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DGButton("Cancel", onCancel, Modifier.weight(1f).height(54.dp).testTag("trip-change-cancel"))
            DGButton(confirm, onConfirm, Modifier.weight(1.6f).height(54.dp).testTag("trip-change-confirm"), style = BtnStyle.BLUE, icon = "pinl")
        }
    }
}

/** A numbered stop, in the purple the design keeps for stops. */
@Composable
fun StopDisc(n: Int, size: Dp = 32.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).clip(CircleShape).background(DG.plug), contentAlignment = Alignment.Center) {
        Text("$n", style = DGType.label, color = Color.White)
    }
}
