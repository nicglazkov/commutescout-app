package com.commutescout.drive

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import com.stadiamaps.ferrostar.core.AudioFocusManager
import com.stadiamaps.ferrostar.core.SpokenInstructionObserver
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import uniffi.ferrostar.SpokenInstruction
import java.util.Locale
import java.util.Timer
import java.util.TimerTask

/**
 * One voice the phone's text-to-speech engine offers, reduced to what
 * the picker ranks on. [quality] and [latency] use the
 * [android.speech.tts.Voice] scale: 500 is very high, 100 very low.
 */
data class VoiceInfo(
    val name: String,
    val language: String,
    val country: String,
    val quality: Int,
    val latency: Int = 300,
    /** Streams from the engine's servers: free, but it needs data. */
    val network: Boolean = false,
    /** False for a voice the engine lists but has not downloaded yet. */
    val installed: Boolean = true,
) {
    companion object {
        fun of(v: Voice) = VoiceInfo(
            name = v.name,
            language = v.locale.language,
            country = v.locale.country,
            quality = v.quality,
            latency = v.latency,
            network = v.isNetworkConnectionRequired,
            installed = TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in (v.features ?: emptySet()),
        )
    }
}

/**
 * Which voice speaks. Pure functions, so the ranking, the default and the
 * fallback are tested without a phone.
 *
 * The best voice is the driver's region before their language, a voice
 * already on the phone before one still to download, higher quality
 * before lower, and on the phone before over the network: a voice that
 * streams goes quiet in the places a driver most needs it.
 */
object VoicePick {
    /** 2 for the driver's language and region, 1 for the language alone, 0 for neither. */
    fun match(v: VoiceInfo, locale: Locale): Int = when {
        !v.language.equals(locale.language, ignoreCase = true) -> 0
        locale.country.isNotEmpty() && v.country.equals(locale.country, ignoreCase = true) -> 2
        else -> 1
    }

    private val best = compareByDescending<VoiceInfo> { it.installed }
        .thenByDescending { it.quality }
        .thenBy { it.network }
        .thenBy { it.latency }
        // Among equals, the one the engine itself picks for the language.
        .thenByDescending { VoiceLabels.isDefault(it) }
        .thenBy { it.name }

    /**
     * Every voice, best first: the driver's region, then their language,
     * then the rest; downloaded voices before those still to download.
     */
    fun rank(voices: List<VoiceInfo>, locale: Locale): List<VoiceInfo> =
        listed(voices).sortedWith(compareByDescending<VoiceInfo> { match(it, locale) }
            .thenByDescending { it.installed }
            // Other accents and languages in groups, one region after another.
            .thenBy { if (match(it, locale) < 2) "${it.language}-${it.country}".lowercase() else "" }
            .then(best))

    /**
     * Google lists its default voice for a language twice: under its own
     * name and as "en-US-language". The second is left off the list
     * whenever the first could be there.
     */
    private fun listed(voices: List<VoiceInfo>): List<VoiceInfo> = voices.filter { v ->
        !VoiceLabels.isDefault(v) || voices.none { it !== v && !VoiceLabels.isDefault(it) && it.language == v.language && it.country == v.country }
    }

    /**
     * The voices the page lists first: the driver's region when the
     * engine has any for it, otherwise their language in every accent.
     */
    fun forLocale(voices: List<VoiceInfo>, locale: Locale): List<VoiceInfo> {
        val ranked = rank(voices, locale)
        val region = ranked.filter { match(it, locale) == 2 }
        return region.ifEmpty { ranked.filter { match(it, locale) == 1 } }
    }

    /**
     * Everything [forLocale] leaves out, best first: other accents of
     * the driver's language, downloaded or not, and other languages
     * ready to speak. An engine can list hundreds of voices still to
     * download in other languages; those are a job for system settings.
     */
    fun others(voices: List<VoiceInfo>, locale: Locale): List<VoiceInfo> {
        val mine = forLocale(voices, locale).map { it.name }.toSet()
        return rank(voices, locale).filter { it.name !in mine && (it.installed || match(it, locale) > 0) }
    }

