package com.commutescout.drive

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Plays a voice's sample clip from the release, streamed, so a voice can
 * be heard before its pack is downloaded. One clip at a time.
 */
object PreviewPlayer {
    private var player: MediaPlayer? = null
    private val _playing = MutableStateFlow<String?>(null)
    /** The voice id whose sample is playing. */
    val playing = _playing.asStateFlow()

    fun play(v: VoiceEntry) {
        stop()
        val url = v.preview?.url ?: return
        _playing.value = v.id
        val p = MediaPlayer()
        player = p
        runCatching {
            p.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            p.setDataSource(url)
            p.setOnPreparedListener { it.start() }
            p.setOnCompletionListener { if (player === it) stop() }
            p.setOnErrorListener { mp, what, extra ->
                Log.w("Neural", "sample for ${v.id} did not play: $what/$extra")
                if (player === mp) stop()
                true
            }
            p.prepareAsync()
        }.onFailure { Log.w("Neural", "sample for ${v.id}: $it"); stop() }
    }

    fun stop() {
        player?.let { runCatching { it.reset(); it.release() } }
        player = null
        _playing.value = null
    }
}

/**
 * "CommuteScout voices": the neural voices, each with its sample, and
 * per pack a download with progress and cancel, then Delete with the
 * size it frees. Downloaded voices are chosen like system voices.
 */
@Composable
fun NeuralVoicesSection(model: DriveViewModel, packs: VoicePacks, installed: Set<String>, active: NeuralVoice?) {
    val prefs = model.prefs
    val listed = packs.catalog.listed
    if (listed.isEmpty()) return
    var askMetered by remember { mutableStateOf<VoicePackInfo?>(null) }
    var confirmDelete by remember { mutableStateOf<VoicePackInfo?>(null) }
    val playing by PreviewPlayer.playing.collectAsStateWithLifecycle()

    // The page's own test sentence, ready by the time the driver taps Test voice.
    LaunchedEffect(active?.id, prefs.voiceRate) {
        active?.let { Neural.renderer.request(it, prefs.voiceRate, VoiceLabels.preview(Units.spoken(800.0)), Double.NEGATIVE_INFINITY) }
    }

    fun download(pack: VoicePackInfo) {
        if (Connectivity.onWifi.value) packs.download(pack, metered = false) else askMetered = pack
    }

    GroupTitle("CommuteScout voices")
    for (pack in listed) {
        val state by remember(pack.id) { packs.state(pack) }.collectAsStateWithLifecycle()
        val ready = pack.id in installed
        PageGroup {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(pack.title, style = MaterialTheme.typography.titleSmall)
                    Text(pack.engineVersion + " · " + NeuralLabels.GENERATED, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            PackControls(pack, state, onDownload = { download(pack) }, onMetered = { packs.download(pack, metered = true) },
                onCancel = { packs.cancel(pack.id) }, onDelete = { confirmDelete = pack })
            HorizontalDivider()
            pack.voices.forEach { v ->
                NeuralVoiceRow(v, selected = prefs.voiceName == v.id, enabled = ready, playing = playing == v.id,
                    onPick = {
                        if (ready) prefs.voiceName = v.id
                        PreviewPlayer.play(v)
                    },
                    onPlay = { if (playing == v.id) PreviewPlayer.stop() else PreviewPlayer.play(v) })
            }
        }
    }
    Note(if (installed.isEmpty()) "Natural voices run on this phone and need no connection once downloaded. Tap a voice to hear a sample."
        else "Downloaded voices run on this phone and need no connection. If one cannot speak a sentence in time, the system voice says it.")

    askMetered?.let { pack ->
        val left = (pack.downloadSize - PackFiles.bytesOnDisk(packs.dir(pack.id), pack)).coerceAtLeast(0)
        AlertDialog(onDismissRequest = { askMetered = null },
            title = { Text("Download over mobile data?") },
            text = { Text("${pack.title} are ${Units.bytes(left)}. You can wait for Wi-Fi instead, and the download starts when you connect.") },
            confirmButton = { TextButton({ packs.download(pack, metered = true); askMetered = null }, Modifier.testTag("voice-metered-yes")) { Text("Use mobile data") } },
            dismissButton = { TextButton({ packs.download(pack, metered = false); askMetered = null }, Modifier.testTag("voice-metered-wait")) { Text("Wait for Wi-Fi") } })
    }
    confirmDelete?.let { pack ->
        AlertDialog(onDismissRequest = { confirmDelete = null },
            title = { Text("Delete ${pack.title.lowercase()}?") },
            text = { Text("This frees ${Units.bytes(packs.bytes(pack.id))}. Directions use the system voice until you download a voice again.") },
            confirmButton = { TextButton({
                if (pack.voices.any { it.id == prefs.voiceName }) prefs.voiceName = ""
                PreviewPlayer.stop()
                packs.delete(pack.id)
                Engine.alerts.speaker.invalidate(); Engine.tts.speaker.invalidate()
                confirmDelete = null
            }, Modifier.testTag("voice-delete-yes")) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text("Cancel") } })
    }
}

