import CoreLocation
import Foundation

/// A saved destination: Home, Work, or anything the driver starred.
struct Place: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case home, work, saved, recent }

    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var kind: Kind
    var lastUsed: Date

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var shortName: String { name.split(separator: ",").first.map(String.init) ?? name }

    init(name: String, coordinate: CLLocationCoordinate2D, kind: Kind) {
        id = UUID().uuidString
        self.name = name
        lat = coordinate.latitude
        lon = coordinate.longitude
        self.kind = kind
        lastUsed = Date()
    }
}

/// Favorites and recents, kept on the device. Home and Work are one
/// each; saved places and recents are lists, recents capped at 20.
@MainActor
final class PlaceStore: ObservableObject {
    @Published private(set) var places: [Place] = []
    private let key = "cs.places.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        }
    }

    var home: Place? { places.first { $0.kind == .home } }
    var work: Place? { places.first { $0.kind == .work } }
    var saved: [Place] { places.filter { $0.kind == .saved }.sorted { $0.lastUsed > $1.lastUsed } }
    var recents: [Place] { places.filter { $0.kind == .recent }.sorted { $0.lastUsed > $1.lastUsed } }

    func set(_ kind: Place.Kind, name: String, coordinate: CLLocationCoordinate2D) {
        if kind == .home || kind == .work {
            places.removeAll { $0.kind == kind }
        }
        places.append(Place(name: name, coordinate: coordinate, kind: kind))
        trim()
        persist()
    }

    func remove(_ place: Place) {
        places.removeAll { $0.id == place.id }
        persist(removal: true)
    }

    func removeAll() {
        places = []
        persist(removal: true)
    }

    func touch(_ place: Place) {
        if let i = places.firstIndex(where: { $0.id == place.id }) {
            places[i].lastUsed = Date()
            persist()
        }
    }

    /// Remember a destination that was navigated to, once, most recent first.
    func noteRecent(name: String, coordinate: CLLocationCoordinate2D) {
        if let existing = places.first(where: {
            abs($0.lat - coordinate.latitude) < 0.0005 && abs($0.lon - coordinate.longitude) < 0.0005
        }) {
            touch(existing)
            return
        }
        places.append(Place(name: name, coordinate: coordinate, kind: .recent))
        trim()
        persist()
    }

    private func trim() {
        let recent = recents
        if recent.count > 20 {
            for old in recent.dropFirst(20) { places.removeAll { $0.id == old.id } }
        }
    }

    private func persist(removal: Bool = false) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
        pushToAccount(replace: removal)
    }

    // MARK: account sync (Home, Work, favorites and recents follow the account)

    /// Set by the app model: the signed-in account's ID token, or nil.
    var tokenProvider: (() async -> String?)?
    private var pushTask: Task<Void, Never>?
    /// Whether this phone has taken the account's list this session.
    /// Until it has, its own list is partial, and must never replace
    /// the account's: a new phone saving Home once wiped Work and every
    /// favorite saved on the website.
    private var synced = false

    private struct Wire: Codable {
        let id: String
        let kind: String
        let name: String
        let lat: Double
        let lon: Double
        let used_at: Double
    }
    private struct Body: Decodable { let places: [Wire] }

    private func wire() -> [[String: Any]] {
        places.map { ["id": $0.id, "kind": $0.kind.rawValue, "name": $0.name,
                      "lat": $0.lat, "lon": $0.lon, "used_at": $0.lastUsed.timeIntervalSince1970] }
    }

    private func apply(_ wires: [Wire]) {
        places = wires.compactMap { w in
            guard let kind = Place.Kind(rawValue: w.kind) else { return nil }
            var p = Place(name: w.name, coordinate: CLLocationCoordinate2D(latitude: w.lat, longitude: w.lon), kind: kind)
            p.id = w.id
            p.lastUsed = Date(timeIntervalSince1970: w.used_at)
            return p
        }
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// On sign-in: send this phone's list, take the merged list back.
    func syncWithAccount() async {
        guard let token = await tokenProvider?() else { return }
        guard let (status, data) = try? await Backend.send("PUT", "api/me/places", token: token, body: ["places": wire()]),
              status == 200, let body = try? JSONDecoder().decode(Body.self, from: data) else { return }
        apply(body.places)
        synced = true
        DriveLog.note("places: synced \(places.count) with the account")
    }

    /// Signing out: let a pending change reach the account, then drop the
    /// list from this phone so the next account to sign in here does not
    /// merge it in. Nothing is pushed: a push now would wipe the account.
    /// A deleted account gets no last push (flush false): it would bring
    /// the account's places back on the server.
    func forgetForSignOut(flush: Bool = true) async {
        if flush { await pushTask?.value } else { pushTask?.cancel() }
        pushTask = nil
        places = []
        UserDefaults.standard.removeObject(forKey: key)
        synced = false
    }

    /// After a change: the account gets this phone's list, debounced.
    /// An addition merges, so nothing saved elsewhere is lost. A removal
    /// replaces, so it is a removal everywhere, but only once this phone
    /// holds the account's whole list; before that it merges too, and the
    /// removal lands on the next sync.
    private func pushToAccount(replace: Bool) {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let token = await tokenProvider?() else { return }
            var body: [String: Any] = ["places": wire()]
            if replace && synced { body["replace"] = true }
            guard let (status, data) = try? await Backend.send("PUT", "api/me/places", token: token, body: body),
                  status == 200, !Task.isCancelled,
                  let merged = try? JSONDecoder().decode(Body.self, from: data) else { return }
            // What came back is the account's whole list, this phone included.
            apply(merged.places)
            synced = true
        }
    }
}
