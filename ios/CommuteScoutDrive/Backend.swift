import CoreLocation
import Foundation

/// The CommuteScout server: everything the app reads or writes goes
/// through here. No third-party keys live in the app; routing, tiles,
/// search and live data are all proxied by commutescout.com.
enum Backend {
    static let base = URL(string: "https://commutescout.com")!
    static let navRouteURL = base.appendingPathComponent("api/nav/route")
    static let styleURL = base.appendingPathComponent("api/tiles/style.json")
    static let trafficTiles = base.absoluteString + "/api/traffictile/{z}/{x}/{y}.png"

    /// The base map: light, dark or outdoors, all through the proxy.
    static func styleURL(_ style: String) -> URL {
        var c = URLComponents(url: styleURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "style", value: style)]
        return c.url!
    }

    /// The website page focused on a spot, the same link the site shares.
    static func mapURL(lat: Double, lon: Double, kind: String? = nil) -> URL {
        var c = URLComponents(string: "https://commutescout.com/map")!
        var items = [URLQueryItem(name: "focus", value: String(format: "%.5f,%.5f", lat, lon))]
        if let kind { items.append(URLQueryItem(name: "k", value: kind)) }
        c.queryItems = items
        return c.url!
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "CommuteScoutDrive/\(AppInfo.version) iOS"]
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ path: String, query: [String: String] = [:],
                                  as type: T.Type) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BackendError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum BackendError: LocalizedError {
    case status(Int)

    var errorDescription: String? {
        switch self {
        case let .status(code): "The server answered \(code)."
        }
    }
}

enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}

// MARK: - Search

