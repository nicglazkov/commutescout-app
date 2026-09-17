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
        persist()
    }

    func removeAll() {
        places = []
        persist()
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

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Distance units follow the device locale until chosen in Settings,
/// the same rule as the website.
enum Units {
    static var useMiles: Bool {
        get {
            if let v = UserDefaults.standard.string(forKey: "cs.units") { return v == "mi" }
            return Locale.current.measurementSystem == .us
        }
        set { UserDefaults.standard.set(newValue ? "mi" : "km", forKey: "cs.units") }
    }

    static func distance(_ meters: Double) -> String {
        if useMiles {
            let mi = meters / 1609.344
            if mi < 0.2 { return "\(Int((meters * 3.28084 / 50).rounded() * 50)) ft" }
            return mi < 10 ? String(format: "%.1f mi", mi) : "\(Int(mi.rounded())) mi"
        }
        if meters < 1000 { return "\(Int((meters / 50).rounded() * 50)) m" }
        let km = meters / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// Distances as a voice says them: "half a mile", "2 miles", "800 meters".
    static func spoken(_ meters: Double) -> String {
        if useMiles {
            let mi = meters / 1609.344
            if mi < 0.3 { return "a quarter mile" }
            if mi < 0.6 { return "half a mile" }
            if mi < 1.3 { return "one mile" }
            return "\(Int(mi.rounded())) miles"
        }
        if meters < 950 { return "\(Int((meters / 100).rounded() * 100)) meters" }
        let km = meters / 1000
        return km < 1.5 ? "one kilometer" : "\(Int(km.rounded())) kilometers"
    }

    static func duration(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) min"
    }
}
