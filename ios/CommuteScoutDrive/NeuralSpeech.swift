import AVFoundation
import Foundation
import SherpaOnnx
import SherpaOnnxC
import UIKit

/// One sherpa-onnx engine for the active CommuteScout voice: one per
/// pack, and for Kokoro one per accent, because the US and UK voices
/// read different lexicons. Loading takes about a second, so the engine
/// is kept for the drive and let go when the drive ends or memory runs
/// low. Used only on the render queue: sherpa-onnx engines are not
/// thread-safe.
private final class NeuralEngine {
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var loadedKey: String?
    private var lexicon: Set<String> = []
    /// Engines that failed to load this session; not tried again until
    /// the pack is downloaded again.
    private var failedKeys: Set<String> = []

    static func key(_ pack: VoiceCatalog.Pack, _ voice: VoiceCatalog.Voice) -> String {
        pack.isKokoro ? "\(pack.id)|\(voice.accent)" : pack.id
    }

    var isLoaded: Bool { tts != nil }

    func unload() {
        tts = nil
        loadedKey = nil
        lexicon = []
    }

    func forget(_ packId: String) {
        failedKeys = failedKeys.filter { !$0.hasPrefix(packId) }
        if loadedKey?.hasPrefix(packId) == true { unload() }
    }

    /// Loads the engine for this voice unless it is the one loaded.
    private func load(_ pack: VoiceCatalog.Pack, _ voice: VoiceCatalog.Voice) -> NeuralPlan.Reason? {
        let key = Self.key(pack, voice)
        if loadedKey == key, tts != nil { return nil }
        if failedKeys.contains(key) { return .modelFailed }
        unload()
        guard VoicePackFiles.installedAndIntact(pack) else {
            DriveLog.note("neural: \(pack.id) failed its size check before loading")
            Task { @MainActor in VoicePacks.shared.recheck() }
            return .packMissing
        }
        let dir = VoicePackFiles.directory(pack.id)
        func path(_ role: String) -> String { pack.file(role: role).map { dir.appendingPathComponent($0.name).path } ?? "" }
        let t0 = Date()
        let made: SherpaOnnxOfflineTtsWrapper? = autoreleasepool {
            var model: SherpaOnnxOfflineTtsModelConfig
            if pack.isKokoro {
                let lexicons = (pack.lexicons?[voice.accent] ?? pack.lexicons?["en-US"] ?? [])
                    .map { dir.appendingPathComponent($0).path }.joined(separator: ",")
                let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
                    model: path("model"), voices: path("voices"), tokens: path("tokens"), lexicon: lexicons)
                model = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: 2)
            } else {
                let supertonic = sherpaOnnxOfflineTtsSupertonicModelConfig(
                    durationPredictor: path("duration_predictor"), textEncoder: path("text_encoder"),
                    vectorEstimator: path("vector_estimator"), vocoder: path("vocoder"),
                    ttsJson: path("tts_json"), unicodeIndexer: path("unicode_indexer"), voiceStyle: path("voice_style"))
                model = sherpaOnnxOfflineTtsModelConfig(numThreads: 2, supertonic: supertonic)
            }
            var config = sherpaOnnxOfflineTtsConfig(model: model)
            let w = SherpaOnnxOfflineTtsWrapper(config: &config)
            return w.tts == nil ? nil : w
        }
        guard let made else {
            failedKeys.insert(key)
            DriveLog.note("neural: \(pack.id) model failed to load; the system voice speaks instead")
            return .modelFailed
        }
        if pack.isKokoro {
            var words = Set<String>()
            for name in pack.lexicons?[voice.accent] ?? [] {
                guard let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
                text.enumerateLines { line, _ in
                    if let w = line.split(separator: " ", maxSplits: 1).first { words.insert(String(w)) }
                }
            }
            lexicon = words
        }
        tts = made
        loadedKey = key
        DriveLog.note(String(format: "neural: loaded %@ (%@) in %.2f s, %d lexicon words", pack.engineVersion, voice.accent,
                             Date().timeIntervalSince(t0), lexicon.count))
        return nil
    }

    func render(_ text: String, pack: VoiceCatalog.Pack, voice: VoiceCatalog.Voice,
                speed: Float) -> Result<NeuralVoices.Clip, NeuralPlan.Reason> {
        if let reason = load(pack, voice) { return .failure(reason) }
        guard let tts else { return .failure(.modelFailed) }
        var input = text
        if pack.isKokoro {
            input = KokoroText.normalize(text)
            let unknown = KokoroText.unknownWords(input, known: lexicon.contains)
            if !unknown.isEmpty {
                DriveLog.note("neural: not in the lexicon: \(unknown.prefix(5).joined(separator: ", "))")
                return .failure(.unknownWords)
            }
        }
        let config: SherpaOnnxGenerationConfigSwift = pack.isSupertonic
            ? SherpaOnnxGenerationConfigSwift(speed: speed, sid: voice.sid, numSteps: pack.generation.numSteps ?? 5,
                                              extra: (pack.generation.extra ?? ["lang": "en"]) as [String: Any])
            : SherpaOnnxGenerationConfigSwift(speed: speed, sid: voice.sid)
        let t0 = Date()
        let audio = tts.generateWithConfig(text: input, config: config, callback: nil, arg: nil)
        let samples = audio.samples
        let rate = Int(audio.sampleRate)
        guard rate > 0, NeuralPlan.usable(samples) else { return .failure(.synthesisFailed) }
        return .success(.init(data: NeuralPlan.wav(samples, sampleRate: rate),
                              seconds: Double(samples.count) / Double(rate),
                              renderSeconds: Date().timeIntervalSince(t0)))
    }
}

