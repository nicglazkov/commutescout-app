import AVFoundation
import FerrostarCore
import Foundation

/// One voice for the whole app: the turn instructions and the road
/// alerts go through the same synthesizer, so a sentence waits for the
/// one before it instead of talking over it, and every sentence is said
/// with the same voice, speed and pitch from Settings > Voice.
///
/// iOS speaks with its low-quality compact voice unless an utterance
/// names one, so every utterance here names one: the driver's pick, or
/// with none the best voice installed (see `VoicePick`). The choice is
/// read from UserDefaults rather than `Prefs`, because Ferrostar asks
/// for a sentence off the main thread.
enum Voice {
    static let synth = AVSpeechSynthesizer()

    /// The app speaks English: its own sentences and the route's
    /// instructions both are. The voices offered are English ones, and
    /// the accent preferred is the phone's region.
    static let language = "en"

    static let idKey = "cs.voice.id"        // "" = automatic
    static let rateKey = "cs.voice.rate"
    static let pitchKey = "cs.voice.pitch"

    /// AVSpeechUtterance's own scale, 0 to 1. Outside this range speech
    /// is too slow to follow or too fast to catch at highway speed.
    static let defaultRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    static let rateRange: ClosedRange<Double> = 0.4 ... 0.6
    static let defaultPitch = 1.0
    static let pitchRange: ClosedRange<Double> = 0.8 ... 1.2

    private static let lock = NSLock()
    private static var cached: (saved: String, voice: AVSpeechSynthesisVoice?)?
    private static var logged = ""

    /// Every voice on the phone, novelty sets included; `VoicePick`
    /// decides what is offered.
    static var installed: [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices().map(option)
    }

    static func option(_ v: AVSpeechSynthesisVoice) -> VoiceOption {
        let quality: VoiceOption.Quality = switch v.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        let gender: String? = switch v.gender {
        case .female: "Female"
        case .male: "Male"
        default: nil
        }
        var o = VoiceOption(id: v.identifier, name: v.name, language: v.language, quality: quality, gender: gender)
        if #available(iOS 17.0, *) {
            o.novelty = v.voiceTraits.contains(.isNoveltyVoice)
            o.personal = v.voiceTraits.contains(.isPersonalVoice)
        }
        return o
    }

    /// The phone's region, for the accent: "US", "GB", "AU".
    static var region: String? { Locale.current.region?.identifier }

    /// The voice iOS would use for English here, a tie-breaker between
    /// voices of the same quality.
    static var systemDefault: String? {
        (AVSpeechSynthesisVoice(language: "\(language)-\(region ?? "US")")
            ?? AVSpeechSynthesisVoice(language: "\(language)-US"))?.identifier
    }

    static func resolve(saved: String, among all: [VoiceOption]) -> VoiceOption? {
        VoicePick.resolve(saved: saved, all: all, language: language, region: region, systemDefault: systemDefault)
    }

    /// The voice that speaks now: the driver's pick while it is
    /// installed, the best English voice otherwise. Worked out once per
    /// pick and kept until `refresh`.
    static var current: AVSpeechSynthesisVoice? {
        let saved = UserDefaults.standard.string(forKey: idKey) ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let c = cached, c.saved == saved { return c.voice }
        let pick = resolve(saved: saved, among: installed)
        let voice = pick.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
        cached = (saved, voice)
        // Logged when the outcome changes, not on every refresh. With a
        // CommuteScout voice in use, this is the voice that stands in.
        let neural = neural
        let line: String
        if let neural {
            line = "voice: \(neural.voice.name) (\(neural.voice.id))\(saved.isEmpty ? " (automatic)" : ""), "
                + "system voice for fallback \(pick?.id ?? "the system voice")"
        } else if !saved.isEmpty && pick?.id != saved {
            line = "voice: \(saved) is not installed, using \(pick?.id ?? "the system voice")"
        } else {
            line = "voice: \(pick?.id ?? "the system voice")\(saved.isEmpty ? " (automatic)" : "")"
        }
        if line != logged {
            logged = line
            DriveLog.note(line)
        }
        return voice
    }

    /// Voices were downloaded or deleted, or the app came back to the
    /// front: work the voice out again before the next sentence.
    static func refresh() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    /// The CommuteScout voice that speaks: the driver's pick while its
    /// pack is installed, or with Automatic the default voice of an
    /// installed pack. Nil means a system voice speaks.
    static var neural: (pack: VoiceCatalog.Pack, voice: VoiceCatalog.Voice)? {
        guard let catalog = VoiceCatalog.bundled else { return nil }
        return catalog.neuralVoice(saved: UserDefaults.standard.string(forKey: idKey) ?? "",
                                   installed: VoicePacks.installedIds)
    }

    /// The speed slider as the neural engine's speed, 1 being normal.
    /// Pitch applies to system voices only.
    static var neuralSpeed: Float {
        NeuralPlan.speed(rate: stored(rateKey, defaultRate, rateRange), normalRate: defaultRate)
    }

    static var rate: Float { Float(stored(rateKey, defaultRate, rateRange)) }
    static var pitch: Float { Float(stored(pitchKey, defaultPitch, pitchRange)) }

    private static func stored(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let v = UserDefaults.standard.object(forKey: key) as? Double else { return fallback }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    /// A sentence ready to say, in the chosen voice, speed and pitch.
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = current
        u.rate = rate
        u.pitchMultiplier = pitch
        return u
    }

    /// The words of an utterance, without SSML markup. Ferrostar builds
    /// SSML utterances when the route carries SSML; its rate and voice
    /// tags would override the driver's choice, so the text is said
    /// plainly instead.
    static func plainText(_ u: AVSpeechUtterance) -> String {
        let s = u.speechString
        guard s.contains("<") else { return s }
        return s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The synthesizer Ferrostar's turn instructions go through: the shared
/// one, with each sentence said again in the app's voice, speed and
/// pitch. Ferrostar's observer keeps everything else it did before:
/// mute, the queue on the shared synthesizer, and its audio focus.
///
/// With a CommuteScout voice in use, the sentence goes to the neural
/// speaker instead, which plays the audio rendered when the route
/// started, in turn with the road alerts, and falls back to the system
/// voice for a sentence that is not ready.
final class VoicedSynthesizer: SpeechSynthesizer {
    private let synth: AVSpeechSynthesizer

    init(_ synth: AVSpeechSynthesizer) { self.synth = synth }

    var isSpeaking: Bool { synth.isSpeaking || NeuralSpeaker.shared.busy }

    func speak(_ utterance: AVSpeechUtterance) {
        let text = Voice.plainText(utterance)
        if Voice.neural != nil {
            // Ferrostar calls from a background task; the speaker lives
            // on the main thread. Counted as speaking from this moment,
            // so the observer does not let go of the audio focus early.
            NeuralSpeaker.shared.reserve()
            DispatchQueue.main.async {
                NeuralSpeaker.shared.say(text, label: "turn instruction", reserved: true)
            }
            return
        }
        let u = Voice.utterance(text)
        DriveLog.note("turn instruction spoken with \(u.voice?.identifier ?? "the system voice")")
        synth.speak(u)
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        if NeuralSpeaker.shared.busy {
            if Thread.isMainThread { NeuralSpeaker.shared.stop() } else { DispatchQueue.main.async { NeuralSpeaker.shared.stop() } }
        }
        return synth.stopSpeaking(at: boundary)
    }
}
