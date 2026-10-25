package com.commutescout.drive

import android.content.ComponentCallbacks2
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.k2fsa.sherpa.onnx.GenerationConfig
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsKokoroModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsSupertonicModelConfig
import uniffi.ferrostar.Route
import java.io.File
import java.util.PriorityQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

/**
 * What became of a sentence for a neural voice: audio ready to play, or
 * a reason the system voice speaks it instead.
 */
sealed class Rendered {
    class Clip(val pcm: ShortArray, val sampleRate: Int, val renderMs: Long) : Rendered() {
        val audioMs: Long get() = pcm.size * 1000L / sampleRate
    }
    class Failed(val reason: String) : Rendered()
}

/**
 * The rules for speaking a sentence with a neural voice, kept pure so
 * the fallback is tested without a phone.
 */
object NeuralRules {
    /** How long a sentence may wait for its audio before the system voice says it. */
    fun waitMs(pack: VoicePackInfo, preview: Boolean): Long = when {
        // A sample from Settings is not time-critical: the driver asked to hear this voice.
        preview -> 20_000
        // Fast enough to speak live; docs/voices.md allows one second.
        pack.isSupertonic -> 1_000
        // Kokoro is slower than real time on phones: rendered ahead or not at all.
        else -> 300
    }

    /** Whether a sentence not rendered yet should be rendered now, for this very utterance. */
    fun renderOnDemand(pack: VoicePackInfo, preview: Boolean): Boolean = preview || pack.isSupertonic

    /** Audio that is safe to play: some samples and every one of them finite. */
    fun usable(samples: FloatArray?): Boolean = samples != null && samples.isNotEmpty() && samples.all { it.isFinite() }

    /** Float samples to 16-bit PCM, clipped. Half the memory of floats in the cache. */
    fun pcm16(samples: FloatArray): ShortArray = ShortArray(samples.size) { i ->
        (max(-1f, min(1f, samples[i])) * 32767f).toInt().toShort()
    }

    /** The text the engine reads: Kokoro's rules for numbers and abbreviations, raw for the rest. */
    fun engineText(pack: VoicePackInfo, text: String): String = if (pack.textInput == "normalized") KokoroText.normalize(text) else text

    /**
     * The turn instructions of a route in the order they are spoken,
     * each with the distance along the route where it is due.
     */
    fun routeSentences(steps: List<Pair<Double, List<Pair<String, Double>>>>): List<Pair<String, Double>> {
        val out = ArrayList<Pair<String, Double>>()
        var start = 0.0
        for ((distance, spoken) in steps) {
            for ((text, before) in spoken) out.add(text to (start + distance - before).coerceAtLeast(start))
            start += distance
        }
        return out.sortedBy { it.second }
    }
}

/**
 * The neural voices: which one speaks, the engines, the audio rendered
 * ahead of time, and playback. Everything here falls back to the system
 * voice rather than going quiet.
 */
object Neural {
    private const val TAG = "Neural"
    @Volatile private var packStore: VoicePacks? = null

    fun packs(context: Context): VoicePacks = packStore ?: synchronized(this) {
        packStore ?: VoicePacks(context.applicationContext).also { packStore = it }
    }

    val catalog: VoiceCatalog get() = packs(Engine.app).catalog

    /** The neural voice that speaks now, or null when the system voice does. */
    fun active(prefs: Prefs): NeuralVoice? {
        val v = NeuralPick.choose(prefs.voiceName, catalog, packs(Engine.app).installed.value) ?: return null
        return v.takeIf { !renderer.isBroken(it.engineKey) }
    }

    val renderer = Renderer()

    /** A pack is going away: its engine, queue and audio go first. */
    fun forgetPack(packId: String) = renderer.dropPack(packId)

