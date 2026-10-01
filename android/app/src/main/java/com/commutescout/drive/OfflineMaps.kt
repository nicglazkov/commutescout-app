package com.commutescout.drive

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
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * Maps saved on the phone for driving with no signal: the trip
 * corridors the app saved on its own, and whole states the driver
 * chooses here. A state is big, and the sheet says how big before
 * anything downloads.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OfflineMapsSheet(model: DriveViewModel, onClose: () -> Unit) {
    val files by MapFiles.files.collectAsStateWithLifecycle()
    val manifest by MapFiles.manifest.collectAsStateWithLifecycle()
    val progress by MapFiles.progress.collectAsStateWithLifecycle()
    val usingLocal by MapFiles.usingLocal.collectAsStateWithLifecycle()
    val online by Connectivity.online.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var confirming by remember { mutableStateOf<MapFiles.StateFile?>(null) }
    LaunchedEffect(Unit) { MapFiles.refreshManifest() }

    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("offline-maps-sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Offline maps", style = MaterialTheme.typography.titleLarge)
            Text("With no signal the map draws from a file saved here: the corridor saved for the current trip, or a whole state. Guidance and spoken alerts work either way; this is the map underneath.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            usingLocal?.let { Text("Drawing from ${it.name} right now", style = MaterialTheme.typography.bodySmall) }

            Heading("Saved for trips")
            val corridors = files.filter { it.kind == "corridor" }.sortedByDescending { it.savedAt }
            if (corridors.isEmpty()) Text("None yet. A trip's map is saved when it starts, on Wi-Fi, or from the route card on mobile data.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            corridors.forEach { c ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(c.name)
                        Text("${c.sizeText}, saved ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(c.savedAt))}",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton({ MapFiles.delete(c) }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.error) }
                }
            }

            Heading("Whole states")
            Text("A whole state is the entire map at full detail, which can be several gigabytes. Download on Wi-Fi, and only the states you drive in.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val m = manifest
            if (m == null) Text(if (online) "The list of states is loading." else "The list of states needs a signal.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            m?.states?.forEach { s ->
                val saved = MapFiles.has(s.code)
                val p = progress["state-${s.code}"]
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.name)
                        Text(saved?.let { "Saved, ${it.sizeText}" } ?: s.bytes?.let(Units::bytes) ?: "size unknown",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (p != null) LinearProgressIndicator(progress = { p }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                    Spacer(Modifier.width(8.dp))
                    when {
                        p != null -> {}
                        saved != null -> IconButton({ MapFiles.delete(saved) }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.error) }
                        else -> IconButton({ confirming = s }, enabled = online, modifier = Modifier.testTag("download-${s.code}")) { Icon(Icons.Default.Download, "Download") }
                    }
                }
            }
            if (MapFiles.bytesOnDisk > 0) Text("Using ${Units.bytes(MapFiles.bytesOnDisk)} on this phone.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }

    confirming?.let { s ->
        val size = s.bytes?.let(Units::bytes) ?: "size unknown"
        AlertDialog(onDismissRequest = { confirming = null },
            title = { Text("Download ${s.name}?") },
            text = { Text("This is the whole map of ${s.name} at full detail, $size. It may take a while and should go over Wi-Fi.") },
            confirmButton = { TextButton({ confirming = null; scope.launch { MapFiles.downloadState(s) } }) { Text("Download $size") } },
            dismissButton = { TextButton({ confirming = null }) { Text("Cancel") } })
    }
}