/// Renders sentences ahead of time and keeps the audio. A route's every
/// instruction is queued when it starts, and each road alert's sentences
/// when the alert first becomes known; the queue renders the soonest
/// first, one at a time, at low priority on two threads. Audio is cached
/// by voice, speed and words, so a sentence said twice renders once.
final class NeuralVoices {
    static let shared = NeuralVoices()

    struct Clip {
        let data: Data
        let seconds: Double
        let renderSeconds: Double
    }

    private struct Job {
        let key: String
        let text: String
        let voiceId: String
        let speed: Float
        /// Metres along the route at which it is said; lower is sooner.
        let due: Double
        let made: Date
    }

    private let lock = NSLock()
    private var jobs: [Job] = []
    private var inFlight: String?
    private var cache: [String: Clip] = [:]
    private var order: [String] = []
    private var cacheBytes = 0
    private var failed: [String: NeuralPlan.Reason] = [:]
    private var working = false
    private var along = 0.0
    private var warm = false
    private var idleGen = 0
    private let work = DispatchQueue(label: "cs.neural.render", qos: .utility)
    private let engine = NeuralEngine()

    /// Rendered audio kept in memory, about 4 minutes of Kokoro speech.
    private let cacheCap = 24 << 20

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { [weak self] _ in self?.memoryWarning() }
    }

    private func locked<T>(_ f: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return f()
    }

    /// The active voice's cache key for a sentence, or nil with no
    /// CommuteScout voice in use.
    static func key(for text: String) -> String? {
        guard let active = Voice.neural else { return nil }
        return NeuralPlan.cacheKey(voiceId: active.voice.id, speed: Voice.neuralSpeed, text: text)
    }

    func status(_ key: String) -> NeuralPlan.Status {
        locked {
            if cache[key] != nil { return .ready }
            if let r = failed[key] { return .failed(r) }
            if inFlight == key { return .rendering }
            return jobs.contains { $0.key == key } ? .rendering : .absent
        }
    }

    /// Whether the sentence is the one rendering right now, as opposed
    /// to waiting its turn in the queue.
    func isRendering(_ key: String) -> Bool { locked { inFlight == key } }

    func clip(_ key: String) -> Clip? {
        locked {
            guard let c = cache[key] else { return nil }
            if let i = order.firstIndex(of: key) { order.remove(at: i); order.append(key) }
            return c
        }
    }

    /// Where the driver is along the route, in metres; jobs for what is
    /// already behind are dropped.
    func setAlong(_ meters: Double) { locked { along = meters } }

    /// While a trip or a drive runs the engine stays loaded between
    /// sentences; otherwise it is let go a short while after the last.
    func setKeepWarm(_ on: Bool) {
        let changed = locked { () -> Bool in
            defer { warm = on }
            return warm != on
        }
        if changed, !on { scheduleIdleFree() }
    }

    /// Queue sentences to render. `due` orders them: metres along the
    /// route, or -1 for "now". Sentences already cached, failed or
    /// queued are skipped.
    func prerender(_ items: [(text: String, due: Double)]) {
        guard let active = Voice.neural else { return }
        let speed = Voice.neuralSpeed
        let added = locked { () -> Int in
            var n = 0
            for item in items {
                let key = NeuralPlan.cacheKey(voiceId: active.voice.id, speed: speed, text: item.text)
                guard cache[key] == nil, failed[key] == nil, inFlight != key else { continue }
                if let i = jobs.firstIndex(where: { $0.key == key }) {
                    if item.due < jobs[i].due {
                        let j = jobs[i]
                        jobs[i] = Job(key: key, text: j.text, voiceId: j.voiceId, speed: j.speed, due: item.due, made: Date())
                    }
                    continue
                }
                jobs.append(Job(key: key, text: item.text, voiceId: active.voice.id, speed: speed, due: item.due, made: Date()))
                n += 1
            }
            return n
        }
        if added > 0 { kick() }
    }

    /// A new route: what was queued for the old one is dropped. Audio
    /// already rendered is kept, since many sentences recur.
    func clearQueue() { locked { jobs = [] } }

    private func kick() {
        let start = locked { () -> Bool in
            guard !working else { return false }
            working = true
            return true
        }
        guard start else { return }
        work.async { [weak self] in self?.drain() }
    }

    private func next() -> Job? {
        locked {
            let now = Date()
            jobs.removeAll { now.timeIntervalSince($0.made) > 20 * 60 || ($0.due >= 0 && $0.due < along - 300) }
            guard let i = jobs.indices.min(by: { jobs[$0].due < jobs[$1].due }) else {
                working = false
                return nil
            }
            let job = jobs.remove(at: i)
            inFlight = job.key
            return job
        }
    }

    private func drain() {
        while let job = next() {
            // The driver may have picked another voice or speed since.
            guard let active = Voice.neural, active.voice.id == job.voiceId, Voice.neuralSpeed == job.speed else {
                locked { inFlight = nil }
                continue
            }
            let result = engine.render(job.text, pack: active.pack, voice: active.voice, speed: job.speed)
            locked {
                inFlight = nil
                switch result {
                case let .success(clip): store(clip, for: job.key)
                case let .failure(reason): failed[job.key] = reason
                }
            }
            switch result {
            case let .success(clip):
                DriveLog.note(String(format: "neural: rendered in %.2f s, %.1f s of audio (%@): '%@'",
                                     clip.renderSeconds, clip.seconds, active.voice.name, Self.short(job.text)))
            case let .failure(reason):
                DriveLog.note("neural: \(reason.rawValue) (\(active.voice.name)): '\(Self.short(job.text))'")
            }
            DispatchQueue.main.async { NeuralSpeaker.shared.rendered(job.key) }
        }
        scheduleIdleFree()
    }

    /// Called under the lock.
    private func store(_ clip: Clip, for key: String) {
        if cache[key] == nil { order.append(key) }
        cache[key] = clip
        cacheBytes += clip.data.count
        while cacheBytes > cacheCap, let oldest = order.first {
            order.removeFirst()
            cacheBytes -= cache.removeValue(forKey: oldest)?.data.count ?? 0
        }
    }

    private func scheduleIdleFree() {
        let gen = locked { () -> Int in idleGen += 1; return idleGen }
        work.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            let idle = self.locked { gen == self.idleGen && !self.warm && self.jobs.isEmpty && !self.working }
            if idle, self.engine.isLoaded {
                self.engine.unload()
                DriveLog.note("neural: engine freed (not driving)")
            }
        }
    }

    /// Let go of the engine now, for example in the background with no
    /// trip running. The next sentence loads it again.
    func free(_ why: String) {
        work.async { [weak self] in
            guard let self, self.engine.isLoaded else { return }
            self.engine.unload()
            DriveLog.note("neural: engine freed (\(why))")
        }
    }

    private func memoryWarning() {
        locked {
            jobs = []
            while cacheBytes > cacheCap / 4, let oldest = order.first {
                order.removeFirst()
                cacheBytes -= cache.removeValue(forKey: oldest)?.data.count ?? 0
            }
        }
        free("memory warning")
    }

    /// A pack was deleted or downloaded again: forget its audio, its
    /// failures and its engine. `then` runs on the engine's queue once
    /// the engine has let go of the pack's files: sherpa-onnx ends the
    /// process if a file it is reading disappears, so a pack's files are
    /// deleted only from there.
    func forget(packId: String, then: (() -> Void)? = nil) {
        locked {
            let prefix = packId + "."
            jobs.removeAll { $0.voiceId.hasPrefix(prefix) }
            for k in cache.keys where k.hasPrefix(prefix) { cacheBytes -= cache.removeValue(forKey: k)?.data.count ?? 0 }
            order.removeAll { $0.hasPrefix(prefix) }
            failed = failed.filter { !$0.key.hasPrefix(prefix) }
        }
        work.async { [weak self] in
            self?.engine.forget(packId)
            then?()
        }
    }

    static func short(_ text: String) -> String {
        text.count > 70 ? String(text.prefix(67)) + "..." : text
    }
}

