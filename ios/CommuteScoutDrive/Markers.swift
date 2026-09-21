import Combine
import CoreLocation
import MapLibre
import SwiftUI
import UIKit

/// The road markers the website draws.
///
/// Two paths fill this store, and both are needed. At launch the
/// published snapshot is fetched straight from the CDN, decoded off the
/// main thread and painted at once: that happens in parallel with the
/// map loading and the camera zooming to the driver, so the dots are
/// there when the camera lands. The snapshot is slim, so as soon as the
/// view settles the usual viewport call to /api/mapdata runs and takes
/// over, bringing the closure stretches and toll corridors the snapshot
/// drops. After that the viewport is refreshed every minute, filtered
/// by the Layers sheet. Nothing is fetched while zoomed out past a
/// state.
@MainActor
final class MarkerStore: ObservableObject {
    @Published private(set) var markers: [RoadMarker] = []
    @Published private(set) var loading = false
    /// Bumped whenever `markers` is replaced, so views can cache the
    /// shapes they build from it instead of rebuilding every frame.
    @Published private(set) var stamp = 0
    private var byKey: [String: RoadMarker] = [:]
    private var box: (s: Double, w: Double, n: Double, e: Double)?
    private var kinds = ""
    private var fetchedAt = Date.distantPast
    private var task: Task<Void, Never>?
    private var timer: Timer?
    // After a failed fetch, a 429 or a 5xx the timed refresh waits: two
    // minutes, then double each time up to ten; a success resets it.
    private var backoff: TimeInterval = 0
    private var holdUntil = Date.distantPast
    // The launch snapshot: held only until the first viewport answer
    // lands, and kept on screen if that answer never comes.
    private var snapshot: [String: RoadMarker] = [:]
    private var snapshotRetired = false
    private var bootStarted: Date?
    private var bootBox: GeoBox?
    private var fetchedFeeds: Set<Snapshot.Feed> = []

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date() >= self.holdUntil else { return }
                self.refresh(force: true)
            }
        }
    }

    func marker(for key: String) -> RoadMarker? { byKey[key] }

    // MARK: launch snapshot

    /// Start the launch fetch. Called from the app model, not from the
    /// map, so it runs while the map is still loading its style and the
    /// camera is still animating.
    ///
    /// Everything that is switched on by default rides in the two small
    /// bundles. Cameras are their own object, about half a megabyte, and
    /// are only asked for when that layer is on.
    func boot(near center: CLLocationCoordinate2D, cameras: Bool) {
        guard bootStarted == nil else { return }
        bootStarted = Date()
        let area = GeoBox.around(center)
        bootBox = area
        DriveLog.note("snapshot: boot around " + String(format: "%.3f,%.3f", center.latitude, center.longitude))
        load(.live, box: area)
        load(.signs, box: area)
        if cameras { load(.cameras, box: area) }
    }

    /// Fetch one bundle once per session. Turning the camera layer on
    /// later calls this; the viewport refresh that the toggle also
    /// triggers is what keeps it current.
    func load(_ feed: Snapshot.Feed, box: GeoBox? = nil) {
        // Once the viewport is answering, /api/mapdata is both fresher
        // and far smaller than a nationwide object. The snapshot's job
        // is the first paint, and it is over.
        guard !snapshotRetired, !fetchedFeeds.contains(feed) else { return }
        fetchedFeeds.insert(feed)
        let area = box ?? bootBox
        Task { [weak self] in
            do {
                let payload = try await Snapshot.fetch(feed, box: area)
                self?.seed(feed, payload)
            } catch {
                self?.fetchedFeeds.remove(feed)
                DriveLog.note("snapshot: \(feed.rawValue) failed, \(error)")
            }
        }
    }

    /// Paint what a bundle brought. The bundles add up: live, signs and
    /// cameras each carry their own kinds.
    private func seed(_ feed: Snapshot.Feed, _ payload: SnapshotPayload) {
        let waited = bootStarted.map { Date().timeIntervalSince($0) } ?? 0
        let age = payload.published.map { Int(Date().timeIntervalSince($0)) }
        DriveLog.note("snapshot: \(feed.rawValue) gave \(payload.markers.count) markers "
                      + String(format: "%.2f s after launch", waited)
                      + (age.map { ", published \($0) s ago" } ?? "")
                      + (payload.degraded ? ", publisher reports degraded feeds" : ""))
        guard !snapshotRetired else { return }   // the viewport answer is the fresher one
        for marker in payload.markers { snapshot[marker.key] = marker }
        publish(Array(snapshot.values))
    }

    private func publish(_ found: [RoadMarker]) {
        markers = found
        byKey = Dictionary(found.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        stamp &+= 1
    }

    /// The visible area changed. Fetch when it moved outside the last box
    /// or the layer set changed; the box carries a margin so small pans
    /// do not hit the server.
    func view(bounds: MLNCoordinateBounds, zoom: Double, kinds: String) {
        guard zoom >= 5.5, !kinds.isEmpty else {
            if kinds.isEmpty { publish([]) }
            return
        }
        let latPad = (bounds.ne.latitude - bounds.sw.latitude) * 0.5
        let lonPad = (bounds.ne.longitude - bounds.sw.longitude) * 0.5
        let inside = box.map { b in
            bounds.sw.latitude >= b.s && bounds.sw.longitude >= b.w && bounds.ne.latitude <= b.n && bounds.ne.longitude <= b.e
        } ?? false
        if inside && kinds == self.kinds && Date().timeIntervalSince(fetchedAt) < 60 { return }
        box = (bounds.sw.latitude - latPad, bounds.sw.longitude - lonPad, bounds.ne.latitude + latPad, bounds.ne.longitude + lonPad)
        self.kinds = kinds
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard let b = box, !kinds.isEmpty else { return }
        task?.cancel()
        task = Task { [kinds] in
            if !force { try? await Task.sleep(nanoseconds: 350_000_000) }   // let the pan settle
            guard !Task.isCancelled else { return }
            loading = true
            defer { loading = false }
            let result = await Task { try await LiveData.markers(in: (b.s, b.w, b.n, b.e), kinds: kinds) }.result
            if case let .failure(e) = result {
                NSLog("CS markers fetch failed: %@", String(describing: e))
                if case let BackendError.status(code) = e, code != 429, code < 500 { return }   // not a server problem
                backoff = min(600, backoff == 0 ? 120 : backoff * 2)
                holdUntil = Date().addingTimeInterval(backoff)
                DriveLog.note("markers: fetch failed, next timed refresh in \(Int(backoff)) s")
            }
            if case let .success(found) = result, !Task.isCancelled {
                DriveLog.note("markers: \(found.count) in box")
                // The viewport answer carries the closure stretches and
                // toll corridors the snapshot drops, so it replaces the
                // snapshot outright. A failed fetch leaves the snapshot
                // up rather than blanking the map.
                snapshotRetired = true
                snapshot = [:]
                publish(found)
                fetchedAt = Date()
                backoff = 0
                holdUntil = .distantPast
            }
        }
    }
}

