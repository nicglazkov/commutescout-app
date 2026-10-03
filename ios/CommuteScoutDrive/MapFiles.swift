import Combine
import CoreLocation
import Foundation

/// Our own base map.
///
/// The map is drawn from a vector tile archive (PMTiles) of the United
/// States on the data host, read by byte range, with three styles and
/// their fonts and sprites bundled in the app so the map draws with no
/// signal at all. For driving through a dead zone the phone keeps
/// pieces of that archive on disk: a corridor cut for the trip when it
/// starts, and whole states the driver chooses in Settings. When the
/// signal goes, the map is pointed at the best local file; when it is
/// back, at the online one again.
@MainActor
final class MapFiles: ObservableObject {
    static let shared = MapFiles()

    struct Manifest: Codable {
        struct Entry: Codable { let url: String; let bytes: Int64? }
        struct StateFile: Codable, Identifiable { let code: String; let name: String; let bytes: Int64?; let url: String; var id: String { code } }
        struct Corridor: Codable { let buffer_m: Double; let max_route_m: Double }
        let build: String?
        let us: Entry
        let assets: String
        let states: [StateFile]
        let corridor: Corridor
    }

    /// A map file on the phone and the ground it covers.
    struct LocalFile: Codable, Identifiable, Equatable {
        enum Kind: String, Codable { case corridor, state }
        let id: String
        let kind: Kind
        let name: String
        let bytes: Int64
        let south: Double, west: Double, north: Double, east: Double
        let savedAt: Date
        let build: String?

        func covers(_ c: CLLocationCoordinate2D) -> Bool {
            c.latitude >= south && c.latitude <= north && c.longitude >= west && c.longitude <= east
        }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    @Published private(set) var manifest: Manifest?
    @Published private(set) var files: [LocalFile] = []
    /// Downloads in flight, by file id, 0 to 1.
    @Published private(set) var progress: [String: Double] = [:]
    /// The local file the map is drawing from, or nil while online.
    @Published private(set) var usingLocal: LocalFile?
    @Published var lastNotice: String?

    /// Where the phone is, for choosing which local file to draw from.
    var position: (() -> CLLocationCoordinate2D?)?
    static let flavors = ["light", "dark", "grayscale"]
    static let defaultUS = "https://data.commutescout.com/map/us.pmtiles"
    /// A trip corridor is kept this long; it is for one drive.
    static let corridorKeep: TimeInterval = 7 * 24 * 3600
    static let corridorMax = 6

    private let folder: URL
    private var cancellables = Set<AnyCancellable>()
    private var styleFiles: [String: URL] = [:]
    private var styleCount = 0
    private var offlineSince: Date?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("maps", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = (try? JSONDecoder().decode([LocalFile].self, from: Data(contentsOf: folder.appendingPathComponent("files.json")))) ?? []
        files = files.filter { FileManager.default.fileExists(atPath: path(for: $0).path) }
        manifest = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        Connectivity.shared.$online.receive(on: DispatchQueue.main).sink { [weak self] up in self?.networkChanged(up) }.store(in: &cancellables)
        Task { await refreshManifest() }
        pruneCorridors()
    }

    // MARK: style

    /// The style file the map loads: the bundled style for `flavor`
    /// with the fonts and sprites pointed into the bundle and the tiles
    /// pointed at the online file, or at the local one while offline.
    /// A new file is written whenever either changes, so the map sees a
    /// new URL and reloads.
    func styleURL(flavor: String) -> URL {
        let source = tileSource()
        let key = "\(flavor)|\(source)"
        if let u = styleFiles[key] { return u }
        let bundle = Bundle.main.resourceURL!.appendingPathComponent("Map", isDirectory: true)
        var text = (try? String(contentsOf: bundle.appendingPathComponent("styles/\(flavor).json"), encoding: .utf8)) ?? "{}"
        text = text.replacingOccurrences(of: "__PMTILES_URL__", with: source)
        text = text.replacingOccurrences(of: "__ASSETS__", with: bundle.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        styleCount += 1
        let name = "style-\(flavor)-\(styleCount).json"
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        styleFiles[key] = url
        return url
    }

    private func tileSource() -> String {
        if let local = usingLocal { return path(for: local).absoluteString }
        return manifest?.us.url ?? Self.defaultUS
    }

    // MARK: online and offline

    private func networkChanged(_ up: Bool) {
        if up {
            offlineSince = nil
            if usingLocal != nil {
                usingLocal = nil
                DriveLog.note("map: back online, drawing from the online file")
            }
            return
        }
        offlineSince = Date()
        // A moment's grace: a signal that flickers should not reload the map twice.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Connectivity.shared.online else { return }
            self.pickLocal()
        }
    }

