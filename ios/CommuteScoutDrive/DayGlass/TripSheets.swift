import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import SwiftUI

// The trip pages: the place sheet, the route choices with "leave later",
// and what shows on arrival. The search field is SearchBar; reporting
// is ReportFlow.

// MARK: - Leave later

/// `GET /api/leave-later`: the drive time if you leave now or at each
/// step in the next hour, and the departure that saves the most.
/// Asks once per trip and keeps the answer a few minutes; errors (400,
/// 429, 503, or no signal) leave nothing, and the pages show less.
@MainActor
final class LeaveLaterStore: ObservableObject {
    static let shared = LeaveLaterStore()
    @Published private(set) var answers: [String: LeaveLater] = [:]
    private var asked: [String: Date] = [:]

    static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f>%.3f,%.3f", a.latitude, a.longitude, b.latitude, b.longitude)
    }

    func answer(from a: CLLocationCoordinate2D?, to b: CLLocationCoordinate2D) -> LeaveLater? {
        guard let a else { return nil }
        return answers[Self.key(a, b)]
    }

    func ask(from a: CLLocationCoordinate2D?, to b: CLLocationCoordinate2D) async {
        guard let a else { return }
        let k = Self.key(a, b)
        if let t = asked[k], Date().timeIntervalSince(t) < 300 { return }
        asked[k] = Date()
        let q = ["from": String(format: "%.5f,%.5f", a.latitude, a.longitude),
                 "to": String(format: "%.5f,%.5f", b.latitude, b.longitude)]
        for window in ["70", "60"] {
            do {
                let r = try await Backend.get("api/leave-later", query: q.merging(["window": window, "step": "10"]) { $1 }, as: LeaveLater.self)
                answers[k] = r
                return
            } catch BackendError.status(400) {
                continue
            } catch {
                DriveLog.note("leave-later: \(error.localizedDescription)")
                return
            }
        }
    }
}

// MARK: - Events along a route

