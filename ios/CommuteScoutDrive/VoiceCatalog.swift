import Foundation

/// The CommuteScout voices: neural voice packs the driver downloads from
/// inside the app, described by `shared/voices.json` (bundled with the
/// app; see docs/voices.md). Plain Foundation, so the rules here can be
/// tested without the engine.
struct VoiceCatalog: Decodable, Equatable {
    /// Supertonic 2 is under the OpenRAIL-M license, whose use
    /// restrictions must be part of the app's terms before the pack is
    /// offered. Until then this stays false: the pack is left out of the
    /// list, out of Automatic, and out of the licenses page.
    static let supertonicCleared = false

    struct Pack: Decodable, Equatable, Identifiable {
        struct Generation: Decodable, Equatable {
            var numSteps: Int?
            var extra: [String: String]?
            var speed: Double?
        }

        struct License: Decodable, Equatable {
            let spdx: String
            let name: String
            let url: String
        }

        struct File: Decodable, Equatable {
            let name: String
            let role: String
            let url: URL
            let sha256: String
            let size: Int64
        }

        let id: String
        let title: String
        let engine: String          // "kokoro" or "supertonic"
        let engineVersion: String
        let sampleRate: Int
        let textInput: String       // "raw" or "normalized"
        let generation: Generation
        let lexicons: [String: [String]]?
        let license: License
        let attribution: String
        let voices: [Voice]
        let files: [File]
        let downloadSize: Int64

        var isKokoro: Bool { engine == "kokoro" }
        var isSupertonic: Bool { engine == "supertonic" }
        var defaultVoice: Voice? { voices.first { $0.isDefault } ?? voices.first }

        func file(role: String) -> File? { files.first { $0.role == role } }
    }

    struct Voice: Decodable, Equatable, Identifiable {
        struct Preview: Decodable, Equatable {
            let url: URL
            let size: Int64
            let sha256: String
        }

        let id: String              // "kokoro-en-v1_0.af_heart": the value saved as the driver's pick
        let sid: Int
        let upstream: String
        let name: String
        let accent: String          // BCP 47: "en-US", "en-GB"
        let gender: String          // "female", "male"
        let isDefault: Bool
        let preview: Preview?

        enum CodingKeys: String, CodingKey {
            case id, sid, upstream, name, accent, gender, preview
            case isDefault = "default"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            sid = try c.decode(Int.self, forKey: .sid)
            upstream = try c.decode(String.self, forKey: .upstream)
            name = try c.decode(String.self, forKey: .name)
            accent = try c.decode(String.self, forKey: .accent)
            gender = try c.decode(String.self, forKey: .gender)
            isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
            preview = try c.decodeIfPresent(Preview.self, forKey: .preview)
        }

        /// The pack id: everything before the last dot of the voice id.
        var packId: String { id.components(separatedBy: ".").dropLast().joined(separator: ".") }
    }

    let schema: Int
    let release: String
    let defaultPack: String
    let packs: [Pack]

    static func decode(_ data: Data) throws -> VoiceCatalog {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(VoiceCatalog.self, from: data)
    }

    /// The catalog bundled with the app. Nil only if the build left the
    /// file out, in which case the app offers system voices alone.
    static let bundled: VoiceCatalog? = {
        guard let url = Bundle.main.url(forResource: "voices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }()

    /// Whether a pack may be offered to the driver.
    static func isOffered(_ pack: Pack, supertonicCleared: Bool = supertonicCleared) -> Bool {
        pack.isSupertonic ? supertonicCleared : true
    }

    /// The packs the driver sees, in catalog order.
    func offeredPacks(supertonicCleared: Bool = VoiceCatalog.supertonicCleared) -> [Pack] {
        packs.filter { Self.isOffered($0, supertonicCleared: supertonicCleared) }
    }

    func pack(_ id: String) -> Pack? { packs.first { $0.id == id } }

    func voice(_ id: String) -> (pack: Pack, voice: Voice)? {
        for p in packs { if let v = p.voices.first(where: { $0.id == id }) { return (p, v) } }
        return nil
    }

    /// The neural voice that speaks for a saved pick, or nil for a
    /// system voice.
    ///
    /// - A pick of a CommuteScout voice whose pack is installed and
    ///   offered: that voice.
    /// - Automatic (an empty pick) with an offered pack installed: the
    ///   default voice of the catalog's default pack if that is
    ///   installed, otherwise of the first installed pack.
    /// - Anything else (a system voice, or a pack that is missing):
    ///   nil, and the system voice rules apply.
    func neuralVoice(saved: String, installed: Set<String>,
                     supertonicCleared: Bool = VoiceCatalog.supertonicCleared) -> (pack: Pack, voice: Voice)? {
        let offered = offeredPacks(supertonicCleared: supertonicCleared).filter { installed.contains($0.id) }
        if saved.isEmpty {
            let pack = offered.first { $0.id == defaultPack } ?? offered.first
            guard let pack, let v = pack.defaultVoice else { return nil }
            return (pack, v)
        }
        for p in offered { if let v = p.voices.first(where: { $0.id == saved }) { return (p, v) } }
        return nil
    }

    /// Whether a saved pick names a CommuteScout voice at all, installed
    /// or not.
    func isNeuralId(_ id: String) -> Bool { !id.isEmpty && voice(id) != nil }
}