    /// With no signal, draw from the local file that covers the phone:
    /// a state first (it covers more), else the newest corridor, else
    /// any file at all rather than nothing.
    func pickLocal() {
        guard !files.isEmpty else { return }
        let here = position?()
        let covering = files.filter { f in here.map { f.covers($0) } ?? false }
        let choice = covering.first { $0.kind == .state } ?? covering.max { $0.savedAt < $1.savedAt }
            ?? files.max { $0.savedAt < $1.savedAt }
        if choice != usingLocal {
            usingLocal = choice
            DriveLog.note("map: offline, drawing from \(choice?.name ?? "nothing") (\(choice?.kind.rawValue ?? ""))")
        }
    }

    // MARK: manifest

    func refreshManifest() async {
        guard Connectivity.shared.online else { return }
        do {
            let m = try await Backend.get("api/map/manifest", query: [:], as: Manifest.self)
            manifest = m
            if let data = try? JSONEncoder().encode(m) { try? data.write(to: folder.appendingPathComponent("manifest.json")) }
        } catch {
            DriveLog.note("map: manifest unavailable: \(error)")
        }
    }

    // MARK: downloads

    /// The corridor for a trip. Automatic only on Wi-Fi with the
    /// setting on; `manual` is the driver's own tap, on any network.
    @discardableResult
    func saveCorridor(route: [CLLocationCoordinate2D], name: String, manual: Bool, autoAllowed: Bool) async -> LocalFile? {
        guard Connectivity.shared.online, route.count >= 2 else { return nil }
        if !manual {
            guard autoAllowed, Connectivity.shared.onWifi else {
                DriveLog.note("map: corridor not saved automatically (wifi=\(Connectivity.shared.onWifi), setting=\(autoAllowed))")
                return nil
            }
        }
        let id = "corridor-" + String(Int(Date().timeIntervalSince1970))
        guard progress[id] == nil else { return nil }
        progress[id] = 0
        defer { progress[id] = nil }
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        let pad = (manifest?.corridor.buffer_m ?? 2500) / 100_000
        // At most 2,000 points to the server; every nth keeps the shape.
        let step = max(1, route.count / 2000 + 1)
        let pts = stride(from: 0, to: route.count, by: step).map { [route[$0].latitude, route[$0].longitude] }
        do {
            var req = URLRequest(url: Backend.base.appendingPathComponent("api/map/extract"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["path": pts])
            req.timeoutInterval = 300
            let file = LocalFile(id: id, kind: .corridor, name: "Trip to \(name)", bytes: 0,
                                 south: lats.min()! - pad, west: lons.min()! - pad, north: lats.max()! + pad, east: lons.max()! + pad,
                                 savedAt: Date(), build: manifest?.build)
            let written = try await Downloader.fetch(req, to: path(for: file)) { [weak self] p in self?.progress[id] = p }
            let done = LocalFile(id: file.id, kind: file.kind, name: file.name, bytes: written, south: file.south, west: file.west,
                                 north: file.north, east: file.east, savedAt: file.savedAt, build: file.build)
            files.append(done)
            persist()
            pruneCorridors()
            DriveLog.note("map: corridor saved, \(done.sizeText)")
            lastNotice = "Map for this trip saved (\(done.sizeText))."
            return done
        } catch {
            DriveLog.note("map: corridor failed: \(error)")
            if manual { lastNotice = Connectivity.isOffline(error) ? OfflineText.retry : "Could not save the map for this trip." }
            return nil
        }
    }

    func downloadState(_ s: Manifest.StateFile) async {
        let id = "state-\(s.code)"
        guard progress[id] == nil, let url = URL(string: s.url), Connectivity.shared.online else { return }
        progress[id] = 0
        defer { progress[id] = nil }
        let bounds = StateBounds.of(s.code)
        let file = LocalFile(id: id, kind: .state, name: s.name, bytes: s.bytes ?? 0,
                             south: bounds.south, west: bounds.west, north: bounds.north, east: bounds.east,
                             savedAt: Date(), build: manifest?.build)
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 3600
            let written = try await Downloader.fetch(req, to: path(for: file)) { [weak self] p in self?.progress[id] = p }
            let done = LocalFile(id: file.id, kind: .state, name: file.name, bytes: written, south: file.south, west: file.west,
                                 north: file.north, east: file.east, savedAt: file.savedAt, build: file.build)
            files.removeAll { $0.id == id }
            files.append(done)
            persist()
            lastNotice = "\(s.name) saved (\(done.sizeText))."
            DriveLog.note("map: state \(s.code) saved, \(done.sizeText)")
        } catch {
            try? FileManager.default.removeItem(at: path(for: file))
            lastNotice = Connectivity.isOffline(error) ? OfflineText.retry : "Could not download \(s.name)."
            DriveLog.note("map: state \(s.code) failed: \(error)")
        }
    }

