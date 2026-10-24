import Foundation

/// An installed voice as the Voice page and the picker see it. Kept
/// apart from AVFoundation so the rules below can be tested without a
/// synthesizer.
struct VoiceOption: Identifiable, Equatable {
    enum Quality: Int, Comparable, CaseIterable {
        case standard = 1, enhanced = 2, premium = 3

        var label: String { switch self { case .standard: "Default"; case .enhanced: "Enhanced"; case .premium: "Premium" } }

        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String          // AVSpeechSynthesisVoice.identifier
    let name: String
    let language: String    // BCP 47, as the voice reports it: "en-US", "en-GB"
    let quality: Quality
    var gender: String?     // "Female", "Male", or nil when the voice does not say
    /// Novelty voices (Bells, Zarvox) and personal voices, which need
    /// the driver's permission. Neither is offered.
    var novelty = false
    var personal = false

    /// "English (UK)": the accent, for the row under the name.
    var accent: String { VoicePick.accent(language) }
}

/// Which voices to offer and which one speaks when the driver has not
/// picked one.
enum VoicePick {
    /// Identifier prefixes of voices that are not for guidance: the
    /// Eloquence set (Eddy, Flo, Grandma, Reed) and the old Mac novelty
    /// and MacinTalk voices (Albert, Bad News, Bells, Boing, Bubbles,
    /// Cellos, Fred, Good News, Jester, Organ, Superstar, Trinoids,
    /// Whisper, Wobble, Zarvox). iOS lists both sets beside the real
    /// voices, and only some of them carry the novelty trait.
    static let skippedPrefixes = ["com.apple.eloquence.", "com.apple.speech.synthesis.voice."]

    /// The voices worth offering for a language ("en"), best first:
    /// Premium, then Enhanced, then Default, by name within each.
    static func offered(_ all: [VoiceOption], language: String) -> [VoiceOption] {
        all.filter { v in
            !v.novelty && !v.personal
                && !skippedPrefixes.contains { v.id.hasPrefix($0) }
                && languageCode(v.language) == language.lowercased()
        }
        .sorted { a, b in
            a.quality != b.quality ? a.quality > b.quality
                : a.name != b.name ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                : a.id < b.id
        }
    }

    /// The best of `offered` for a driver in `region` ("US"): the highest
    /// quality installed, and within that quality a voice with the
    /// driver's own accent, then the voice iOS itself would use, then
    /// the first by name.
    static func best(_ offered: [VoiceOption], region: String?, systemDefault: String?) -> VoiceOption? {
        let home = region?.uppercased()
        func rank(_ v: VoiceOption) -> (Int, Int, Int) {
            (v.quality.rawValue, regionCode(v.language) == home ? 1 : 0, v.id == systemDefault ? 1 : 0)
        }
        // `offered` is sorted by name within each quality, so the first
        // of the highest rank is the alphabetical one.
        var pick: VoiceOption?
        for v in offered where pick == nil || rank(v) > rank(pick!) { pick = v }
        return pick
    }

    /// The voice that speaks. The driver's pick while it is still
    /// installed and still offered; otherwise, or with no pick (an
    /// empty `saved`), the best installed voice.
    static func resolve(saved: String, all: [VoiceOption], language: String,
                        region: String?, systemDefault: String?) -> VoiceOption? {
        let offered = offered(all, language: language)
        if !saved.isEmpty, let v = offered.first(where: { $0.id == saved }) { return v }
        return best(offered, region: region, systemDefault: systemDefault)
    }

    /// "en" from "en-US", "en_GB" or "en".
    static func languageCode(_ language: String) -> String {
        String(language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    /// "US" from "en-US"; "SCOTLAND" from "en-scotland"; nil from "en".
    static func regionCode(_ language: String) -> String? {
        let parts = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        return parts.count > 1 ? String(parts[1]).uppercased() : nil
    }

    /// "English (US)", "English (UK)", "English (Australia)",
    /// "English (Scotland)". The app's own text is English, so the names
    /// are too, whatever the phone's language.
    static func accent(_ language: String) -> String {
        let en = Locale(identifier: "en_US")
        let lang = en.localizedString(forLanguageCode: languageCode(language)) ?? language
        guard let region = regionCode(language) else { return lang }
        let place: String
        switch region {
        case "US": place = "US"
        case "GB": place = "UK"
        default: place = en.localizedString(forRegionCode: region) ?? region.capitalized
        }
        return "\(lang) (\(place))"
    }
}
