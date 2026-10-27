import Foundation

/// The rules for speaking with a CommuteScout voice, kept apart from
/// the engine and the audio so they can be tested alone: which audio a
/// sentence gets, how long it may wait, how audio is cached, and which
/// alert sentences are worth rendering ahead.
enum NeuralPlan {
    /// The longest a sentence waits for its audio. Past this the system
    /// voice says it: a late turn instruction is worse than a plain one.
    static let patience: TimeInterval = 0.3

    /// Why a sentence was said by the system voice instead.
    enum Reason: String, Error, Equatable {
        case notReady = "not rendered yet"
        case packMissing = "voice pack missing or damaged"
        case modelFailed = "model failed to load"
        case synthesisFailed = "synthesis failed"
        case unknownWords = "word not in the lexicon"
        case playbackFailed = "playback failed"
    }

    /// Where a sentence's audio stands when it is its turn to speak.
    enum Status: Equatable {
        case ready
        case rendering
        case failed(Reason)
        case absent
    }

    enum Choice: Equatable {
        case clip
        case wait(TimeInterval)
        case system(Reason)
    }

    /// Rendered audio speaks. Audio still rendering is waited for until
    /// the sentence's deadline, and no longer. Anything else, or a
    /// deadline that has passed, is said by the system voice.
    static func choose(_ status: Status, now: Date, deadline: Date) -> Choice {
        switch status {
        case .ready: return .clip
        case let .failed(reason): return .system(reason)
        case .rendering:
            let left = deadline.timeIntervalSince(now)
            return left > 0 ? .wait(left) : .system(.notReady)
        case .absent: return .system(.notReady)
        }
    }

    /// The same words said the same way, whatever the case, spacing or
    /// punctuation: an SSML instruction and its plain text share audio.
    static func canonical(_ text: String) -> String {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    /// Audio is cached per voice, speed and words.
    static func cacheKey(voiceId: String, speed: Float, text: String) -> String {
        "\(voiceId)|\(String(format: "%.2f", speed))|\(canonical(text))"
    }

    /// The speed slider (AVSpeechUtterance's scale, normal at
    /// `normalRate`) as the engine's speed, where 1 is normal.
    static func speed(rate: Double, normalRate: Double) -> Float {
        guard normalRate > 0 else { return 1 }
        return Float(min(max(rate / normalRate, 0.5), 2.0))
    }

    /// Audio worth playing: some samples, all of them finite. The stock
    /// Kokoro int8 model returns NaN on ARM (docs/voices.md).
    static func usable(_ samples: [Float]) -> Bool {
        !samples.isEmpty && samples.allSatisfy(\.isFinite) && samples.contains { $0 != 0 }
    }

    /// What every clip gets before it plays (scripts/voices/clean.py is
    /// the reference): a 30 Hz high-pass, because Kokoro's output sits on
    /// a DC offset of about 0.025 that clicks where a clip starts and
    /// ends; a gain that brings speech to -20 dBFS RMS, at most 4x and
    /// never past a 0.95 peak, so every voice is about as loud as the
    /// next; and 5 ms fades at both ends.
    static func clean(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        let r = exp(-2 * Double.pi * 30 / Double(sampleRate))
        var y = [Double](repeating: 0, count: samples.count)
        var px = Double(samples[0].isFinite ? samples[0] : 0), py = 0.0
        for (i, s) in samples.enumerated() {
            let x = Double(s.isFinite ? s : 0)
            py = x - px + r * py
            px = x
            y[i] = py
        }
        // Speech level: the RMS of the 20 ms frames within 30 dB of the loudest.
        let n = max(1, sampleRate / 50)
        var frames: [Double] = []
        var i = 0
        while i < y.count {
            let f = y[i..<min(i + n, y.count)]
            frames.append((f.reduce(0) { $0 + $1 * $1 } / Double(f.count)).squareRoot())
            i += n
        }
        let top = frames.max() ?? 0
        let loud = frames.filter { $0 >= top * pow(10, -30.0 / 20) }
        let level = loud.isEmpty ? 0 : (loud.reduce(0) { $0 + $1 * $1 } / Double(loud.count)).squareRoot()
        let peak = y.reduce(0) { max($0, abs($1)) }
        let gain = level <= 0 || peak <= 0 ? 1 : min(0.1 / level, 4, 0.95 / peak)
        let k = min(sampleRate / 200, y.count / 2)
        return y.indices.map { j in
            var v = y[j] * gain
            if j < k { v *= Double(j) / Double(k) }
            if j >= y.count - k { v *= Double(y.count - 1 - j) / Double(k) }
            return Float(v)
        }
    }

    /// 16-bit mono PCM in a WAV container, for AVAudioPlayer.
    static func wav(_ samples: [Float], sampleRate: Int) -> Data {
        var d = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            let v = Int16(max(-1, min(1, s.isFinite ? s : 0)) * 32767)
            u16(UInt16(bitPattern: v))
        }
        return d
    }

    /// The alert sentences one marker can produce, to render before any
    /// of them is due: the first warning at its distance, the second
    /// warning if there is one, the sentence with no distance (a tap to
    /// repeat), and, when the marker is already inside its first
    /// distance, the sentence for where it is now. `sentence` builds the
    /// text exactly the way the alerts engine does.
    static func alertSentences(firstMeters: Double, repeatMeters: Double, gapNow: Double,
                               sentence: (Double) -> String) -> [String] {
        var gaps = [min(firstMeters, gapNow), firstMeters * 0.95]
        if repeatMeters > 0 { gaps.append(repeatMeters) }
        var out: [String] = []
        for g in gaps where g > -100 {
            let s = sentence(max(0, g))
            if !out.contains(s) { out.append(s) }
        }
        let bare = sentence(0)
        if !out.contains(bare) { out.append(bare) }
        return out
    }

    /// When each spoken instruction of a route is due, in metres along
    /// the route: `stepDistances[i]` is step i's length and
    /// `triggers[i]` how far before the end of step i each of its
    /// instructions is said.
    static func instructionDue(stepDistances: [Double], triggers: [[Double]]) -> [[Double]] {
        var along = 0.0
        var out: [[Double]] = []
        for (i, d) in stepDistances.enumerated() {
            let t = i < triggers.count ? triggers[i] : []
            out.append(t.map { along + max(0, d - $0) })
            along += d
        }
        return out
    }
}