    func delete(_ f: LocalFile) {
        try? FileManager.default.removeItem(at: path(for: f))
        files.removeAll { $0.id == f.id }
        if usingLocal?.id == f.id { usingLocal = nil; pickLocal() }
        persist()
    }

    var bytesOnDisk: Int64 { files.reduce(0) { $0 + $1.bytes } }

    func has(state code: String) -> LocalFile? { files.first { $0.id == "state-\(code)" } }

    // MARK: files

    func path(for f: LocalFile) -> URL { folder.appendingPathComponent("\(f.id).pmtiles") }

    /// What the disk says about a saved map, for the detail page: a
    /// double check on the record the app kept.
    struct Check {
        let exists: Bool
        let bytesOnDisk: Int64
        let header: PMTilesHeader?
    }

    func check(_ f: LocalFile) async -> Check {
        let url = path(for: f)
        return await Task.detached(priority: .utility) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs != nil else { return Check(exists: false, bytesOnDisk: 0, header: nil) }
            let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return Check(exists: true, bytesOnDisk: bytes, header: PMTilesHeader.read(url))
        }.value
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(files) { try? data.write(to: folder.appendingPathComponent("files.json")) }
    }

    private func pruneCorridors() {
        let corridors = files.filter { $0.kind == .corridor }.sorted { $0.savedAt > $1.savedAt }
        for (i, c) in corridors.enumerated() where i >= Self.corridorMax || Date().timeIntervalSince(c.savedAt) > Self.corridorKeep {
            delete(c)
        }
    }

}