    /**
     * The voice used when the driver has not chosen one: the best voice
     * on the phone for their language, their region first. A network
     * voice only when nothing on the phone speaks the language and there
     * is a connection; null leaves the engine's own default.
     */
    fun smartDefault(voices: List<VoiceInfo>, locale: Locale, online: Boolean): VoiceInfo? {
        val usable = voices.filter { it.installed && match(it, locale) > 0 && (!it.network || online) }
        return usable.sortedWith(compareBy<VoiceInfo> { it.network }
            .thenByDescending { match(it, locale) }
            .then(best)).firstOrNull()
    }

    /**
     * The voice that speaks now. The saved one while it is on the phone
     * and, for a network voice, while there is a signal. Without one a
     * network voice hands over to its on-device twin when the engine has
     * it (Google's "-network" and "-local" pairs), else to the default.
     * A saved voice the engine no longer has falls back to the default.
     */
    fun resolve(saved: String, voices: List<VoiceInfo>, locale: Locale, online: Boolean): VoiceInfo? {
        val chosen = voices.firstOrNull { it.name == saved && saved.isNotEmpty() }
        if (chosen != null && chosen.installed && (!chosen.network || online)) return chosen
        if (chosen != null && chosen.network) {
            val twin = voices.firstOrNull {
                it.installed && !it.network && it.language == chosen.language && it.country == chosen.country &&
                    VoiceLabels.id(it) == VoiceLabels.id(chosen)
            }
            if (twin != null) return twin
        }
        return smartDefault(voices, locale, online)
    }
}

/**
 * Names a person can read. Engines name voices for machines:
 * Google's "en-us-x-iob-local" becomes "English (US) · Voice 3 · High
 * quality · On device".
 */
object VoiceLabels {
    /** The voice's own part of its name, shared by its on-device and network versions. */
    fun id(v: VoiceInfo): String {
        var n = v.name.lowercase()
        n = n.substringAfter("-x-", n)
        val prefix = "${v.language}-${v.country}-".lowercase()
        if (n.startsWith(prefix)) n = n.removePrefix(prefix)
        return n.removeSuffix("-local").removeSuffix("-network")
    }

    /** The engine's own default for a language, as Google names it. */
    fun isDefault(v: VoiceInfo) = id(v) == "language"

    /** "English (US)", "English (UK)", "Spanish (Mexico)", "French". */
    fun language(language: String, country: String): String {
        val l = Locale(language, country)
        val name = l.getDisplayLanguage(Locale.US).ifEmpty { language }
        val region = when (country.uppercase()) {
            "" -> return name
            "US" -> "US"
            "GB" -> "UK"
            else -> l.getDisplayCountry(Locale.US).ifEmpty { country }
        }
        return "$name ($region)"
    }

    /**
     * Voices of one language and region numbered 1, 2, 3 in the order of
     * their names, so a number stays the same from one visit to the next
     * and the on-device and network versions of a voice share it.
     */
    fun number(v: VoiceInfo, all: List<VoiceInfo>): Int {
        val ids = all.filter { it.language == v.language && it.country == v.country && !isDefault(it) }.map(::id).distinct().sorted()
        return ids.indexOf(id(v)) + 1
    }

    fun quality(q: Int): String = when {
        q >= 500 -> "Very high quality"
        q >= 400 -> "High quality"
        q >= 300 -> "Normal quality"
        else -> "Low quality"
    }

    /** "English (US) · Voice 3", or "English (US) · Default voice" for the engine's own. */
    fun title(v: VoiceInfo, all: List<VoiceInfo>): String =
        language(v.language, v.country) + if (isDefault(v)) " · Default voice" else " · Voice " + number(v, all)

