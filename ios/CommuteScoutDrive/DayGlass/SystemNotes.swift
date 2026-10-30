import Foundation

/// A message from the app itself, shown in the capsule while driving:
/// what it says, how urgent it is, and the buttons under it.
struct SystemNote: Equatable {
    enum ID: String, CaseIterable { case arrive, offline, reroute, gps, speeding, confirm, watch, faster }

    var id: ID
    var icon: String
    var title: String
    var detail: String
    var primary: String?
    var secondary: String?

    var tone: DGTone { SystemNote.tone(id) }

    /// One action and a short line sit on the same row as the words.
    var inline: Bool { primary != nil && secondary == nil && detail.count < 40 }

    /// Each message's tone, as in the mockups.
    static func tone(_ id: ID) -> DGTone {
        switch id {
        case .faster, .reroute: return .low
        case .confirm: return .mid
        case .speeding: return .high
        case .gps, .offline: return .clear
        case .watch, .arrive: return .good
        }
    }
}

/// Picks the one message to show while driving. The order is the
/// mockups': arrival, then no connection, rerouting, a lost signal,
/// speeding, and last a question about a report just passed.
enum SystemNotes {
    struct Input {
        var navigating = false
        var arrivedAt: String?          // the destination's name once arrived
        var online = true
        var offlineSince: String?       // "8:14 AM"
        var offlineWords: (title: String, detail: String)?   // the app's own wording, when it has it
        var rerouting = false
        var fixAge: TimeInterval = 0    // seconds since the last location
        var speed: Int?                 // in the display unit
        var limit: Int?
        var confirmKind: DGKind?
        var confirmAgo: String?         // "Reported 4 min ago, 0.1 mi behind you"
    }

    /// Seconds without a location before the signal counts as lost.
    static let lostAfter: TimeInterval = 12
    /// How far over the posted limit counts as speeding, in the display unit.
    static let overBy = 5

    static func pick(_ i: Input) -> SystemNote? {
        guard i.navigating else { return nil }
        if let place = i.arrivedAt {
            return SystemNote(id: .arrive, icon: "arrive", title: "You have arrived", detail: place, primary: "Done")
        }
        if !i.online {
            if let w = i.offlineWords { return SystemNote(id: .offline, icon: "offline", title: w.title, detail: w.detail) }
            return offline(since: i.offlineSince)
        }
        if i.rerouting {
            return SystemNote(id: .reroute, icon: "reroute", title: "Rerouting", detail: "Finding a new route from here.")
        }
        if i.fixAge > lostAfter {
            return SystemNote(id: .gps, icon: "gps", title: "GPS signal lost", detail: "Following the route from your last position")
        }
        if let s = i.speed, let l = i.limit, l > 0, s > l + overBy {
            return SystemNote(id: .speeding, icon: "speed", title: "Over the limit", detail: "\(s) in a \(l)")
        }
        if let k = i.confirmKind {
            return SystemNote(id: .confirm, icon: "confirm", title: confirmTitle(k),
                              detail: i.confirmAgo ?? "Reported just behind you", primary: "Still there", secondary: "Gone")
        }
        return nil
    }

    /// The word for one event of a kind, in a sentence.
    static func noun(_ k: DGKind) -> String {
        switch k {
        case .crash: return "crash"
        case .closure: return "closure"
        case .hazard: return "hazard"
        case .police: return "police report"
        case .jam: return "slowdown"
        case .chain: return "chain control"
        case .fire: return "fire"
        case .ice: return "icy stretch"
        case .sign: return "sign"
        case .camera: return "camera"
        case .toll: return "toll"
        }
    }

    /// "Is the crash still there?", in words that fit the kind.
    static func confirmTitle(_ k: DGKind) -> String {
        switch k {
        case .police: return "Are the police still there?"
        case .hazard: return "Is the object still there?"
        case .jam: return "Is it still slow?"
        case .ice: return "Is the road still icy?"
        case .closure: return "Is it still closed?"
        case .chain: return "Are chains still required?"
        case .fire: return "Is the fire still there?"
        case .crash: return "Is the crash still there?"
        case .sign: return "Is the sign still there?"
        case .camera: return "Is the camera still there?"
        case .toll: return "Is the toll still there?"
        }
    }

    static func offline(since: String?) -> SystemNote {
        SystemNote(id: .offline, icon: "offline", title: "No connection",
                   detail: since.map { "Road data from \($0). Live updates resume when you are back online." }
                       ?? "Live updates resume when you are back online.")
    }

    /// Every message with the mockups' sample words, for the catalog.
    static let samples: [SystemNote] = [
        SystemNote(id: .faster, icon: "reroute", title: "Faster route found", detail: "Saves 6 min via I-280 S",
                   primary: "Take it", secondary: "Keep route"),
        SystemNote(id: .confirm, icon: "confirm", title: "Is the object still there?",
                   detail: "Reported 4 min ago, 0.1 mi behind you", primary: "Still there", secondary: "Gone"),
        SystemNote(id: .speeding, icon: "speed", title: "Over the limit", detail: "72 in a 65"),
        SystemNote(id: .gps, icon: "gps", title: "GPS signal lost", detail: "Following the route from your last position"),
        offline(since: "8:14 AM"),
        SystemNote(id: .watch, icon: "watch", title: "Home area: crash on US-101",
                   detail: "Tapped from a notification. Cleared 25 min ago.", primary: "Show on map"),
        SystemNote(id: .arrive, icon: "arrive", title: "You have arrived", detail: "San Jose Airport, Terminal B", primary: "Done"),
    ]
}
