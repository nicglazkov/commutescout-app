import Foundation

// The settings pages' logic, kept free of views so the unit tests can
// run it: feed health from /api/sources, today's API use from
// /api/keys, the alert chips, and the short summaries on the home page.
// Android reads the same answers the same way (DataSources.kt,
// ApiUsage.kt, AlertChips.kt).

// MARK: - Data sources

/// A feed's health, as /api/sources reports it.
enum FeedStatus: String, CaseIterable {
    case fresh, stale, down, live, off

    var word: String {
        switch self { case .fresh: "Fresh"; case .stale: "Stale"; case .down: "Down"; case .live: "Live"; case .off: "Off" }
    }

    /// How bad it is: a state reads as its worst feed.
    var rank: Int {
        switch self { case .down: 3; case .stale: 2; case .fresh, .live: 1; case .off: 0 }
    }
}

/// One entry of /api/sources, with the health fields worked out when an
/// older server leaves them out.
struct SourceFeed: Equatable {
    var name: String
    var agency: String
    var state: String
    var status: FeedStatus
    var ageS: Int?
    var national: Bool
    var stateCode: String?
    var asOf: Date?
}

/// A row on the Data sources page: a national feed, or every feed of one state.
struct FeedRow: Equatable, Identifiable {
    var code: String
    var title: String
    var by: String
    var status: FeedStatus
    var ageS: Int?
    var asOf: Date?
    var id: String { code + "|" + title + "|" + by }
}

struct SourcesReport: Equatable {
    var checkedAt: Date?
    var fresh: Int
    var stale: Int
    var down: Int
    var states: Int
    var national: [FeedRow]
    var stateRows: [FeedRow]

    /// The home row's value: "1 down", "2 stale" or "All fresh".
    var headline: String {
        if down > 0 { return "\(down) down" }
        if stale > 0 { return "\(stale) stale" }
        return "All fresh"
    }

    var worst: FeedStatus { down > 0 ? .down : stale > 0 ? .stale : .fresh }

    /// "All 50 states and DC" when every state answers, else the count.
    var coverage: String {
        states >= 51 ? "All 50 states and DC" : states == 1 ? "1 state" : "\(states) states"
    }
}

enum SourcesHealth {
    /// The server's own limit for a feed with no stale_after_s, in seconds.
    static let defaultStaleS = 90 * 60

    static let codes: [String: String] = [
        "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA", "Colorado": "CO",
        "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA",
        "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS",
        "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA",
        "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT",
        "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
        "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
        "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
        "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
        "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
    ]

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// A JSON number as an Int; a JSON true or false is not one.
    static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.intValue
    }

    /// One entry: the server's status when it sends one, else the same rules the server uses.
    static func feed(_ o: [String: Any], now: Date) -> SourceFeed {
        let state = o["state"] as? String ?? ""
        let asOf = date(o["as_of"] as? String)
        let age = int(o["age_s"]) ?? asOf.map { max(0, Int(now.timeIntervalSince($0))) }
        let status: FeedStatus
        if let s = (o["status"] as? String).flatMap({ FeedStatus(rawValue: $0.lowercased()) }) {
            status = s
        } else if o["enabled"] as? Bool == false {
            status = .off
        } else if o["ok"] == nil {
            status = .live
        } else if o["ok"] as? Bool != true {
            status = .down
        } else if o["stale"] as? Bool == true || (age ?? 0) > (int(o["stale_after_s"]) ?? defaultStaleS) {
            status = .stale
        } else {
            status = .fresh
        }
        let national = (o["group"] as? String).map { $0 == "national" } ?? (state == "Nationwide")
        return SourceFeed(name: o["name"] as? String ?? "Feed", agency: o["agency"] as? String ?? "", state: state,
                          status: status, ageS: age, national: national,
                          stateCode: o["state_code"] as? String ?? codes[state], asOf: asOf)
    }

    /// The response body, or nil when it is not one.
    static func parse(_ data: Data, now: Date = Date()) -> SourcesReport? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["sources"] as? [[String: Any]] else { return nil }
        return report(list.map { feed($0, now: now) }, checkedAt: date(root["checked_at"] as? String),
                      summary: root["summary"] as? [String: Any])
    }

    static func report(_ feeds: [SourceFeed], checkedAt: Date?, summary: [String: Any]? = nil) -> SourcesReport {
        func count(_ k: String, _ s: FeedStatus) -> Int { int(summary?[k]) ?? feeds.filter { $0.status == s }.count }
        // On-demand feeds are asked as needed, so they are as fresh as a feed can be.
        let fresh = count("fresh", .fresh) + count("live", .live)
        let states = int(summary?["states"])
            ?? Set(feeds.filter { !$0.national && $0.status != .off }.compactMap(\.stateCode)).count
        let national = feeds.filter { $0.national && $0.status != .off }.map {
            FeedRow(code: "US", title: $0.name, by: $0.agency, status: $0.status, ageS: $0.ageS, asOf: $0.asOf)
        }
        var byCode: [String: [SourceFeed]] = [:]
        var order: [String] = []
        for f in feeds where !f.national && f.status != .off {
            guard let c = f.stateCode else { continue }
            if byCode[c] == nil { order.append(c) }
            byCode[c, default: []].append(f)
        }
        let rows: [FeedRow] = order.map { code in
            let fs = byCode[code]!
            // A state reads as its worst feed; its age is the oldest of the feeds that answer.
            let worst = fs.max { $0.status.rank < $1.status.rank }!
            var agencies: [String] = []
            for f in fs where !f.agency.isEmpty && !agencies.contains(f.agency) { agencies.append(f.agency) }
            let age = worst.status == .down ? worst.ageS : fs.compactMap(\.ageS).max()
            return FeedRow(code: code, title: fs[0].state, by: agencies.prefix(2).joined(separator: ", "),
                           status: worst.status, ageS: age, asOf: worst.asOf)
        }.sorted { $0.title < $1.title }
        return SourcesReport(checkedAt: checkedAt, fresh: fresh, stale: count("stale", .stale), down: count("down", .down),
                             states: states, national: national, stateRows: rows)
    }

    /// "30 s ago", "22 min ago", "Live"; a down feed says when it last answered.
    static func ageText(_ row: FeedRow, clock: (Date) -> String = { Units.time($0) }) -> String {
        if row.status == .live { return "Live" }
        if row.status == .down { return row.asOf.map { "No reply since \(clock($0))" } ?? "Not answering" }
        guard let a = row.ageS else { return "" }
        if a < 60 { return "\(a) s ago" }
        if a < 3600 { return "\(a / 60) min ago" }
        if a < 48 * 3600 { return "\(a / 3600) h ago" }
        return "\(a / 86400) days ago"
    }
}