/// One icon per marker kind, drawn once: a colored disc with a white glyph.
enum MarkerIcons {
    static let color: [String: UIColor] = [
        "incident": UIColor(red: 0.95, green: 0.62, blue: 0.10, alpha: 1),
        "lane_closure": UIColor(red: 0.84, green: 0.19, blue: 0.19, alpha: 1),
        "chain_control": UIColor(red: 0.16, green: 0.45, blue: 0.85, alpha: 1),
        "wildfire": UIColor(red: 0.90, green: 0.35, blue: 0.10, alpha: 1),
        "plugin": UIColor(red: 0.45, green: 0.30, blue: 0.80, alpha: 1),
        // The website's four reference layers, in its colours.
        "camera": UIColor(red: 0.18, green: 0.51, blue: 0.97, alpha: 1),      // #2f81f7
        "sign": UIColor(red: 0.63, green: 0.38, blue: 0.03, alpha: 1),        // #a16207
        "rwis": UIColor(red: 0.18, green: 0.62, blue: 0.43, alpha: 1),        // #2f9e6e
        "toll": UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1),        // #7c3aed
    ]
    static let symbol: [String: String] = [
        "incident": "exclamationmark.triangle.fill",
        "lane_closure": "xmark.octagon.fill",
        "chain_control": "snowflake",
        "wildfire": "flame.fill",
        "plugin": "person.2.fill",
        "camera": "video.fill",
        "sign": "text.bubble.fill",
        "rwis": "thermometer.snowflake",
        "toll": "dollarsign.circle.fill",
    ]
    static let kinds = ["incident", "lane_closure", "chain_control", "wildfire", "plugin",
                        "camera", "sign", "rwis", "toll"]

    /// The word the card puts above the title, the same as the website's
    /// popup chip.
    static let heading: [String: String] = [
        "incident": "INCIDENT",
        "lane_closure": "CLOSURE",
        "chain_control": "CHAIN CONTROL",
        "wildfire": "WILDFIRE",
        "plugin": "COMMUNITY REPORT",
        "camera": "LIVE CAMERA",
        "sign": "MESSAGE SIGN",
        "rwis": "ROAD WEATHER",
        "toll": "TOLL PRICE",
    ]

    static func tint(_ kind: String) -> Color { Color(color[kind] ?? .gray) }
    static func name(_ kind: String) -> String { symbol[kind] ?? "mappin.circle.fill" }

    static let images: [String: UIImage] = {
        var out: [String: UIImage] = [:]
        for k in kinds {
            let size = CGSize(width: 30, height: 30)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                (color[k] ?? .gray).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5))
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
                if let glyph = UIImage(systemName: symbol[k] ?? "mappin", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let r = CGRect(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2,
                                   width: glyph.size.width, height: glyph.size.height)
                    glyph.draw(in: r)
                }
            }
            out[k] = img
        }
        return out
    }()
}

