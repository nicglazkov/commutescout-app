package com.commutescout.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Disc
import com.commutescout.drive.design.Drawings
import com.commutescout.drive.design.LaneDrawing
import com.commutescout.drive.design.LaneThumb
import com.commutescout.drive.design.Looks
import com.commutescout.drive.design.NavDisc
import com.commutescout.drive.design.Tone
import com.commutescout.drive.design.struck
import com.commutescout.drive.design.tint
import java.time.ZoneId
import java.util.Locale

/**
 * The words for a watch alert whose event has cleared: the capsule at
 * the top of the map and the panel under it. The noun and the road come
 * from the alert's own title when it reads "<Kind> on <road>", so the
 * capsule says "The crash on US-101 is over" rather than "The incident
 * is over".
 */
data class ClearedText(
    val capsuleTitle: String,
    val capsuleSub: String,
    val panelTitle: String,
    val panelSub: String?,
    val headline: String,
    val detail: String,
    val saidHeader: String,
) {
    companion object {
        private val ON = Regex("""^\s*([A-Za-z][A-Za-z -]{1,30}?) on (.+?)\s*$""")

        fun of(alert: AlertTap, status: EventStatus, nowMs: Long, zone: ZoneId, locale: Locale = Locale.US): ClearedText {
            val title = alert.title?.trim()?.takeIf { it.isNotEmpty() }
            val m = title?.let { ON.find(it) }
            val kindNoun = EventKinds.noun(alert.kind)
            val noun = m?.groupValues?.get(1)?.lowercase()?.takeIf { it.split(' ').size <= 3 } ?: kindNoun
            val road = m?.groupValues?.get(2)
            // A cleared push is sent when the event went away; the status
            // check says when it did. Either gives the time.
            val clearedMs = status.clearedAt ?: if (alert.status == "cleared") alert.sentAt?.let { it * 1000 } else null
            val ago = clearedMs?.let { EventText.agoMs(it, nowMs) }
            val clearedLine = if (ago != null) "Cleared $ago" else "Cleared"
            val lanes = if (alert.laneLayout != null) " All lanes are open." else ""
            // The alert's own time is known only when this is the alert, not the clear.
            val saidAt = if (alert.status != "cleared") alert.sentAt?.let { EventText.clock(it * 1000, nowMs, zone, locale) } else null
            return ClearedText(
                capsuleTitle = if (road != null) "The $noun on $road is over" else "The $noun is over",
                capsuleSub = clearedLine,
                panelTitle = title ?: kindNoun.replaceFirstChar { it.uppercase() },
                panelSub = alert.watch,
                headline = "This $noun has cleared",
                detail = "$clearedLine.$lanes",
                saidHeader = if (saidAt != null) "What your alert said at $saidAt" else "What your alert said",
            )
        }
    }
}

/** True when the sheet is a watch alert whose event is over: the cleared layout shows. */
fun EventSheet.isClearedAlert(): Boolean = alert != null && marker == null && status?.state == EventState.CLEARED

/** The capsule at the top of the map while a cleared alert is open. */
@Composable
fun ClearedCapsule(sheet: EventSheet, nowMs: Long, modifier: Modifier = Modifier) {
    val alert = sheet.alert ?: return
    val status = sheet.status ?: return
    val t = ClearedText.of(alert, status, nowMs, ZoneId.systemDefault())
    // Clear of the map buttons on the right, the way the search capsule is.
    com.commutescout.drive.design.Note("check", Tone.GOOD, t.capsuleTitle, t.capsuleSub, modifier.fillMaxWidth().padding(end = 64.dp), tag = "cleared-capsule")
}

/**
 * The panel for a cleared alert: what it was, a green "has cleared"
 * box with the open lanes, what the alert said (struck through), and
 * Show on map / Done.
 */
@Composable
fun ClearedPanel(sheet: EventSheet, nowMs: Long, model: DriveViewModel) {
    val alert = sheet.alert ?: return
    val status = sheet.status ?: return
    val t = ClearedText.of(alert, status, nowMs, ZoneId.systemDefault())
    val look = Looks.ofKind(alert.kind ?: "incident")
    Column(Modifier.fillMaxWidth().testTag("cleared-panel")) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Disc(look.icon, look.tone, DG.disc, ghost = true)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(t.panelTitle, style = DGType.cardTitle, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    t.panelSub?.let { Text(it, style = DGType.body, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
                NavDisc("close", "Close", { model.clearMarker() }, Modifier.testTag("marker-close"))
            }
            // The green box: it is over, and the road as it is now.
            val box = RoundedCornerShape(22.dp)
            Column(Modifier.fillMaxWidth().clip(box).background(Brush.verticalGradient(listOf(DG.good.tint(.12f), DG.good.tint(.06f))))
                .border(1.dp, DG.good.copy(alpha = .24f), box).padding(12.dp).testTag("event-status")) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Disc("check", Tone.GOOD, DG.disc)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(t.headline, style = DGType.alertTitle, color = DG.goodInk)
                        Text(t.detail, style = DGType.small, color = DG.sub)
                    }
                }
                Spacer(Modifier.height(12.dp))
                Box(Modifier.fillMaxWidth().height(100.dp).clip(RoundedCornerShape(16.dp)).background(Color.White.copy(alpha = .8f))
                    .border(0.5.dp, DG.good.copy(alpha = .2f), RoundedCornerShape(16.dp))) {
                    // Nothing to steer around any more: the open road, no arrow.
                    LaneDrawing(Drawings.cleared(alert.laneLayout).copy(path = null, you = null), look.draw, Modifier.fillMaxWidth().height(100.dp))
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 4.dp)) {
                    DGIcon("watch", DG.sub, 14.dp)
                    Spacer(Modifier.width(6.dp))
                    Text(t.saidHeader, style = DGType.small.copy(fontWeight = FontWeight.SemiBold), color = DG.sub)
                }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(DG.ink.copy(alpha = .03f))
                    .border(1.dp, DG.hair, RoundedCornerShape(18.dp)).padding(10.dp).testTag("your-alert"),
                    verticalAlignment = Alignment.CenterVertically) {
                    LaneThumb(Drawings.forAlert(look.draw, alert.laneLayout), look.draw, width = 60.dp, height = 56.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(struck(alert.title ?: t.panelTitle), style = DGType.row, color = DG.faint, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        alert.body?.let { Text(it, style = DGType.small, color = DG.faint, maxLines = 3, overflow = TextOverflow.Ellipsis) }
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(DG.hair))
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DGButton("Show on map", { model.focusOn(alert.lat, alert.lon) }, Modifier.weight(1f).testTag("show-on-map"), icon = "locate")
            DGButton("Done", { model.clearMarker() }, Modifier.weight(1f).testTag("cleared-done"), style = BtnStyle.PRIMARY)
        }
    }
}
