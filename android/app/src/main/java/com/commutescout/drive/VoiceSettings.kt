package com.commutescout.drive

import android.content.Intent
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.GroupFoot
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.SwitchRow
import com.commutescout.drive.design.Tag
import com.commutescout.drive.design.TagLook
import com.commutescout.drive.design.tag
import kotlinx.coroutines.delay
import java.util.Locale
import kotlin.math.roundToInt

/** The system screen for text-to-speech: engines, voice downloads, the default engine. */
const val TTS_SETTINGS = "com.android.settings.TTS_SETTINGS"

/** What the home page shows for the voice: "Automatic", a neural voice's name, or the chosen one's number. */
fun voiceSummary(prefs: Prefs, voices: List<VoiceInfo>): String {
    if (prefs.voiceName.isEmpty()) return "Automatic"
    runCatching { Neural.catalog.voice(prefs.voiceName) }.getOrNull()?.let { return it.name }
    val v = voices.firstOrNull { it.name == prefs.voiceName } ?: return "Automatic"
    return "Voice " + VoiceLabels.number(v, voices)
}

/**
 * The voice for road alerts and turn instructions. One switch mutes
 * every voice. The list holds Automatic, the CommuteScout voices and the
 * phone's own, best first: a tap picks one, and its play button says a
 * sample without picking it. A CommuteScout voice that is not on the
 * phone yet plays its recorded sample and asks before the download.
 */
