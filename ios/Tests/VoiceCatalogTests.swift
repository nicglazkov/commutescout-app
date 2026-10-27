import XCTest

/// The voice catalog as the app reads it, the Supertonic gate, and which
/// CommuteScout voice Automatic picks.
final class VoiceCatalogTests: XCTestCase {
    private func bundledCatalog() throws -> VoiceCatalog {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "voices", withExtension: "json"))
        return try VoiceCatalog.decode(Data(contentsOf: url))
    }

    func testParsesTheSharedCatalog() throws {
        let c = try bundledCatalog()
        XCTAssertEqual(c.schema, 1)
        XCTAssertEqual(c.release, "voices-v1")
        XCTAssertEqual(c.defaultPack, "supertonic2-en")
        XCTAssertEqual(c.packs.map(\.id), ["supertonic2-en", "kokoro-en-v1_0"])

        let kokoro = try XCTUnwrap(c.pack("kokoro-en-v1_0"))
        XCTAssertTrue(kokoro.isKokoro)
        XCTAssertEqual(kokoro.textInput, "normalized")
        XCTAssertEqual(kokoro.sampleRate, 24000)
        XCTAssertEqual(kokoro.voices.count, 8)
        XCTAssertEqual(kokoro.defaultVoice?.name, "Harper")
        XCTAssertEqual(kokoro.defaultVoice?.sid, 3)
        XCTAssertEqual(kokoro.lexicons?["en-GB"], ["lexicon-gb-en.txt", "lexicon-gb-en-extra.txt"])
        XCTAssertEqual(kokoro.license.spdx, "Apache-2.0")
        XCTAssertNotNil(kokoro.file(role: "model"))
        XCTAssertNotNil(kokoro.file(role: "voices"))
        XCTAssertNotNil(kokoro.file(role: "tokens"))

        let supertonic = try XCTUnwrap(c.pack("supertonic2-en"))
        XCTAssertTrue(supertonic.isSupertonic)
        XCTAssertEqual(supertonic.generation.numSteps, 5)
        XCTAssertEqual(supertonic.generation.extra, ["lang": "en"])
        XCTAssertEqual(supertonic.defaultVoice?.name, "Nora")
        for role in ["duration_predictor", "text_encoder", "vector_estimator", "vocoder", "tts_json", "unicode_indexer", "voice_style"] {
            XCTAssertNotNil(supertonic.file(role: role), role)
        }
    }

    func testEveryFileIsAPerFileAssetWithAHashAndTheSizesAddUp() throws {
        for pack in try bundledCatalog().packs {
            XCTAssertEqual(pack.files.reduce(0) { $0 + $1.size }, pack.downloadSize, pack.id)
            XCTAssertTrue(pack.files.contains { $0.name == "LICENSE" } && pack.files.contains { $0.name == "NOTICE" })
            for f in pack.files {
                // "<pack>.<file>", or "<pack>.v2.<file>" for a later build of a file that keeps its name.
                let asset = f.url.lastPathComponent
                let tag = asset.hasPrefix(pack.id + ".v") && asset.hasSuffix("." + f.name)
                    ? asset.dropFirst(pack.id.count + 2).dropLast(f.name.count + 1) : ""
                XCTAssertTrue(asset == pack.id + "." + f.name || (!tag.isEmpty && tag.allSatisfy(\.isNumber)), asset)
                XCTAssertEqual(f.sha256.count, 64)
            }
            for v in pack.voices {
                XCTAssertEqual(v.packId, pack.id)
                XCTAssertNotNil(v.preview, v.id)
                XCTAssertEqual(v.preview?.url.pathExtension, "m4a")
            }
        }
    }

    func testSupertonicStaysHiddenUntilItsLicenseIsCleared() throws {
        let c = try bundledCatalog()
        XCTAssertFalse(VoiceCatalog.supertonicCleared, "Supertonic needs the OpenRAIL-M use restrictions in the terms first")
        XCTAssertEqual(c.offeredPacks().map(\.id), ["kokoro-en-v1_0"])
        XCTAssertEqual(c.offeredPacks(supertonicCleared: true).map(\.id), ["supertonic2-en", "kokoro-en-v1_0"])
    }

    func testAutomaticUsesNoNeuralVoiceUntilAPackIsInstalled() throws {
        let c = try bundledCatalog()
        XCTAssertNil(c.neuralVoice(saved: "", installed: []))
    }

    func testAutomaticUsesHarperOnceKokoroIsInstalled() throws {
        let c = try bundledCatalog()
        XCTAssertEqual(c.neuralVoice(saved: "", installed: ["kokoro-en-v1_0"])?.voice.name, "Harper")
    }

    func testAutomaticIgnoresAnInstalledSupertonicWhileItIsGated() throws {
        let c = try bundledCatalog()
        XCTAssertNil(c.neuralVoice(saved: "", installed: ["supertonic2-en"], supertonicCleared: false))
        XCTAssertEqual(c.neuralVoice(saved: "", installed: ["supertonic2-en", "kokoro-en-v1_0"], supertonicCleared: false)?.voice.name, "Harper")
        // Cleared, the catalog's default pack wins.
        XCTAssertEqual(c.neuralVoice(saved: "", installed: ["supertonic2-en", "kokoro-en-v1_0"], supertonicCleared: true)?.voice.name, "Nora")
    }

    func testAPickedVoiceSpeaksOnlyWhileItsPackIsInstalled() throws {
        let c = try bundledCatalog()
        XCTAssertEqual(c.neuralVoice(saved: "kokoro-en-v1_0.bm_george", installed: ["kokoro-en-v1_0"])?.voice.name, "George")
        XCTAssertNil(c.neuralVoice(saved: "kokoro-en-v1_0.bm_george", installed: []))
        // A system voice pick is not a neural voice, whatever is installed.
        XCTAssertNil(c.neuralVoice(saved: "com.apple.voice.premium.en-US.Zoe", installed: ["kokoro-en-v1_0"]))
        XCTAssertTrue(c.isNeuralId("kokoro-en-v1_0.af_heart"))
        XCTAssertFalse(c.isNeuralId("com.apple.voice.premium.en-US.Zoe"))
        XCTAssertFalse(c.isNeuralId(""))
    }
}
