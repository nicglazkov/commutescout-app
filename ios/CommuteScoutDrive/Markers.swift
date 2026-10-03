import AVKit
import Combine
import CoreLocation
import MapLibre
import SwiftUI
import UIKit

/// The road markers the website draws, held for the whole country.
///
/// Two paths fill this store and both keep running. At launch the
/// published snapshot is fetched from the CDN, decoded off the main
/// thread and painted at once: that happens in parallel with the map
/// loading and the camera zooming to the driver, so the dots are there
/// when the camera lands, at any zoom. As soon as the view settles the
/// viewport call to /api/mapdata runs for the area on screen, bringing
/// the closure stretches and toll corridors the snapshot drops, and is
/// repeated every minute; the snapshot is read again every five.
///
/// Neither answer replaces the other outright. Inside the box the
/// viewport call owns, its answer is the truth for the kinds it asked
/// for; everywhere else the snapshot is. A marker is added or removed
/// by key, so zooming out never empties the map and zooming back in
/// never makes it blink.
@MainActor
final class MarkerStore: ObservableObject {
    @Published private(set) var markers: [RoadMarker] = []
    @Published private(set) var loading = false
    /// Bumped whenever `markers` is replaced, so views can cache the
    /// shapes they build from it instead of rebuilding every frame.
    @Published private(set) var stamp = 0
    /// How new the markers on screen are: the newest answer that
    /// reached them. Shown in the offline banner.
    @Published private(set) var asOf: Date?

    private enum Origin { case snapshot, viewport }
    private struct Held { var marker: RoadMarker; var origin: Origin; var at: Date }
    private var held: [String: Held] = [:]
    /// Bundles that painted from the network this session. One that
    /// failed or came from the saved copy is fetched again when the
    /// signal comes back.
    private var liveFeeds: Set<Snapshot.Feed> = []
    private var wantedFeeds: Set<Snapshot.Feed> = []
    private var fetchedFeeds: Set<Snapshot.Feed> = []
    private var feedAt: [Snapshot.Feed: Date] = [:]
    private var box: (s: Double, w: Double, n: Double, e: Double)?
    private var kinds = ""
    private var fetchedAt = Date.distantPast
    private var task: Task<Void, Never>?
    private var timer: Timer?
    // After a failed fetch, a 429 or a 5xx the timed refresh waits: two
    // minutes, then double each time up to ten; a success resets it.
    private var backoff: TimeInterval = 0
    private var holdUntil = Date.distantPast
    private var bootStarted: Date?

