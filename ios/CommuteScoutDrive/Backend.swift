import CoreLocation
import Foundation

/// The CommuteScout server: everything the app reads or writes goes
/// through here. No third-party keys live in the app; routing, tiles,
/// search and live data are all proxied by commutescout.com.
enum Backend {
    static let base = URL(string: "https://commutescout.com")!
    static let navRouteURL = base.appendingPathComponent("api/nav/route")
    static let styleURL = base.appendingPathComponent("api/tiles/style.json")

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

    enum CodingKeys: String, CodingKey {
        case kind, lat, lon, id, type, cls, label, location, route, status, name, source, description
        case flareKind = "flare_kind"
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
    var corridorMeters: Double {
        switch kind {
        case "wildfire": return 12_000
        case "chain_control": return 1_000
        default: return 300
        }
    }
}

private struct MapDataResponse: Decodable { let markers: [RoadMarker] }

enum LiveData {
    static let kinds = "incident,closure,chain,fire,plugin"

    static func markers(in box: (south: Double, west: Double, north: Double, east: Double)) async throws -> [RoadMarker] {
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", box.south, box.west, box.north, box.east)
        return try await Backend.get("api/mapdata", query: ["bbox": bbox, "kinds": kinds],
                                     as: MapDataResponse.self).markers
    }
}
