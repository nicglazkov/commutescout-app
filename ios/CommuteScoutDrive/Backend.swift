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

/// One entry point on a toll corridor: where a driver joins it, the
/// road-following points that lead there, and the price to each
/// destination from that point.
struct TollEntry: Decodable, Hashable {
    let label: String?
    let pts: [[Double]]?        // [[lat, lon], ...]
    let rows: [TollRow]?
}

/// One priced destination on a toll corridor. On the wire it is a pair,
/// ["South Main St", 1.5], not an object.
struct TollRow: Decodable, Hashable {
    let destination: String
    let price: Double?

    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        // Nothing past the container is allowed to throw: one odd row
        // must not cost the map the whole payload it arrived in.
        var name = ""
        if !row.isAtEnd, (try? row.decodeNil()) == false {
            name = (try? row.decode(String.self)) ?? ""
        }
        destination = name
        var amount: Double?
        if !row.isAtEnd { amount = try? row.decode(Double.self) }
        price = amount
    }
}

/// Which way the wind blows from. The roadside stations disagree about
/// how to say it: most send a compass point like "NNE", some send
/// degrees. Both arrive in the same field, so reading it as a number
/// alone threw on every station that sent text, and with a synthesized
/// decoder that costs the whole station.
struct WindDirection: Decodable, Hashable {
    let text: String

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let degrees = try? value.decode(Double.self) {
            text = Units.windDirection(degrees)
        } else {
            text = ((try? value.decode(String.self)) ?? "").uppercased()
        }
    }
}