@Composable
fun VoicePage(model: DriveViewModel, openLicenses: () -> Unit = {}) {
    val prefs = model.prefs
    val nav = LocalSettingsNav.current
    val packs = remember { Neural.packs(Engine.app) }
    val installed by packs.installed.collectAsStateWithLifecycle()
    val listed = packs.catalog.listed
    val states = listed.associate { p -> p.id to remember(p.id) { packs.state(p) }.collectAsStateWithLifecycle().value }
    val neural = NeuralPick.choose(prefs.voiceName, packs.catalog, installed)
    val neuralAuto = NeuralPick.automatic(packs.catalog, installed)
    val picked = listed.firstNotNullOfOrNull { p -> p.voices.firstOrNull { it.id == prefs.voiceName }?.let { p to it } }
    val speaker = Engine.alerts.speaker
    val context = LocalContext.current
    val ready by speaker.ready.collectAsStateWithLifecycle()
    val online by Connectivity.online.collectAsStateWithLifecycle()
    val playing by PreviewPlayer.playing.collectAsStateWithLifecycle()
    val uiState by model.navigationUiState.collectAsStateWithLifecycle()
    var showOthers by remember { mutableStateOf(false) }
    // Read again on coming back from the system's settings, where
    // voices are downloaded and the default engine is set.
    var visits by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        visits++
        speaker.invalidate()
        onPauseOrDispose { }
    }
    val voices = remember(ready, visits) { if (ready) speaker.voices().map(VoiceInfo::of) else emptyList() }
    val engines = remember(ready, visits) { if (ready) speaker.engines() else emptyList() }
    val locale = Locale.getDefault()
    val mine = VoicePick.forLocale(voices, locale)
    val others = VoicePick.others(voices, locale)
    val auto = VoicePick.smartDefault(voices, locale, online)
    val speaking = VoicePick.resolve(prefs.voiceName, voices, locale, online)
    val neuralVoices = listed.flatMap { p -> p.voices.map { p to it } }
    val localNeural = neuralVoices.filter { it.second.accent.endsWith("-" + locale.country) }
    val otherNeural = neuralVoices.filter { it !in localNeural }
    val automatic = picked == null && voices.none { it.name == prefs.voiceName }
    val sample = VoiceLabels.preview(Units.spoken(800.0))

    // A system voice saying its sample: which row, and how far along.
    var trialRow by remember { mutableStateOf<String?>(null) }
    var trialProgress by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(trialRow) {
        if (trialRow == null) return@LaunchedEffect
        val start = System.currentTimeMillis()
        val estimate = (sample.length * 68 / prefs.voiceRate).toLong().coerceAtLeast(1500)
        while (true) {
            val t = System.currentTimeMillis() - start
            trialProgress = (t.toFloat() / estimate).coerceIn(0f, .98f)
            if ((t > 900 && !speaker.isSpeaking) || t > estimate * 3) break
            delay(80)
        }
        speaker.trial = null
        trialRow = null
    }
    // The neural samples have no length up front: the ring fills over a usual sample.
    var neuralStart by remember { mutableStateOf(0L) }
    var neuralProgress by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(playing) {
        if (playing == null) return@LaunchedEffect
        neuralStart = System.currentTimeMillis()
        while (true) { neuralProgress = ((System.currentTimeMillis() - neuralStart) / 5000f).coerceAtMost(.98f); delay(80) }
    }

    // The page's own test sentence, ready by the time the driver taps Test voice.
    LaunchedEffect(neural?.id, prefs.voiceRate) {
        neural?.let { Neural.renderer.request(it, prefs.voiceRate, sample, Double.NEGATIVE_INFINITY) }
    }

    fun stopAll() { PreviewPlayer.stop(); if (trialRow != null) { speaker.stop(); speaker.trial = null; trialRow = null } }
    fun preview() { stopAll(); Engine.alerts.preview(sample) }
    fun trial(row: String, voiceName: String?) {
        if (trialRow == row) { stopAll(); return }
        stopAll()
        speaker.trial = voiceName
        trialProgress = 0f
        Engine.alerts.preview(sample)
        trialRow = row
    }
    fun openSystem() {
        runCatching { context.startActivity(Intent(TTS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            .onFailure { Log.w("Voice", "no text-to-speech settings screen: $it") }
    }
    // The engine's own voice download screen, one tap away; the general
    // settings screen when the engine has none.
    fun openDownloads() {
        val engine = prefs.voiceEngine.ifEmpty { speaker.defaultEngine ?: "" }
        val install = Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (engine.isNotEmpty()) install.setPackage(engine)
        runCatching { context.startActivity(install) }
            .onFailure { Log.w("Voice", "no voice download screen for $engine: $it"); openSystem() }
    }
    fun pick(v: VoiceInfo?) {
        if (v != null && !v.installed) { openDownloads(); return }
        prefs.voiceName = v?.name ?: ""
        // Automatic with a neural pack on the phone: its own sample, at once.
        if (v == null && neuralAuto != null) { stopAll(); PreviewPlayer.play(neuralAuto.voice) } else preview()
    }
    fun choose(pack: VoicePackInfo, v: VoiceEntry, metered: Boolean) {
        prefs.voiceName = v.id
        packs.download(pack, metered)
    }
    fun offer(pack: VoicePackInfo, v: VoiceEntry) {
        val left = (pack.downloadSize - PackFiles.bytesOnDisk(packs.dir(pack.id), pack)).coerceAtLeast(0)
        val onWifi = Connectivity.onWifi.value
        val body = "${v.name} comes in ${pack.title.lowercase()}, a ${Units.bytes(left)} download with ${pack.voices.size - 1} more voices. " +
            "Until it finishes, the system voice speaks." + if (onWifi) "" else " You can wait for Wi-Fi, and the download starts when you connect."
        val actions = if (onWifi) listOf(ConfirmAction("Cancel") { PreviewPlayer.stop() },
            ConfirmAction("Download", BtnStyle.PRIMARY, "voice-offer-download") { choose(pack, v, metered = false) })
        else listOf(ConfirmAction("Wait for Wi-Fi", tag = "voice-metered-wait") { choose(pack, v, metered = false) },
            ConfirmAction("Use mobile data", BtnStyle.PRIMARY, "voice-metered-yes") { choose(pack, v, metered = true) })
        nav?.confirm(ConfirmRequest("Download ${v.name}?", body, actions) { PreviewPlayer.stop() })
    }
    // On the phone: picked like any voice. Downloading: picked, and its
    // recorded sample plays. Otherwise the sample plays and the download is offered.
    fun pickNeural(pack: VoicePackInfo, v: VoiceEntry) {
        when (states[pack.id]) {
            is PackState.Installed -> { prefs.voiceName = v.id; preview() }
            is PackState.Downloading, is PackState.Waiting -> { prefs.voiceName = v.id; stopAll(); PreviewPlayer.play(v) }
            else -> { stopAll(); PreviewPlayer.play(v); offer(pack, v) }
        }
    }

    @Composable
    fun NeuralRow(pack: VoicePackInfo, v: VoiceEntry) {
        var sub = NeuralLabels.accent(v.accent) + " · " + v.gender.replaceFirstChar { it.uppercase() }
        val status = when (val s = states[pack.id]) {
            is PackState.Installed -> null
            is PackState.Downloading -> "Downloading ${percent(s.done, s.total)}"
            is PackState.Waiting -> if (s.metered) "Waiting for a connection" else "Waiting for Wi-Fi"
            is PackState.Paused -> "Paused at ${percent(s.done, s.total)}"
            is PackState.Failed -> "Download did not finish"
            else -> { sub += " · ${Units.bytes(pack.downloadSize)} download"; null }
        }
        VoiceChoice(v.name, "Enhanced", sub, prefs.voiceName == v.id, "voice-${v.id}", status = status,
            playing = playing == v.id, progress = neuralProgress, sample = sample, onPick = { pickNeural(pack, v) }) {
            if (playing == v.id) PreviewPlayer.stop() else { stopAll(); PreviewPlayer.play(v) }
        }
    }

    @Composable
    fun SystemRow(v: VoiceInfo) {
        VoiceChoice(VoiceLabels.title(v, voices), if (v.quality >= 400) "Enhanced" else null, VoiceLabels.detail(v), prefs.voiceName == v.name,
            "voice-${v.name}", enabled = v.installed, playing = trialRow == v.name, progress = trialProgress, sample = sample,
            onPick = { pick(v) }, onPlay = if (v.installed) ({ trial(v.name, v.name) }) else null)
    }

    Group(Modifier.padding(top = 4.dp)) {
        SwitchRow("Speak directions and alerts", uiState.isMuted != true, { if (it == (uiState.isMuted == true)) model.toggleMute() },
            icon = "speaker", tileColor = DG.low, sub = "Turn this off to mute every voice. Alerts still show on screen.",
            tag = "switch-Speak directions and alerts")
    }
    GroupHead("Voices on this phone", trailing = { Tag("Free, works offline", TagLook.GOOD) })
    Group {
        VoiceChoice("Automatic", null, neuralAuto?.let { "Uses ${it.name}" } ?: auto?.let { "Uses " + VoiceLabels.full(it, voices) }
            ?: "Uses the speech engine's default voice", automatic, "voice-auto", playing = trialRow == "auto", progress = trialProgress,
            sample = sample, onPick = { pick(null) }) { trial("auto", null) }
        localNeural.forEach { (p, v) -> RowDivider(48.dp); NeuralRow(p, v) }
        if (!ready) { RowDivider(48.dp); SRow("Loading the phone's voices", sub = null) }
        mine.forEach { RowDivider(48.dp); SystemRow(it) }
        if (mine.isEmpty() && ready) {
            RowDivider(48.dp)
            Text("No voice on this phone speaks ${locale.getDisplayLanguage(Locale.US)}. Download one in text-to-speech settings.",
                Modifier.padding(16.dp), style = PageType.rowSub, color = DG.sub)
        }
        // Other accents on request; the picked voice stays in sight whatever its accent.
        otherNeural.filter { showOthers || it.second.id == prefs.voiceName }.forEach { (p, v) -> RowDivider(48.dp); NeuralRow(p, v) }
        others.filter { showOthers || it.name == prefs.voiceName }.forEach { RowDivider(48.dp); SystemRow(it) }
        val more = others.size + otherNeural.size
        if (more > 0) {
            RowDivider(0.dp)
            SRow(if (showOthers) "Hide other accents and languages" else "Show other accents and languages ($more)", Modifier.tag("voice-others"),
                labelColor = DG.lowInk, onClick = { showOthers = !showOthers })
        }
    }
    val fallback = speaking?.let { VoiceLabels.title(it, voices) } ?: "the engine's default voice"
    if (picked != null && neural == null) {
        GroupFoot("${picked.second.name} speaks once ${picked.first.title.lowercase()} finish downloading. Until then, $fallback speaks.")
    } else if (picked == null && prefs.voiceName.isNotEmpty() && speaking?.name != prefs.voiceName) {
        GroupFoot(if (voices.any { it.name == prefs.voiceName && it.network } && !online) "No connection: $fallback speaks until the signal is back."
            else "The chosen voice is no longer on this phone, so $fallback speaks instead.")
    }
    GroupFoot("These voices are built into your phone and cost nothing. Add more in your phone’s text-to-speech settings.")

    GroupHead("Speed and pitch")
    Group {
        SliderRow("Speed", VoiceLabels.rate(prefs.voiceRate), prefs.voiceRate, VoiceLabels.MIN_RATE..VoiceLabels.MAX_RATE, 7, "voice-rate",
            { prefs.voiceRate = (it * 10).roundToInt() / 10f }) { preview() }
        if (neural == null) {
            RowDivider(16.dp)
            SliderRow("Pitch", VoiceLabels.pitch(prefs.voicePitch), prefs.voicePitch, VoiceLabels.MIN_PITCH..VoiceLabels.MAX_PITCH, 7, "voice-pitch",
                { prefs.voicePitch = (it * 20).roundToInt() / 20f }) { preview() }
        }
        Row(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DGButton("Test voice", { preview() }, Modifier.weight(1f).tag("voice-test"), style = BtnStyle.BLUE, icon = "play", enabled = ready)
            DGButton("Reset", { prefs.voiceRate = 1f; prefs.voicePitch = 1f }, Modifier.weight(1f).tag("voice-reset"),
                enabled = prefs.voiceRate != 1f || prefs.voicePitch != 1f)
        }
    }
    GroupFoot(if (neural != null) "${neural.name} keeps its own pitch and prepares each sentence ahead of time, so a new one can take a few seconds to test."
        else "Used for road alerts and turn instructions.")

    VoicePackGroup(packs, listed, states, prefs)

    if (engines.size > 1) {
        GroupHead("Speech engine")
        val inUse = prefs.voiceEngine.ifEmpty { speaker.defaultEngine ?: "" }
        Group {
            engines.forEachIndexed { i, e ->
                if (i > 0) RowDivider(18.dp)
                RadioRow(e.label, e.name == inUse, "engine-${e.name}", sub = if (e.name == speaker.defaultEngine) "System default" else "Installed") {
                    if (e.name != inUse) {
                        // Voice names belong to an engine: the new one starts on Automatic.
                        prefs.voiceEngine = if (e.name == speaker.defaultEngine) "" else e.name
                        prefs.voiceName = ""
                        Engine.voiceEngineChanged()
                    }
                }
            }
        }
        GroupFoot("Each engine has its own voices.")
    }

    Spacer(Modifier.height(14.dp))
    Group {
        SRow("Download more system voices", icon = "download", tileColor = DG.low, chevron = true, onClick = { openDownloads() })
        RowDivider()
        SRow("Text-to-speech settings", icon = "gear", tileColor = DG.faint, chevron = true, onClick = { openSystem() })
        RowDivider()
        SRow("Voice licenses", Modifier.tag("voice-licenses"), icon = "lock", tileColor = DG.faint, chevron = true, onClick = openLicenses)
    }
}

private fun percent(done: Long, total: Long): String = "${if (total <= 0) 0 else (done * 100 / total).coerceIn(0, 100)}%"

/**
 * One voice: a check when chosen, its name and a note, the accent under
 * it, and a play button. While it plays, the line under the name is
 * the sentence it says, with bars, and the button is stop with a ring.
 */
@Composable
private fun VoiceChoice(title: String, note: String?, sub: String, selected: Boolean, tag: String, enabled: Boolean = true, status: String? = null,
                        playing: Boolean = false, progress: Float = 0f, sample: String = "", onPick: () -> Unit, onPlay: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().clickable(enabled = true, onClick = onPick).semantics { this.selected = selected }.tag(tag)
        .padding(start = 12.dp, end = 10.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) { if (selected) DGIcon("check", DG.low, 20.dp, stroke = 2.6f) }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = PageType.rowLabel.copy(fontWeight = FontWeight.SemiBold), color = if (enabled) DG.ink else DG.faint,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (note != null) Text("  $note", style = PageType.note.copy(fontWeight = FontWeight.SemiBold), color = DG.sub, maxLines = 1)
            }
            if (playing) Row(verticalAlignment = Alignment.CenterVertically) {
                Bars()
                Spacer(Modifier.width(6.dp))
                Text("“$sample”", style = PageType.rowSub, color = DG.lowInk, maxLines = 1, overflow = TextOverflow.Ellipsis)
            } else Text(sub, style = PageType.rowSub, color = DG.sub, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (status != null) Text(status, style = PageType.rowSub, color = DG.lowInk)
        }
        if (onPlay != null) {
            Spacer(Modifier.width(8.dp))
            PlayButton(playing, progress, onPlay)
        }
    }
}