/// What a tapped marker says: the website's popup, on the phone.
struct MarkerCard: View {
    @EnvironmentObject var model: AppModel
    let marker: RoadMarker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: MarkerIcons.name(marker.kind)).font(.title2).foregroundStyle(MarkerIcons.tint(marker.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.displayTitle).font(.headline).lineLimit(3)
                    ForEach(marker.detailLines, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                    if let here = model.here {
                        Text(Units.distance(AlertsEngine.meters(here, marker.coordinate)) + " from you")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.clearMarker() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("marker-close")
            }
            HStack(spacing: 8) {
                Button {
                    model.show(Place(name: marker.displayTitle, coordinate: marker.coordinate, kind: .recent))
                } label: {
                    Label("Navigate here", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                if marker.kind == "plugin" {
                    ConfirmButtons(marker: marker)
                }
                ShareLink(item: marker.webURL) {
                    Image(systemName: "square.and.arrow.up").padding(.vertical, 10).padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }
}

/// "Still there" and "Gone" for a community report: the vote goes to the
/// plugin through commutescout.com and moves its confirmation count.
struct ConfirmButtons: View {
    @EnvironmentObject var model: AppModel
    let marker: RoadMarker
    @State private var voted: String?
    @State private var showSignIn = false

    var body: some View {
        HStack(spacing: 6) {
            Button { Task { await vote("up") } } label: { Image(systemName: voted == "up" ? "hand.thumbsup.fill" : "hand.thumbsup") }
                .accessibilityIdentifier("confirm-up")
            Button { Task { await vote("gone") } } label: { Image(systemName: voted == "gone" ? "xmark.circle.fill" : "xmark.circle") }
                .accessibilityIdentifier("confirm-gone")
        }
        .buttonStyle(.bordered)
        .disabled(voted != nil)
        .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to confirm reports.") }
    }

    private func vote(_ v: String) async {
        guard let id = marker.id else { return }
        guard let token = await model.account.token() else { showSignIn = true; return }
        do {
            try await model.reporter.confirm(alertId: id, vote: v, token: token)
            voted = v
            model.toast = v == "up" ? "Thanks, confirmed." : "Thanks, marked as gone."
            DriveLog.note("confirm \(v): \(id)")
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

