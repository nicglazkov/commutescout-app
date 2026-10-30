import CoreLocation
import Foundation

// The pure logic behind the trip and watch pages, kept apart from any
// view so the unit tests can build it on its own.

struct LeaveLater: Decodable, Equatable {
    struct Departure: Decodable, Equatable {
        let depart_at: String
        let now: Bool?
        let drive_min: Int?
        let delay_min: Int?
    }
    struct Best: Decodable, Equatable {
        let depart_at: String
        let drive_min: Int
        let saving_min: Int
    }
    let checked_at: String?
    let departures: [Departure]
    let best: Best?
    let reason: String?

    var now: Departure? { departures.first { $0.now == true } ?? departures.first }

    /// One bar per departure, its height scaled between the quickest and
    /// the slowest so a short trip still shows its shape.
    struct Bar: Equatable { let minutes: Int; let height: Double; let isNow: Bool; let isBest: Bool; let label: String }

    func bars(maxHeight: Double = 76, minHeight: Double = 22) -> [Bar] {
        let known = departures.compactMap(\.drive_min)
        guard let lo = known.min(), let hi = known.max() else { return [] }
        return departures.enumerated().compactMap { i, d in
            guard let m = d.drive_min else { return nil }
            let f = hi == lo ? 0.6 : Double(m - lo) / Double(hi - lo)
            let label = i == 0 ? "Now" : (Self.date(d.depart_at).map { Units.time($0).replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "") } ?? "")
            return Bar(minutes: m, height: minHeight + f * (maxHeight - minHeight), isNow: i == 0,
                       isBest: best?.depart_at == d.depart_at, label: label)
        }
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        // "2026-10-29T16:10+00:00": minutes, no seconds.
        let g = DateFormatter()
        g.locale = Locale(identifier: "en_US_POSIX")
        g.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return g.date(from: iso)
    }

    /// "Leave at 9:10 to save 8 min", or nil when now is as good as any.
    var headline: String? {
        guard let b = best, let d = Self.date(b.depart_at) else { return nil }
        return "Leave at \(Units.time(d)) to save \(b.saving_min) min"
    }
}

/// The arithmetic of watch shapes, apart from any view.
enum WatchMath {
    static let maxRadiusKm = 40.2          // 25 mi, the free limit
    static let minRadiusKm = 1.0
    static let maxPolygonSqKm = 5180.0     // 2,000 sq mi
    static let maxRouteKm = 402.0          // 250 mi
    static let bufferKm = 3.2              // 2 mi
    static let maxWatches = 3

    static func circleSqKm(_ rKm: Double) -> Double { .pi * rKm * rKm }

    /// Shoelace on an equirectangular projection around the shape.
    static func polygonSqKm(_ pts: [CLLocationCoordinate2D]) -> Double {
        guard pts.count >= 3 else { return 0 }
        let sum: Double = pts.reduce(0.0) { $0 + $1.latitude }
        let lat0: Double = sum / Double(pts.count) * Double.pi / 180
        let kx: Double = 111.32 * cos(lat0)
        let xs: [Double] = pts.map { $0.longitude * kx }
        let ys: [Double] = pts.map { $0.latitude * 110.574 }
        var a = 0.0
        for i in xs.indices {
            let j = (i + 1) % xs.count
            let t: Double = xs[i] * ys[j]
            a += t - xs[j] * ys[i]
        }
        return abs(a) / 2
    }

    static func areaText(sqKm: Double) -> String {
        if Units.useMiles {
            let mi = sqKm / 2.58999
            return "\(Self.round(mi)) sq mi"
        }
        return "\(Self.round(sqKm)) sq km"
    }

    private static func round(_ v: Double) -> String {
        let r = v < 20 ? (v).rounded() : v < 200 ? (v / 5).rounded() * 5 : (v / 10).rounded() * 10
        return Int(r).formatted()
    }