enum TripMath {
    /// Road events within `within` meters of the line, nearest the start first.
    static func along(_ line: [CLLocationCoordinate2D], markers: [RoadMarker], within: Double = 250) -> [RoadMarker] {
        guard line.count > 1 else { return [] }
        let step = max(1, line.count / 400)
        let pts = stride(from: 0, to: line.count, by: step).map { line[$0] } + [line[line.count - 1]]
        let pad = within / 100_000 + 0.01
        let s = pts.map(\.latitude).min()! - pad, n = pts.map(\.latitude).max()! + pad
        let w = pts.map(\.longitude).min()! - pad, e = pts.map(\.longitude).max()! + pad
        var out: [(Int, RoadMarker)] = []
        for m in markers where m.lat >= s && m.lat <= n && m.lon >= w && m.lon <= e {
            guard ["incident", "lane_closure", "chain_control", "wildfire", "plugin"].contains(m.kind) else { continue }
            let c = CLLocationCoordinate2D(latitude: m.lat, longitude: m.lon)
            var best = Double.infinity, at = 0
            for (i, p) in pts.enumerated() {
                let d = AlertsEngine.meters(p, c)
                if d < best { best = d; at = i }
            }
            if best <= within + Double(step) * 15 { out.append((at, m)) }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The events the other routes would have met and this one does not.
    static func avoided(chosen: [CLLocationCoordinate2D], others: [[CLLocationCoordinate2D]], markers: [RoadMarker]) -> [RoadMarker] {
        let mine = Set(along(chosen, markers: markers).map(key))
        var seen = Set<String>()
        return others.flatMap { along($0, markers: markers) }.filter { m in
            let k = key(m)
            return !mine.contains(k) && seen.insert(k).inserted
        }
    }

    static func key(_ m: RoadMarker) -> String { m.id ?? "\(m.kind)|\(m.lat)|\(m.lon)" }

    /// The words on an event's row: what it is and where.
    static func title(_ m: RoadMarker) -> String {
        let k = DGKind(marker: m)
        switch k {
        case .crash: return "Crash"
        case .closure: return m.kind == "lane_closure" ? "Lane closed" : "Road closed"
        case .jam: return "Slow traffic"
        default: return k.short.replacingOccurrences(of: " ahead", with: "")
        }
    }

    static func sub(_ m: RoadMarker) -> String {
        [m.route, m.location].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? (m.label ?? "")
    }
}

/// What the trip that just ended met and missed, for the arrival sheet.
@MainActor
enum TripMemo {
    static var startedAt: Date?
    static var distance: Double = 0
    static var avoided: [RoadMarker] = []
}

// MARK: - The sheet frame

/// Glass pinned to the bottom edge, its top corners rounded, with the grab handle.
struct TripSheet<Content: View>: View {
    var identifier: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(DG.ink.opacity(0.18)).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
            content()
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear.dgGlass(DGCorners(radius: DG.R.trip, corners: [.topLeft, .topRight]))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A road event as a tinted row: its little lane drawing, what and where, and what it adds.
struct TripEventRow: View {
    let marker: RoadMarker
    var body: some View {
        let k = DGKind(marker: marker)
        let tone = marker.kind == "plugin" ? DGTone.low : k.tone
        HStack(spacing: 12) {
            LaneDrawing(kind: k, layout: marker.laneLayout)
                .frame(width: 60, height: 42)
                .scaleEffect(0.8)
                .frame(width: 60, height: 42)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(TripMath.title(marker)).font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(1)
                Text(TripMath.sub(marker)).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let d = marker.delayMin, d >= 1 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("+\(Int(d.rounded())) min").font(DG.font(16, .bold)).foregroundStyle(tone.ink).monospacedDigit()
                    Text("adds").font(DG.font(11.5, .medium)).foregroundStyle(DG.sub)
                }
            }
        }
        .padding(8).padding(.trailing, 6)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tone.color.opacity(0.16), lineWidth: 1))
    }
}

// MARK: - Place

