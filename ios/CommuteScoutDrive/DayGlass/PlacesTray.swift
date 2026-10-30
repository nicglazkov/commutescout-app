import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import SwiftUI

/// Browsing with nothing else open: Home, Work and one more place (the
/// newest starred or recent one), each with its drive time from here.
/// A tap shows the place, as picking it in search does.
struct PlacesTray: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var times = DriveTimes()

    struct Row: Identifiable {
        var place: Place
        var icon: String
        var title: String
        var id: String { place.id }
    }

    /// Home, Work, then one starred and one recent, three at most and
    /// never the same spot twice.
    static func rows(_ store: PlaceStore) -> [Row] {
        var out: [Row] = []
        if let h = store.home { out.append(Row(place: h, icon: "home", title: "Home")) }
        if let w = store.work { out.append(Row(place: w, icon: "work", title: "Work")) }
        for p in Array(store.saved.prefix(1)) + Array(store.recents.prefix(1)) {
            out.append(Row(place: p, icon: p.kind == .saved ? "nav" : "recent", title: p.shortName))
        }
        var seen = Set<String>()
        return out.filter { seen.insert(String(format: "%.5f,%.5f", $0.place.lat, $0.place.lon)).inserted }.prefix(3).map { $0 }
    }

    static func height(rows: Int) -> CGFloat { rows == 0 ? 0 : CGFloat(rows) * 58 + 12 + 6 }

    var body: some View {
        let rows = Self.rows(model.places)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(DG.hair).frame(height: 0.5).padding(.horizontal, 14) }
                    Button { model.show(r.place) } label: { row(r) }
                        .buttonStyle(DGPressStyle())
                        .accessibilityIdentifier("places-tray-" + r.icon)
                }
            }
            .padding(6)
            .dgGlass(radius: DG.R.sheet)
            .padding(.horizontal, 12).padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("places-tray")
            .task(id: rows.map(\.id).joined()) { await times.refresh(rows.filter { $0.icon != "recent" }.map(\.place), model: model) }
        }
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: 14) {
            DGIconView(name: r.icon, size: 20, stroke: 2.1)
                .foregroundStyle(DGTone.low.color)
                .frame(width: 40, height: 40)
                .background(DGTone.low.color.opacity(0.12), in: Circle())
            Text(r.title).font(DG.font(17, .semibold)).foregroundStyle(DG.ink).lineLimit(1)
            Spacer(minLength: 8)
            if let s = trailing(r) { Text(s).font(DG.font(15, .medium)).foregroundStyle(DG.sub) }
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
        .contentShape(Rectangle())
    }

    /// The drive time when it is known, the distance until then, and
    /// "Recent" for a recent place.
    private func trailing(_ r: Row) -> String? {
        if r.icon == "recent" { return "Recent" }
        if let s = times.seconds[r.place.id] { return Units.duration(s) }
        guard let here = model.here else { return nil }
        return Units.distance(CLLocation(latitude: here.latitude, longitude: here.longitude)
            .distance(from: CLLocation(latitude: r.place.lat, longitude: r.place.lon)))
    }
}

/// Drive times to the tray's places, from routes the routing service
/// returns. Kept for ten minutes, or until the driver has moved a
/// kilometer, so an idle map does not ask again.
@MainActor
final class DriveTimes: ObservableObject {
    @Published private(set) var seconds: [String: Double] = [:]
    private var asked: [String: (at: Date, from: CLLocation)] = [:]

    func refresh(_ places: [Place], model: AppModel) async {
        // Tests run without a network to spare; distances are enough there.
        if ProcessInfo.processInfo.arguments.contains("-csSimulate") { return }
        for p in places {
            guard model.online, let c = model.here else { return }
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let a = asked[p.id], Date().timeIntervalSince(a.at) < 600, a.from.distance(from: here) < 1000 { continue }
            // Too close to be worth a route, or too far to be a commute.
            let d = here.distance(from: CLLocation(latitude: p.lat, longitude: p.lon))
            guard d > 150, d < 300_000 else { continue }
            asked[p.id] = (Date(), here)
            guard let route = try? await model.core.getRoutes(
                initialLocation: UserLocation(clCoordinateLocation2D: c),
                waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: p.coordinate), kind: .break)]).first
            else { continue }
            seconds[p.id] = route.steps.reduce(0) { $0 + $1.duration }
        }
    }
}
