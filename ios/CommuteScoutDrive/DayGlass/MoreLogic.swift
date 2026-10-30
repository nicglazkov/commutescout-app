import CoreLocation
import Foundation

// The pure logic behind the plugin marketplace, the plugin page and
// offline maps, kept apart from any view so the unit tests can build it
// on its own. The same rules as Android's Market and AreaMath.

/// The marketplace and plugin page's rules and words.
enum Market {
    /// Where a plugin's data comes from.
    enum Data { case official, plugin }

    enum Filter: String, CaseIterable, Hashable {
        case all = "All", official = "Official data", plugin = "Plugin data"
    }

    /// Official data is what CommuteScout runs itself from public sources
    /// (the catalog's trust "official"). Everything else, reviewed or
    /// not, is plugin data: it comes from the plugin's maker.
    static func data(trust: String?) -> Data { trust == "official" ? .official : .plugin }

    static func shows(_ f: Filter, trust: String?) -> Bool {
        switch f {
        case .all: return true
        case .official: return data(trust: trust) == .official
        case .plugin: return data(trust: trust) == .plugin
        }
    }

    /// In the person's list: shown on the map, or switched off for now.
    static func isAdded(_ id: String, hidden: Set<String>, paused: Set<String>) -> Bool {
        !hidden.contains(id) || paused.contains(id)
    }

    /// "2 added, 4 more to try", "All 3 added" or "4 to try".
    static func countLine(visible: Int, added: Int) -> String {
        if visible == 0 { return "Nothing listed here yet" }
        if added >= visible { return "All \(visible) added" }
        if added > 0 { return "\(added) added, \(visible - added) more to try" }
        return "\(visible) to try"
    }

    /// Who makes it, under its name. A maker named the same as the plugin
    /// says nothing twice.
    static func maker(name: String, trust: String?, tier: String, attribution: String?) -> String {
        if trust == "official" { return "By CommuteScout" }
        if tier == "private" { return "Added by you" }
        if let a = attribution?.trimmingCharacters(in: .whitespaces), !a.isEmpty, a != name { return "By \(a)" }
        return "By its community"
    }

    /// What it does, in a line or two.
    static func purpose(summary: String?, kindsLabel: String) -> String {
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        return kindsLabel.isEmpty ? "Alerts for your map." : "Shows \(kindsLabel) on your map."
    }

    /// The design icon on its badge, from what it shows.
    static func glyph(kinds: [String]) -> String {
        if kinds.isEmpty { return "piece" }
        if kinds.allSatisfy({ $0.hasPrefix("CAMERA") }) { return "camera" }
        if kinds.contains(where: { $0.hasPrefix("POLICE") || $0.hasPrefix("CRASH") || $0.hasPrefix("HAZARD") || $0.hasPrefix("JAM") }) { return "people" }
        if kinds.allSatisfy({ $0.hasPrefix("CHAINS") }) { return "chain" }
        return "piece"
    }

    static func showSub(_ on: Bool) -> String {
        on ? "Its alerts are on your map" : "Off for now. Nothing is shown or asked for."
    }

    /// The "In alerts" line: reviewed plugins may speak; the others only
    /// if the person says so.
    static func inAlerts(tier: String) -> String {
        switch tier {
        case "approved": return "Its alerts can be spoken while you drive, like official ones."
        case "private": return "Shown on your map. Spoken only if you turn that on in Settings > Alerts."
        default: return "Not reviewed: shown on your map, spoken only if you turn that on in Settings > Alerts."
        }
    }

    struct Use: Equatable { let title: String; let sub: String; let allowed: Bool }

    /// What the plugin can use, honestly: who asks it, and with what.
    static func uses(ownSession: Bool, direct: Bool, reports: Bool) -> [Use] {
        var out: [Use] = []
        if ownSession {
            out.append(Use(title: "The area around you, while the app is open", sub: "Rounded to about 5 km, to find alerts near you", allowed: true))
            out.append(Use(title: "Your sign-in", sub: "So what it shows stays yours", allowed: true))
        } else if direct {
            out.append(Use(title: "The area on your map, while the app is open", sub: "Rounded to about 5 km. This phone asks it directly", allowed: true))
        } else {
            out.append(Use(title: "The area on your map, through CommuteScout", sub: "It never gets your exact location", allowed: true))
        }
        if reports { out.append(Use(title: "Reports you choose to send", sub: "Only when you send one", allowed: true)) }
        out.append(Use(title: ownSession ? "Never your places or contacts" : "Never your places, contacts or account",
                       sub: "Plugins can't ask for these", allowed: false))
        return out
    }

    /// "Yes, 2 min ago", "No" or "Not asked yet", and whether it reads as
    /// good (true), bad (false) or unknown (nil).
    static func answering(ok: Bool?, lastOk: String?, now: Date = Date()) -> (text: String, good: Bool?) {
        switch ok {
        case true?: return (lastOk.map { "Yes, " + ago($0, now: now) } ?? "Yes", true)
        case false?: return ("No", false)
        case nil: return ("Not asked yet", nil)
        }
    }

    static func alertsNow(_ n: Int) -> String {
        n == 0 ? "None" : n == 1 ? "1 alert" : "\(n.formatted()) alerts"
    }

    static func every(_ seconds: Int) -> String {
        if seconds < 60 { return "Every \(seconds) s" }
        if seconds < 3600 { return "Every \(seconds / 60) min" }
        return "Every \(seconds / 3600) h"
    }

    static func footnote(attribution: String?) -> String {
        let from = attribution?.trimmingCharacters(in: .whitespaces) ?? ""
        return (from.isEmpty ? "" : "Data from \(from). ") + "Verify an alert before you rely on it."
    }