/// Rough bounds per state, for choosing which saved state covers the
/// phone. Generous on purpose; a file that also covers a neighbour's
/// edge is better than one that stops at the line.
enum StateBounds {
    struct Box { let south: Double, west: Double, north: Double, east: Double }
    static func of(_ code: String) -> Box {
        let t: [String: (Double, Double, Double, Double)] = [
            "AL": (30.1, -88.6, 35.1, -84.8), "AK": (51.0, -180, 72.0, -129.0), "AZ": (31.2, -115.0, 37.1, -108.9),
            "AR": (32.9, -94.7, 36.6, -89.5), "CA": (32.4, -124.6, 42.1, -114.0), "CO": (36.9, -109.2, 41.1, -101.9),
            "CT": (40.9, -73.8, 42.1, -71.7), "DE": (38.4, -75.9, 39.9, -74.9), "FL": (24.3, -87.7, 31.1, -79.9),
            "GA": (30.3, -85.7, 35.1, -80.7), "HI": (18.8, -160.4, 22.4, -154.7), "ID": (41.9, -117.3, 49.1, -110.9),
            "IL": (36.9, -91.6, 42.6, -87.4), "IN": (37.7, -88.2, 41.8, -84.7), "IA": (40.3, -96.7, 43.6, -90.0),
            "KS": (36.9, -102.1, 40.1, -94.5), "KY": (36.4, -89.6, 39.2, -81.9), "LA": (28.8, -94.1, 33.1, -88.7),
            "ME": (42.9, -71.2, 47.5, -66.8), "MD": (37.8, -79.6, 39.8, -74.9), "MA": (41.1, -73.6, 42.9, -69.8),
            "MI": (41.6, -90.5, 48.4, -82.3), "MN": (43.4, -97.3, 49.5, -89.4), "MS": (30.0, -91.7, 35.1, -88.0),
            "MO": (35.9, -95.8, 40.7, -89.0), "MT": (44.3, -116.1, 49.1, -104.0), "NE": (39.9, -104.1, 43.1, -95.2),
            "NV": (34.9, -120.1, 42.1, -113.9), "NH": (42.6, -72.6, 45.4, -70.6), "NJ": (38.8, -75.6, 41.4, -73.8),
            "NM": (31.2, -109.1, 37.1, -102.9), "NY": (40.4, -79.8, 45.1, -71.8), "NC": (33.7, -84.4, 36.7, -75.4),
            "ND": (45.9, -104.1, 49.1, -96.5), "OH": (38.3, -84.9, 42.0, -80.4), "OK": (33.5, -103.1, 37.1, -94.3),
            "OR": (41.9, -124.7, 46.4, -116.4), "PA": (39.6, -80.6, 42.4, -74.6), "RI": (41.1, -71.9, 42.1, -71.0),
            "SC": (31.9, -83.4, 35.3, -78.4), "SD": (42.4, -104.1, 46.0, -96.3), "TN": (34.9, -90.4, 36.8, -81.6),
            "TX": (25.7, -106.7, 36.6, -93.4), "UT": (36.9, -114.1, 42.1, -108.9), "VT": (42.6, -73.5, 45.1, -71.4),
            "VA": (36.4, -83.7, 39.6, -75.1), "WA": (45.4, -124.9, 49.1, -116.8), "WV": (37.1, -82.7, 40.7, -77.6),
            "WI": (42.4, -92.9, 47.2, -86.7), "WY": (40.9, -111.1, 45.1, -104.0), "DC": (38.7, -77.2, 39.1, -76.8),
        ]
        let b = t[code] ?? (24.0, -125.0, 50.0, -66.0)
        return Box(south: b.0, west: b.1, north: b.2, east: b.3)
    }
}

/// One file download at native speed, with progress. The byte-by-byte
/// async sequence this replaced managed about 70 KB a second.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: (Double) -> Void
    private var session: URLSession!

    private init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Download `request` into `target` (replacing it); returns the byte count.
    static func fetch(_ request: URLRequest, to target: URL, onProgress: @escaping (Double) -> Void) async throws -> Int64 {
        let d = Downloader(onProgress: onProgress)
        defer { d.session.finishTasksAndInvalidate() }
        let tmp: URL = try await withCheckedThrowingContinuation { cont in
            d.continuation = cont
            d.session.downloadTask(with: request).resume()
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        return (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? 0
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is gone after this returns; keep it.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pmtiles")
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                try? FileManager.default.removeItem(at: keep)
                continuation?.resume(throwing: BackendError.status(http.statusCode))
            } else {
                continuation?.resume(returning: keep)
            }
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [onProgress] in onProgress(p) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }
}