    /** "High quality · On device", "Very high quality · Needs a connection", "Not downloaded" */
    fun detail(v: VoiceInfo): String = when {
        !v.installed -> "Not downloaded"
        v.network -> quality(v.quality) + " · Needs a connection"
        else -> quality(v.quality) + " · On device"
    }

    fun full(v: VoiceInfo, all: List<VoiceInfo>): String = title(v, all) + " · " + detail(v)

    /** What the preview says: a turn and an alert, in the driver's units. */
    fun preview(distance: String): String = "In $distance, turn right onto Main Street. Police reported ahead."

    const val MIN_RATE = 0.7f
    const val MAX_RATE = 1.5f
    const val MIN_PITCH = 0.8f
    const val MAX_PITCH = 1.2f

    /** "Normal", "1.2x" */
    fun rate(r: Float): String = if (kotlin.math.abs(r - 1f) < 0.01f) "Normal" else "%.1fx".format(Locale.US, r)
    fun pitch(p: Float): String = when {
        kotlin.math.abs(p - 1f) < 0.01f -> "Normal"
        p < 1f -> "Lower"
        else -> "Higher"
    }
}

/**
 * A [TextToSpeech] that speaks in the driver's voice: the engine, voice,
 * speed and pitch from Settings. Road alerts and turn instructions each
 * have one, so both sound the same.
 *
 * The voice is applied before each sentence when anything it depends on
 * has changed since the last one, the signal included, so a network
 * voice gives way to one on the phone when the signal goes and comes
 * back with it.
 */
class Speaker(
    context: Context,
    private val prefs: Prefs,
    private val onStart: (String?) -> Unit = {},
    private val onDone: (String?) -> Unit = {},
    private val onError: (String?) -> Unit = {},
) {
    private val context = context.applicationContext
    private var tts: TextToSpeech? = null
    private val _ready = MutableStateFlow(false)
    /** The engine answered and can speak. The voice list is readable from then. */
    val ready = _ready.asStateFlow()
    private var applied: String? = null
    /** The voice speaking now, after any fallback; null for the engine's default. */
    var current: String? = null
        private set

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    val isSpeaking: Boolean get() = tts?.isSpeaking == true

    fun start() {
        if (tts != null) return
        val engine = prefs.voiceEngine.ifEmpty { null }
        var created: TextToSpeech? = null
        created = TextToSpeech(context, { status ->
            val t = tts
            // An engine replaced before it answered is not this one.
            if (t == null || t !== created) return@TextToSpeech
            if (status != TextToSpeech.SUCCESS) {
                Log.e(TAG, "text-to-speech did not start: code $status")
                return@TextToSpeech
            }
            t.setAudioAttributes(attributes)
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = this@Speaker.onStart(utteranceId)
                override fun onDone(utteranceId: String?) = this@Speaker.onDone(utteranceId)
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = this@Speaker.onError(utteranceId)
                override fun onError(utteranceId: String?, errorCode: Int) = this@Speaker.onError(utteranceId)
                // Cut off by a preview or a stop: finished, as far as audio focus is concerned.
                override fun onStop(utteranceId: String?, interrupted: Boolean) = this@Speaker.onDone(utteranceId)
            })
            applied = null
            applyVoice()
            _ready.value = true
        }, engine)
        tts = created
    }

    fun shutdown() {
        _ready.value = false
        tts?.shutdown()
        tts = null
        applied = null
    }

    /** A new engine was chosen: the engine is bound again and the voice picked again. */
    fun restart() {
        val running = tts != null
        shutdown()
        if (running) start()
    }

    fun stop() { tts?.stop() }

    /** Pick the voice again before the next sentence: voices may have been downloaded or removed. */
    fun invalidate() { applied = null }

    /** Every voice the engine offers, downloaded or not. */
    fun voices(): List<Voice> = runCatching { tts?.voices?.toList() }.getOrNull().orEmpty()

    /** The installed engines, and the one the system uses by default. */
    fun engines(): List<TextToSpeech.EngineInfo> = runCatching { tts?.engines }.getOrNull().orEmpty()
    val defaultEngine: String? get() = runCatching { tts?.defaultEngine }.getOrNull()

    /** Speaks [text]; false when the engine is not ready or refused it. */
    fun speak(text: String, id: String, flush: Boolean = false): Boolean {
        val t = tts ?: return false
        if (!_ready.value) return false
        applyVoice()
        return t.speak(text, if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null, id) == TextToSpeech.SUCCESS
    }

    @Synchronized
    private fun applyVoice() {
        val t = tts ?: return
        val online = Connectivity.online.value
        val key = "${prefs.voiceName}|${prefs.voiceRate}|${prefs.voicePitch}|$online"
        if (key == applied) return
        applied = key
        val all = runCatching { t.voices?.toList() }.getOrNull().orEmpty()
        val pick = VoicePick.resolve(prefs.voiceName, all.map(VoiceInfo::of), Locale.getDefault(), online)
        val voice = pick?.let { p -> all.firstOrNull { it.name == p.name } }
        if (voice == null || t.setVoice(voice) != TextToSpeech.SUCCESS) {
            t.language = Locale.getDefault()
            current = null
        } else current = voice.name
        t.setSpeechRate(prefs.voiceRate)
        t.setPitch(prefs.voicePitch)
        Log.i(TAG, "voice ${current ?: "engine default"}, saved \"${prefs.voiceName}\", rate ${prefs.voiceRate}, pitch ${prefs.voicePitch}, online $online")
    }

    companion object { private const val TAG = "Voice" }
}