/// Says sentences in a CommuteScout voice, one after another, in the
/// order they were asked for, with the system voice standing in for any
/// sentence whose audio is not ready in time. Turn instructions and road
/// alerts both come through here while a CommuteScout voice is in use,
/// so neither talks over the other. The audio session is handled the way
/// the system voice's is (`SpeechFocus`): music ducks for the sentence
/// and comes back after.
///
/// Main thread only, except `busy` and `reserve`.
final class NeuralSpeaker: NSObject, AVAudioPlayerDelegate {
    static let shared = NeuralSpeaker()

    private struct Item {
        let text: String
        let key: String
        let voiceName: String
        let deadline: Date
        let label: String
    }

    private var pending: [Item] = []
    private var player: AVAudioPlayer?
    private var systemSpeaking = false
    private var waitGen = 0
    private let flag = NSLock()
    private var active = false
    private var reserved = 0

    /// Something is being said or waits to be. Ferrostar asks this, off
    /// the main thread, before it lets go of the audio focus.
    var busy: Bool {
        flag.lock()
        defer { flag.unlock() }
        return active || reserved > 0
    }

    /// Counts a sentence that is on its way to `say` from another thread.
    func reserve() {
        flag.lock()
        reserved += 1
        flag.unlock()
    }

    private func updateBusy(unreserve: Bool = false) {
        flag.lock()
        if unreserve { reserved = max(0, reserved - 1) }
        active = player != nil || systemSpeaking || !pending.isEmpty
        flag.unlock()
    }

