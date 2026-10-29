import CoreLocation
import Foundation

/// A watch alert the person tapped: the event it named, as the push
/// described it at the moment it was sent.
struct AlertRef: Equatable {
    var id: String?
    /// The map's kind ("lane_closure"), not the watch's ("closure").
    var kind: String
    var lat: Double
    var lon: Double
    var title: String?
    var body: String?
    var watch: String?
    var sentAt: Date?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// What the watch checker calls a kind, as the map calls it.
    static func markerKind(_ k: String) -> String {
        ["closure": "lane_closure", "chain": "chain_control", "fire": "wildfire"][k] ?? k
    }

    /// The word for one of these in a sentence.
    static func noun(_ kind: String) -> String {
        ["incident": "incident", "lane_closure": "closure", "chain_control": "chain control",
         "wildfire": "wildfire"][kind] ?? "event"
    }

    /// From a push's data. Newer pushes carry the event itself; older
    /// ones only a map link with the spot and the kind.
    static func from(userInfo: [AnyHashable: Any]) -> AlertRef? {
        func str(_ k: String) -> String? {
            (userInfo[k] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let lat = str("event_lat").flatMap(Double.init), let lon = str("event_lon").flatMap(Double.init) {
            return AlertRef(id: str("event_id"), kind: markerKind(str("event_kind") ?? "incident"),
                            lat: lat, lon: lon, title: str("event_title"), body: str("event_body"),
                            watch: str("event_watch"),
                            sentAt: str("event_sent_at").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) })
        }
        guard var ref = str("url").flatMap(URL.init(string:)).flatMap(from(url:)) else { return nil }
        if let aps = userInfo["aps"] as? [String: Any], let alert = aps["alert"] as? [String: Any] {
            ref.title = alert["title"] as? String
            ref.body = alert["body"] as? String
        }
        return ref
    }

    /// From a map link: `?focus=lat,lon&k=kind`.
    static func from(url: URL) -> AlertRef? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let parts = (items.first { $0.name == "focus" }?.value ?? "").split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let k = items.first { $0.name == "k" }?.value ?? "incident"
        return AlertRef(id: nil, kind: markerKind(k), lat: parts[0], lon: parts[1])
    }

    /// The map's own marker for this event: the same CHP id when there
    /// is one, else the nearest of the kind within 300 m.
    func localMatch(in markers: [RoadMarker]) -> RoadMarker? {
        if let id, id.hasPrefix("chp:") {
            let chp = String(id.dropFirst(4))
            if let m = markers.first(where: { $0.kind == "incident" && $0.id == chp }) { return m }
        }
        return markers.filter { $0.kind == kind }
            .map { ($0, CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: CLLocation(latitude: lat, longitude: lon))) }
            .filter { $0.1 <= 300 }
            .min { $0.1 < $1.1 }?.0
    }
}

/// What became of the event, as the sheet tells it.
enum EventStatus: Equatable {
    case loading
    /// Still reported. `confirmed` is false when the server could not be
    /// asked and the map's own copy is all there is.
    case active(confirmed: Bool)
    case changed(nowTitle: String)
    case cleared(at: Date?)
    case gone
    case unknown
}

/// The server's answer for one alerted event.
struct EventStatusReply: Decodable {
    struct Brief: Decodable { let title: String?; let body: String? }
    let state: String
    let clearedAt: String?
    let checkedAt: String?
    let event: Brief?
    let marker: RoadMarker?
    let nearby: RoadMarker?

    enum CodingKeys: String, CodingKey {
        case state, event, marker, nearby
        case clearedAt = "cleared_at"
        case checkedAt = "checked_at"
    }
}

/// The alert being shown, and what the app knows of it now.
struct AlertFocus: Equatable {
    var ref: AlertRef
    var status: EventStatus = .loading
    var checkedAt: Date?
    /// The same kind of event still reported at the spot after a clear:
    /// offered, never passed off as the one in the alert.
    var nearby: RoadMarker?

    static func == (a: Self, b: Self) -> Bool {
        a.ref == b.ref && a.status == b.status && a.checkedAt == b.checkedAt && a.nearby?.key == b.nearby?.key
    }

    /// Turn the server's answer (nil when it could not be reached) and
    /// the map's own copy into a status and the marker to show.
    static func resolve(_ reply: EventStatusReply?, local: RoadMarker?) -> (EventStatus, RoadMarker?, RoadMarker?) {
        guard let reply else {
            return local != nil ? (.active(confirmed: false), local, nil) : (.unknown, nil, nil)
        }
        switch reply.state {
        case "active":
            return (.active(confirmed: true), reply.marker ?? local, nil)
        case "changed":
            let now = reply.event?.title ?? reply.marker.map(\.displayTitle) ?? "a new status"
            return (.changed(nowTitle: now), reply.marker, nil)
        case "cleared":
            return (.cleared(at: reply.clearedAt.flatMap(EventContent.date)), nil, reply.nearby)
        default:
            return (.gone, nil, nil)
        }
    }
}

/// A tapped alert can arrive before the app's model exists (a cold
/// launch from the notification). It waits here until the model takes it.
@MainActor
final class AlertInbox {
    static let shared = AlertInbox()
    private var pending: AlertRef?
    var handler: ((AlertRef) -> Void)? {
        didSet { if let handler, let p = pending { pending = nil; handler(p) } }
    }

    func deliver(_ ref: AlertRef) {
        if let handler { handler(ref) } else { pending = ref }
    }
}

/// One CHP call's dispatch log, translated by the server.
struct DispatchReply: Decodable {
    struct Row: Decodable, Hashable { let time: String; let text: String; let plain: String? }
    struct Step: Decodable, Hashable { let status: String; let time: String }
    struct Unit: Decodable, Hashable { let unit: Int; let steps: [Step]; let done: Bool }
    struct Log: Decodable { let log: [Row]; let units: [Unit] }
    let dispatch: Log?
}

enum EventAPI {
    static func status(_ ref: AlertRef) async throws -> EventStatusReply {
        var q = ["kind": ref.kind, "lat": String(ref.lat), "lon": String(ref.lon)]
        if let id = ref.id { q["id"] = id }
        return try await Backend.get("api/event-status", query: q, as: EventStatusReply.self)
    }

    static func dispatch(_ chpId: String) async throws -> DispatchReply {
        try await Backend.get("api/incident/" + chpId, as: DispatchReply.self)
    }
}