    /**
     * A trip started or was rerouted: every spoken instruction of the
     * route is rendered in the background, in the order it will be
     * spoken. Nothing happens for a system voice.
     */
    fun prerenderRoute(route: Route, prefs: Prefs) {
        val voice = active(prefs) ?: return
        val steps = route.steps.map { s -> s.distance to s.spokenInstructions.map { it.text to it.triggerDistanceBeforeManeuver } }
        val sentences = NeuralRules.routeSentences(steps)
        renderer.clearQueue()
        var added = 0
        for ((text, due) in sentences) if (renderer.request(voice, prefs.voiceRate, text, due)) added++
        Log.i(TAG, "prerender: ${sentences.size} spoken instructions on the route, $added queued for ${voice.name}")
    }

    /** Road alert sentences, each with where it is due, rendered once each before the alert is spoken. */
    fun prerenderAlerts(sentences: List<Pair<String, Double>>, prefs: Prefs) {
        val voice = active(prefs) ?: return
        var added = 0
        for ((text, due) in sentences) if (renderer.request(voice, prefs.voiceRate, text, due)) added++
        if (added > 0) Log.i(TAG, "prerender: $added road alert sentence(s) queued")
    }

    /** The trip is over: what was queued for it is dropped; the engine goes when idle. */
    fun tripEnded() = renderer.clearQueue()

    fun trim(level: Int) {
        @Suppress("DEPRECATION")
        when {
            level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> { renderer.releaseEngines("memory: complete"); renderer.clearCache() }
            !Engine.tripActive && level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> { renderer.releaseEngines("memory: background"); renderer.clearCache() }
            level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ->
                renderer.releaseEngines("memory: running low")
        }
    }
}

/**
 * Renders sentences on one background thread at low priority, with
 * engines that run on two threads, and keeps the audio. The sentence
 * due soonest goes first.
 */
class Renderer {
    data class Key(val voiceId: String, val speed: Float, val text: String)

    private class Request(val key: Key, val voice: NeuralVoice, val due: Double, val seq: Long)

    private class Loaded(val engineKey: String, val tts: OfflineTts, val lexicon: LexiconIndex?)

    private val lock = Object()
    private val cache = LinkedHashMap<Key, Rendered>(64, 0.75f, true)
    private var cacheBytes = 0L
    private val queue = PriorityQueue<Request>(compareBy<Request>({ it.due }, { it.seq }))
    private val queued = HashSet<Key>()
    private var seq = 0L
    private var thread: Thread? = null
    private var loaded: Loaded? = null
    private val broken = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    @Volatile private var releaseWanted: String? = null
    private var lastWork = SystemClock.elapsedRealtime()

    /** Where the driver is along the route; work behind them is dropped. */
    @Volatile var hereAlong: () -> Double = { 0.0 }

    fun isBroken(engineKey: String) = engineKey in broken

    fun key(voice: NeuralVoice, speed: Float, text: String) = Key(voice.id, speed, text)

    fun get(key: Key): Rendered? = synchronized(lock) { cache[key] }

    /** Queues a sentence unless it is done or queued already; true when queued. */
    fun request(voice: NeuralVoice, speed: Float, text: String, due: Double): Boolean {
        if (text.isBlank()) return false
        val k = key(voice, speed, text)
        synchronized(lock) {
            if (k in cache || k in queued) return false
            queued.add(k)
            queue.add(Request(k, voice, due, seq++))
            ensureThread()
            lock.notifyAll()
        }
        return true
    }

    /** Waits until [key] is rendered, [untilMs] (elapsedRealtime) passes, or [cancelled] says stop. */
    fun await(key: Key, untilMs: Long, cancelled: () -> Boolean = { false }): Rendered? {
        synchronized(lock) {
            while (true) {
                cache[key]?.let { return it }
                val left = untilMs - SystemClock.elapsedRealtime()
                if (left <= 0 || cancelled()) return null
                lock.wait(min(left, 50L))
            }
        }
    }

    fun clearQueue() = synchronized(lock) { queue.clear(); queued.clear() }

    fun clearCache() = synchronized(lock) { cache.clear(); cacheBytes = 0 }

