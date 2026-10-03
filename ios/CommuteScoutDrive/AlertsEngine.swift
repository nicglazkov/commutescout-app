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
/// With no destination there is no route to project onto, so the road
/// ahead is taken to be the direction of travel: a marker counts when
/// it lies ahead inside a narrow cone, and its distance along is its
/// distance straight ahead. The same rules and the same voice apply, so
/// a camera or a crash is called out on the way to the store too.
///
/// Projection is done once per location update and cached in
/// `hereAlong`; nothing here runs per frame, so a 500-mile route with
/// tens of thousands of vertices costs the same as a short one on screen.
/// The shared audio session while an alert is spoken: music ducks
/// (turns down) for the sentence and comes back after, podcasts pause
/// and resume. Nothing is stopped outright, and the session is let go
/// as soon as the voice is done. Ferrostar's turn-by-turn voice does
/// the same for its own sentences.
final class SpeechFocus: NSObject, AVSpeechSynthesizerDelegate {
    private var held = false

    func take() {
        guard !held else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            held = true
        } catch {
            DriveLog.note("audio: could not take focus: \(error.localizedDescription)")
        }
    }

    func release() {
        guard held else { return }
        held = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking { release() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking { release() }
    }
}

@MainActor
final class AlertsEngine: ObservableObject {
    struct Upcoming: Identifiable, Hashable {
        let marker: RoadMarker
        let alongMeters: Double     // distance along the route from its start
        var offsetMeters: Double = 0   // how far off the route line the marker sits
        var id: String { marker.key }
    }

    @Published private(set) var ahead: [Upcoming] = []
    /// Alerts the driver swiped away; they stay off the banner until a
    /// new trip or free drive starts, and still get spoken on schedule.
    @Published private(set) var dismissed: Set<String> = []

    func dismiss(_ id: String) { dismissed.insert(id) }

    /// What the banner shows: the nearest alert ahead that was not
    /// dismissed and is within `within` metres.
    func banner(within: Double) -> Upcoming? {
        ahead.first { !dismissed.contains($0.id) && $0.alongMeters - hereAlong <= within }
    }
    @Published private(set) var hereAlong: Double = 0
    @Published private(set) var lastAnnounced: String?
    /// Identical text is not repeated within this window: several markers can
    /// share one label (the same ramp closure recorded per lane).
    private var spokenAt: [String: Date] = [:]
    @Published var spoken = true
    var announceAheadMeters = 1500.0
    /// Per-kind rules from Settings; nil means the one distance above.
    var rules: ((RoadMarker) -> Prefs.AlertRule)?
    /// What the map is showing and how new it is. Used when the route's
    /// own fetch cannot reach the server, so a trip started without a
    /// signal still announces what the phone already knows.
    var fallback: (() -> (markers: [RoadMarker], asOf: Date?))?
    /// When the list in `all` was current.
    private var allAsOf: Date?

    private var route: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []
    private var all: [Upcoming] = []
    /// Free drive: no route, the markers around the car instead.
    private var freeDrive = false
    private var around: [RoadMarker] = []
    private var aroundCenter: CLLocationCoordinate2D?
    private var lastCourse: (degrees: Double, at: Date)?
    private var announced: Set<String> = []
    private var repeated: Set<String> = []
    private var timer: Timer?
    private var box: (south: Double, west: Double, north: Double, east: Double)?
    private var lastSegment = 0
    private let synth = AVSpeechSynthesizer()
    private let focus = SpeechFocus()

    static let refreshSeconds = 60.0

