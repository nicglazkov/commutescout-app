package com.commutescout.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.tag

/**
 * What an unreviewed plugin needs before it may alert: the notice, a
 * checkbox the person must tick, and the action (Install, or Allow alerts
 * from Settings > Alerts) disabled until it is ticked. Cancel changes nothing.
 */
@Composable
fun UnreviewedNoticeDialog(s: FlareSource, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    var ticked by remember(s.id) { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.tag("plugin-notice"),
        title = { Text("${s.name} is not reviewed") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(PluginConsent.NOTICE, Modifier.fillMaxWidth().background(DG.plug.copy(alpha = .08f), RoundedCornerShape(12.dp)).padding(12.dp)
                    .tag("plugin-notice-text"), fontWeight = FontWeight.SemiBold)
                Text("You can turn its alerts, and whether they are spoken, on or off anytime in Settings > Alerts.", color = DG.sub)
                Row(Modifier.clickable(role = Role.Checkbox) { ticked = !ticked }.tag("plugin-notice-agree"),
                    verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(ticked, { ticked = it })
                    Text(PluginConsent.AGREE, Modifier.padding(start = 4.dp))
                }
            }
        },
        confirmButton = {
            TextButton({ onConfirm(); onDismiss() }, Modifier.tag("plugin-notice-confirm"), enabled = ticked) { Text(action) }
        },
        dismissButton = { TextButton(onDismiss, Modifier.tag("plugin-notice-cancel")) { Text("Cancel") } },
    )
}