@Composable
private fun PackControls(pack: VoicePackInfo, state: PackState, onDownload: () -> Unit, onMetered: () -> Unit, onCancel: () -> Unit, onDelete: () -> Unit) {
    val tag = "voice-pack-${pack.id}"
    when (state) {
        PackState.NotInstalled -> Button(onDownload, Modifier.testTag("$tag-download")) { Text("Download (${Units.bytes(pack.downloadSize)})") }
        is PackState.Paused -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onDownload, Modifier.testTag("$tag-download")) { Text("Resume download") }
            Text("${Units.bytes(state.done)} of ${Units.bytes(state.total)}", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        is PackState.Waiting -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            LinearProgressIndicator({ fraction(state.done, state.total) }, Modifier.fillMaxWidth())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (state.metered) "Waiting for a connection" else "Waiting for Wi-Fi", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                TextButton(onCancel, Modifier.testTag("$tag-cancel")) { Text("Cancel") }
            }
            if (!state.metered) OutlinedButton(onMetered, Modifier.testTag("$tag-metered")) {
                Text("Use mobile data (${Units.bytes((state.total - state.done).coerceAtLeast(0))})")
            }
        }
        is PackState.Downloading -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            LinearProgressIndicator({ fraction(state.done, state.total) }, Modifier.fillMaxWidth().testTag("$tag-progress"))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Downloading · ${Units.bytes(state.done)} of ${Units.bytes(state.total)}", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                TextButton(onCancel, Modifier.testTag("$tag-cancel")) { Text("Cancel") }
            }
        }
        is PackState.Failed -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(state.reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            Button(onDownload, Modifier.testTag("$tag-download")) { Text("Try again") }
        }
        is PackState.Installed -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Downloaded · ${Units.bytes(state.bytes)}", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onDelete, Modifier.testTag("$tag-delete")) { Text("Delete", color = MaterialTheme.colorScheme.error) }
        }
    }
}

private fun fraction(done: Long, total: Long): Float = if (total <= 0) 0f else (done.toFloat() / total).coerceIn(0f, 1f)

/** A neural voice: chosen once its pack is on the phone; its sample plays either way. */
@Composable
private fun NeuralVoiceRow(v: VoiceEntry, selected: Boolean, enabled: Boolean, playing: Boolean, onPick: () -> Unit, onPlay: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onPick).testTag("voice-${v.id}"), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, null, enabled = enabled)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(v.name, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(NeuralLabels.accent(v.accent) + " · " + v.gender.replaceFirstChar { it.uppercase() } + " · " + NeuralLabels.GENERATED,
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (v.preview != null) IconButton(onPlay, Modifier.testTag("voice-play-${v.id}")) {
            Icon(if (playing) Icons.Default.Stop else Icons.Default.PlayArrow, if (playing) "Stop sample of ${v.name}" else "Play sample of ${v.name}")
        }
    }
}

/**
 * Each voice pack's credits and license. The full LICENSE and NOTICE
 * come with the pack, so they show here once it is downloaded.
 */
@Composable
fun VoiceLicensesPage() {
    val context = LocalContext.current
    val packs = remember { Neural.packs(Engine.app) }
    val installed by packs.installed.collectAsStateWithLifecycle()
    Note("CommuteScout voices are computer generated. Each pack keeps its own license.")
    for (pack in packs.catalog.listed) {
        var notice by remember(pack.id, installed) { mutableStateOf<String?>(null) }
        var license by remember(pack.id, installed) { mutableStateOf<String?>(null) }
        var showLicense by remember(pack.id) { mutableStateOf(false) }
        LaunchedEffect(pack.id, installed) {
            if (pack.id !in installed) return@LaunchedEffect
            val dir = packs.dir(pack.id)
            withContext(Dispatchers.IO) {
                notice = runCatching { File(dir, "NOTICE").readText() }.getOrNull()
                license = runCatching { File(dir, "LICENSE").readText() }.getOrNull()
            }
        }
        GroupTitle(pack.title)
        PageGroup {
            Text(pack.engineVersion, style = MaterialTheme.typography.titleSmall)
            Text(pack.attribution, style = MaterialTheme.typography.bodyMedium)
            Text("License: ${pack.license.name}", style = MaterialTheme.typography.bodyMedium)
            if (pack.license.url.isNotEmpty()) LinkRow("License and model card") {
                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(pack.license.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            if (pack.id !in installed) {
                Text("The full LICENSE and NOTICE show here once the pack is downloaded.", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                notice?.let {
                    Text("NOTICE", style = MaterialTheme.typography.labelLarge)
                    Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp, modifier = Modifier.testTag("voice-notice-${pack.id}"))
                }
                TextButton({ showLicense = !showLicense }, Modifier.testTag("voice-license-${pack.id}")) {
                    Text(if (showLicense) "Hide LICENSE" else "Show LICENSE")
                }
                if (showLicense) license?.let { Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp) }
            }
        }
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp))
}