/// The pin's sheet: what it is, how long it takes now, what is on the
/// way, Save, Watch this area, Share, and Go.
struct PlaceCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var later = LeaveLaterStore.shared
    let place: Place
    @State private var preview: [Route] = []
    @State private var showWatch = false

    private var from: CLLocationCoordinate2D? { model.origin?.coordinate ?? model.here }
    private var answer: LeaveLater? { later.answer(from: from, to: place.coordinate) }
    private var driveMin: Int? { answer?.now?.drive_min ?? preview.first.map { Int(($0.steps.reduce(0) { $0 + $1.duration } / 60).rounded()) } }
    private var along: [RoadMarker] {
        guard let r = preview.first else { return [] }
        return Array(TripMath.along(r.geometry.map(\.clLocationCoordinate2D), markers: model.allMarkers).prefix(2))
    }

    var body: some View {
        TripSheet(identifier: "place-sheet") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    DGDisc(systemImage: icon, tone: .low, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.kind == .home ? "Home" : place.kind == .work ? "Work" : place.shortName)
                            .font(DG.T.sheetTitle).foregroundStyle(DG.ink).lineLimit(2)
                        Text(place.name).font(DG.font(14)).foregroundStyle(DG.sub).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    DGBackButton(symbol: "xmark") { model.clearFound() }
                        .accessibilityIdentifier("place-close")
                }
                timeBlock.padding(.top, 16)
                if !along.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(DGTone.high.color).frame(width: 7, height: 7)
                        Text("On the way").font(DG.T.section).foregroundStyle(DG.sub)
                    }
                    .padding(.top, 16).padding(.bottom, 8)
                    VStack(spacing: 8) { ForEach(along, id: \.self) { TripEventRow(marker: $0) } }
                        .transition(.opacity)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("Save as Home") { model.places.set(.home, name: place.name, coordinate: place.coordinate) }
                        Button("Save as Work") { model.places.set(.work, name: place.name, coordinate: place.coordinate) }
                        Button("Save to favorites") { model.places.set(.saved, name: place.name, coordinate: place.coordinate) }
                    } label: {
                        Label("Save", systemImage: isSaved ? "star.fill" : "star").font(DG.T.button)
                            .foregroundStyle(DG.ink).frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.white.opacity(0.8), in: Capsule())
                            .overlay(Capsule().strokeBorder(DG.hair, lineWidth: 1))
                    }
                    .layoutPriority(1)
                    .accessibilityIdentifier("save-menu")
                    Button { showWatch = true } label: {
                        Label("Watch this area", systemImage: "eye").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dgGlass)
                    .layoutPriority(1.6)
                    .accessibilityIdentifier("place-watch")
                    ShareLink(item: Backend.mapURL(lat: place.lat, lon: place.lon)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(DG.ink)
                            .frame(width: 48, height: 48).background(Color.white.opacity(0.8), in: Circle())
                            .overlay(Circle().strokeBorder(DG.hair, lineWidth: 1))
                    }
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("place-share")
                }
                .padding(.top, 16)
                HStack(spacing: 12) {
                    Text(routesLine)
                        .font(DG.font(15, .semibold)).foregroundStyle(DG.sub)
                    Spacer()
                    Button { Task { await model.routes(to: place) } } label: {
                        Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(width: 150)
                    }
                    .buttonStyle(.dgPrimary)
                    .accessibilityIdentifier("navigate")
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 16)
        }
        .animation(DG.springSoft, value: along.count)
        .animation(DG.springSoft, value: driveMin)
        .task(id: place.id) {
            await later.ask(from: from, to: place.coordinate)
        }
        .task(id: place.id) { await loadPreview() }
        .sheet(isPresented: $showWatch) {
            WatchEditorView(start: .init(name: place.kind == .home ? "Home area" : place.shortName, center: place.coordinate))
        }
    }

    private var icon: String {
        switch place.kind {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .saved: return "star.fill"
        case .recent: return "mappin"
        }
    }

    /// "3 routes, 4.2 mi away".
    private var routesLine: String {
        let routes = preview.isEmpty ? nil : preview.count == 1 ? "1 route" : "\(preview.count) routes"
        let away = model.here.map { Units.distance(AlertsEngine.meters($0, place.coordinate)) + " away" }
        let line = [routes, away].compactMap { $0 }.joined(separator: ", ")
        return line.isEmpty ? " " : line
    }

    private var isSaved: Bool { model.places.places.contains { $0.kind != .recent && abs($0.lat - place.lat) < 1e-5 && abs($0.lon - place.lon) < 1e-5 } }

    @ViewBuilder private var timeBlock: some View {
        if let m = driveMin {
            VStack(alignment: .leading, spacing: 2) {
                Text(Units.duration(Double(m) * 60)).font(DG.font(34, .bold)).foregroundStyle(DG.ink).monospacedDigit()
                HStack(spacing: 8) {
                    Text("Arrive \(Units.time(Date().addingTimeInterval(Double(m) * 60)))").font(DG.font(15, .medium)).foregroundStyle(DG.sub)
                    if let d = answer?.now?.delay_min, d >= 2 {
                        Text("\(d) min slower than usual").font(DG.font(15, .semibold)).foregroundStyle(DGTone.mid.ink)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("place-time")
        } else if let here = model.here {
            Text(Units.distance(AlertsEngine.meters(here, place.coordinate)) + " away")
                .font(DG.font(17, .semibold)).foregroundStyle(DG.sub)
        }
    }

    /// The likely routes, fetched quietly for the time and "On the way";
    /// Go still asks for them the usual way.
    private func loadPreview() async {
        guard let from else { return }
        preview = []
        if let found = try? await model.core.getRoutes(initialLocation: UserLocation(clCoordinateLocation2D: from),
                                                       waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: place.coordinate), kind: .break)]) {
            preview = found
        }
    }
}