    fun dropPack(packId: String) {
        synchronized(lock) {
            queue.removeAll { it.voice.pack.id == packId }
            queued.retainAll(queue.map { it.key }.toSet())
            val gone = cache.keys.filter { it.voiceId.startsWith("$packId.") }
            gone.forEach { k -> (cache.remove(k) as? Rendered.Clip)?.let { cacheBytes -= it.pcm.size * 2L } }
            broken.removeAll { it.startsWith(packId) }
        }
        releaseEngines("pack $packId removed")
    }

    /** The engines go on the render thread, between sentences. */
    fun releaseEngines(why: String) {
        synchronized(lock) {
            if (loaded == null && thread == null) return
            releaseWanted = why
            lock.notifyAll()
        }
    }

    private fun ensureThread() {
        if (thread != null) return
        thread = Thread({ loop() }, "neural-voice").apply { isDaemon = true; start() }
    }

    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        while (true) {
            val req: Request? = synchronized(lock) {
                while (queue.isEmpty() && releaseWanted == null) {
                    // Idle: once the drive is over the engine goes, and comes back when needed.
                    val idle = SystemClock.elapsedRealtime() - lastWork
                    if (loaded != null && !Engine.tripActive && idle >= IDLE_RELEASE_MS) { releaseWanted = "idle"; break }
                    lock.wait(if (loaded != null) 15_000L else 0L)
                }
                if (releaseWanted != null) null else queue.poll()?.also { queued.remove(it.key) }
            }
            if (req == null) {
                val why = synchronized(lock) { releaseWanted.also { releaseWanted = null } }
                freeEngine(why ?: "")
                continue
            }
            if (Engine.tripActive && req.due < hereAlong() - 200) continue // the driver is past it
            if (get(req.key) != null) continue
            val result = render(req)
            synchronized(lock) {
                cache[req.key] = result
                if (result is Rendered.Clip) cacheBytes += result.pcm.size * 2L
                trimCache()
                lastWork = SystemClock.elapsedRealtime()
                lock.notifyAll()
            }
        }
    }

    private fun trimCache() {
        val it = cache.entries.iterator()
        while (cacheBytes > CACHE_BYTES && it.hasNext()) {
            val e = it.next()
            (e.value as? Rendered.Clip)?.let { c -> cacheBytes -= c.pcm.size * 2L }
            it.remove()
        }
    }

    private fun freeEngine(why: String) {
        val l = loaded ?: return
        loaded = null
        runCatching { l.tts.release() }
        Log.i(TAG, "engine ${l.engineKey} released ($why)")
    }

    private fun engine(voice: NeuralVoice): Loaded? {
        loaded?.let { if (it.engineKey == voice.engineKey) return it }
        // One engine at a time: a Kokoro model is 114 MB.
        freeEngine("switching to ${voice.engineKey}")
        if (voice.engineKey in broken) return null
        val t0 = SystemClock.elapsedRealtime()
        return runCatching { load(voice) }
            .onSuccess { Log.i(TAG, "engine ${voice.engineKey} loaded in ${SystemClock.elapsedRealtime() - t0} ms") }
            .onFailure { e ->
                broken.add(voice.engineKey)
                Log.e(TAG, "engine ${voice.engineKey} did not load; the system voice speaks instead", e)
            }
            .getOrNull()?.also { loaded = it }
    }

    private fun load(voice: NeuralVoice): Loaded {
        val pack = voice.pack
        val dir = Neural.packs(Engine.app).dir(pack.id)
        check(PackFiles.installed(dir, pack)) { "pack ${pack.id} is missing or incomplete" }
        fun path(role: String): String = File(dir, (pack.file(role) ?: error("no $role in ${pack.id}")).name).absolutePath
        val model = if (pack.isSupertonic) OfflineTtsModelConfig(
            supertonic = OfflineTtsSupertonicModelConfig(
                durationPredictor = path("duration_predictor"),
                textEncoder = path("text_encoder"),
                vectorEstimator = path("vector_estimator"),
                vocoder = path("vocoder"),
                ttsJson = path("tts_json"),
                unicodeIndexer = path("unicode_indexer"),
                voiceStyle = path("voice_style"),
            ),
            numThreads = THREADS,
        ) else {
            val lex = pack.lexicons[voice.voice.accent] ?: error("no lexicon for ${voice.voice.accent}")
            OfflineTtsModelConfig(
                kokoro = OfflineTtsKokoroModelConfig(
                    model = path("model"),
                    voices = path("voices"),
                    tokens = path("tokens"),
                    lexicon = lex.joinToString(",") { File(dir, it).absolutePath },
                ),
                numThreads = THREADS,
            )
        }
        // No AssetManager: the files are on disk, not in the APK.
        val tts = OfflineTts(assetManager = null, config = OfflineTtsConfig(model = model))
        val lexicon = pack.lexicons[voice.voice.accent]?.let { names -> LexiconIndex.load(names.map { File(dir, it) }) }
        return Loaded(voice.engineKey, tts, lexicon)
    }

    private fun render(req: Request): Rendered {
        val voice = req.voice
        val pack = voice.pack
        val loaded = engine(voice) ?: return Rendered.Failed("engine did not load")
        val text = NeuralRules.engineText(pack, req.key.text)
        loaded.lexicon?.let { lex ->
            val unknown = KokoroText.unknownWords(text) { it in lex }
            if (unknown.isNotEmpty()) {
                Log.w(TAG, "not in the lexicon: $unknown; the system voice will say \"${req.key.text}\"")
                return Rendered.Failed("unknown words $unknown")
            }
        }
        val t0 = SystemClock.elapsedRealtime()
        val audio = runCatching {
            loaded.tts.generateWithConfig(text, GenerationConfig(
                sid = voice.voice.sid,
                speed = req.key.speed,
                numSteps = if (pack.generation.numSteps > 0) pack.generation.numSteps else 5,
                extra = pack.generation.extra,
            ))
        }.onFailure { Log.e(TAG, "synthesis failed for \"${req.key.text}\"", it) }.getOrNull()
        val ms = SystemClock.elapsedRealtime() - t0
        if (audio == null || !NeuralRules.usable(audio.samples)) {
            Log.w(TAG, "no usable audio for \"${req.key.text}\" after $ms ms; the system voice will say it")
            return Rendered.Failed("no usable audio")
        }
        val clip = Rendered.Clip(NeuralRules.pcm16(audio.samples), audio.sampleRate, ms)
        Log.i(TAG, "rendered \"${req.key.text}\" with ${voice.name}: $ms ms for ${clip.audioMs} ms of audio (rtf %.2f)".format(ms.toDouble() / max(1L, clip.audioMs)))
        return clip
    }

    companion object {
        private const val TAG = "Neural"
        const val THREADS = 2
        /** About ten minutes of 24 kHz speech. */
        const val CACHE_BYTES = 32L * 1024 * 1024
        const val IDLE_RELEASE_MS = 60_000L
    }
}