    /// The viewport is asked again this often, and a bundle this often.
    static let viewportEvery: TimeInterval = 60
    static let snapshotEvery: TimeInterval = 5 * 60
    /// Below this zoom the view is a region or the country: the
    /// viewport call would be the whole snapshot again, so only the
    /// snapshot runs.
    static let viewportFromZoom = 5.5

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.viewportEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !Connectivity.shared.online { self.pruneStale(); return }
                for feed in self.wantedFeeds where Date().timeIntervalSince(self.feedAt[feed] ?? .distantPast) >= Self.snapshotEvery {
                    self.load(feed, again: true)
                }
                guard Date() >= self.holdUntil else { return }
                self.refresh(force: true)
            }
        }
        Connectivity.shared.onReconnect { [weak self] in self?.reconnected() }
    }

    /// Without a signal nothing on screen gets newer, so what has gone
    /// stale for its kind (a police report after half an hour) is taken
    /// off rather than shown as if it were current.
    func pruneStale() {
        let now = Date()
        let before = held.count
        held = held.filter { ShelfLife.keep($0.value.marker.kind, age: now.timeIntervalSince($0.value.at)) }
        if held.count != before {
            DriveLog.note("markers: offline, \(before - held.count) gone stale")
            publish()
        }
    }

    /// The signal is back: catch up at once rather than at the next tick.
    private func reconnected() {
        backoff = 0
        holdUntil = .distantPast
        for feed in wantedFeeds.subtracting(liveFeeds) { load(feed, again: true) }
        refresh(force: true)
    }

    func marker(for key: String) -> RoadMarker? { held[key]?.marker }

    // MARK: snapshot

    /// Start the launch fetch. Called from the app model, not from the
    /// map, so it runs while the map is still loading its style and the
    /// camera is still animating.
    ///
    /// Everything that is switched on by default rides in the two small
    /// bundles. Cameras are their own object, about half a megabyte, and
    /// are only asked for when that layer is on.
    func boot(cameras: Bool) {
        guard bootStarted == nil else { return }
        bootStarted = Date()
        load(.live)
        load(.signs)
        if cameras { load(.cameras) }
    }

    /// Fetch one bundle: once per session on its own, or again on the
    /// snapshot period. Turning the camera layer on later calls this.
    func load(_ feed: Snapshot.Feed, again: Bool = false) {
        wantedFeeds.insert(feed)
        guard again || !fetchedFeeds.contains(feed) else { return }
        fetchedFeeds.insert(feed)
        feedAt[feed] = Date()
        Task { [weak self] in
            do {
                let payload = try await Snapshot.fetch(feed, box: nil)
                self?.seed(feed, payload)
            } catch {
                self?.fetchedFeeds.remove(feed)
                DriveLog.note("snapshot: \(feed.rawValue) failed, \(error)")
            }
        }
    }

    /// Paint what a bundle brought. The bundle is the truth for its
    /// kinds everywhere but inside the box the viewport call owns.
    private func seed(_ feed: Snapshot.Feed, _ payload: SnapshotPayload) {
        let waited = bootStarted.map { Date().timeIntervalSince($0) } ?? 0
        let age = payload.published.map { Int(Date().timeIntervalSince($0)) }
        DriveLog.note("snapshot: \(feed.rawValue) gave \(payload.markers.count) markers "
                      + String(format: "%.2f s after launch", waited)
                      + (age.map { ", published \($0) s ago" } ?? "")
                      + (payload.degraded ? ", publisher reports degraded feeds" : ""))
        if payload.savedAt == nil { liveFeeds.insert(feed) }
        let stamp = payload.asOf ?? Date()
        let kinds = Set(payload.markers.map(\.kind))
        held = held.filter { _, h in
            guard kinds.contains(h.marker.kind) else { return true }
            // Inside the box, the viewport answer stays: it carries the
            // road-following lines the bundle drops, and is newer.
            return h.origin == .viewport && inBox(h.marker)
        }
        for m in payload.markers where held[m.key] == nil {
            held[m.key] = Held(marker: m, origin: .snapshot, at: stamp)
        }
        if asOf.map({ stamp > $0 }) ?? true { asOf = stamp }
        publish()
    }

    private func inBox(_ m: RoadMarker) -> Bool {
        guard let b = box else { return false }
        return m.lat >= b.s && m.lat <= b.n && m.lon >= b.w && m.lon <= b.e
    }

    private func publish() {
        markers = held.values.map(\.marker)
        stamp &+= 1
    }

    // MARK: viewport

    /// The visible area changed. Fetch when it moved outside the last box
    /// or the layer set changed; the box carries a margin so small pans
    /// do not hit the server. Zoomed out past a state nothing is fetched
    /// and nothing is dropped: the snapshot is the map there.
    func view(bounds: MLNCoordinateBounds, zoom: Double, kinds: String) {
        guard zoom >= Self.viewportFromZoom, !kinds.isEmpty else { return }
        let latPad = (bounds.ne.latitude - bounds.sw.latitude) * 0.5
        let lonPad = (bounds.ne.longitude - bounds.sw.longitude) * 0.5
        let inside = box.map { b in
            bounds.sw.latitude >= b.s && bounds.sw.longitude >= b.w && bounds.ne.latitude <= b.n && bounds.ne.longitude <= b.e
        } ?? false
        if inside && kinds == self.kinds && Date().timeIntervalSince(fetchedAt) < Self.viewportEvery { return }
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
                take(found, kinds: kinds, box: b)
                fetchedAt = Date()
                asOf = fetchedAt
                backoff = 0
                holdUntil = .distantPast
            }
        }
    }

    /// The viewport answer is the truth inside its box for the kinds it
    /// asked for: what is there and not in it is gone, what is in it is
    /// current, and everything outside the box is left alone.
    private func take(_ found: [RoadMarker], kinds: String, box b: (s: Double, w: Double, n: Double, e: Double)) {
        let asked = Set(kinds.split(separator: ",").map { Prefs.emittedKind(String($0)) })
        let now = Date()
        held = held.filter { _, h in
            let m = h.marker
            let inside = m.lat >= b.s && m.lat <= b.n && m.lon >= b.w && m.lon <= b.e
            return !(inside && asked.contains(m.kind))
        }
        for m in found { held[m.key] = Held(marker: m, origin: .viewport, at: now) }
        publish()
    }
}