// MARK: - Routes

/// The alternatives, fastest first, with what is on each, when to
/// leave, saving the map, and Start.
struct RoutesCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var later = LeaveLaterStore.shared
    let routes: [Route]
    let place: Place
    @State private var chosen = 0
    @State private var barsOpen = false
    @Namespace private var ns

    private var from: CLLocationCoordinate2D? { model.origin?.coordinate ?? model.here }
    private var answer: LeaveLater? { later.answer(from: from, to: place.coordinate) }

    var body: some View {
        TripSheet(identifier: "routes-sheet") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("To \(place.kind == .home ? "Home" : place.kind == .work ? "Work" : place.shortName)")
                            .font(DG.font(22, .bold)).foregroundStyle(DG.ink).lineLimit(1)
                        Text(model.origin.map { "From \($0.shortName)" } ?? "From where you are").font(DG.font(13.5)).foregroundStyle(DG.sub)
                    }
                    Spacer()
                    DGBackButton(symbol: "xmark") { model.state = .found(place); model.preview = nil }
                        .accessibilityIdentifier("routes-close")
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(routes.prefix(3).enumerated()), id: \.offset) { i, route in routeRow(i, route) }
                }
                .padding(.horizontal, 8)
                leaveLater.padding(.horizontal, 16).padding(.top, 10)
                HStack(spacing: 10) {
                    saveMapButton
                    Button { start() } label: {
                        HStack(spacing: 8) {
                            Text("Start")
                            Text("Arrive \(Units.time(Date().addingTimeInterval(seconds(routes[chosen]))))")
                                .font(DG.font(14, .medium)).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dgPrimary)
                    .accessibilityIdentifier("start")
                }
                .padding(.horizontal, 16).padding(.top, 14)
            }
        }
        .task(id: place.id) { await later.ask(from: from, to: place.coordinate) }
    }

    private func seconds(_ r: Route) -> Double { r.steps.reduce(0) { $0 + $1.duration } }

    private func routeRow(_ i: Int, _ route: Route) -> some View {
        let on = i == chosen
        let events = TripMath.along(route.geometry.map(\.clLocationCoordinate2D), markers: model.allMarkers)
        return Button {
            withAnimation(DG.snap) { chosen = i }
            model.preview = route
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(roadName(route).map { "via \($0)" } ?? (i == 0 ? "Fastest route" : "Route \(i + 1)"))
                            .font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(1)
                        if i == 0 { DGTag(text: "Fastest", tone: .good) }
                    }
                    HStack(spacing: 6) {
                        if events.isEmpty {
                            Text("Nothing reported on the way").font(DG.T.rowSub).foregroundStyle(DG.sub)
                        } else {
                            ForEach(Array(groups(events).prefix(2).enumerated()), id: \.offset) { _, g in chip(g.kind, g.count) }
                        }
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Units.duration(seconds(route))).font(DG.font(22, .bold))
                        .foregroundStyle(on ? DGTone.low.ink : DG.ink).monospacedDigit()
                    Text(Units.distance(route.distance)).font(DG.font(13, .medium)).foregroundStyle(DG.sub)
                }
            }
            .padding(.horizontal, 12).frame(height: 74)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DG.path.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DG.path.opacity(0.55), lineWidth: 1.5))
                        .matchedGeometryEffect(id: "route-pill", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route-\(i)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func groups(_ ms: [RoadMarker]) -> [(kind: DGKind, count: Int)] {
        var order: [DGKind] = [], count: [DGKind: Int] = [:]
        for m in ms { let k = DGKind(marker: m); if count[k] == nil { order.append(k) }; count[k, default: 0] += 1 }
        return order.sorted { $0.tone.rank < $1.tone.rank }.map { ($0, count[$0] ?? 0) }
    }

    private func chip(_ k: DGKind, _ n: Int) -> some View {
        HStack(spacing: 5) {
            DGDisc(kind: k, tone: k.tone, size: 18)
            Text(n > 1 ? "\(n) \(plural(k))" : k.short.replacingOccurrences(of: " ahead", with: "")).font(DG.T.chip)
        }
        .foregroundStyle(k.tone.ink)
        .padding(.leading, 4).padding(.trailing, 9).frame(height: 26)
        .background(k.tone.color.opacity(0.12), in: Capsule())
    }

    private func plural(_ k: DGKind) -> String {
        switch k {
        case .crash: return "crashes"
        case .closure: return "closures"
        case .hazard: return "hazards"
        case .jam: return "slowdowns"
        default: return k.rawValue + "s"
        }
    }

    @ViewBuilder private var leaveLater: some View {
        if let a = answer, a.departures.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Leave later").font(DG.T.section).foregroundStyle(DG.sub)
                VStack(spacing: 0) {
                    Button { withAnimation(DG.springSoft) { barsOpen.toggle() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: a.best == nil ? "clock" : "clock.badge.checkmark").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(a.best == nil ? DG.sub : DGTone.good.ink)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.headline ?? "Leaving now is quickest").font(DG.font(15, .semibold))
                                    .foregroundStyle(a.best == nil ? DG.ink : DGTone.good.ink)
                                if let r = a.reason { Text(r).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(2) }
                            }
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.sub)
                                .rotationEffect(.degrees(barsOpen ? 180 : 0))
                        }
                        .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("leave-later")
                    if barsOpen { LeaveLaterBars(bars: a.bars()).padding(.horizontal, 14).padding(.bottom, 12).transition(.opacity) }
                }
                .background((a.best == nil ? DG.ink.opacity(0.04) : DGTone.good.color.opacity(0.1)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    /// Save the trip's map: done on its own on Wi-Fi when the trip
    /// starts; this is the tap for mobile data.
    @ViewBuilder private var saveMapButton: some View {
        let saving = !model.mapFiles.progress.isEmpty
        let auto = Connectivity.shared.onWifi && model.prefs.mapAutoSave
        Button { model.saveTripMap(routes[chosen], to: place, manual: true) } label: {
            ZStack {
                if saving {
                    Circle().trim(from: 0, to: model.mapFiles.progress.values.first ?? 0)
                        .stroke(DG.path, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        .padding(4)
                }
                Image(systemName: auto ? "checkmark" : "arrow.down.to.line").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(DG.ink)
            .frame(width: 48, height: 48).background(Color.white.opacity(0.8), in: Circle())
            .overlay(Circle().strokeBorder(DG.hair, lineWidth: 1))
        }
        .buttonStyle(DGPressStyle())
        .disabled(!model.online || saving || auto)
        .accessibilityLabel(auto ? "The map saves on its own on Wi-Fi" : Connectivity.shared.onWifi ? "Save the map for this trip" : "Save the map for this trip (mobile data)")
        .accessibilityIdentifier("save-trip-map")
    }

    private func start() {
        let pick = routes[chosen]
        TripMemo.startedAt = Date()
        TripMemo.distance = pick.distance
        TripMemo.avoided = TripMath.avoided(chosen: pick.geometry.map(\.clLocationCoordinate2D),
                                            others: routes.enumerated().filter { $0.offset != chosen }.map { $0.element.geometry.map(\.clLocationCoordinate2D) },
                                            markers: model.allMarkers)
        model.start(pick, to: place)
    }

    private func roadName(_ route: Route) -> String? {
        route.steps.max { $0.distance < $1.distance }?.roadName?.trimmingCharacters(in: .whitespaces)
            .split(separator: ";").first.map(String.init)
    }
}

extension DGTone {
    /// Most urgent first.
    var rank: Int { switch self { case .high: 0; case .mid: 1; case .low: 2; case .good: 3; case .clear: 4 } }
}

/// One bar per departure: the now bar blue, the best one green. They
/// grow in one after another when the row opens.
struct LeaveLaterBars: View {
    let bars: [LeaveLater.Bar]
    @State private var grown = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                VStack(spacing: 4) {
                    Text("\(b.minutes)").font(DG.font(11, .semibold)).foregroundStyle(b.isBest ? DGTone.good.ink : DG.sub).monospacedDigit()
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(b.isBest ? DGTone.good.color : b.isNow ? DG.path.opacity(0.45) : DG.ink.opacity(0.12))
                        .frame(height: b.height)
                        .scaleEffect(x: 1, y: grown ? 1 : 0.05, anchor: .bottom)
                        .animation(DG.spring.delay(Double(i) * 0.035), value: grown)
                    Text(b.label).font(DG.font(10.5, .medium)).foregroundStyle(DG.sub).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 76 + 34, alignment: .bottom)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.map { "\($0.label), \($0.minutes) minutes" }.joined(separator: "; "))
        .accessibilityIdentifier("leave-later-bars")
    }
}

// MARK: - Arrive

/// The trip is over: how long it took, how far, when, and what the
/// route kept you clear of.
struct ArriveCard: View {
    @EnvironmentObject var model: AppModel
    let place: Place
    @State private var saved = false

    var body: some View {
        TripSheet(identifier: "arrive-sheet") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    DGDisc(systemImage: "flag.checkered", tone: .good, size: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You have arrived").font(DG.T.sheetTitle).foregroundStyle(DG.ink)
                        Text(place.kind == .home ? "Home" : place.kind == .work ? "Work" : place.shortName)
                            .font(DG.font(15)).foregroundStyle(DG.sub).lineLimit(1)
                    }
                }
                HStack(spacing: 0) {
                    stat("Drive time", TripMemo.startedAt.map { Units.duration(Date().timeIntervalSince($0)) } ?? "–")
                    Rectangle().fill(DG.hair).frame(width: 1, height: 36)
                    stat("Distance", TripMemo.distance > 0 ? Units.distance(TripMemo.distance) : "–")
                    Rectangle().fill(DG.hair).frame(width: 1, height: 36)
                    stat("Arrived", Units.time(Date()))
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
                .padding(.top, 16)
                if !TripMemo.avoided.isEmpty {
                    Text("What you avoided").font(DG.T.section).foregroundStyle(DG.sub).padding(.top, 16).padding(.bottom, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(TripMemo.avoided.prefix(3).enumerated()), id: \.offset) { i, m in
                            if i > 0 { DGDivider(inset: 54) }
                            HStack(spacing: 12) {
                                DGDisc(kind: DGKind(marker: m), tone: .clear, size: 32, ghost: true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(TripMath.title(m)).font(DG.T.rowTitle).foregroundStyle(DG.ink)
                                    Text(TripMath.sub(m)).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1)
                                }
                                Spacer()
                                if let d = m.delayMin, d >= 1 {
                                    Text("\(Int(d)) min saved").font(DG.font(13, .semibold)).foregroundStyle(DGTone.good.ink)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 54)
                        }
                    }
                    .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
                }
                HStack(spacing: 10) {
                    Button {
                        model.places.set(.saved, name: place.name, coordinate: place.coordinate)
                        withAnimation(DG.spring) { saved = true }
                    } label: { Label(saved ? "Saved" : "Save place", systemImage: saved ? "checkmark" : "star").frame(maxWidth: .infinity) }
                        .buttonStyle(saved ? DGButtonStyle.dgDone : DGButtonStyle.dgGlass)
                        .disabled(saved || place.kind != .recent)
                        .accessibilityIdentifier("arrive-save")
                    Button { model.stop() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(.dgPrimary)
                        .accessibilityIdentifier("arrive-done")
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DG.font(18, .bold)).foregroundStyle(DG.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(DG.font(12, .medium)).foregroundStyle(DG.sub)
        }
        .frame(maxWidth: .infinity)
    }
}