@Composable
private fun PlayButton(playing: Boolean, progress: Float, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(DG.low.copy(alpha = .1f)).clickable(role = Role.Button, onClick = onClick)
        .semantics { contentDescription = if (playing) "Stop" else "Play a sample" }, contentAlignment = Alignment.Center) {
        if (playing) Canvas(Modifier.fillMaxSize().padding(3.dp)) {
            drawArc(DG.low, -90f, 360f * progress, false, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round), size = Size(size.width, size.height), topLeft = Offset.Zero)
        }
        DGIcon(if (playing) "stop" else "play", DG.low, 18.dp, stroke = 2.4f)
    }
}

/** Three bars that rise and fall: a voice speaking. */
@Composable
private fun Bars() {
    val t = rememberInfiniteTransition(label = "bars")
    Row(Modifier.height(12.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) {
        listOf(0, 160, 320).forEach { d ->
            val h by t.animateFloat(.3f, 1f, infiniteRepeatable(tween(420, d), RepeatMode.Reverse), label = "bar")
            Box(Modifier.width(3.dp).fillMaxHeightFraction(h).clip(RoundedCornerShape(2.dp)).background(DG.low))
        }
    }
}

private fun Modifier.fillMaxHeightFraction(f: Float) = this.then(Modifier.height((12 * f).dp))

@Composable
private fun SliderRow(label: String, value: String, current: Float, range: ClosedFloatingPointRange<Float>, steps: Int, tag: String,
                      onChange: (Float) -> Unit, onDone: () -> Unit) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(label, Modifier.weight(1f), style = PageType.rowLabel, color = DG.ink)
            Text(value, style = PageType.rowValue, color = DG.sub)
        }
        Slider(current, onChange, Modifier.testTag(tag), valueRange = range, steps = steps, onValueChangeFinished = onDone,
            colors = SliderDefaults.colors(thumbColor = DG.low, activeTrackColor = DG.low, inactiveTrackColor = DG.ink.copy(alpha = .08f),
                activeTickColor = DG.low.copy(alpha = .4f), inactiveTickColor = DG.ink.copy(alpha = .15f)))
    }
}