    /// "just now", "5 min ago", "3 h ago" or "2 days ago" for an ISO time.
    static func ago(_ iso: String, now: Date = Date()) -> String {
        guard let d = date(iso) else { return iso }
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        let days = s / 86400
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}

/// What a picked download area costs: its size on the phone and the
/// path the map server cuts along.
enum AreaMath {
    /// The server cuts squares this far either side of the path (mapfiles.MAX_BUFFER_M).
    static let bufferM = 6000.0
    /// And refuses paths longer than this (MAX_ROUTE_M), with some room.
    static let maxPathKm = 780.0
    /// Without a state to learn from: a suburban square kilometer of full detail.
    static let fallbackBytesPerSqKm = 250_000.0

    static func widthKm(south: Double, west: Double, north: Double, east: Double) -> Double {
        let mid = (south + north) / 2
        return WatchMath.haversine(CLLocationCoordinate2D(latitude: mid, longitude: west),
                                   CLLocationCoordinate2D(latitude: mid, longitude: east)) / 1000
    }

    static func heightKm(south: Double, north: Double) -> Double { (north - south) * 110.54 }

    /// A back and forth path whose squares cover the box: rows two
    /// buffers apart, from one side to the other. The server takes
    /// corridors only, so an area is a corridor that folds.
    static func serpentine(south: Double, west: Double, north: Double, east: Double) -> [CLLocationCoordinate2D] {
        guard [south, west, north, east].allSatisfy(\.isFinite), north > south, east > west else { return [] }
        let rowStep = 2 * bufferM / 110_540
        let rows = max(1, Int(ceil((north - south) / rowStep)))
        let inset = min(bufferM / 110_540, (north - south) / 2)
        var out: [CLLocationCoordinate2D] = []
        for i in 0 ..< rows {
            let lat = max(south + inset, min(south + inset + Double(i) * rowStep, north - inset))
            let a = CLLocationCoordinate2D(latitude: lat, longitude: west), b = CLLocationCoordinate2D(latitude: lat, longitude: east)
            out += i % 2 == 0 ? [a, b] : [b, a]
        }
        // Points every few km, so the server's samples land on the line.
        var dense: [CLLocationCoordinate2D] = []
        for (a, b) in zip(out, out.dropFirst()) {
            let n = max(1, Int(ceil(WatchMath.haversine(a, b) / 4000)))
            for k in 0 ..< n {
                let t = Double(k) / Double(n)
                dense.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                    longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        if let last = out.last { dense.append(last) }
        return dense
    }

    static func fits(south: Double, west: Double, north: Double, east: Double) -> Bool {
        let path = serpentine(south: south, west: west, north: north, east: east)
        return path.count > 1 && WatchMath.lengthKm(path) <= maxPathKm
    }

    /// Bytes per square km, learned from a whole state's file and its box.
    static func density(stateBytes: Int64?, south: Double, west: Double, north: Double, east: Double) -> Double? {
        guard let b = stateBytes, b > 0 else { return nil }
        let km2 = widthKm(south: south, west: west, north: north, east: east) * heightKm(south: south, north: north)
        return km2 > 0 ? Double(b) / km2 : nil
    }

    static func estimateBytes(widthKm: Double, heightKm: Double, bytesPerSqKm: Double?) -> Int64 {
        let v = widthKm * heightKm * (bytesPerSqKm ?? fallbackBytesPerSqKm)
        // A frame not laid out yet has no size; never trap on it.
        guard v.isFinite, v > 0 else { return 0 }
        return Int64(min(v, 9e15))
    }

    /// "About 310 MB", rounded so it never claims more precision than it has.
    static func aboutText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1e6
        if bytes >= 1_000_000_000 { return String(format: "About %.1f GB", Double(bytes) / 1e9) }
        if bytes >= 10_000_000 { return "About \(Int((mb / 5).rounded()) * 5) MB" }
        return "About \(max(1, Int(mb.rounded()))) MB"
    }

    /// "22 by 16 mi", or km where the person reads km.
    static func spanText(widthKm: Double, heightKm: Double, miles: Bool) -> String {
        func n(_ km: Double) -> Int { max(1, Int((miles ? km / 1.609344 : km).rounded())) }
        return "\(n(widthKm)) by \(n(heightKm)) \(miles ? "mi" : "km")"
    }
}

/// How the storage bar splits what is saved: states, areas and trips, as
/// fractions of everything saved. A sliver too thin to see still shows.
struct StorageSplit: Equatable {
    var states: Double
    var areas: Double
    var trips: Double

    static func of(states: Int64, areas: Int64, trips: Int64) -> StorageSplit {
        let total = Double(states + areas + trips)
        guard total > 0 else { return StorageSplit(states: 0, areas: 0, trips: 0) }
        func f(_ v: Int64) -> Double { v <= 0 ? 0 : max(Double(v) / total, 0.03) }
        let raw = [f(states), f(areas), f(trips)], sum = raw.reduce(0, +)
        return StorageSplit(states: raw[0] / sum, areas: raw[1] / sum, trips: raw[2] / sum)
    }
}

enum SavedText {
    /// "today, 6:40 AM", "yesterday, 9:05 PM" or "Oct 12".
    static func when(_ d: Date, now: Date = Date(), calendar: Calendar = .current, clock: (Date) -> String = Units.time) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "today, \(clock(d))" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "yesterday, \(clock(d))" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    /// "1.4 GB", "312 MB": the size the way the mockups write it.
    static func size(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return "\(Int((Double(bytes) / 1e6).rounded())) MB" }
        return "\(max(1, Int((Double(bytes) / 1e3).rounded()))) KB"
    }
}
