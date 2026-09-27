import CoreLocation
@preconcurrency import FerrostarCoreFFI
import Foundation
import Network

/// Whether the phone can reach the network right now, and what to do
/// the moment it can again.
///
/// Nothing in the app waits on this before trying: a request is always
/// the real test. It decides what the app says (the offline banner, an
/// honest error) and it is the trigger for catching up once the signal
/// is back: markers, spoken alerts and any reports queued meanwhile.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var online = true
    private var reconnect: [() -> Void] = []
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.set(up) }
        }
        monitor.start(queue: DispatchQueue(label: "cs.connectivity"))
    }

    /// Run `action` every time the network comes back.
    func onReconnect(_ action: @escaping () -> Void) { reconnect.append(action) }

    private func set(_ up: Bool) {
        guard up != online else { return }
        online = up
        DriveLog.note(up ? "network: back" : "network: lost")
        if up { reconnect.forEach { $0() } }
    }

    /// Errors that mean the network was not there, as opposed to a
    /// server that answered and said no.
    nonisolated static func isOffline(_ error: Error) -> Bool {
        let codes: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                               NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut,
                               NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
                               NSURLErrorCallIsActive]
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, codes.contains(ns.code) { return true }
        if let inner = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOffline(inner) }
        return false
    }
}

/// What the app says when something needs the network and there is none.
enum OfflineText {
    static let routes = "No connection. Routes need a signal. Your saved places and the map you already loaded still work."
    static let search = "No connection. Search needs a signal. Saved and recent places still work."
    static let retry = "No connection. Try again when you have a signal."
    static let camera = "No connection, so the picture cannot load."

    /// A short clock time, the way the phone shows it.
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

/// How long a road event can be trusted without a fresh copy. A report
/// of police is stale in half an hour; a closure for roadwork lasts all
/// day. Only ever applied to data that could not be refreshed: while the
/// phone is online everything is minutes old anyway.
enum ShelfLife {
    /// Past this, nothing saved is shown at all.
    static let maxAge: TimeInterval = 24 * 3600

    static func seconds(for kind: String) -> TimeInterval {
        switch kind {
        case "plugin": 30 * 60
        case "incident", "sign", "toll": 60 * 60
        case "rwis": 2 * 3600
        case "chain_control": 6 * 3600
        case "lane_closure": 12 * 3600
        default: maxAge          // wildfires, cameras
        }
    }

    static func keep(_ kind: String, age: TimeInterval) -> Bool { age <= seconds(for: kind) }

    /// The markers still worth showing when the newest copy is `asOf`.
    static func prune(_ markers: [RoadMarker], asOf: Date?, now: Date = Date()) -> [RoadMarker] {
        guard let asOf else { return markers }
        let age = now.timeIntervalSince(asOf)
        guard age > 15 * 60 else { return markers }   // nothing expires this quickly
        return markers.filter { keep($0.kind, age: age) }
    }
}

/// Files kept on the phone so the app has something to show without a
/// signal: the last snapshot of road markers (in Caches, which the
/// system may clear), and the running trip and unsent reports (in
/// Application Support, which it does not).
enum OfflineStore {
    enum Area { case cache, support }

    private static func dir(_ place: Area) -> URL {
        let base = FileManager.default.urls(for: place == .cache ? .cachesDirectory : .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("offline", isDirectory: true)
    }

    /// Write atomically, compressed: a snapshot is several megabytes of
    /// JSON and compresses to a fraction of that.
    static func save(_ data: Data, as name: String, in place: Area = .cache) {
        let folder = dir(place)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let packed = try (data as NSData).compressed(using: .lzfse) as Data
            try packed.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            DriveLog.note("offline: could not save \(name): \(error)")
        }
    }

    /// The file and when it was written, when there is one young enough.
    static func load(_ name: String, maxAge: TimeInterval, in place: Area = .cache) -> (data: Data, savedAt: Date)? {
        let url = dir(place).appendingPathComponent(name)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let savedAt = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(savedAt) <= maxAge,
              let packed = try? Data(contentsOf: url),
              let data = try? (packed as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return (data, savedAt)
    }

    static func remove(_ name: String, in place: Area = .cache) {
        try? FileManager.default.removeItem(at: dir(place).appendingPathComponent(name))
    }
}

/// The trip in progress, written when it starts and removed when it
/// ends, so an app that was closed or killed mid-drive can pick the
/// route up again without a signal. Guidance only needs the route.
struct SavedTrip: Codable {
    let route: Route
    let place: Place
    let startedAt: Date

    private static let file = "trip.json"
    /// A trip left this long is not one anybody is still on.
    static let maxAge: TimeInterval = 12 * 3600

    static func save(route: Route, place: Place) {
        guard let data = try? JSONEncoder().encode(SavedTrip(route: route, place: place, startedAt: Date())) else { return }
        OfflineStore.save(data, as: file, in: .support)
    }

    static func load() -> SavedTrip? {
        guard let saved = OfflineStore.load(file, maxAge: maxAge, in: .support) else { return nil }
        // A trip saved by an older build may not decode; it is dropped.
        guard let trip = try? JSONDecoder().decode(SavedTrip.self, from: saved.data) else { clear(); return nil }
        return trip
    }

    static func clear() { OfflineStore.remove(file, in: .support) }
}

/// Reports made with no signal, sent once it is back.
///
/// The server stamps a report with the time it arrives, so one that
/// waited too long would land on the map as fresh news about something
/// that may be long gone. A report older than `maxAge` is dropped
/// instead of sent.
struct PendingReport: Codable, Identifiable {
    var id = UUID()
    let kind: String
    let lat: Double
    let lon: Double
    let heading: Double?
    let note: String
    let createdAt: Date

    static let maxAge: TimeInterval = 15 * 60
    private static let file = "pending-reports.json"

    static func all() -> [PendingReport] {
        guard let saved = OfflineStore.load(file, maxAge: 24 * 3600, in: .support),
              let list = try? JSONDecoder().decode([PendingReport].self, from: saved.data) else { return [] }
        return list
    }

    static func store(_ list: [PendingReport]) {
        if list.isEmpty { OfflineStore.remove(file, in: .support); return }
        if let data = try? JSONEncoder().encode(list) { OfflineStore.save(data, as: file, in: .support) }
    }

    static func add(_ report: PendingReport) { store(all() + [report]) }
}