/// How a plugin's alerts look, everywhere they show.
///
/// Official agency data is a round icon. A plugin alert is a rounded
/// square badge instead: the picture says what the alert is, the color
/// says which plugin it came from. The website draws the same thing
/// (plugin-badges.js), with the same colors and categories.
enum PluginStyle {
    /// The plugins CommuteScout runs get fixed colors; any other plugin
    /// gets one from its id, so it is the same on every launch.
    private static let known: [String: UIColor] = [
        "wz-flare": UIColor(red: 0.11, green: 0.31, blue: 0.85, alpha: 1),      // #1d4ed8
        "osm-cameras": UIColor(red: 0.92, green: 0.35, blue: 0.05, alpha: 1),   // #ea580c
    ]
    private static let palette: [UIColor] = [
        UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1), UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1),
        UIColor(red: 0.75, green: 0.07, blue: 0.24, alpha: 1), UIColor(red: 0.30, green: 0.49, blue: 0.06, alpha: 1),
        UIColor(red: 0.63, green: 0.38, blue: 0.03, alpha: 1), UIColor(red: 0.01, green: 0.41, blue: 0.63, alpha: 1),
    ]

    static func color(_ sourceId: String) -> UIColor {
        if let c = known[sourceId] { return c }
        var h: UInt32 = 0
        for u in sourceId.unicodeScalars { h = h &* 31 &+ u.value }
        return palette[Int(h % UInt32(palette.count))]
    }

    /// The plugin a marker came from: the part of its id before the colon.
    static func sourceId(_ m: RoadMarker) -> String {
        if let id = m.id, let colon = id.firstIndex(of: ":") { return String(id[..<colon]) }
        return m.source ?? "plugin"
    }

    static func category(_ flareKind: String?) -> String {
        let k = (flareKind ?? "").uppercased()
        if k.hasPrefix("POLICE") { return "police" }
        if k.hasPrefix("CRASH") { return "crash" }
        if k.hasPrefix("CAMERA") { return "camera" }
        if k.hasPrefix("JAM") { return "jam" }
        if k.hasPrefix("WEATHER") { return "weather" }
        if k.hasPrefix("ROAD_CLOSED") || k.hasPrefix("LANE_CLOSED") || k.hasPrefix("RAMP_CLOSED") { return "closed" }
        if k.hasPrefix("CHAINS") { return "chains" }
        if k.hasPrefix("HAZARD") { return "hazard" }
        return "other"
    }

    static func symbol(_ category: String) -> String {
        switch category {
        case "police": "shield.fill"
        case "crash": "car.side.rear.and.collision.and.car.side.front"
        case "camera": "camera.fill"
        case "jam": "car.2.fill"
        case "weather": "cloud.fill"
        case "closed": "minus.circle.fill"
        case "chains": "link"
        case "hazard": "exclamationmark.triangle.fill"
        default: "circle.fill"
        }
    }

    /// What names a badge: the plugin and the category, in a form that is
    /// safe inside a layer identifier.
    static func key(_ m: RoadMarker) -> String {
        let id = sourceId(m).map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(id) + "_" + category(m.flareKind)
    }

    private static var cache: [String: UIImage] = [:]

    /// The badge for one plugin and category, drawn once.
    static func image(sourceId: String, category: String) -> UIImage {
        let cacheKey = sourceId + "|" + category
        if let hit = cache[cacheKey] { return hit }
        let size = CGSize(width: 30, height: 30)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9).fill()
            color(sourceId).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5), cornerRadius: 7).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            let glyph = (UIImage(systemName: symbol(category), withConfiguration: config)
                ?? UIImage(systemName: "circle.fill", withConfiguration: config))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let glyph {
                // Some symbols are wider than the badge; fit them inside.
                let scale = min(1, 20 / max(glyph.size.width, glyph.size.height))
                let w = glyph.size.width * scale, h = glyph.size.height * scale
                glyph.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
        }
        cache[cacheKey] = img
        return img
    }

    static func image(for m: RoadMarker) -> UIImage { image(sourceId: sourceId(m), category: category(m.flareKind)) }
}