    static func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func lengthKm(_ pts: [CLLocationCoordinate2D]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + haversine($1.0, $1.1) / 1000 }
    }

    /// The create body the server takes for each shape.
    static func body(name: String, kinds: [String], quiet: Bool, push: Bool, email: Bool,
                     circle: (CLLocationCoordinate2D, Double)? = nil, route: [CLLocationCoordinate2D]? = nil,
                     polygon: [CLLocationCoordinate2D]? = nil) -> [String: Any] {
        var b: [String: Any] = ["name": name, "kinds": kinds, "quiet_hours": quiet, "channels": ["push": push, "email": email]]
        if let (c, r) = circle {
            b["type"] = "circle"
            b["center"] = ["lat": c.latitude, "lon": c.longitude]
            b["radius_km"] = min(maxRadiusKm, max(minRadiusKm, (r * 100).rounded() / 100))
        } else if let route {
            let step = max(1, route.count / 80)
            var pts = stride(from: 0, to: route.count, by: step).map { [route[$0].latitude, route[$0].longitude] }
            if let last = route.last, pts.last != [last.latitude, last.longitude] { pts.append([last.latitude, last.longitude]) }
            b["type"] = "route"; b["points"] = pts; b["buffer_km"] = bufferKm
        } else if let polygon {
            b["type"] = "polygon"; b["points"] = polygon.map { [$0.latitude, $0.longitude] }
        }
        return b
    }

    /// The change the server takes for a watch area that exists. A shape
    /// sends its corners; a drive keeps its line, and a circle is fixed
    /// once made, so a new radius is `resized` and replaces the circle.
    static func update(name: String, kinds: [String], quiet: Bool, polygon: [CLLocationCoordinate2D]? = nil) -> [String: Any] {
        var b: [String: Any] = ["name": label(name), "kinds": kinds, "quiet_hours": quiet]
        if let polygon { b["points"] = polygon.map { [$0.latitude, $0.longitude] } }
        return b
    }

    /// A name for the server: trimmed, at most 60 characters.
    static func label(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Watch area" : String(t.prefix(60))
    }

    /// Whether a circle's radius really changed, at the precision saved.
    static func resized(from old: Double?, to new: Double) -> Bool {
        guard let old else { return false }
        return abs(old - new) >= 0.005
    }
}

/// Web Mercator in MapLibre's 512-point tiles: where a coordinate falls
/// on a map of a given center, zoom and size, and back. The editors keep
/// the map still and draw their shapes over it with this.
struct Mercator {
    var center: CLLocationCoordinate2D
    var zoom: Double
    var size: CGSize

    private var world: Double { 512 * pow(2, zoom) }
    private func project(_ c: CLLocationCoordinate2D) -> (Double, Double) {
        let s = sin(max(-85, min(85, c.latitude)) * .pi / 180)
        return ((c.longitude + 180) / 360 * world, (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * world)
    }

    func point(_ c: CLLocationCoordinate2D) -> CGPoint {
        let (x, y) = project(c), (cx, cy) = project(center)
        return CGPoint(x: x - cx + size.width / 2, y: y - cy + size.height / 2)
    }

    func coordinate(_ p: CGPoint) -> CLLocationCoordinate2D {
        let (cx, cy) = project(center)
        let x = Double(p.x) - size.width / 2 + cx, y = Double(p.y) - size.height / 2 + cy
        let lon = x / world * 360 - 180
        let n = .pi - 2 * .pi * y / world
        return CLLocationCoordinate2D(latitude: 180 / .pi * atan(0.5 * (exp(n) - exp(-n))), longitude: lon)
    }

    /// Points per meter at the center.
    var pointsPerMeter: Double { world / (40_075_016.686 * cos(center.latitude * .pi / 180)) }

    /// The zoom at which `meters` spans `points` at this latitude.
    static func zoom(fitting meters: Double, in points: Double, at lat: Double) -> Double {
        log2(points * 40_075_016.686 * cos(lat * .pi / 180) / (512 * max(1, meters)))
    }
}


/// The report flow's lane picker and wording.
enum ReportGrid {
    enum Lane: String, CaseIterable { case left = "Left lane", right = "Right lane", shoulder = "Shoulder" }

    /// The lanes drawn on the confirm card: a four-lane road with the
    /// picked lane closed (the shoulder closes the right shoulder).
    static func layout(_ lane: Lane) -> LaneLayout {
        let closed: Int? = lane == .left ? 1 : lane == .right ? 4 : nil
        return LaneLayout(total: 4, lanes: (1 ... 4).map { LaneLayout.Lane(n: $0, closed: $0 == closed) },
                          rightShoulderClosed: lane == .shoulder, target: lane == .left ? 2 : lane == .right ? 3 : nil, basis: "feed")
    }

    /// "southbound", from a course in degrees.
    static func bound(_ course: Double?) -> String? {
        guard let c = course, c >= 0 else { return nil }
        let names = ["northbound", "eastbound", "southbound", "westbound"]
        return names[Int(((c.truncatingRemainder(dividingBy: 360)) + 45) / 90) % 4]
    }

    /// The note the plugin gets: the driver's words, with the lane in front.
    static func description(note: String, lane: Lane?) -> String {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lane else { return n }
        return n.isEmpty ? lane.rawValue : "\(lane.rawValue). \(n)"
    }
}
