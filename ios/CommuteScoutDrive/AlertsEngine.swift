import AVFoundation
import CoreLocation
import Foundation

/// Live alerts while driving. Every 60 seconds the engine reads the
/// markers inside the route's box, projects each onto the route, keeps
/// those within a corridor (300 m for incidents and closures, 1 km for
/// chain controls, 12 km for fires), orders them by distance along the
/// route, and announces each one once when it is about a minute ahead.
/// The same list feeds the strip under the maneuver card.
///
/// Projection is done once per location update and cached in
/// `hereAlong`; nothing here runs per frame, so a 500-mile route with
/// tens of thousands of vertices costs the same as a short one on screen.
@MainActor
final class AlertsEngine: ObservableObject {
    struct Upcoming: Identifiable, Hashable {
        let marker: RoadMarker
        let alongMeters: Double     // distance along the route from its start
        var id: String { marker.key }
    }

    @Published private(set) var ahead: [Upcoming] = []
    @Published private(set) var hereAlong: Double = 0
    @Published private(set) var lastAnnounced: String?
    @Published var spoken = true
    var announceAheadMeters = 1500.0
    /// Per-kind rules from Settings; nil means the one distance above.
    var rules: ((RoadMarker) -> Prefs.AlertRule)?

    private var route: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []
    private var all: [Upcoming] = []
    private var announced: Set<String> = []
    private var repeated: Set<String> = []
    private var timer: Timer?
    private var box: (south: Double, west: Double, north: Double, east: Double)?
    private var lastSegment = 0
    private let synth = AVSpeechSynthesizer()

    static let refreshSeconds = 60.0

    func start(route coordinates: [CLLocationCoordinate2D]) {
        stop()
        route = coordinates
        cumulative = Self.cumulativeDistances(coordinates)
        lastSegment = 0
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let s = lats.min(), let n = lats.max(), let w = lons.min(), let e = lons.max() else { return }
        box = (s - 0.05, w - 0.05, n + 0.05, e + 0.05)
        announced = []
        repeated = []
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
        hereAlong = 0
        box = nil
    }

    /// Called with each snapped location while navigating.
    func update(position: CLLocationCoordinate2D) {
        guard !route.isEmpty else { return }
        let hit = Self.along(route, cumulative, position, near: lastSegment)
        lastSegment = hit.segment
        hereAlong = hit.along
        let upcoming = all.filter { $0.alongMeters > hit.along - 100 && (rules?($0.marker).enabled ?? true) }
        if upcoming != ahead { ahead = upcoming }
        for item in upcoming {
            let rule = rules?(item.marker) ?? Prefs.AlertRule(enabled: true, speak: spoken, firstMeters: announceAheadMeters, repeatMeters: 0)
            let gap = item.alongMeters - hit.along
            if !announced.contains(item.id), gap <= rule.firstMeters, gap > -100 {
                announced.insert(item.id)
                if rule.speak { announce(item.marker, in: gap) }
            } else if announced.contains(item.id), !repeated.contains(item.id), rule.repeatMeters > 0,
                      gap <= rule.repeatMeters, gap > -100 {
                repeated.insert(item.id)
                if rule.speak { announce(item.marker, in: gap) }
            }
        }
    }

    /// Repeat an alert on demand, muted or not.
    func say(_ marker: RoadMarker) {
        DriveLog.note("say (tap): \(marker.kind) \(marker.displayTitle)")
        let utterance = AVSpeechUtterance(string: marker.spokenTitle)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    private func announce(_ marker: RoadMarker, in gap: Double) {
        let text = marker.spokenTitle + (gap > 200 ? ", in " + Units.spoken(gap) : "")
        lastAnnounced = text
        DriveLog.note("alert spoken: \(marker.kind) '\(marker.displayTitle)' in \(DriveLog.meters(gap))")
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    private func refresh() async {
        guard let box else { return }
        guard let markers = try? await LiveData.markers(in: box, kinds: LiveData.kinds) else { return }
        let pts = route, cum = cumulative
        let found: [Upcoming] = await Task.detached(priority: .utility) {
            markers.compactMap { m in
                let hit = Self.along(pts, cum, m.coordinate, near: nil)
                return hit.offset <= m.corridorMeters ? Upcoming(marker: m, alongMeters: hit.along) : nil
            }.sorted { $0.alongMeters < $1.alongMeters }
        }.value
        all = found
    }

    // MARK: geometry (plain functions, safe off the main actor)

    nonisolated static func cumulativeDistances(_ pts: [CLLocationCoordinate2D]) -> [Double] {
        var out = [Double](repeating: 0, count: pts.count)
        if pts.count > 1 {
            for i in 1 ..< pts.count { out[i] = out[i - 1] + meters(pts[i - 1], pts[i]) }
        }
        return out
    }

    nonisolated static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let k = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dx = (b.longitude - a.longitude) * 111_320 * k
        let dy = (b.latitude - a.latitude) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Nearest point on the polyline: distance along it, offset from it,
    /// and the segment index. With `near`, a window around the last
    /// segment is searched first (the driver moves forward); the full
    /// coarse pass is the fallback.
    nonisolated static func along(_ pts: [CLLocationCoordinate2D], _ cum: [Double], _ p: CLLocationCoordinate2D,
                                  near: Int?) -> (along: Double, offset: Double, segment: Int) {
        guard pts.count >= 2 else { return (0, .infinity, 0) }
        let kx = 111_320.0 * cos(p.latitude * .pi / 180), ky = 111_320.0
        var best = (along: 0.0, offset: Double.infinity, segment: 0)
        func test(_ j: Int) {
            let a = pts[j], b = pts[j + 1]
            let ax = (a.longitude - p.longitude) * kx, ay = (a.latitude - p.latitude) * ky
            let bx = (b.longitude - p.longitude) * kx, by = (b.latitude - p.latitude) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / len2))
            let ox = ax + t * dx, oy = ay + t * dy
            let offset = (ox * ox + oy * oy).squareRoot()
            if offset < best.offset { best = (cum[j] + t * (cum[j + 1] - cum[j]), offset, j) }
        }
        if let near {
            for j in max(0, near - 20) ..< min(pts.count - 1, near + 60) { test(j) }
            if best.offset < 120 { return best }
        }
        best = (0, .infinity, 0)
        var i = 0
        while i < pts.count {
            if meters(pts[i], p) < 3000 {
                for j in max(0, i - 8) ..< min(pts.count - 1, i + 8) { test(j) }
            }
            i += 8
        }
        return best
    }
}