struct Suggestion: Decodable, Identifiable, Hashable {
    let name: String
    let lat: Double
    let lon: Double
    var id: String { "\(name)|\(lat)|\(lon)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

private struct SuggestResponse: Decodable { let suggestions: [Suggestion] }
private struct GeocodeResponse: Decodable { let candidates: [Suggestion] }

enum Search {
    /// Search-as-you-type: the server merges its gazetteer with Stadia's
    /// autocomplete, biased toward where the driver is.
    static func suggest(_ q: String, near: CLLocationCoordinate2D?) async throws -> [Suggestion] {
        var query = ["q": q]
        if let near {
            query["lat"] = String(format: "%.4f", near.latitude)
            query["lon"] = String(format: "%.4f", near.longitude)
        }
        return try await Backend.get("api/suggest", query: query, as: SuggestResponse.self).suggestions
    }

    static func geocode(_ q: String) async throws -> [Suggestion] {
        try await Backend.get("api/geocode", query: ["q": q], as: GeocodeResponse.self).candidates
    }
}

// MARK: - Live road data

/// One marker from /api/mapdata, the same records the web map draws.
struct RoadMarker: Decodable, Identifiable, Hashable {
    let kind: String
    let lat: Double
    let lon: Double
    let id: String?
    let type: String?
    let cls: String?
    let label: String?
    let location: String?
    let route: String?
    let status: String?
    let name: String?
    let flareKind: String?
    let source: String?
    let description: String?
    let area: String?
    let dir: String?
    let reported: String?
    let county: String?
    let delayMin: Double?
    let lanes: String?
    let since: Double?      // epoch seconds
    let until: Double?
    let work: String?
    let facility: String?
    let tier: String?          // approved, unreviewed or private, for plugin markers
    var acres: Double? = nil         // wildfires
    var contained: Double? = nil     // wildfires, percent

    enum CodingKeys: String, CodingKey {
        case kind, lat, lon, id, type, cls, label, location, route, status, name, source, description
        case area, dir, reported, county, lanes, since, until, work, facility, tier, acres, contained
        case flareKind = "flare_kind"
        case delayMin = "delay_min"
    }

    /// The lines under the title in the marker card.
    var detailLines: [String] {
        var out: [String] = []
        if kind == "incident" {
            if let location, !location.isEmpty { out.append(location) }
            let where_ = [dir, area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            if !where_.isEmpty { out.append(where_) }
            if let reported { out.append("Reported " + Self.when(reported)) }
        } else if kind == "lane_closure" {
            if let lanes, !lanes.isEmpty { out.append(lanes) }
            if let work, !work.isEmpty { out.append(work) }
            let span = [since.map { "from " + Self.when(epoch: $0) }, until.map { "until " + Self.when(epoch: $0) }].compactMap { $0 }
            if !span.isEmpty { out.append(span.joined(separator: " ")) }
            if let delayMin, delayMin > 0 { out.append("Expect about \(Int(delayMin)) min of delay") }
            if let county, !county.isEmpty { out.append(county + " County") }
        } else if kind == "chain_control" {
            if let location, !location.isEmpty { out.append(location) }
        } else if kind == "wildfire" {
            if let county, !county.isEmpty { out.append(county + " County") }
            if let reported { out.append("Updated " + Self.when(reported)) }
        } else if kind == "plugin" {
            if let source, !source.isEmpty {
                let badge = tier == "approved" ? " (approved by CommuteScout)" : tier == "private" ? " (your private plugin)" : " (public, not reviewed)"
                out.append("Community report via " + source + badge)
            }
            if let reported { out.append(Self.when(reported)) }
        }
        return out
    }

    /// A shareable link to this spot on the website.
    var webURL: URL { Backend.mapURL(lat: lat, lon: lon, kind: kind) }

    static func when(epoch: Double) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: Date(timeIntervalSince1970: epoch), relativeTo: Date())
    }

    static func when(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) ?? { f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: iso) }() else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: d, relativeTo: Date())
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// Stable enough to remember what was already announced.
    var key: String { id ?? "\(kind)|\(lat)|\(lon)|\(label ?? type ?? "")" }

    /// What a driver hears: short, specific, no codes.
    var spokenTitle: String {
        switch kind {
        case "incident":
            let t = (type ?? "").lowercased()
            if t.contains("collision") || t.contains("hit and run") { return "Collision reported ahead" }
            if t.contains("fire") { return "Fire reported ahead" }
            if t.contains("hazard") || t.contains("debris") || t.contains("animal") { return "Hazard on the road ahead" }
            return "Incident reported ahead"
        case "lane_closure":
            switch cls {
            case "full-roadway": return "Road closed ahead"
            case "ramp": return "Ramp closed ahead"
            case "one-way-traffic", "alternating-lanes": return "One-way traffic control ahead"
            default: return "Lane closure ahead"
            }
        case "chain_control":
            return "Chain control ahead" + ((status ?? "").isEmpty ? "" : ", \(status!)")
        case "wildfire":
            return "Wildfire near the road ahead"
        case "plugin":
            let k = (flareKind ?? "").replacingOccurrences(of: "_", with: " ").lowercased()
            return "Community report ahead: \(k)"
        default:
            return "Something reported ahead"
        }
    }

    var displayTitle: String {
        switch kind {
        case "incident": return label ?? type ?? "Incident"
        case "lane_closure": return label ?? "Lane closure"
        case "chain_control": return "Chain control \(status ?? "") on \(route ?? "")"
        case "wildfire": return "\(name ?? "Wildfire") Fire"
        case "plugin": return description ?? (flareKind ?? "Report").replacingOccurrences(of: "_", with: " ").capitalized
        default: return kind
        }
    }

    /// Meters either side of the route that count as "on it".
    /// How far from the route a marker still counts as being on it. A fire
    /// matters at a distance only when it is big; a spot fire out of sight
    /// of the road is not worth a word.
    var corridorMeters: Double {
        switch kind {
        case "wildfire": return (acres ?? 0) >= 1_000 ? 5_000 : (acres ?? 0) >= 100 ? 3_000 : 1_500
        case "chain_control": return 1_000
        default: return 300
        }
    }

    /// Fires too small or too contained to announce on a drive.
    var tooMinorToAnnounce: Bool {
        guard kind == "wildfire" else { return false }
        if let c = contained, c >= 90 { return true }
        if let a = acres, a < 10 { return true }
        return false
    }
}

private struct MapDataResponse: Decodable { let markers: [RoadMarker] }

enum LiveData {
    static let kinds = "incident,closure,chain,fire,plugin"

    static func markers(in box: (south: Double, west: Double, north: Double, east: Double),
                        kinds: String = kinds) async throws -> [RoadMarker] {
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", box.south, box.west, box.north, box.east)
        return try await Backend.get("api/mapdata", query: ["bbox": bbox, "kinds": kinds],
                                     as: MapDataResponse.self).markers
    }
}
