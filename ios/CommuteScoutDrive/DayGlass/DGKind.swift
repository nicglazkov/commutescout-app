import Foundation

/// How urgent something is, which sets its color everywhere.
enum DGTone: String, CaseIterable {
    case high, mid, low, good, clear
}

/// What a road event is, for its icon, color and drawing. Every marker
/// kind the server sends maps to one of these.
enum DGKind: String, CaseIterable {
    case crash, closure, hazard, police, jam, chain, fire, ice, sign, camera, toll

    var tone: DGTone {
        switch self {
        case .crash, .closure, .chain, .fire: return .high
        case .hazard, .jam, .ice: return .mid
        case .police, .sign, .camera, .toll: return .low
        }
    }

    /// The catalog section a kind belongs to.
    var section: String {
        switch tone {
        case .high: return "Act on it"
        case .mid: return "Heads up"
        default: return "Good to know"
        }
    }

    /// The short words on the alert: "Crash ahead".
    var short: String {
        switch self {
        case .crash: return "Crash ahead"
        case .closure: return "Lanes closed"
        case .hazard: return "Hazard ahead"
        case .police: return "Police"
        case .jam: return "Slowdown"
        case .chain: return "Chains required"
        case .fire: return "Wildfire nearby"
        case .ice: return "Ice possible"
        case .sign: return "Sign ahead"
        case .camera: return "Camera ahead"
        case .toll: return "Toll lanes"
        }
    }

    init(marker m: RoadMarker) {
        self.init(kind: m.kind, words: [m.type, m.label, m.flareKind, m.cls].compactMap { $0?.lowercased() }.joined(separator: " "))
    }

    /// From a push: the map's kind ("incident") and the alert's title.
    init(markerKind: String, title: String?) {
        self.init(kind: markerKind, words: (title ?? "").lowercased())
    }

    private init(kind: String, words: String) {
        func has(_ any: String...) -> Bool { any.contains { words.contains($0) } }
        switch kind {
        case "lane_closure": self = .closure
        case "chain_control": self = .chain
        case "wildfire": self = .fire
        case "camera": self = .camera
        case "sign": self = .sign
        case "rwis": self = .ice
        case "toll": self = .toll
        default:
            if has("collision", "crash", "accident", "1183", "1181", "1182", "1180") { self = .crash }
            else if has("police", "speed trap", "enforcement") { self = .police }
            else if has("closed", "closure", "road_closed") { self = .closure }
            else if has("fire") { self = .fire }
            else if has("ice", "snow", "frost") { self = .ice }
            else if has("hazard", "debris", "object", "animal", "1125") { self = .hazard }
            else if has("jam", "slow", "congestion", "traffic") { self = .jam }
            else if has("camera") { self = .camera }
            else { self = .hazard }
        }
    }
}