/**
 * One line for every sentence spoken while a neural voice is chosen,
 * from both speakers (turn instructions and road alerts), so they never
 * talk over each other. A sentence plays its rendered audio through
 * AudioTrack, or the system voice says it when the audio is not ready.
 * The callers keep their audio focus handling: each sentence still
 * reports its start and its end through its speaker's callbacks.
 */
object SpeechQueue {
    private const val TAG = "Neural"

    class Item(val owner: Speaker, val text: String, val id: String, val voice: NeuralVoice?, val speed: Float, val deadline: Long, val preview: Boolean)

    private val lock = Object()
    private val items = ArrayDeque<Item>()
    @Volatile private var current: Item? = null
    @Volatile private var stopCurrent = false
    private var thread: Thread? = null
    private val waiting = java.util.concurrent.ConcurrentHashMap<String, CountDownLatch>()
    private var seq = 0L

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    fun busy(owner: Speaker): Boolean = synchronized(lock) { current?.owner === owner || items.any { it.owner === owner } }

    fun enqueue(owner: Speaker, text: String, id: String, flush: Boolean, voice: NeuralVoice?, speed: Float): Boolean {
        val preview = id == "preview"
        val wait = voice?.let { NeuralRules.waitMs(it.pack, preview) } ?: 0L
        if (voice != null && NeuralRules.renderOnDemand(voice.pack, preview)) {
            Neural.renderer.request(voice, speed, text, Double.NEGATIVE_INFINITY)
        }
        if (flush) stop(owner)
        synchronized(lock) {
            items.addLast(Item(owner, text, id, voice, speed, SystemClock.elapsedRealtime() + wait, preview))
            if (thread == null) thread = Thread({ loop() }, "speech-queue").apply { isDaemon = true; start() }
            lock.notifyAll()
        }
        return true
    }