/// One marker from /api/mapdata, the same records the web map draws.
/// The launch snapshot publishes the same shape, minus the road-following
/// geometry and the null fields.
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
    var discovered: String? = nil    // wildfires, ISO 8601
    var updated: String? = nil       // chain controls and toll rates, ISO 8601
    var src: String? = nil           // the agency or network behind the record
    // Cameras.
    var image: String? = nil         // still image, refetched each time it is shown
    var stream: String? = nil        // live video page, when the agency publishes one
    var direction: String? = nil     // spelled out: "North", "East"
    var near: String? = nil          // the nearby place, for cameras and signs
    // Message signs.
    var message: String? = nil       // the whole text, lines joined with " / "
    var lines: [String]? = nil       // the same text already split into lines
    var blank: Bool? = nil           // the sign is displaying nothing right now
    // Roadside weather stations. Temperatures Celsius, wind mph, visibility metres.
    var station: String? = nil
    var airC: Double? = nil
    var paveC: Double? = nil
    var wind: Double? = nil
    var gust: Double? = nil
    var windDir: WindDirection? = nil   // degrees on some feeds, a compass point on others
    var rh: Double? = nil            // relative humidity, percent
    var precip: String? = nil
    var surface: String? = nil
    var visM: Double? = nil
    // Toll prices.
    var corridor: String? = nil
    var minPrice: Double? = nil
    var maxPrice: Double? = nil
    var pricing: String? = nil       // "live" or "fixed"
    var tollType: String? = nil      // "required" or "express"
    var tollDir: String? = nil       // the tolled direction, when only one is
    var tollNote: String? = nil      // what that direction leads to
    var asOf: String? = nil          // when a posted schedule took effect
    var entries: [TollEntry]? = nil
    // Geometry. Closure stretches and toll corridors come only from
    // /api/mapdata: the launch snapshot is slim and drops both. Burn
    // footprints survive the slimming and arrive with either.
    var path: [[Double]]? = nil      // closure stretch, road-following
    var end: [Double]? = nil         // closure end point, when there is no path
    var segs: [[[Double]]]? = nil    // toll corridor, one chain per segment
    var poly: [[[Double]]]? = nil    // burn footprint, one list per ring

    enum CodingKeys: String, CodingKey {
        case kind, lat, lon, id, type, cls, label, location, route, status, name, source, description
        case area, dir, reported, county, lanes, since, until, work, facility, tier, acres, contained
        case discovered, updated, src, image, stream, direction, near, message, lines, blank
        case station, wind, gust, rh, precip, surface, corridor, pricing, entries, path, end, segs, poly
        case flareKind = "flare_kind"
        case delayMin = "delay_min"
        case airC = "air_c"
        case paveC = "pave_c"
        case windDir = "wind_dir"
        case visM = "vis_m"
        case minPrice = "min"
        case maxPrice = "max"
        case tollType = "toll_type"
        case tollDir = "toll_dir"
        case tollNote = "toll_note"
        case asOf = "as_of"
    }

    /// "I-80 East, Vacaville": the road a camera watches, the direction
    /// it faces and the place it is near. Agencies routinely name a
    /// camera after the place it is near, so the place is left off when
    /// the title already says it.
    var whereLine: String {
        let road = [route, direction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let title = displayTitle.lowercased()
        let place = near.flatMap { $0.isEmpty || title.contains($0.lowercased()) ? nil : $0 }
        return [road, place].compactMap { $0 }.joined(separator: ", ")
    }

    /// What a toll costs right now: one price, or the span across the
    /// corridor's entry points.
    var priceRange: String {
        guard let low = minPrice else { return "Toll" }
        let high = maxPrice ?? low
        return low == high ? Self.money(low) : Self.money(low) + " to " + Self.money(high)
    }

    static func money(_ value: Double) -> String {
        value == value.rounded() ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }

    /// The message a sign is showing, split into its board lines.
    var signLines: [String] {
        if let lines, !lines.isEmpty { return lines }
        guard let message, !message.isEmpty else { return [] }
        return message.components(separatedBy: " / ")
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
            if let acres, acres > 0 {
                let size = acres >= 1_000 ? "\(Int(acres).formatted()) acres" : "\(Int(acres)) acres"
                out.append(contained.map { "\(size), \(Int($0))% contained" } ?? size)
            }
            if let when = reported ?? discovered { out.append("Updated " + Self.when(when)) }
        } else if kind == "camera" {
            if !whereLine.isEmpty { out.append(whereLine) }
            out.append(stream == nil ? "Still image, not video" : "Live video available")
        } else if kind == "sign" {
            // The title already carries the road and the direction.
            if let near, !near.isEmpty { out.append(near) }
            if blank == true || signLines.isEmpty { out.append("Blank right now") }
        } else if kind == "rwis" {
            if let route, !route.isEmpty { out.append(route) }
            if let airC { out.append("Air " + Units.temperature(celsius: airC)) }
        } else if kind == "toll" {
            out.append(priceRange + (tollType == "required" ? ", all lanes tolled" : ", optional express lane"))
            if let tollDir, !tollDir.isEmpty {
                out.append(tollDir.capitalized + (tollNote.map { ", " + $0 } ?? ""))
            }
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
        case "camera":
            return "Traffic camera ahead"
        case "sign":
            return "Message sign ahead"
        case "rwis":
            return "Roadside weather station ahead"
        case "toll":
            return "Toll ahead, \(priceRange)"
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
        case "camera": return name ?? "Roadside camera"
        case "sign":
            let road = [route, direction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return road.isEmpty ? "Changeable message sign" : road + " message sign"
        case "rwis": return station ?? name ?? "Weather station"
        case "toll": return corridor ?? name ?? "Toll"
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

    /// What a drive says nothing about: fires too small or too contained
    /// to matter, and the four reference layers. A camera, a message
    /// sign, a weather station and a toll price are things to look at on
    /// the map, not events to announce at the wheel.
    var tooMinorToAnnounce: Bool {
        if ["camera", "sign", "rwis", "toll"].contains(kind) { return true }
        guard kind == "wildfire" else { return false }
        if let c = contained, c >= 90 { return true }
        if let a = acres, a < 10 { return true }
        return false
    }

    /// Something that happened, as opposed to roadside equipment that is
    /// always there. The nearby list and the route conditions read this.
    var isEvent: Bool { !["camera", "rwis"].contains(kind) }

    /// The burn footprint's rings, as coordinates. Rings stay separate:
    /// flattening a multi-lobed fire into one ring draws lines between
    /// the lobes.
    var polygonRings: [[CLLocationCoordinate2D]] {
        (poly ?? []).map { ring in
            ring.compactMap { p in
                p.count >= 2 ? CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) : nil
            }
        }.filter { $0.count >= 3 }
    }

    /// The road-following lines this marker draws: a closure stretch, or
    /// every segment of a toll corridor. Empty when the server sent no
    /// geometry, which is always true of the launch snapshot.
    var polylines: [[CLLocationCoordinate2D]] {
        func line(_ pts: [[Double]]) -> [CLLocationCoordinate2D] {
            pts.compactMap { p in
                p.count >= 2 ? CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) : nil
            }
        }
        if kind == "toll" { return (segs ?? []).map(line).filter { $0.count >= 2 } }
        guard kind == "lane_closure" else { return [] }
        if let path, path.count >= 2 { return [line(path)].filter { $0.count >= 2 } }
        // No snapped shape yet: a straight line to the recorded end is
        // still truer than a lone dot at the start of a ten-mile closure.
        if let end, end.count >= 2 {
            return [[coordinate, CLLocationCoordinate2D(latitude: end[0], longitude: end[1])]]
        }
        return []
    }
}

private struct MapDataResponse: Decodable { let markers: [RoadMarker] }

enum LiveData {
    /// The kinds a drive is announced from. The map asks for more than
    /// this: what it draws comes from `Prefs.apiKinds`, which follows the
    /// Layers sheet. Note that these are the query names, not the kinds
    /// the server emits: `closure` comes back as `lane_closure`, `chain`
    /// as `chain_control` and `fire` as `wildfire`. The four reference
    /// layers use the same name on both sides.
    static let kinds = "incident,closure,chain,fire,plugin"

    static func markers(in box: (south: Double, west: Double, north: Double, east: Double),
                        kinds: String = kinds) async throws -> [RoadMarker] {
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", box.south, box.west, box.north, box.east)
        return try await Backend.get("api/mapdata", query: ["bbox": bbox, "kinds": kinds],
                                     as: MapDataResponse.self).markers
    }
}
