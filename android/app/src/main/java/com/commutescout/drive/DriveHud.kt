package com.commutescout.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.roundToInt

// What the driver sees over the map while moving: the alert ahead as a
// banner at the top, and the speedometer at the bottom. Both stay
// clear of the search bar, the instruction card and the side buttons,
// read at arm's length, and go away with one tap. The iPhone app has
// the same two.

/**
 * The next alert, dropped in from the top. Shows from the first warning
 * distance, says what and how far, speaks again on a tap, and leaves
 * with the X, a swipe up, or once the alert is behind.
 */
@Composable
fun AlertBanner(item: Upcoming, along: Double, more: Int, canConfirm: Boolean, onVote: (String) -> Unit, onDismiss: () -> Unit, onTap: () -> Unit) {
    val m = item.marker
    val color = if (m.kind == "plugin") PluginStyle.color(PluginStyle.sourceId(m)) else MarkerIcons.color(m.kind)
    Column(
        Modifier.fillMaxWidth().shadow(8.dp, RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(16.dp))
            .pointerInput(item.id) { detectVerticalDragGestures { _, dy -> if (dy < -12) onDismiss() } }
            .testTag("alert-banner"),
    ) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onTap), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(5.dp).height(56.dp).padding(vertical = 8.dp).background(color, RoundedCornerShape(3.dp)))
        Spacer(Modifier.width(10.dp))
        Box(Modifier.size(44.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            MarkerGlyph(m, 30.dp)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
            Text(m.displayTitle, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row {
                Text(Units.distance(max(0.0, item.alongMeters - along)) + " ahead", style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, color = color)
                if (more > 0) Text("  +$more more", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.width(12.dp))
    }
    // The buttons a hand can hit from the wheel: big, colored, one row.
    // Dismiss always; Still there and Gone when the plugin takes
    // confirmations (the Waze relay does), and those dismiss too.
    Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, bottom = 10.dp, top = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (canConfirm) {
            BigButton("Still there", Icons.Default.ThumbUp, Color(0xFF2E7D32), Modifier.weight(1.25f).testTag("alert-confirm-up"), iconToo = false) { onVote("up"); onDismiss() }
            BigButton("Gone", Icons.Default.ThumbDown, Color(0xFFC62828), Modifier.weight(1f).testTag("alert-confirm-gone"), iconToo = false) { onVote("gone"); onDismiss() }
        }
        BigButton("Dismiss", Icons.Default.Close, Color(0xFF3F4854), Modifier.weight(1f).testTag("alert-dismiss"), iconToo = !canConfirm, onClick = onDismiss)
    }
    }
}

@Composable
private fun BigButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, modifier: Modifier, iconToo: Boolean = true, onClick: () -> Unit) {
    // Three across, the words alone fit; the icon joins when there is room.
    Row(modifier.height(52.dp).background(color, RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        if (iconToo) { Icon(icon, null, tint = Color.White); Spacer(Modifier.width(6.dp)) }
        Text(label, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1, fontSize = 15.sp)
    }
}

/**
 * Speed and the posted limit, the way a dashboard shows them: the
 * speed large, the limit as the sign on the road. Red when over.
 */
@Composable
fun Speedometer(speedMps: Double, limitKmh: Double?) {
    val miles = Units.useMiles
    val speed = if (speedMps < 0) 0 else (if (miles) speedMps * 2.236936 else speedMps * 3.6).roundToInt()
    val limit = limitKmh?.let { (if (miles) it / 1.609344 else it).roundToInt() }
    val over = limit != null && speed > limit + 1
    Row(
        Modifier.shadow(6.dp, RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp).testTag("speedometer"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(56.dp)) {
            Text("$speed", fontSize = 32.sp, fontWeight = FontWeight.Bold, lineHeight = 34.sp,
                color = if (over) Color(0xFFD32F2F) else MaterialTheme.colorScheme.onSurface)
            Text(if (miles) "mph" else "km/h", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        when {
            limit != null && miles -> Column(
                Modifier.size(42.dp, 50.dp).background(Color.White, RoundedCornerShape(5.dp)).border(2.dp, Color.Black, RoundedCornerShape(5.dp)),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                Text("SPEED", fontSize = 8.sp, fontWeight = FontWeight.Bold, color = Color.Black, lineHeight = 9.sp)
                Text("LIMIT", fontSize = 8.sp, fontWeight = FontWeight.Bold, color = Color.Black, lineHeight = 9.sp)
                Text("$limit", fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color.Black, lineHeight = 22.sp)
            }
            limit != null -> Box(
                Modifier.size(46.dp).clip(CircleShape).background(Color.White).border(5.dp, Color(0xFFD32F2F), CircleShape),
                contentAlignment = Alignment.Center,
            ) { Text("$limit", fontSize = 17.sp, fontWeight = FontWeight.Black, color = Color.Black) }
            else -> Text("limit\nunknown", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline, textAlign = TextAlign.Center)
        }
    }
}