/**
 * Turn instructions for Ferrostar, in the driver's voice.
 *
 * It behaves as Ferrostar's own AndroidTtsObserver does: audio focus is
 * taken before each instruction and let go half a second after the
 * last, losing focus stops the voice, and mute silences instructions
 * without dropping them. What it adds is the chosen engine, voice,
 * speed and pitch, and a restart when the engine changes.
 */
class GuidanceVoice(context: Context, prefs: Prefs) : SpokenInstructionObserver {
    private val _muteState = MutableStateFlow(false)
    override val muteState: StateFlow<Boolean> = _muteState.asStateFlow()

    private val focus = AudioFocusManager(context.applicationContext) { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stopAndClearQueue()
    }
    private var releaseTimer: Timer? = null
    val speaker = Speaker(context, prefs,
        onStart = { synchronized(this) { releaseTimer?.cancel(); releaseTimer = null } },
        onDone = { scheduleRelease() },
        onError = { focus.releaseAudioFocus() })

    fun start() = speaker.start()

    fun shutdown() {
        speaker.shutdown()
        focus.releaseAudioFocus()
    }

    fun restart() = speaker.restart()

    override fun setMuted(isMuted: Boolean) {
        _muteState.update {
            if (isMuted && speaker.isSpeaking) speaker.stop()
            isMuted
        }
    }

    override fun onSpokenInstructionTrigger(spokenInstruction: SpokenInstruction) {
        if (!speaker.ready.value) {
            Log.e(TAG, "text-to-speech is not ready")
            return
        }
        if (!focus.requestAudioFocus()) Log.w(TAG, "no audio focus; the instruction mixes with other audio")
        if (!isMuted && !speaker.speak(spokenInstruction.text, spokenInstruction.utteranceId.toString())) {
            Log.e(TAG, "could not speak the instruction")
        }
    }

    override fun stopAndClearQueue() {
        speaker.stop()
        focus.releaseAudioFocus()
    }

    private fun scheduleRelease() {
        synchronized(this) {
            releaseTimer?.cancel()
            releaseTimer = Timer().apply {
                schedule(object : TimerTask() { override fun run() { focus.releaseAudioFocus() } }, 500L)
            }
        }
    }

    companion object { private const val TAG = "GuidanceVoice" }
}
