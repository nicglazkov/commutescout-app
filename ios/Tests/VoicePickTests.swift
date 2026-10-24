import AVFoundation
import XCTest

/// The rules for which voice speaks: what is offered, the automatic
/// pick, and what happens when the picked voice is deleted.
final class VoicePickTests: XCTestCase {
    private func v(_ id: String, _ name: String, _ lang: String, _ q: VoiceOption.Quality,
                   novelty: Bool = false, personal: Bool = false) -> VoiceOption {
        VoiceOption(id: id, name: name, language: lang, quality: q, novelty: novelty, personal: personal)
    }

    private lazy var samantha = v("com.apple.voice.compact.en-US.Samantha", "Samantha", "en-US", .standard)
    private lazy var fred = v("com.apple.speech.synthesis.voice.Fred", "Fred", "en-US", .standard)
    private lazy var zarvox = v("com.apple.speech.synthesis.voice.Zarvox", "Zarvox", "en-US", .standard, novelty: true)
    private lazy var eddy = v("com.apple.eloquence.en-US.Eddy", "Eddy", "en-US", .standard)
    private lazy var daniel = v("com.apple.voice.compact.en-GB.Daniel", "Daniel", "en-GB", .standard)
    private lazy var avaEnhanced = v("com.apple.voice.enhanced.en-US.Ava", "Ava", "en-US", .enhanced)
    private lazy var serenaPremium = v("com.apple.voice.premium.en-GB.Serena", "Serena", "en-GB", .premium)
    private lazy var zoePremium = v("com.apple.voice.premium.en-US.Zoe", "Zoe", "en-US", .premium)
    private lazy var anna = v("com.apple.voice.compact.de-DE.Anna", "Anna", "de-DE", .standard)
    private lazy var mine = v("com.apple.speech.personalvoice.1", "My Voice", "en-US", .premium, personal: true)

    func testOfferedSkipsNoveltyEloquencePersonalAndOtherLanguages() {
        let all = [samantha, fred, zarvox, eddy, anna, mine, daniel]
        XCTAssertEqual(VoicePick.offered(all, language: "en").map(\.name), ["Daniel", "Samantha"])
    }

    func testOfferedIsBestQualityFirstThenByName() {
        let all = [samantha, avaEnhanced, daniel, zoePremium, serenaPremium]
        XCTAssertEqual(VoicePick.offered(all, language: "en").map(\.name), ["Serena", "Zoe", "Ava", "Daniel", "Samantha"])
    }

    func testAutomaticPrefersHigherQuality() {
        let offered = VoicePick.offered([samantha, avaEnhanced, daniel], language: "en")
        XCTAssertEqual(VoicePick.best(offered, region: "US", systemDefault: samantha.id), avaEnhanced)
    }

    func testAutomaticPrefersTheDriversAccentWithinAQuality() {
        let offered = VoicePick.offered([serenaPremium, zoePremium, samantha], language: "en")
        XCTAssertEqual(VoicePick.best(offered, region: "US", systemDefault: nil), zoePremium)
        XCTAssertEqual(VoicePick.best(offered, region: "GB", systemDefault: nil), serenaPremium)
    }

    func testQualityOutranksAccent() {
        let offered = VoicePick.offered([serenaPremium, avaEnhanced], language: "en")
        XCTAssertEqual(VoicePick.best(offered, region: "US", systemDefault: nil), serenaPremium)
    }

    func testSystemDefaultBreaksATie() {
        let aaron = v("com.apple.voice.compact.en-US.Aaron", "Aaron", "en-US", .standard)
        let offered = VoicePick.offered([aaron, samantha], language: "en")
        XCTAssertEqual(VoicePick.best(offered, region: "US", systemDefault: samantha.id), samantha)
        XCTAssertEqual(VoicePick.best(offered, region: "US", systemDefault: nil), aaron)
    }

    func testRegionWithNoVoiceStillGetsTheBest() {
        let offered = VoicePick.offered([samantha, daniel, avaEnhanced], language: "en")
        XCTAssertEqual(VoicePick.best(offered, region: "DE", systemDefault: nil), avaEnhanced)
        XCTAssertEqual(VoicePick.best(offered, region: nil, systemDefault: nil), avaEnhanced)
    }

    func testResolveKeepsTheDriversPick() {
        let all = [samantha, daniel, avaEnhanced]
        XCTAssertEqual(VoicePick.resolve(saved: daniel.id, all: all, language: "en", region: "US", systemDefault: nil), daniel)
    }

    func testResolveFallsBackWhenThePickIsDeleted() {
        let all = [samantha, avaEnhanced]
        XCTAssertEqual(VoicePick.resolve(saved: serenaPremium.id, all: all, language: "en", region: "US", systemDefault: nil), avaEnhanced)
    }

    func testResolveIgnoresAPickThatIsNotOffered() {
        let all = [samantha, zarvox]
        XCTAssertEqual(VoicePick.resolve(saved: zarvox.id, all: all, language: "en", region: "US", systemDefault: nil), samantha)
    }

    func testResolveWithNothingPickedIsAutomatic() {
        let all = [samantha, zoePremium]
        XCTAssertEqual(VoicePick.resolve(saved: "", all: all, language: "en", region: "US", systemDefault: nil), zoePremium)
    }

    func testResolveWithNoEnglishVoiceIsNil() {
        XCTAssertNil(VoicePick.resolve(saved: "", all: [anna, fred], language: "en", region: "US", systemDefault: nil))
    }

    /// The voices this iOS really lists: whatever the runtime has, the
    /// list offered holds no novelty, Eloquence or personal voice.
    func testRealVoicesOnThisRuntime() {
        let all = AVSpeechSynthesisVoice.speechVoices().map { v -> VoiceOption in
            let q: VoiceOption.Quality = v.quality == .premium ? .premium : v.quality == .enhanced ? .enhanced : .standard
            var o = VoiceOption(id: v.identifier, name: v.name, language: v.language, quality: q)
            if #available(iOS 17.0, *) {
                o.novelty = v.voiceTraits.contains(.isNoveltyVoice)
                o.personal = v.voiceTraits.contains(.isPersonalVoice)
            }
            return o
        }
        for o in all where VoicePick.languageCode(o.language) == "en" {
            print("CS voice \(o.id) | \(o.name) | \(o.language) | \(o.quality.label) | novelty \(o.novelty)")
        }
        let offered = VoicePick.offered(all, language: "en")
        print("CS offered: \(offered.map(\.name))")
        XCTAssertFalse(offered.isEmpty)
        XCTAssertFalse(offered.contains { $0.novelty || $0.personal })
        XCTAssertFalse(offered.contains { o in VoicePick.skippedPrefixes.contains { o.id.hasPrefix($0) } })
        let ssml = AVSpeechUtterance(ssmlRepresentation: "<speak><prosody rate=\"1.08\">In 1 mile, turn right.</prosody></speak>")
        print("CS ssml speechString: \(ssml?.speechString ?? "nil")")
    }

    func testAccentNames() {
        XCTAssertEqual(VoicePick.accent("en-US"), "English (US)")
        XCTAssertEqual(VoicePick.accent("en-GB"), "English (UK)")
        XCTAssertEqual(VoicePick.accent("en-AU"), "English (Australia)")
        XCTAssertEqual(VoicePick.accent("en-IN"), "English (India)")
        XCTAssertEqual(VoicePick.accent("en-scotland"), "English (Scotland)")
        XCTAssertEqual(VoicePick.accent("en"), "English")
    }
}
