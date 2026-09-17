import AVFoundation
import CoreLocation
import Foundation

/// Live alerts while driving. Every 60 seconds the engine reads the
/// markers inside the route's box, projects each onto the route, keeps
/// those within a corridor (300 m for incidents and closures, 1 km for
/// chain controls, 12 km for fires), orders them by distance along the
/// route, and announces each one once when it is about a minute ahead.
/// The same list feeds the banner under the maneuver card.
@MainActor
final class AlertsEngine: ObservableObject {
    struct Upcoming: Identifiable, Hashable {
        let marker: RoadMarker
        let alongMeters: Double     // distance along the route from its start
        var id: String { marker.key }
    }

    @Published private(set) var ahead: [Upcoming] = []
    @Published private(set) var lastAnnounced: String?
    @Published var spoken = true

    private var route: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []
    private var all: [Upcoming] = []
    private var announced: Set<String> = []
    private var timer: Timer?
    private var box: (south: Double, west: Double, north: Double, east: Double)?
    private let synth = AVSpeechSynthesizer()

    static let announceAheadMeters = 1500.0
    static let refreshSeconds = 60.0

    func start(route coordinates: [CLLocationCoordinate2D]) {
        stop()
        route = coordinates
        cumulative = Self.cumulativeDistances(coordinates)
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let s = lats.min(), let n = lats.max(), let w = lons.min(), let e = lons.max() else { return }
        box = (s - 0.05, w - 0.05, n + 0.05, e + 0.05)
        announced = []
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshSeconds, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        route = []
        cumulative = []
        all = []
        ahead = []
        box = nil
    }

    /// Called with each snapped location while navigating.
    func update(position: CLLocationCoordinate2D) {
        guard !route.isEmpty else { return }
        let here = Self.along(route, cumulative, position).along
        let upcoming = all.filter { $0.alongMeters > here - 100 }
        ahead = upcoming
        for item in upcoming where !announced.contains(item.id) {
            let gap = item.alongMeters - here
            if gap <= Self.announceAheadMeters, gap > -100 {
                announced.insert(item.id)
                announce(item.marker)
            }
        }
    }

    /// Repeat an alert on demand, muted or not.
    func say(_ marker: RoadMarker) {
        let utterance = AVSpeechUtterance(string: marker.spokenTitle)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    private func announce(_ marker: RoadMarker) {
        let text = marker.spokenTitle
        lastAnnounced = text
        guard spoken else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func refresh() async {
        guard let box, !route.isEmpty else { return }
        guard let markers = try? await LiveData.markers(in: box) else { return }
        var found: [Upcoming] = []
        for m in markers {
            let p = Self.along(route, cumulative, m.coordinate)
            if p.offset <= m.corridorMeters {
                found.append(Upcoming(marker: m, alongMeters: p.along))
            }
        }
        all = found.sorted { $0.alongMeters < $1.alongMeters }
    }

    // MARK: geometry

    static func cumulativeDistances(_ pts: [CLLocationCoordinate2D]) -> [Double] {
        var out = [0.0]
        out.reserveCapacity(pts.count)
        for i in 1 ..< max(pts.count, 1) {
            out.append(out[i - 1] + meters(pts[i - 1], pts[i]))
        }
        return out
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let kx = 111_320.0 * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dy = (b.latitude - a.latitude) * 111_320.0
        let dx = (b.longitude - a.longitude) * kx
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Nearest point on the polyline: distance along it and offset from it.
    static func along(_ pts: [CLLocationCoordinate2D], _ cum: [Double],
                      _ p: CLLocationCoordinate2D) -> (along: Double, offset: Double) {
        guard pts.count >= 2 else { return (0, .infinity) }
        var best = (along: 0.0, offset: Double.infinity)
        let kx = 111_320.0 * cos(p.latitude * .pi / 180)
        let ky = 111_320.0
        // Coarse pass every 8th vertex, exact segment test around hits.
        var candidates: [Int] = []
        var i = 0
        while i < pts.count {
            if meters(pts[i], p) < 3000 { candidates.append(i) }
            i += 8
        }
        var checked = Set<Int>()
        for c in candidates {
            for j in max(0, c - 8) ..< min(pts.count - 1, c + 8) where !checked.contains(j) {
                checked.insert(j)
                let a = pts[j], b = pts[j + 1]
                let ax = (a.longitude - p.longitude) * kx, ay = (a.latitude - p.latitude) * ky
                let bx = (b.longitude - p.longitude) * kx, by = (b.latitude - p.latitude) * ky
                let dx = bx - ax, dy = by - ay
                let len2 = dx * dx + dy * dy
                let t = len2 == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / len2))
                let ox = ax + t * dx, oy = ay + t * dy
                let offset = (ox * ox + oy * oy).squareRoot()
                if offset < best.offset {
                    best = (cum[j] + t * (cum[j + 1] - cum[j]), offset)
                }
            }
        }
        return best
    }
}
