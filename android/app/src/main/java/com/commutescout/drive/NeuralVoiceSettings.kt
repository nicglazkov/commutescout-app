package com.commutescout.drive

import com.commutescout.drive.design.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
 * "Downloaded voices": each set of CommuteScout voices that is on the
 * phone or on its way, with its progress, and Cancel, Resume or Delete.
 * Voices are picked in the list above; picking one that is not
 * downloaded starts its set here.
 */
@Composable
fun VoicePackGroup(packs: VoicePacks, listed: List<VoicePackInfo>, states: Map<String, PackState>, prefs: Prefs) {
    val shown = listed.filter { states[it.id] != null && states[it.id] != PackState.NotInstalled }
    if (shown.isEmpty()) return
    val nav = LocalSettingsNav.current
    fun delete(pack: VoicePackInfo) {
        nav?.confirm(ConfirmRequest("Delete ${pack.title.lowercase()}?",
            "This frees ${Units.bytes(packs.bytes(pack.id))}. Directions use the system voice until you download a voice again.",
            listOf(ConfirmAction("Cancel"), ConfirmAction("Delete", BtnStyle.DANGER, "voice-delete-yes") {
                if (pack.voices.any { it.id == prefs.voiceName }) prefs.voiceName = ""
                PreviewPlayer.stop()
                packs.delete(pack.id)
                Engine.alerts.speaker.invalidate(); Engine.tts.speaker.invalidate()
            })))
    }
    GroupHead("Downloaded voices")
    Group {
        shown.forEachIndexed { i, pack ->
            if (i > 0) RowDivider(16.dp)
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(pack.title, style = PageType.rowLabel.copy(fontWeight = FontWeight.SemiBold), color = DG.ink)
                Text("${pack.voices.size} voices · ${Units.bytes(pack.downloadSize)} · ${NeuralLabels.GENERATED}", style = PageType.rowSub, color = DG.sub)
                PackControls(pack, states.getValue(pack.id), onResume = { packs.download(pack, metered = false) },
                    onMetered = { packs.download(pack, metered = true) }, onCancel = { packs.cancel(pack.id) }, onDelete = { delete(pack) })
            }
        }
    }
    GroupFoot("One download adds every voice in a set. If a voice cannot say a sentence in time, the system voice says it.")
}

@Composable
private fun PackControls(pack: VoicePackInfo, state: PackState, onResume: () -> Unit, onMetered: () -> Unit, onCancel: () -> Unit, onDelete: () -> Unit) {
    val tag = "voice-pack-${pack.id}"
    @Composable fun Line(text: String, color: androidx.compose.ui.graphics.Color = DG.sub, buttons: @Composable () -> Unit) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = PageType.rowSub, color = color)
            buttons()
        }
    }
    @Composable fun Small(label: String, t: String, style: BtnStyle = BtnStyle.PLAIN, onClick: () -> Unit) {
        DGButton(label, onClick, Modifier.padding(start = 6.dp).tag(t), style = style)
    }
    @Composable fun Bar(done: Long, total: Long, t: String? = null) {
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(DG.ink.copy(alpha = .07f)).then(if (t != null) Modifier.tag(t) else Modifier)) {
            Box(Modifier.fillMaxWidth(fraction(done, total)).height(6.dp).clip(CircleShape).background(DG.low))
        }
    }
    when (state) {
        PackState.NotInstalled -> {}
        is PackState.Paused -> Line("Paused · ${Units.bytes(state.done)} of ${Units.bytes(state.total)}") {
            Small("Delete", "$tag-delete", BtnStyle.WARN, onDelete); Small("Resume", "$tag-download", onClick = onResume)
        }
        is PackState.Waiting -> {
            Bar(state.done, state.total)
            Line(if (state.metered) "Waiting for a connection" else "Waiting for Wi-Fi") {
                if (!state.metered) Small("Use data (${Units.bytes((state.total - state.done).coerceAtLeast(0))})", "$tag-metered", onClick = onMetered)
                Small("Cancel", "$tag-cancel", onClick = onCancel)
            }
        }
        is PackState.Downloading -> {
            Bar(state.done, state.total, "$tag-progress")
            Line("Downloading · ${Units.bytes(state.done)} of ${Units.bytes(state.total)}") { Small("Cancel", "$tag-cancel", onClick = onCancel) }
        }
        is PackState.Failed -> Line(state.reason, DG.highInk) {
            Small("Delete", "$tag-delete", BtnStyle.WARN, onDelete); Small("Try again", "$tag-download", onClick = onResume)
        }
        is PackState.Installed -> Line("Downloaded · ${Units.bytes(state.bytes)}") { Small("Delete", "$tag-delete", BtnStyle.WARN, onDelete) }
    }
}

private fun fraction(done: Long, total: Long): Float = if (total <= 0) 0f else (done.toFloat() / total).coerceIn(0f, 1f)

/**
 * Each voice pack's credits and license. The full LICENSE and NOTICE
 * come with the pack, so they show here once it is downloaded.
 */
@Composable
fun VoiceLicensesPage() {
    val context = LocalContext.current
    val packs = remember { Neural.packs(Engine.app) }
    val installed by packs.installed.collectAsStateWithLifecycle()
    GroupFoot("CommuteScout voices are computer generated. Each pack keeps its own license.", Modifier.padding(bottom = 4.dp))
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
        GroupHead(pack.title)
        Group {
            SRow(pack.engineVersion, sub = pack.attribution)
            RowDivider(18.dp)
            SRow("License", value = pack.license.name)
            if (pack.license.url.isNotEmpty()) {
                RowDivider(18.dp)
                SRow("License and model card", chevron = true, onClick = {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(pack.license.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                })
            }
            RowDivider(18.dp)
            if (pack.id !in installed) {
                Text("The full LICENSE and NOTICE show here once the pack is downloaded.", Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
            } else {
                notice?.let {
                    Text(it, Modifier.padding(16.dp).testTag("voice-notice-${pack.id}"), fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = DG.ink)
                    RowDivider(18.dp)
                }
                SRow(if (showLicense) "Hide LICENSE" else "Show LICENSE", Modifier.testTag("voice-license-${pack.id}"), onClick = { showLicense = !showLicense })
                if (showLicense) license?.let { Text(it, Modifier.padding(16.dp), fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = DG.ink) }
            }
        }
    }
}