// MARK: - API use

/// Today's API use for the signed-in account, from /api/keys: requests
/// against the account's daily limit (2,000 on a free key, 10,000 on a
/// pro key) and the limit for calls with no key, per address.
struct ApiUsage: Equatable {
    static let freeDaily = 2_000

    var requests: Int
    var limit: Int
    var tier: String
    var keylessDaily: Int?
    var activeKeys: Int

    /// How full the meter is, 0 to 1.
    var fraction: Double { limit <= 0 ? 0 : min(1, max(0, Double(requests) / Double(limit))) }
    var full: Bool { limit > 0 && requests >= limit }
    var usedText: String { Self.n(requests) }
    var limitText: String { "of " + Self.n(limit) }
    /// Under the account's limit: "a day with your free key".
    var tierText: String { activeKeys == 0 ? "a day with a free key" : "a day with your \(tier) key" }
    var keysText: String { activeKeys == 0 ? "None" : activeKeys == 1 ? "1 key" : "\(activeKeys) keys" }

    static let footnote = "A free key allows 2,000 requests a day and a pro key 10,000. The count starts over at midnight UTC."

    static func n(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// The response body, or nil when it is not one. Older servers leave
    /// out usage: then the tier's limit and 0 requests.
    static func parse(_ data: Data) -> ApiUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let keys = root["keys"] as? [[String: Any]] else { return nil }
        let int = SourcesHealth.int
        let active = keys.filter { $0["revoked"] as? Bool != true }
        let usage = root["usage"] as? [String: Any]
        let tiers = root["tiers"] as? [String: Any]
        let tier = usage?["tier"] as? String ?? (active.contains { $0["tier"] as? String == "pro" } ? "pro" : "free")
        let limit = int(usage?["limit"]) ?? int(tiers?[tier]) ?? active.compactMap { int($0["daily_limit"]) }.max() ?? freeDaily
        return ApiUsage(requests: int(usage?["requests"]) ?? 0, limit: limit, tier: tier,
                        keylessDaily: int(root["keyless_daily"]), activeKeys: active.count)
    }
}

// MARK: - Alerts

/// How alerts reach the driver.
enum AlertDelivery: String, CaseIterable {
    case voice, sound, silent
    var label: String { switch self { case .voice: "Voice"; case .sound: "Sound"; case .silent: "Silent" } }
}

/// What one alert does after the Alerts page: whether it alerts at all,
/// is spoken, or chimes.
struct AlertOutcome: Equatable {
    var enabled: Bool
    var speak: Bool
    var chime: Bool
}

/// The alert chips on the Alerts page: official kinds in the three
/// groups the alerts themselves use (act on it, heads up, good to know).
/// A chip turned off stops the alert, never the marker on the map.
/// Plugin alerts are not here: they have their own section and switches.
/// The looks on offer, as saved. A look that is no longer offered
/// (Light, Dark) goes back to the default, Positron.
enum MapStyleChoice {
    static let offered = ["auto", "positron", "bright", "slate", "outdoors"]

    static func stored(_ raw: String) -> String { offered.contains(raw) ? raw : "auto" }
}

