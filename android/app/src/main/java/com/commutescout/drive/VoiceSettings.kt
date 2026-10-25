package com.commutescout.drive

import android.content.Intent
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
 * The voice for road alerts and turn instructions: every voice the
 * phone's engine has for the driver's language, best first, then speed
 * and pitch, then the engine. A tap picks a voice and plays a sample of
 * a drive, so the choice is made by ear.
 */
@Composable
fun VoicePage(model: DriveViewModel, openLicenses: () -> Unit = {}) {
    val prefs = model.prefs
    val packs = remember { Neural.packs(Engine.app) }
    val installed by packs.installed.collectAsStateWithLifecycle()
    val neural = NeuralPick.choose(prefs.voiceName, packs.catalog, installed)
    val neuralAuto = NeuralPick.automatic(packs.catalog, installed)
    val speaker = Engine.alerts.speaker
    val context = LocalContext.current
    val ready by speaker.ready.collectAsStateWithLifecycle()
    val online by Connectivity.online.collectAsStateWithLifecycle()
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

    fun preview() = Engine.alerts.preview(VoiceLabels.preview(Units.spoken(800.0)))
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
        if (v == null && neuralAuto != null) PreviewPlayer.play(neuralAuto.voice) else preview()
    }

    NeuralVoicesSection(model, packs, installed, neural)
    GroupTitle("System voices")

    if (!ready) {
        PageGroup {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("Loading voices")
            }
        }
    } else {
        PageGroup {
            VoiceRow("Automatic", neuralAuto?.let { "Uses ${it.name} · ${NeuralLabels.GENERATED}" }
                ?: auto?.let { "Uses " + VoiceLabels.full(it, voices) } ?: "Uses the speech engine's default voice",
                prefs.voiceName.isEmpty(), "voice-auto") { pick(null) }
            mine.forEach { v ->
                VoiceRow(VoiceLabels.title(v, voices), VoiceLabels.detail(v), prefs.voiceName == v.name, "voice-${v.name}", v.installed) { pick(v) }
            }
            if (mine.isEmpty()) Text("No voice on this phone speaks ${locale.getDisplayLanguage(Locale.US)}. Download one in text-to-speech settings.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (others.isNotEmpty()) TextButton({ showOthers = !showOthers }, Modifier.testTag("voice-others")) {
                Text(if (showOthers) "Hide other accents and languages" else "Show other accents and languages (${others.size})")
            }
        }
        if (prefs.voiceName.isNotEmpty() && neural == null && speaking?.name != prefs.voiceName) {
            Note(if (voices.any { it.name == prefs.voiceName && it.network } && !online)
                "No connection: " + (speaking?.let { VoiceLabels.title(it, voices) } ?: "the engine's default voice") + " speaks until the signal is back."
                else "The chosen voice is no longer on this phone, so " + (speaking?.let { VoiceLabels.title(it, voices) } ?: "the engine's default voice") + " speaks instead.")
        }
        Note("Tap a voice to hear it. Voices that need a connection are free and stream over mobile data; with no signal, the best voice on this phone speaks instead.")
        if (showOthers && others.isNotEmpty()) {
            GroupTitle("Other accents and languages")
            PageGroup {
                others.forEach { v ->
                    VoiceRow(VoiceLabels.title(v, voices), VoiceLabels.detail(v), prefs.voiceName == v.name, "voice-${v.name}", v.installed) { pick(v) }
                }
            }
        }
    }

    GroupTitle("Speed and pitch")
    PageGroup {
        SliderRow("Speed", VoiceLabels.rate(prefs.voiceRate), prefs.voiceRate, VoiceLabels.MIN_RATE..VoiceLabels.MAX_RATE, 7, "voice-rate",
            { prefs.voiceRate = (it * 10).roundToInt() / 10f }) { preview() }
        SliderRow("Pitch", VoiceLabels.pitch(prefs.voicePitch), prefs.voicePitch, VoiceLabels.MIN_PITCH..VoiceLabels.MAX_PITCH, 7, "voice-pitch",
            { prefs.voicePitch = (it * 20).roundToInt() / 20f }, enabled = neural == null) { preview() }
        if (neural != null) Text("Pitch applies to system voices only.", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button({ preview() }, Modifier.testTag("voice-test"), enabled = ready) { Text("Test voice") }
            TextButton({ prefs.voiceRate = 1f; prefs.voicePitch = 1f }, Modifier.testTag("voice-reset"),
                enabled = prefs.voiceRate != 1f || prefs.voicePitch != 1f) { Text("Reset") }
        }
    }
    Note(if (neural != null) "Used for road alerts and turn instructions. ${neural.name} prepares each sentence ahead of time, so a new one can take a few seconds to test."
        else "Used for road alerts and turn instructions.")

    if (engines.size > 1) {
        GroupTitle("Speech engine")
        val inUse = prefs.voiceEngine.ifEmpty { speaker.defaultEngine ?: "" }
        PageGroup {
            engines.forEach { e ->
                VoiceRow(e.label, if (e.name == speaker.defaultEngine) "System default" else "Installed", e.name == inUse, "engine-${e.name}") {
                    if (e.name != inUse) {
                        // Voice names belong to an engine: the new one starts on Automatic.
                        prefs.voiceEngine = if (e.name == speaker.defaultEngine) "" else e.name
                        prefs.voiceName = ""
                        Engine.voiceEngineChanged()
                    }
                }
            }
        }
        Note("Each engine has its own voices.")
    }

    PageGroup {
        LinkRow("Download more voices") { openDownloads() }
        LinkRow("Text-to-speech settings") { openSystem() }
    }
    Note("More natural voices are free to download. Pick a voice there, then come back to choose it here.")
    PageGroup {
        Row(Modifier.fillMaxWidth().clickable(onClick = openLicenses).padding(vertical = 6.dp).testTag("voice-licenses"), verticalAlignment = Alignment.CenterVertically) {
            Text("Voice licenses", Modifier.weight(1f))
            androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A choice with a radio button: a voice or an engine, and a line about it. */
@Composable
private fun VoiceRow(title: String, detail: String, selected: Boolean, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 2.dp).testTag(tag), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, null, enabled = enabled)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SliderRow(label: String, value: String, current: Float, range: ClosedFloatingPointRange<Float>, steps: Int, tag: String,
                      onChange: (Float) -> Unit, enabled: Boolean = true, onDone: () -> Unit) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Slider(current, onChange, Modifier.testTag(tag), enabled = enabled, valueRange = range, steps = steps, onValueChangeFinished = onDone)
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp))
}