    /** Stops [owner]'s sentence and drops the rest of its queue; each dropped one ends as stopped. */
    fun stop(owner: Speaker) {
        val dropped = synchronized(lock) {
            val d = items.filter { it.owner === owner }
            items.removeAll { it.owner === owner }
            if (current?.owner === owner) stopCurrent = true
            d
        }
        dropped.forEach { it.owner.onDone(it.id) }
    }

    /** The system voice finished a sentence the queue gave it. */
    fun systemFinished(utteranceId: String?) { utteranceId?.let { waiting.remove(it)?.countDown() } }

    private fun loop() {
        while (true) {
            val item = synchronized(lock) {
                while (items.isEmpty()) lock.wait()
                items.removeFirst().also { current = it; stopCurrent = false }
            }
            runCatching { play(item) }.onFailure { Log.e(TAG, "speech queue: $it") }
            current = null
        }
    }

    private fun play(item: Item) {
        val voice = item.voice
        var clip: Rendered? = null
        if (voice != null) {
            val key = Neural.renderer.key(voice, item.speed, item.text)
            clip = Neural.renderer.get(key) ?: Neural.renderer.await(key, item.deadline) { stopCurrent }
        }
        if (stopCurrent) { item.owner.onDone(item.id); return }
        if (clip is Rendered.Clip) {
            Log.i(TAG, "spoke with ${voice?.name} (${voice?.pack?.id}): \"${item.text}\" [${clip.audioMs} ms, rendered in ${clip.renderMs} ms]")
            item.owner.onStart(item.id)
            playPcm(clip)
            item.owner.onDone(item.id)
            return
        }
        if (voice != null) {
            val why = (clip as? Rendered.Failed)?.reason ?: "not rendered within ${NeuralRules.waitMs(voice.pack, item.preview)} ms"
            Log.i(TAG, "fallback to the system voice ($why): \"${item.text}\"")
        }
        val uid = "nq${seq++}|${item.id}"
        val latch = CountDownLatch(1)
        waiting[uid] = latch
        if (!item.owner.speakSystem(item.text, uid)) {
            waiting.remove(uid)
            item.owner.onError(uid)
            return
        }
        // The system voice reports its own start and end; wait for the end, with a limit.
        if (!latch.await(60, TimeUnit.SECONDS)) waiting.remove(uid)
    }

    private fun playPcm(clip: Rendered.Clip) {
        val rate = clip.sampleRate
        val min = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(max(min, rate / 5 * 2))
            .build()
        try {
            track.play()
            val chunk = rate / 10
            var off = 0
            while (off < clip.pcm.size && !stopCurrent) {
                val n = min(chunk, clip.pcm.size - off)
                val w = track.write(clip.pcm, off, n)
                if (w <= 0) break
                off += w
            }
            // Let the buffer drain before saying the sentence is done.
            val end = SystemClock.elapsedRealtime() + clip.audioMs + 1000
            while (!stopCurrent && track.playbackHeadPosition < off && SystemClock.elapsedRealtime() < end) Thread.sleep(20)
        } finally {
            runCatching { track.stop() }
            track.release()
        }
    }
}