    /// Queue a sentence. It waits at most `patience` for its audio once
    /// its turn comes; a sentence that is not even being rendered when
    /// its turn comes does not wait at all.
    func say(_ text: String, label: String, patience: TimeInterval = NeuralPlan.patience,
             urgent: Bool = false, reserved wasReserved: Bool = false) {
        guard let active = Voice.neural, let key = NeuralVoices.key(for: text) else {
            if wasReserved { updateBusy(unreserve: true) }
            sayWithSystem(text, label: label, reason: .packMissing)
            return
        }
        if urgent { NeuralVoices.shared.prerender([(text, -1)]) }
        pending.append(Item(text: text, key: key, voiceName: active.voice.name,
                            deadline: Date().addingTimeInterval(patience), label: label))
        updateBusy(unreserve: wasReserved)
        pump()
    }

    /// A sentence's audio is ready (or failed): its turn may have come.
    func rendered(_ key: String) {
        if pending.first?.key == key { pump() }
    }

    /// Stop now and drop the queue: mute, or a new preview.
    func stop() {
        pending = []
        waitGen += 1
        player?.stop()
        player = nil
        if systemSpeaking {
            systemSpeaking = false
            Voice.synth.stopSpeaking(at: .immediate)
        }
        updateBusy()
        SpeechFocus.shared.release()
    }