    /// Alerts with no destination. Runs from launch and again after
    /// every trip; a trip's `start` takes over from it.
    func startFreeDrive() {
        stop()
        dismissed = []
        freeDrive = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshSeconds, repeats: true) { [weak self] _ in
            Task { await self?.refreshAround() }
        }
    }

    func start(route coordinates: [CLLocationCoordinate2D]) {
        stop()
        route = coordinates
        cumulative = Self.cumulativeDistances(coordinates)
        lastSegment = 0
        dismissed = []
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let s = lats.min(), let n = lats.max(), let w = lons.min(), let e = lons.max() else { return }
        box = (s - 0.05, w - 0.05, n + 0.05, e + 0.05)
        announced = []
        repeated = []
        allAsOf = nil
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshSeconds, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// The route ahead of the driver as a sparse line: a vertex every
    /// `every` metres for the next `limit` metres, starting just behind
    /// where the driver is. Empty when no route is running.
    ///
    /// The server keeps this stretch warm for the community plugins and
    /// serves alerts along it to this phone alone. It never includes the
    /// destination: an hour of road ahead is all anyone needs to know.
    func stretchAhead(limit: Double = 60_000, every: Double = 5_000) -> [CLLocationCoordinate2D] {
        guard route.count > 1, cumulative.count == route.count else { return [] }
        var out: [CLLocationCoordinate2D] = []
        var lastAt = -every
        for i in lastSegment ..< route.count {
            let d = cumulative[i]
            if d < hereAlong - 500 { continue }
            if d - hereAlong > limit { break }
            if d - lastAt >= every {
                out.append(route[i])
                lastAt = d
            }
        }
        return out
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
        freeDrive = false
        around = []
        aroundCenter = nil
    }

    /// A fix with no trip running: the cone ahead of the car.
    func update(position: CLLocationCoordinate2D, course: Double?, speed: Double) {
        guard freeDrive else { return }
        // Moving away from where the markers were fetched for: fetch again.
        if let c = aroundCenter, Self.meters(c, position) > 4000 { aroundCenter = nil }
        if aroundCenter == nil, box == nil || Self.meters(box.map { CLLocationCoordinate2D(latitude: ($0.south + $0.north) / 2, longitude: ($0.west + $0.east) / 2) } ?? position, position) > 4000 {
            box = (position.latitude - 0.12, position.longitude - 0.15, position.latitude + 0.12, position.longitude + 0.15)
            aroundCenter = position
            Task { await refreshAround() }
        }
        // At a light the course goes away; the last one holds for a while.
        let now = Date()
        if let course, speed >= 1 { lastCourse = (course, now) }
        guard let heading = lastCourse, now.timeIntervalSince(heading.at) < 120 else {
            if !ahead.isEmpty { ahead = [] }
            return
        }
        let upcoming: [Upcoming] = around.compactMap { m in
            guard rules?(m).enabled ?? true, !m.tooMinorToAnnounce else { return nil }
            let d = Self.meters(position, m.coordinate)
            guard d <= 6000, d > 20 else { return nil }
            let off = Self.angleBetween(heading.degrees, Self.bearing(position, m.coordinate))
            // Straight ahead, or close and roughly ahead: a road bends.
            guard off <= 22 || (d < 400 && off <= 55) else { return nil }
            let along = d * cos(off * .pi / 180)
            let offset = d * sin(off * .pi / 180)
            guard offset <= max(m.corridorMeters, 120) else { return nil }
            // A closure for the other direction of a divided road is not ahead of this driver.
            if let h = Self.heading(of: m), Self.angleBetween(h, heading.degrees) > 110 { return nil }
            return Upcoming(marker: m, alongMeters: along, offsetMeters: offset)
        }.sorted { $0.alongMeters < $1.alongMeters }
        hereAlong = 0
        if upcoming != ahead { ahead = upcoming }
        announce(upcoming, from: 0)
    }

    /// What is around the car, for the cone. Without a signal the map's
    /// own markers stand in, as they do on a trip.
    private func refreshAround() async {
        guard freeDrive, let box else { return }
        do {
            around = try await LiveData.markers(in: box, kinds: LiveData.kinds)
        } catch {
            guard let saved = fallback?(), !saved.markers.isEmpty else { return }
            around = ShelfLife.prune(saved.markers, asOf: saved.asOf).filter {
                $0.lat >= box.south && $0.lat <= box.north && $0.lon >= box.west && $0.lon <= box.east
            }
        }
    }

    /// Called with each snapped location while navigating.
    func update(position: CLLocationCoordinate2D) {
        guard !route.isEmpty else { return }
        let hit = Self.along(route, cumulative, position, near: lastSegment)
        lastSegment = hit.segment
        hereAlong = hit.along
        let upcoming = all.filter { $0.alongMeters > hit.along - 100 && (rules?($0.marker).enabled ?? true) }
        if upcoming != ahead { ahead = upcoming }
        announce(upcoming, from: hit.along)
    }

    /// Each marker once when it comes within its first distance, and
    /// once more within its second, by the per-kind rules.
    private func announce(_ upcoming: [Upcoming], from along: Double) {
        for item in upcoming {
            // A public plugin nobody reviewed shows and is listed, but it
            // does not speak unless a rule of the driver's says so; the
            // settings text promises exactly that.
            let quiet = item.marker.kind == "plugin" && !["approved", "private"].contains(item.marker.tier ?? "")
            let rule = rules?(item.marker) ?? Prefs.AlertRule(enabled: true, speak: spoken && !quiet, firstMeters: announceAheadMeters, repeatMeters: 0)
            let gap = item.alongMeters - along
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
        speak(utterance)
    }

    /// Every sentence goes out the same way: take the audio focus
    /// (music ducks), say it, give the focus back when done.
    private func speak(_ utterance: AVSpeechUtterance) {
        if synth.delegate == nil { synth.delegate = focus }
        focus.take()
        synth.speak(utterance)
    }

    private func announce(_ marker: RoadMarker, in gap: Double) {
        let text = marker.spokenTitle + (gap > 200 ? ", in " + Units.spoken(gap) : "")
        if let t = spokenAt[marker.spokenTitle], Date().timeIntervalSince(t) < 90 { return }
        spokenAt[marker.spokenTitle] = Date()
        lastAnnounced = text
        DriveLog.note("alert spoken: \(marker.kind) '\(marker.displayTitle)' in \(DriveLog.meters(gap))")
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speak(utterance)
    }

    /// Fetch again now: the signal came back.
    func refreshNow() {
        guard box != nil else { return }
        Task { await refresh() }
    }

    private func refresh() async {
        guard let box else { return }
        let markers: [RoadMarker]
        let asOf: Date
        do {
            markers = try await LiveData.markers(in: box, kinds: LiveData.kinds)
            asOf = Date()
        } catch {
            // No answer. A list fetched earlier on this trip covers the
            // whole route, so it is kept, less whatever has gone stale
            // for its kind since. With none, because the trip began
            // without a signal, the map's own markers stand in.
            if let was = allAsOf, !all.isEmpty {
                let age = Date().timeIntervalSince(was)
                let kept = age > 15 * 60 ? all.filter { ShelfLife.keep($0.marker.kind, age: age) } : all
                if kept.count != all.count {
                    DriveLog.note("alerts: offline, \(all.count - kept.count) gone stale on the route")
                    all = kept
                }
                return
            }
            guard let saved = fallback?(), !saved.markers.isEmpty else { return }
            markers = ShelfLife.prune(saved.markers, asOf: saved.asOf)
            asOf = saved.asOf ?? Date()
            DriveLog.note("alerts: no answer from the server, using \(markers.count) markers the map already had")
        }
        let pts = route, cum = cumulative
        let found: [Upcoming] = await Task.detached(priority: .utility) {
            markers.compactMap { m in
                if m.tooMinorToAnnounce { return nil }
                let hit = Self.along(pts, cum, m.coordinate, near: nil)
                guard hit.offset <= m.corridorMeters else { return nil }
                // A closure for the other direction of a divided road is not ahead of this driver.
                if let h = Self.heading(of: m), hit.segment + 1 < pts.count {
                    let rb = Self.bearing(pts[hit.segment], pts[hit.segment + 1])
                    if Self.angleBetween(h, rb) > 110 { return nil }
                }
                return Upcoming(marker: m, alongMeters: hit.along, offsetMeters: hit.offset)
            }.sorted { $0.alongMeters < $1.alongMeters }
        }.value
        all = found
        allAsOf = asOf
    }

    // MARK: geometry (plain functions, safe off the main actor)

    /// The direction a marker applies to, as a compass bearing, from its
    /// `dir` field or a "(northbound)" / "NB" in its label. Nil when it
    /// applies to both directions or says nothing.
    nonisolated static func heading(of m: RoadMarker) -> Double? {
        // The server's dir field: "North", "NB", "N"... and only that word.
        if let d = m.dir?.trimmingCharacters(in: .whitespaces).lowercased(), !d.isEmpty {
            if d.hasPrefix("both") || d.contains("/") || d.contains("&") { return nil }
            switch d.first {
            case "n": return 0
            case "e": return 90
            case "s": return 180
            case "w": return 270
            default: break
            }
        }
        // Otherwise a "(northbound)" or "NB" in the label; two directions say nothing.
        let text = " " + m.displayTitle.lowercased()
        let table: [(String, Double)] = [("northbound", 0), ("eastbound", 90), ("southbound", 180), ("westbound", 270),
                                          (" nb", 0), (" eb", 90), (" sb", 180), (" wb", 270)]
        let found = table.filter { text.contains($0.0) }.map(\.1)
        return found.count == 1 ? found[0] : nil
    }

    nonisolated static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let k = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dx = (b.longitude - a.longitude) * k, dy = b.latitude - a.latitude
        let deg = atan2(dx, dy) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    nonisolated static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

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