enum AlertChips {
    struct Chip: Equatable { var key: String; var label: String }
    struct Tier { var label: String; var chips: [Chip] }

    static let tiers: [Tier] = [
        Tier(label: "Act on it", chips: [Chip(key: "crash", label: "Crashes"), Chip(key: "closure", label: "Closures"),
                                         Chip(key: "chain", label: "Chain controls"), Chip(key: "fire", label: "Wildfires")]),
        Tier(label: "Heads up", chips: [Chip(key: "traffic", label: "Slow traffic"), Chip(key: "ice", label: "Icy roads"),
                                        Chip(key: "hazard", label: "Road hazards")]),
        Tier(label: "Good to know", chips: [Chip(key: "sign", label: "Message signs"), Chip(key: "camera", label: "Speed cameras"),
                                            Chip(key: "toll", label: "Toll prices")]),
    ]

    static var keys: [String] { tiers.flatMap { $0.chips.map(\.key) } }

    /// Large and noisy, as on the website: off until the driver wants them.
    static let offByDefault: Set<String> = ["camera", "toll"]

    /// The chip a drawn kind falls under (DGKind's raw value): police
    /// reports are road hazards, jams are slow traffic.
    static func key(forKind kind: String) -> String {
        switch kind {
        case "jam": return "traffic"
        case "police": return "hazard"
        default: return keys.contains(kind) ? kind : "hazard"
        }
    }

    static func tierIndex(of key: String) -> Int {
        tiers.firstIndex { $0.chips.contains { $0.key == key } } ?? 1
    }

    /// One alert's outcome: chips and plugin switches can turn it off;
    /// the delivery picks voice, a chime or nothing. A plugin alert is
    /// spoken only with `speakPlugins`; otherwise it chimes where an
    /// official one would speak.
    static func apply(enabled: Bool, speak: Bool, plugin: Bool, chipOff: Bool, pluginOff: Bool,
                      delivery: AlertDelivery, speakPlugins: Bool) -> AlertOutcome {
        let off = plugin ? pluginOff : chipOff
        let voice = speak && delivery == .voice && (!plugin || speakPlugins)
        let chime: Bool
        switch delivery {
        case .sound: chime = !voice
        case .voice: chime = !voice && speak
        case .silent: chime = false
        }
        return AlertOutcome(enabled: enabled && !off, speak: voice, chime: chime)
    }

    /// The three "warn me ahead by" choices, in meters, for the units in use.
    static func aheadSteps(miles: Bool) -> [(meters: Double, label: String)] {
        miles ? [(805, "0.5 mi"), (1609, "1 mi"), (3219, "2 mi")] : [(800, "800 m"), (1500, "1.5 km"), (3000, "3 km")]
    }

    /// The step nearest a stored distance, so a value saved in other units still shows as picked.
    static func nearestStep(_ meters: Double, miles: Bool) -> Double {
        aheadSteps(miles: miles).min { abs($0.meters - meters) < abs($1.meters - meters) }!.meters
    }
}

// MARK: - Summaries on the home page

enum SettingsSummary {
    /// "Voice, 1 mi ahead"; "Per kind" when each kind has its own rules.
    static func alerts(delivery: AlertDelivery, aheadMeters: Double, advanced: Bool, miles: Bool) -> String {
        if advanced { return delivery.label + ", per kind" }
        let label = AlertChips.aheadSteps(miles: miles).first { $0.meters == AlertChips.nearestStep(aheadMeters, miles: miles) }!.label
        return "\(delivery.label), \(label) ahead"
    }

    /// "Miles, 12-hour".
    static func units(miles: Bool, clock24: Bool) -> String {
        (miles ? "Miles" : "Kilometers") + ", " + (clock24 ? "24-hour" : "12-hour")
    }

    /// "Fastest", or what the route avoids.
    static func route(tolls: Bool, highways: Bool, ferries: Bool) -> String {
        let avoid = [tolls ? "tolls" : nil, highways ? "highways" : nil, ferries ? "ferries" : nil].compactMap { $0 }
        return avoid.isEmpty ? "Fastest" : "Avoids " + avoid.joined(separator: ", ")
    }
}

// MARK: - First run

/// The three steps of the first run.
enum WelcomeStep: Int, CaseIterable {
    case location, notifications, account

    var title: String {
        switch self {
        case .location: "Know the road before you drive it"
        case .notifications: "Hear about your watch areas"
        case .account: "Sign in, if you like"
        }
    }

    var body: String {
        switch self {
        case .location: "Live crashes, closures, weather and more from official sources, on any route in the US."
        case .notifications: "Get a notification when something happens near home, work or any area you watch, even when the app is closed."
        case .account: "Driving works without an account. Signing in adds:"
        }
    }

    var progress: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }

    /// The first run shows once. An install that already has settings is
    /// an update, and counts as done.
    static func shouldShow(done: Bool, hasOtherPrefs: Bool) -> Bool { !done && !hasOtherPrefs }
}