    private func pump() {
        guard player == nil, !systemSpeaking else { return }
        guard let item = pending.first else {
            updateBusy()
            if !Voice.synth.isSpeaking { SpeechFocus.shared.release() }
            return
        }
        var status = NeuralVoices.shared.status(item.key)
        // Queued behind other sentences rather than rendering: it will
        // not be ready in time, so do not wait for it.
        if status == .rendering, !NeuralVoices.shared.isRendering(item.key), item.deadline.timeIntervalSinceNow < 1 {
            status = .absent
        }
        switch NeuralPlan.choose(status, now: Date(), deadline: item.deadline) {
        case .clip:
            pending.removeFirst()
            guard let clip = NeuralVoices.shared.clip(item.key) else {
                sayWithSystem(item.text, label: item.label, reason: .notReady)
                return
            }
            play(clip, item)
        case let .wait(seconds):
            waitGen += 1
            let gen = waitGen
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.01) { [weak self] in
                guard let self, gen == self.waitGen else { return }
                self.pump()
            }
        case let .system(reason):
            pending.removeFirst()
            sayWithSystem(item.text, label: item.label, reason: reason)
        }
    }

    private func play(_ clip: NeuralVoices.Clip, _ item: Item) {
        do {
            let p = try AVAudioPlayer(data: clip.data)
            p.delegate = self
            SpeechFocus.shared.take()
            player = p
            updateBusy()
            guard p.play() else { throw NSError(domain: "cs.neural", code: 1) }
            DriveLog.note("\(item.label) spoken with \(item.voiceName) (pre-rendered): '\(NeuralVoices.short(item.text))'")
        } catch {
            player = nil
            sayWithSystem(item.text, label: item.label, reason: .playbackFailed)
        }
    }

    /// The fallback: the system voice says it, in the queue's order.
    private func sayWithSystem(_ text: String, label: String, reason: NeuralPlan.Reason) {
        let u = Voice.utterance(text)
        DriveLog.note("\(label) spoken with \(u.voice?.identifier ?? "the system voice") (fallback: \(reason.rawValue)): '\(NeuralVoices.short(text))'")
        if Voice.synth.delegate == nil { Voice.synth.delegate = SpeechFocus.shared }
        SpeechFocus.shared.take()
        systemSpeaking = true
        updateBusy()
        Voice.synth.speak(u)
    }

    /// The system voice finished a sentence of ours.
    func systemFinished() {
        guard systemSpeaking, !Voice.synth.isSpeaking else { return }
        systemSpeaking = false
        updateBusy()
        pump()
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully _: Bool) {
        guard p === player else { return }
        player = nil
        updateBusy()
        pump()
    }

    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error _: Error?) {
        audioPlayerDidFinishPlaying(p, successfully: false)
    }
}
