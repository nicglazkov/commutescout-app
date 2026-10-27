import XCTest

/// When a sentence gets its CommuteScout voice and when the system voice
/// says it instead, and the pieces that decide what to render ahead.
final class NeuralPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRenderedAudioSpeaks() {
        XCTAssertEqual(NeuralPlan.choose(.ready, now: now, deadline: now), .clip)
    }

    func testAudioStillRenderingIsWaitedForUntilTheDeadlineOnly() {
        guard case let .wait(left) = NeuralPlan.choose(.rendering, now: now, deadline: now.addingTimeInterval(0.3)) else {
            return XCTFail("a render in progress is waited for")
        }
        XCTAssertEqual(left, 0.3, accuracy: 0.001)
        XCTAssertEqual(NeuralPlan.choose(.rendering, now: now.addingTimeInterval(0.31), deadline: now.addingTimeInterval(0.3)),
                       .system(.notReady))
        XCTAssertLessThanOrEqual(NeuralPlan.patience, 0.3)
    }

    func testACacheMissFallsBackToTheSystemVoiceAtOnce() {
        XCTAssertEqual(NeuralPlan.choose(.absent, now: now, deadline: now.addingTimeInterval(0.3)), .system(.notReady))
    }

    func testEveryFailureFallsBackToTheSystemVoice() {
        for reason: NeuralPlan.Reason in [.packMissing, .modelFailed, .synthesisFailed, .unknownWords, .playbackFailed] {
            XCTAssertEqual(NeuralPlan.choose(.failed(reason), now: now, deadline: now.addingTimeInterval(5)), .system(reason))
        }
    }

    func testUnusableAudioIsCaught() {
        XCTAssertFalse(NeuralPlan.usable([]))
        XCTAssertFalse(NeuralPlan.usable([0.1, .nan, 0.2]))
        XCTAssertFalse(NeuralPlan.usable([0.1, .infinity]))
        XCTAssertFalse(NeuralPlan.usable([0, 0, 0]))
        XCTAssertTrue(NeuralPlan.usable([0, 0.2, -0.1]))
    }

    func testSSMLAndPlainTextShareACacheKey() {
        XCTAssertEqual(NeuralPlan.canonical("Turn right onto Main Street."), "turn right onto main street")
        XCTAssertEqual(NeuralPlan.cacheKey(voiceId: "k.v", speed: 1, text: "Turn right  onto Main Street."),
                       NeuralPlan.cacheKey(voiceId: "k.v", speed: 1, text: "turn right onto main street"))
        XCTAssertNotEqual(NeuralPlan.cacheKey(voiceId: "k.v", speed: 1, text: "x"), NeuralPlan.cacheKey(voiceId: "k.v", speed: 1.1, text: "x"))
        XCTAssertNotEqual(NeuralPlan.cacheKey(voiceId: "k.a", speed: 1, text: "x"), NeuralPlan.cacheKey(voiceId: "k.b", speed: 1, text: "x"))
    }

    func testTheSpeedSliderBecomesTheEngineSpeed() {
        XCTAssertEqual(NeuralPlan.speed(rate: 0.5, normalRate: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(NeuralPlan.speed(rate: 0.6, normalRate: 0.5), 1.2, accuracy: 0.0001)
        XCTAssertEqual(NeuralPlan.speed(rate: 0.4, normalRate: 0.5), 0.8, accuracy: 0.0001)
    }

    func testCleanRemovesTheOffsetFadesTheEndsAndSetsTheLevel() {
        // One second of a 200 Hz tone at 0.02 on Kokoro's 0.025 offset.
        let sr = 24000
        let x = (0..<sr).map { Float(0.025 + 0.02 * sin(2 * Double.pi * 200 * Double($0) / Double(sr))) }
        let y = NeuralPlan.clean(x, sampleRate: sr)
        XCTAssertEqual(y.count, x.count)
        XCTAssertEqual(y.first, 0)
        XCTAssertEqual(y.last, 0)
        let tail = y[sr / 2 ..< sr]
        XCTAssertEqual(Double(tail.reduce(0, +)) / Double(tail.count), 0, accuracy: 0.002, "no DC left")
        let rms = (tail.reduce(0) { $0 + Double($1 * $1) } / Double(tail.count)).squareRoot()
        XCTAssertEqual(rms, 0.057, accuracy: 0.005, "gain is capped at 4x")
        // Loud speech is turned down to the level, never clipped.
        let loud = NeuralPlan.clean((0..<sr).map { Float(0.9 * sin(2 * Double.pi * 200 * Double($0) / Double(sr))) }, sampleRate: sr)
        XCTAssertLessThanOrEqual(loud.map(abs).max() ?? 1, 0.95)
        let lt = loud[sr / 2 ..< sr]
        XCTAssertEqual((lt.reduce(0) { $0 + Double($1 * $1) } / Double(lt.count)).squareRoot(), 0.1, accuracy: 0.01)
    }

    func testWavHeaderDescribesMono16BitAudio() {
        let d = NeuralPlan.wav([0, 0.5, -0.5, 1], sampleRate: 24000)
        XCTAssertEqual(d.count, 44 + 8)
        XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: d[8 ..< 12], as: UTF8.self), "WAVE")
        func u32(_ at: Int) -> UInt32 { d[at ..< at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        XCTAssertEqual(u32(24), 24000)
        XCTAssertEqual(u32(40), 8)
        XCTAssertEqual(d[50], 0xFF)   // 1.0 -> 32767, little endian
        XCTAssertEqual(d[51], 0x7F)
    }

    func testAlertSentencesCoverTheFirstAndSecondWarningAndARepeat() {
        // The alerts engine's rule: a distance only when over 200 m.
        let sentence: (Double) -> String = { gap in "Police reported" + (gap > 200 ? ", in \(Int((gap / 500).rounded()) * 500) m" : "") }
        let s = NeuralPlan.alertSentences(firstMeters: 1500, repeatMeters: 500, gapNow: 5000, sentence: sentence)
        XCTAssertEqual(s, ["Police reported, in 1500 m", "Police reported, in 500 m", "Police reported"])
        // Learned of when already inside the first distance: said for where it is.
        let late = NeuralPlan.alertSentences(firstMeters: 1500, repeatMeters: 0, gapNow: 1000, sentence: sentence)
        XCTAssertEqual(late, ["Police reported, in 1000 m", "Police reported, in 1500 m", "Police reported"])
    }

    func testInstructionsAreDueWhereFerrostarSaysThem() {
        let due = NeuralPlan.instructionDue(stepDistances: [1000, 400, 50], triggers: [[800, 100], [400], [80]])
        XCTAssertEqual(due, [[200, 900], [1000], [1400]])
    }
}