/// A plugin's badge in a list or a card: the same picture as on the map.
struct PluginBadge: View {
    let sourceId: String
    let category: String?
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color(PluginStyle.color(sourceId)))
            .frame(width: size, height: size)
            .overlay {
                if let category {
                    Image(systemName: PluginStyle.symbol(category)).resizable().scaledToFit()
                        .foregroundStyle(.white).padding(size * 0.22)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The icon beside a marker in a list or a card: a plugin badge for a
/// plugin alert, the kind's own symbol for everything else.
struct MarkerGlyph: View {
    let marker: RoadMarker
    var size: CGFloat = 22

    var body: some View {
        if marker.kind == "plugin" {
            PluginBadge(sourceId: PluginStyle.sourceId(marker), category: PluginStyle.category(marker.flareKind), size: size)
        } else {
            Image(systemName: MarkerIcons.name(marker.kind)).font(.system(size: size * 0.85))
                .foregroundStyle(MarkerIcons.tint(marker.kind))
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
                MarkerGlyph(marker: marker, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    if marker.kind == "plugin" {
                        Text((marker.source ?? "Plugin").uppercased()).font(.caption2.weight(.bold))
                            .foregroundStyle(Color(PluginStyle.color(PluginStyle.sourceId(marker)))).lineLimit(1)
                    } else if let heading = MarkerIcons.heading[marker.kind] {
                        Text(heading).font(.caption2.weight(.bold)).foregroundStyle(MarkerIcons.tint(marker.kind))
                    }
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
            details
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

    /// What this kind of marker shows beyond its title: a picture for a
    /// camera, a board for a sign, readings for a weather station, rates
    /// for a toll. Every other kind says everything in its detail lines.
    @ViewBuilder private var details: some View {
        switch marker.kind {
        case "camera": CameraView(marker: marker)
        case "sign": SignBoard(marker: marker)
        case "rwis": WeatherReadings(marker: marker)
        case "toll": TollRates(marker: marker)
        default: EmptyView()
        }
    }
}

/// A roadside camera's picture. Most agencies publish a still that is
/// replaced every minute or so, which is why a fresh one is asked for
/// each time the card opens; a few also run live video, on their own
/// page.
struct CameraView: View {
    let marker: RoadMarker
    @State private var still: URL?
    @State private var takenAt: Date?
    @State private var playing = false
    @State private var tick = 0

    /// Live video the app can play: the agencies publish HLS.
    private var videoURL: URL? {
        guard let s = marker.stream, let u = URL(string: s), u.pathExtension.lowercased() == "m3u8" else { return nil }
        return u
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // What this is, before the picture: a still that the agency
            // replaces every so often, or a live stream.
            HStack(spacing: 8) {
                if marker.stream != nil {
                    Text("LIVE VIDEO").font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red, in: Capsule()).foregroundStyle(.white)
                    Text(playing ? "Streaming from the agency" : "Tap the picture to play").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("STILL PICTURE").font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                    Text(takenText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if marker.stream == nil || !playing {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityIdentifier("camera-refresh")
                }
            }
            if playing, let url = videoURL {
                CameraVideo(url: url)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("camera-video")
            } else if let url = still {
                ZStack {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .failure:
                            Text(Connectivity.shared.online ? "This camera has no picture right now." : OfflineText.camera)
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                        }
                    }
                    if videoURL != nil {
                        Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                    }
                }
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { if videoURL != nil { playing = true } }
                .accessibilityIdentifier("camera-image")
            }
            if marker.stream == nil {
                Text("Not video: the agency replaces this picture every minute or so, and the app fetches it again every minute while this card is open.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let stream = marker.stream, let url = URL(string: stream), videoURL == nil {
                    Link("Watch the live video", destination: url).font(.caption)
                }
                if let image = marker.image, let url = URL(string: image) {
                    Link("Open the full picture", destination: url).font(.caption)
                }
            }
            if let src = marker.src {
                Text("Source: \(src)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: marker.key) {
            playing = false
            reload()
            // A still is replaced by the agency every minute or so: ask
            // again while the card is open, so it is never stale.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !playing { reload() }
            }
        }
    }

    private var takenText: String {
        guard let t = takenAt else { return "Updated when you open it" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 90 { return "Taken just now" }
        if s < 3600 { return "Taken \(s / 60) min ago" }
        return "Taken " + t.formatted(date: .omitted, time: .shortened)
    }

    private func reload() {
        still = Self.fresh(marker.image)
        tick += 1
        takenAt = nil
        guard let url = still else { return }
        // The agency's Last-Modified header is when the picture was taken.
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            if let (_, resp) = try? await Backend.session.data(for: req), let http = resp as? HTTPURLResponse,
               let lm = http.value(forHTTPHeaderField: "Last-Modified") {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let d = f.date(from: lm) { takenAt = d }
            }
        }
    }

    /// The agency's own URL with the time appended, so opening a camera
    /// shows the picture as it is now rather than the cached one.
    private static func fresh(_ image: String?) -> URL? {
        guard let image, var comps = URLComponents(string: image) else { return nil }
        comps.queryItems = (comps.queryItems ?? [])
            + [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        return comps.url
    }
}

/// The agency's live stream, played in the card. HLS is what every
/// state DOT publishes, and the system player handles it.
struct CameraVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
            if failed {
                Text("The agency's stream is not answering right now. Streams come and go; the still picture above it is current.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.white).padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).padding(12)
            }
        }
        .onAppear {
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            p.isMuted = true
            p.play()
            player = p
            // A dead stream fails within a few seconds; say so instead of a black box.
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if item.status == .failed || (item.status != .readyToPlay && p.timeControlStatus != .playing) { failed = true }
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

/// What a changeable message sign is displaying, laid out the way the
/// board itself is: one line per line, centered, fixed width.
struct SignBoard: View {
    let marker: RoadMarker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if marker.signLines.isEmpty {
                Text("This sign is blank right now.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(marker.signLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color(red: 1, green: 0.79, blue: 0.29))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("sign-board")
            }
            if let src = marker.src {
                Text("Source: \(src)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// A roadside weather station's readings. Temperatures and wind arrive
/// in Celsius and miles per hour; they are shown in whatever the driver
/// has chosen. A station with nothing to report says so rather than
/// showing an empty box.
struct WeatherReadings: View {
    let marker: RoadMarker

    private var facts: [(String, String)] {
        var out: [(String, String)] = []
        if let air = marker.airC { out.append(("Air", Units.temperature(celsius: air))) }
        if let pave = marker.paveC { out.append(("Pavement", Units.temperature(celsius: pave))) }
        if let wind = marker.wind {
            // A direction on a calm wind reads as noise, so it is left off.
            var from = ""
            if let dir = marker.windDir, !dir.text.isEmpty, wind >= 1 { from = " from the " + dir.text }
            let gust = marker.gust.map { ", gusts \(Units.speed(mph: $0))" } ?? ""
            out.append(("Wind", Units.speed(mph: wind) + from + gust))
        } else if let gust = marker.gust {
            out.append(("Wind", "gusts " + Units.speed(mph: gust)))
        }
        if let rh = marker.rh { out.append(("Humidity", "\(Int(rh.rounded()))%")) }
        if let precip = marker.precip, !precip.isEmpty { out.append(("Precipitation", precip.capitalized)) }
        if let surface = marker.surface, !surface.isEmpty { out.append(("Surface", surface.capitalized)) }
        // Visibility only matters when it is short. Anything past five
        // kilometres is a clear day and says nothing useful.
        if let vis = marker.visM, vis < 5_000 { out.append(("Visibility", Units.distance(vis))) }
        return out
    }

    var body: some View {
        let readings = facts
        VStack(alignment: .leading, spacing: 4) {
            if readings.isEmpty {
                Text("This station is online. It has no readings right now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(readings.enumerated()), id: \.offset) { _, fact in
                HStack {
                    Text(fact.0).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(fact.1).font(.caption.weight(.semibold))
                }
            }
            if let src = marker.src {
                Text("Source: \(src)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("weather-readings")
    }
}

/// What a toll corridor costs. The price range comes first because it
/// is the question being asked, then whether paying is a choice, then
/// the rate from each entry point.
struct TollRates: View {
    let marker: RoadMarker

    private var entries: [TollEntry] {
        (marker.entries ?? []).filter { !($0.rows ?? []).isEmpty }
    }

    /// Whether the number moves with demand, is a published schedule,
    /// or is simply what the road costs.
    private var freshness: String {
        if marker.pricing == "live" { return "LIVE" }
        return marker.asOf == nil ? "FIXED RATE" : "POSTED RATE"
    }

    private var required: Bool { marker.tollType == "required" }

    /// Where a rate takes you. A bridge charges per crossing and has no
    /// destination to name; an express lane prices each exit.
    private func destinationText(_ row: TollRow) -> String {
        if row.destination.isEmpty { return "Per pass" }
        return required ? row.destination : "to " + row.destination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(marker.priceRange).font(.title3.weight(.semibold))
                Text(freshness).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(required ? "Every vehicle pays here." : "Optional. The regular lanes are free.")
                .font(.caption).foregroundStyle(.secondary)
            if !entries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            if let label = entry.label, !label.isEmpty {
                                Text(required ? label : "From " + label).font(.caption.weight(.semibold))
                            }
                            ForEach(Array((entry.rows ?? []).enumerated()), id: \.offset) { _, row in
                                HStack {
                                    Text(destinationText(row)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(row.price.map { RoadMarker.money($0) } ?? "")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 130)
                .accessibilityIdentifier("toll-rates")
            }
            if let src = marker.src {
                Text("Source: \(src)").font(.caption2).foregroundStyle(.secondary)
            }
        }
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
        guard model.online else { model.errorMessage = OfflineText.retry; return }
        guard let token = await model.account.token() else { showSignIn = true; return }
        do {
            try await model.reporter.confirm(alertId: id, vote: v, token: token)
            voted = v
            model.toast = v == "up" ? "Thanks, confirmed." : "Thanks, marked as gone."
            DriveLog.note("confirm \(v): \(id)")
        } catch {
            model.errorMessage = Connectivity.isOffline(error) ? OfflineText.retry : error.localizedDescription
        }
    }
}

