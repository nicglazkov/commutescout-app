import CoreLocation
import Foundation

/// A rectangle of the world, used to keep a nationwide snapshot down to
/// the part of it the phone can reach.
struct GeoBox: Hashable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    func contains(lat: Double, lon: Double) -> Bool {
        lat >= south && lat <= north && lon >= west && lon <= east
    }

    /// A generous box around a point: far enough that a long drive stays
    /// inside it, small enough that the phone holds hundreds of markers
    /// rather than the country's tens of thousands. Longitude widens
    /// toward the poles so the box stays roughly square on the ground.
    static func around(_ center: CLLocationCoordinate2D, degrees pad: Double = 6) -> GeoBox {
        let lonPad = min(15, pad / max(0.25, cos(center.latitude * .pi / 180)))
        return GeoBox(south: max(-85, center.latitude - pad), west: max(-180, center.longitude - lonPad),
                      north: min(85, center.latitude + pad), east: min(180, center.longitude + lonPad))
    }
}

extension CodingUserInfoKey {
    /// Set on the decoder to drop markers outside the box while the
    /// payload is being read, so the far side of the country is never
    /// held in memory.
    static let snapshotBox = CodingUserInfoKey(rawValue: "cs.snapshot.box")!
}

/// What the publisher uploads: the markers, plus enough about the build
/// to say how fresh they are.
struct SnapshotPayload: Decodable {
    let schema: Int?
    let build: String?
    let published: Date?
    let degraded: Bool
    let markers: [RoadMarker]

    enum CodingKeys: String, CodingKey { case schema, build, published, degraded, markers }

    init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: CodingKeys.self)
        schema = try top.decodeIfPresent(Int.self, forKey: .schema)
        build = try top.decodeIfPresent(String.self, forKey: .build)
        degraded = try top.decodeIfPresent(Bool.self, forKey: .degraded) ?? false
        published = try top.decodeIfPresent(String.self, forKey: .published).flatMap(Snapshot.date)
        let box = decoder.userInfo[.snapshotBox] as? GeoBox
        var list = try top.nestedUnkeyedContainer(forKey: .markers)
        var kept: [RoadMarker] = []
        kept.reserveCapacity(list.count.map { min($0, 2048) } ?? 512)
        while !list.isAtEnd {
            let marker = try list.decode(RoadMarker.self)
            if box == nil || box!.contains(lat: marker.lat, lon: marker.lon) { kept.append(marker) }
        }
        markers = kept
    }
}

/// The nationwide snapshot the website boots from. A publisher rebuilds
/// one object per bundle every few seconds and uploads it pre-gzipped to
/// a CDN, so the first paint is an edge-cached static file: no cold
/// instance, no feed warming, no per-request work. The app fetches it at
/// launch, in parallel with the map and the camera animation, so the
/// dots are already in memory by the time the camera lands.
///
/// The published objects are slim: closure stretches and toll corridors
/// are dropped from them, and so is every null field. Burn footprints
/// survive. The road-following lines come from the viewport call to
/// /api/mapdata that follows, which is why both paths stay.
enum Snapshot {
    static let base = URL(string: "https://data.commutescout.com")!

    /// One published object. The kinds are the query names /api/mapdata
    /// knows, used only when the snapshot host cannot be reached.
    enum Feed: String, CaseIterable, Sendable {
        case live = "live.json.gz"
        case signs = "signs.json.gz"
        case cameras = "cameras.json.gz"

        var kinds: String {
            switch self {
            case .live: return "incident,closure,chain,fire,toll,plugin"
            case .signs: return "sign,rwis"
            case .cameras: return "camera"
            }
        }
    }

    /// Fetch and decode one bundle, keeping only what falls inside the
    /// box. Both the transfer and the decode run off the main thread:
    /// this is a nonisolated async function, so it never borrows the
    /// main actor from the caller that awaits it.
    ///
    /// URLSession asks for gzip and unwraps `Content-Encoding: gzip`
    /// itself, so what arrives here is already JSON.
    static func fetch(_ feed: Feed, box: GeoBox?) async throws -> SnapshotPayload {
        do {
            let url = base.appendingPathComponent(feed.rawValue)
            let (data, response) = try await Backend.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw BackendError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return try decode(data, box: box)
        } catch {
            // A bad day for the snapshot host degrades to the old
            // behaviour, not to a blank map: the same payload is built
            // on demand by the API, slowly.
            DriveLog.note("snapshot: \(feed.rawValue) unavailable (\(error)), asking the API instead")
            return try await fromAPI(feed, box: box)
        }
    }

    private static func fromAPI(_ feed: Feed, box: GeoBox?) async throws -> SnapshotPayload {
        let area = box ?? GeoBox(south: -85, west: -180, north: 85, east: 180)
        var comps = URLComponents(url: Backend.base.appendingPathComponent("api/mapdata"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "bbox", value: String(format: "%.3f,%.3f,%.3f,%.3f",
                                                    area.south, area.west, area.north, area.east)),
            URLQueryItem(name: "kinds", value: feed.kinds),
            URLQueryItem(name: "slim", value: "1"),
        ]
        let (data, response) = try await Backend.session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BackendError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decode(data, box: box)
    }

    static func decode(_ data: Data, box: GeoBox?) throws -> SnapshotPayload {
        let decoder = JSONDecoder()
        if let box { decoder.userInfo[.snapshotBox] = box }
        return try decoder.decode(SnapshotPayload.self, from: data)
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}
