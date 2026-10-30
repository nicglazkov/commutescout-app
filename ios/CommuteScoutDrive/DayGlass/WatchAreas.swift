import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

// Watch areas: the list with each area's live line, how alerts reach
// you (with quiet hours), and the editor for a circle, a route corridor
// or a shape of your own.

// MARK: - Model

struct Watch: Decodable, Identifiable, Equatable {
    struct Point: Decodable, Equatable { let lat: Double; let lon: Double }
    struct Live: Decodable, Equatable {
        struct Top: Decodable, Equatable { let kind: String?; let title: String?; let body: String? }
        let count: Int?
        let by_kind: [String: Int]?
        let top: Top?
        let quiet_since: String?
        let updated_at: String?
    }
    let id: String
    let name: String?
    let type: String?
    let center: Point?
    let radius_km: Double?
    let points: [Point]?
    let buffer_km: Double?
    let length_km: Double?
    let kinds: [String]?
    let active: Bool?
    let quiet_hours: Bool?
    let live: Live?
}

struct WatchPrefs: Codable, Equatable {
    struct Quiet: Codable, Equatable {
        var enabled = false
        var start = "22:00"
        var end = "06:00"
        var tz = TimeZone.current.identifier
        var summary = true
    }
    var alerts_push: Bool?
    var alerts_email: Bool?
    var notify_clears: Bool?
    var quiet_hours: Quiet?
}

private struct WatchMe: Decodable {
    let email: String?
    let status: String?
    let prefs: WatchPrefs?
    let watches: [Watch]
}

enum WatchText {
    static let kinds: [(key: String, label: String, symbol: String, tone: DGTone)] = [
        ("incident", "Incidents", "car.fill", .high), ("closure", "Closures", "xmark.octagon.fill", .high),
        ("chain", "Chain controls", "link", .mid), ("fire", "Wildfires", "flame.fill", .high),
    ]

    static func tone(_ kind: String?) -> DGTone {
        switch kind { case "chain": return .mid; case nil: return .good; default: return .high }
    }

    /// "Quiet since 6:10 AM", "1 crash now", "Chains required on I-70".
    static func status(_ w: Watch) -> (text: String, tone: DGTone, live: Bool) {
        if w.active == false { return ("Paused", .clear, false) }
        guard let l = w.live else { return ("Watching", .clear, false) }
        if (l.count ?? 0) == 0 {
            if let q = l.quiet_since, let d = LeaveLater.date(q) ?? ISO8601DateFormatter().date(from: q) {
                return ("Quiet since \(Calendar.current.isDateInToday(d) ? Units.time(d) : d.formatted(.dateTime.month(.abbreviated).day()))", .good, false)
            }
            return ("Quiet", .good, false)
        }
        if let t = l.top?.title, !t.isEmpty { return (t, tone(l.top?.kind), true) }
        let n = l.count ?? 0
        return ("\(n) alert\(n == 1 ? "" : "s") now", tone(l.top?.kind), true)
    }

    static func meta(_ w: Watch) -> String {
        switch w.type {
        case "route":
            let b = Units.distance((w.buffer_km ?? 3.2) * 1000)
            return w.length_km.map { "\(Units.distance($0 * 1000)) drive, \(b) each side" } ?? "A drive, \(b) each side"
        case "polygon":
            let pts = (w.points ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            return "Your own shape, about \(WatchMath.areaText(sqKm: WatchMath.polygonSqKm(pts)))"
        default:
            return "\(Units.distance((w.radius_km ?? 0) * 1000)) around its center"
        }
    }
}

/// A still map, for drawing shapes over: no gestures, no ornaments.
struct StillMap: View {
    @EnvironmentObject var model: AppModel
    var center: CLLocationCoordinate2D
    var zoom: Double
    var line: [CLLocationCoordinate2D] = []

    var body: some View {
        MapView(styleURL: model.styleURL, camera: .constant(.center(center, zoom: zoom))) {
            if line.count > 1 {
                let src = ShapeSource(identifier: "cs-still-line") {
                    MLNPolylineFeature(coordinates: line, count: UInt(line.count))
                }
                LineStyleLayer(identifier: "cs-still-buffer", source: src)
                    .lineColor(UIColor(red: 0.18, green: 0.49, blue: 0.96, alpha: 1)).lineOpacity(0.16).lineWidth(26).lineCap(.round).lineJoin(.round)
                LineStyleLayer(identifier: "cs-still-road", source: src)
                    .lineColor(UIColor(red: 0.18, green: 0.49, blue: 0.96, alpha: 1)).lineWidth(4).lineCap(.round).lineJoin(.round)
            }
        }
        .unsafeMapViewControllerModifier { c in
            c.mapView.isUserInteractionEnabled = false
            c.mapView.logoView.isHidden = true
            c.mapView.attributionButton.isHidden = true
            c.mapView.compassView.isHidden = true
        }
    }
}

// MARK: - The list

/// Kept for the Tools sheet: the watch areas page in its own stack.
struct WatchesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { WatchAreasView(onClose: { dismiss() }) }
    }
}

struct WatchAreasView: View {
    @EnvironmentObject var model: AppModel
    var onClose: (() -> Void)?
    @State private var watches: [Watch] = []
    @State private var prefs = WatchPrefs()
    @State private var loading = false
    @State private var error: String?
    @State private var showSignIn = false
    @State private var editing = false
    @State private var confirmDelete: Watch?

    var body: some View {
        ZStack(alignment: .bottom) {
            DGPage(title: "Watch areas", largeTitle: true,
                   intro: "Get an alert when something happens inside an area or along a drive, anywhere in the US.",
                   identifier: "watch-areas") {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.account.signedIn {
                        DGGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Watch areas need an account, the same one as the website.").font(DG.font(15, .medium)).foregroundStyle(DG.ink)
                                Button { showSignIn = true } label: { Text("Sign in").frame(maxWidth: .infinity) }.buttonStyle(.dgBlue)
                            }
                            .padding(16)
                        }
                    } else {
                        if loading, watches.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(24) }
                        if !loading, watches.isEmpty {
                            Text("None yet. Draw one with New watch area.").font(DG.font(15)).foregroundStyle(DG.sub).padding(.vertical, 12)
                        }
                        ForEach(watches) { w in card(w) }
                        DGSectionLabel("How you hear about it")
                        DGGroup {
                            DGSwitchRow(title: "Notifications", sub: "On this phone and your others",
                                        isOn: prefBinding(\.alerts_push, default: true, key: "alerts_push"), identifier: "watch-push") {
                                DGSoftTile(symbol: "bell") }
                            DGDivider()
                            DGSwitchRow(title: "Email", sub: "To the address on your account",
                                        isOn: prefBinding(\.alerts_email, default: false, key: "alerts_email"), identifier: "watch-email") {
                                DGSoftTile(symbol: "envelope") }
                            DGDivider()
                            DGSwitchRow(title: "Tell me when it clears", sub: "A short follow-up once it's over",
                                        isOn: prefBinding(\.notify_clears, default: false, key: "notify_clears"), identifier: "watch-clears") {
                                DGSoftTile(symbol: "checkmark") }
                            DGDivider()
                            NavigationLink {
                                QuietHoursPage(quiet: prefs.quiet_hours ?? .init()) { q in
                                    prefs.quiet_hours = q
                                    Task { await savePrefs(["quiet_hours": ["enabled": q.enabled, "start": q.start, "end": q.end, "tz": q.tz, "summary": q.summary]]) }
                                }
                            } label: {
                                DGRow(title: "Quiet hours", sub: quietText) { DGSoftTile(symbol: "moon") }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("watch-quiet")
                        }
                        DGFootnote("You can have up to \(WatchMath.maxWatches) watch areas. Alerts come from official sources only; plugin data never reaches a watch area.")
                    }
                }
            }
            if model.account.signedIn {
                DGDock {
                    Button { editing = true } label: { Label("New watch area", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.dgPrimary)
                        .disabled(watches.count >= WatchMath.maxWatches)
                        .accessibilityIdentifier("watch-new")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose { DGBackButton(symbol: "xmark", action: onClose).padding(.trailing, 16).padding(.top, 10) }
        }
        .task { await load() }
        .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to keep watch areas.") }
        .fullScreenCover(isPresented: $editing, onDismiss: { Task { await load() } }) {
            WatchEditorView(start: .init(name: model.places.home == nil ? "" : "Home area",
                                         center: model.places.home?.coordinate ?? model.here ?? model.viewCenter ?? AppModel.defaultCenter))
        }
        .confirmationDialog(confirmDelete.map { "Delete \($0.name ?? "this watch area")?" } ?? "",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { w in
            Button("Delete", role: .destructive) { Task { await delete(w) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Watch areas", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var quietText: String {
        guard let q = prefs.quiet_hours, q.enabled else { return "Off" }
        return "\(QuietHoursPage.label(q.start)) to \(QuietHoursPage.label(q.end))" + (q.summary ? ", then one summary" : "")
    }

    private func card(_ w: Watch) -> some View {
        let s = WatchText.status(w)
        return HStack(spacing: 14) {
            WatchMini(watch: w).frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.name ?? "Watch area").font(DG.font(17, .semibold)).foregroundStyle(DG.ink).lineLimit(1)
                HStack(spacing: 6) {
                    LiveDot(tone: s.tone, pulsing: s.live)
                    Text(s.text).font(DG.font(14, .semibold)).foregroundStyle(s.tone.ink).lineLimit(1)
                }
                Text(WatchText.meta(w)).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button(role: .destructive) { confirmDelete = w } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(DG.hex(0xb3bccb))
                    .frame(width: 32, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("watch-menu-\(w.id)")
        }
        .padding(10).padding(.trailing, 4)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .shadow(color: DG.ink.opacity(0.05), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-card")
    }

    private func prefBinding(_ kp: WritableKeyPath<WatchPrefs, Bool?>, default d: Bool, key: String) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: kp] ?? d }, set: { v in
            prefs[keyPath: kp] = v
            Task { await savePrefs([key: v]) }
        })
    }

    private func load() async {
        guard let token = await model.account.token() else { return }
        loading = true; defer { loading = false }
        if let (status, data) = try? await Backend.send("GET", "api/watch/me", token: token), status == 200,
           let me = try? JSONDecoder().decode(WatchMe.self, from: data) {
            watches = me.watches
            prefs = me.prefs ?? WatchPrefs()
        }
    }

    private func savePrefs(_ body: [String: Any]) async {
        guard let token = await model.account.token() else { return }
        if let (status, data) = try? await Backend.send("POST", "api/watch/prefs", token: token, body: body), status >= 300 {
            error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Could not save that (\(status))."
        }
    }

    private func delete(_ w: Watch) async {
        guard let token = await model.account.token() else { return }
        _ = try? await Backend.send("DELETE", "api/watch/\(w.id)", token: token)
        await load()
    }
}

/// A status dot that breathes while something is live.
struct LiveDot: View {
    var tone: DGTone
    var pulsing: Bool
    @State private var on = false
    var body: some View {
        ZStack {
            if pulsing {
                Circle().fill(tone.color.opacity(0.35)).frame(width: 14, height: 14)
                    .scaleEffect(on ? 1.3 : 0.6).opacity(on ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: on)
            }
            Circle().fill(tone.color).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear { on = true }
    }
}

/// A watch area's little picture: a street grid with its shape on it.
struct WatchMini: View {
    let watch: Watch
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(r), with: .color(DG.hex(0xeef2f7)))
            for i in 1 ..< 4 {
                let v = size.width * CGFloat(i) / 4
                ctx.stroke(Path { p in p.move(to: CGPoint(x: v, y: 0)); p.addLine(to: CGPoint(x: v, y: size.height)) }, with: .color(.white), lineWidth: 2)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: v)); p.addLine(to: CGPoint(x: size.width, y: v)) }, with: .color(.white), lineWidth: 2)
            }
            let blue = DG.path
            switch watch.type {
            case "route", "polygon":
                let pts = (watch.points ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                guard pts.count > 1 else { return }
                let s = pts.map(\.latitude).min()!, n = pts.map(\.latitude).max()!
                let w = pts.map(\.longitude).min()!, e = pts.map(\.longitude).max()!
                let span = max(n - s, (e - w) * cos(s * .pi / 180), 1e-4)
                func at(_ c: CLLocationCoordinate2D) -> CGPoint {
                    CGPoint(x: size.width / 2 + CGFloat((c.longitude - (w + e) / 2) * cos(s * .pi / 180) / span) * size.width * 0.7,
                            y: size.height / 2 - CGFloat((c.latitude - (s + n) / 2) / span) * size.height * 0.7)
                }
                var path = Path()
                path.move(to: at(pts[0]))
                for c in pts.dropFirst() { path.addLine(to: at(c)) }
                if watch.type == "polygon" {
                    path.closeSubpath()
                    ctx.fill(path, with: .color(blue.opacity(0.18)))
                    ctx.stroke(path, with: .color(blue), lineWidth: 2)
                } else {
                    ctx.stroke(path, with: .color(blue.opacity(0.2)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(blue), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            default:
                let c = CGRect(x: size.width * 0.17, y: size.height * 0.17, width: size.width * 0.66, height: size.height * 0.66)
                ctx.fill(Path(ellipseIn: c), with: .color(blue.opacity(0.14)))
                ctx.stroke(Path(ellipseIn: c), with: .color(blue), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 3, y: size.height / 2 - 3, width: 6, height: 6)), with: .color(blue))
            }
            if let live = watch.live, (live.count ?? 0) > 0 {
                let t = WatchText.tone(live.top?.kind)
                ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.5 - 6, y: size.height * 0.36 - 6, width: 12, height: 12)), with: .color(t.color))
                ctx.stroke(Path(ellipseIn: CGRect(x: size.width * 0.5 - 6, y: size.height * 0.36 - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Quiet hours: when watch alerts hold, and whether one summary follows.
struct QuietHoursPage: View {
    @State var quiet: WatchPrefs.Quiet
    var onChange: (WatchPrefs.Quiet) -> Void

    var body: some View {
        DGPage(title: "Quiet hours", identifier: "quiet-hours") {
            VStack(alignment: .leading, spacing: 0) {
                DGGroup {
                    DGSwitchRow(title: "Quiet hours", sub: "Watch alerts wait until the morning", isOn: $quiet.enabled, identifier: "quiet-enabled")
                    if quiet.enabled {
                        DGDivider(inset: 14)
                        timeRow("Starts", \.start)
                        DGDivider(inset: 14)
                        timeRow("Ends", \.end)
                        DGDivider(inset: 14)
                        DGSwitchRow(title: "Then one summary", sub: "What happened overnight, in one note", isOn: $quiet.summary, identifier: "quiet-summary")
                    }
                }
                .padding(.top, 8)
                DGFootnote("Times are in \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? quiet.tz). A watch area can opt out of quiet hours in its own settings.")
            }
        }
        .onChange(of: quiet) { q in var q = q; q.tz = TimeZone.current.identifier; onChange(q) }
    }

    private func timeRow(_ title: String, _ kp: WritableKeyPath<WatchPrefs.Quiet, String>) -> some View {
        HStack {
            Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
            Spacer()
            DatePicker("", selection: Binding(get: { Self.date(quiet[keyPath: kp]) }, set: { quiet[keyPath: kp] = Self.hhmm($0) }),
                       displayedComponents: .hourAndMinute).labelsHidden()
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
    }

    static func date(_ hhmm: String) -> Date {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: p.first ?? 0, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
    }

    static func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func label(_ hhmm: String) -> String { Units.time(date(hhmm)) }
}

// MARK: - The editor

/// A new watch area: a circle with a handle to drag its radius, the
/// drive from Home to Work with a corridor either side, or a shape with
/// corners to drag. The map stays still and zooms out when the circle
/// outgrows it.
struct WatchEditorView: View {
    struct Start { var name: String; var center: CLLocationCoordinate2D }
    enum Shape: String, CaseIterable { case circle = "Circle", route = "Route", shape = "Shape" }

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: Start
    @State private var name = ""
    @State private var shape: Shape = .circle
    @State private var radiusKm = 12.87         // 8 mi
    @State private var corners: [CLLocationCoordinate2D] = []
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var routeNote: String?
    @State private var kinds: Set<String> = ["incident", "closure", "fire"]
    @State private var quiet = true
    @State private var snap = 0
    @State private var saving = false
    @State private var saved: String?
    @State private var error: String?
    @State private var showSignIn = false
    @State private var dragStart: Double?

    private var center: CLLocationCoordinate2D { start.center }

    /// The map shows 12 mi of radius in 140 points; past that it zooms out.
    private func zoom(for size: CGSize) -> Double {
        switch shape {
        case .circle: return Mercator.zoom(fitting: max(radiusKm, 19.3) * 1000, in: 130, at: center.latitude)
        case .shape:
            return Mercator.zoom(fitting: shapeSpanM * 0.62, in: 130, at: center.latitude)
        case .route:
            guard route.count > 1 else { return 10 }
            let s = route.map(\.latitude).min()!, n = route.map(\.latitude).max()!
            let w = route.map(\.longitude).min()!, e = route.map(\.longitude).max()!
            let m = max((n - s) * 110_574, (e - w) * 111_320 * cos(center.latitude * .pi / 180))
            return Mercator.zoom(fitting: m, in: 260, at: (s + n) / 2)
        }
    }

    private var shapeSpanM: Double {
        guard corners.count > 1 else { return 20_000 }
        var best = 0.0
        for c in corners { best = max(best, AlertsEngine.meters(center, c)) }
        return max(8000, best * 1.6)
    }

    private var mapCenter: CLLocationCoordinate2D {
        guard shape == .route, route.count > 1 else { return center }
        return CLLocationCoordinate2D(latitude: (route.map(\.latitude).min()! + route.map(\.latitude).max()!) / 2,
                                      longitude: (route.map(\.longitude).min()! + route.map(\.longitude).max()!) / 2)
    }

    var body: some View {
        GeometryReader { geo in
            let mapSize = CGSize(width: geo.size.width, height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom - 380)
            let z = zoom(for: mapSize)
            let merc = Mercator(center: mapCenter, zoom: z, size: mapSize)
            ZStack(alignment: .top) {
                StillMap(center: mapCenter, zoom: z, line: shape == .route ? route : [])
                    .frame(height: mapSize.height + 60)
                    .animation(DG.springSoft, value: z)
                overlay(merc)
                    .frame(width: mapSize.width, height: mapSize.height)
                topBar.padding(.horizontal, 16).padding(.top, geo.safeAreaInsets.top + 6)
                VStack {
                    Spacer()
                    DGSheet(snaps: [468, 640], index: $snap, identifier: "watch-editor-sheet") { form }
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            name = start.name
            corners = Self.square(around: center, km: 12)
        }
        .task(id: shape) { if shape == .route, route.isEmpty { await loadRoute() } }
        .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to keep watch areas.") }
        .alert("Watch areas", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    static func square(around c: CLLocationCoordinate2D, km: Double) -> [CLLocationCoordinate2D] {
        let dLat = km / 110.574, dLon = km / (111.32 * cos(c.latitude * .pi / 180))
        return [(-1, -1), (-1, 1), (1, 1), (1, -1)].map { CLLocationCoordinate2D(latitude: c.latitude + $0.0 * dLat, longitude: c.longitude + $0.1 * dLon) }
    }

    private var topBar: some View {
        ZStack {
            Text("New watch area").font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
            HStack { DGBackButton(symbol: "xmark") { dismiss() }; Spacer() }
        }
        .padding(.horizontal, 8).frame(height: 52)
        .dgGlass(radius: 26)
    }

    @ViewBuilder private func overlay(_ m: Mercator) -> some View {
        switch shape {
        case .circle:
            let c = m.point(center)
            let r = radiusKm * 1000 * m.pointsPerMeter
            ZStack {
                Circle().fill(DG.path.opacity(0.14)).overlay(Circle().strokeBorder(DG.path, lineWidth: 2.5))
                    .frame(width: r * 2, height: r * 2).position(c)
                Path { p in p.move(to: c); p.addLine(to: CGPoint(x: c.x + r, y: c.y)) }
                    .stroke(DG.path, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                Circle().fill(DG.path).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white, lineWidth: 2)).position(c)
                Text(Units.distance(radiusKm * 1000)).font(DG.font(14, .bold)).foregroundStyle(DG.ink)
                    .padding(.horizontal, 12).frame(height: 32).dgGlass(Capsule())
                    .position(x: c.x + r * 0.55, y: c.y - 30)
                Circle().fill(.white).frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(DG.path, lineWidth: 3))
                    .shadow(color: DG.ink.opacity(0.25), radius: 4, y: 2)
                    .frame(width: 54, height: 54).contentShape(Circle())
                    .position(x: c.x + r, y: c.y)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        if dragStart == nil { dragStart = radiusKm }
                        let d = Double(hypot(v.location.x - c.x, v.location.y - c.y)) / m.pointsPerMeter / 1000
                        radiusKm = min(WatchMath.maxRadiusKm, max(1.609, d))
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityElement()
                    .accessibilityLabel("Radius")
                    .accessibilityValue(Units.distance(radiusKm * 1000))
                    .accessibilityAdjustableAction { dir in
                        radiusKm = min(WatchMath.maxRadiusKm, max(1.609, radiusKm + (dir == .increment ? 1.609 : -1.609)))
                    }
                    .accessibilityIdentifier("watch-radius")
            }
        case .shape:
            let pts = corners.map(m.point)
            ZStack {
                Path { p in p.addLines(pts); p.closeSubpath() }.fill(DG.path.opacity(0.14))
                Path { p in p.addLines(pts); p.closeSubpath() }.stroke(DG.path, lineWidth: 2.5)
                ForEach(corners.indices, id: \.self) { i in
                    Circle().fill(.white).frame(width: 24, height: 24).overlay(Circle().strokeBorder(DG.path, lineWidth: 3))
                        .shadow(color: DG.ink.opacity(0.25), radius: 3, y: 1)
                        .frame(width: 48, height: 48).contentShape(Circle())
                        .position(pts[i])
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            var next = corners
                            next[i] = m.coordinate(v.location)
                            if WatchMath.polygonSqKm(next) <= WatchMath.maxPolygonSqKm { corners = next }
                        })
                        .accessibilityLabel("Corner \(i + 1)")
                }
            }
        case .route:
            if route.count > 1 {
                ForEach([route.first!, route.last!].indices, id: \.self) { i in
                    let c = i == 0 ? route.first! : route.last!
                    Image(systemName: i == 0 ? "house.fill" : "briefcase.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(DG.path, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(m.point(c))
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name").font(DG.font(12.5, .medium)).foregroundStyle(DG.sub)
                    TextField("Home area", text: $name).font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
                        .accessibilityIdentifier("watch-name")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
                DGSegmented(options: [(Shape.circle, "Circle", "circle.circle"), (.route, "Route", "point.topleft.down.curvedto.point.bottomright.up"),
                                      (.shape, "Shape", "pentagon")], selection: $shape, height: 48, identifier: "watch-shape")
                    .padding(.top, 10)
                Text(help).font(DG.font(13)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    .padding(.horizontal, 4)
                Text("What to watch").font(DG.font(17, .bold)).foregroundStyle(DG.ink).padding(.top, 16)
                FlowRow(spacing: 8) {
                    ForEach(WatchText.kinds, id: \.key) { k in kindChip(k) }
                }
                .padding(.top, 10)
                DGGroup {
                    DGSwitchRow(title: "Quiet hours", sub: "Hold this area's alerts overnight, like your others", isOn: $quiet, identifier: "watch-quiet-hours") {
                        DGSoftTile(symbol: "moon")
                    }
                }
                .padding(.top, 14)
                Button { Task { await save() } } label: {
                    Text(saved.map { "Saved. Watching \($0)" } ?? (kinds.isEmpty ? "Pick at least one kind" : saving ? "Saving" : "Save watch area"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(saved == nil ? DGButtonStyle.dgPrimary : DGButtonStyle.dgDone)
                .disabled(kinds.isEmpty || saving || saved != nil || (shape == .route && route.count < 2))
                .padding(.top, 16)
                .accessibilityIdentifier("watch-save")
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }

    private var help: String {
        switch shape {
        case .circle:
            return "Drag the handle to resize, up to \(Units.distance(WatchMath.maxRadiusKm * 1000)). This circle covers about \(WatchMath.areaText(sqKm: WatchMath.circleSqKm(radiusKm)))."
        case .route:
            return routeNote ?? "Follows your usual drive from Home to Work, \(Units.distance(WatchMath.bufferKm * 1000)) on each side."
        case .shape:
            return "Drag the corners to draw your own area, up to \(WatchMath.areaText(sqKm: WatchMath.maxPolygonSqKm)). This one covers about \(WatchMath.areaText(sqKm: WatchMath.polygonSqKm(corners)))."
        }
    }

    private func kindChip(_ k: (key: String, label: String, symbol: String, tone: DGTone)) -> some View {
        let on = kinds.contains(k.key)
        return Button {
            withAnimation(DG.spring) { if on { kinds.remove(k.key) } else { kinds.insert(k.key) } }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: k.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(k.tone.color)
                Text(k.label).font(DG.font(15, .semibold)).foregroundStyle(on ? DG.ink : DG.sub)
                if on { DGCheck(on: true, size: 22) }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(on ? DG.path.opacity(0.1) : Color.white.opacity(0.8), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? DG.path.opacity(0.5) : DG.hair, lineWidth: 1.5))
        }
        .buttonStyle(DGPressStyle())
        .accessibilityIdentifier("watch-kind-\(k.key)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func loadRoute() async {
        guard let home = model.places.home, let work = model.places.work else {
            routeNote = "Set Home and Work in Saved places to watch your drive between them."
            return
        }
        routeNote = nil
        if let found = try? await model.core.getRoutes(initialLocation: UserLocation(clCoordinateLocation2D: home.coordinate),
                                                       waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: work.coordinate), kind: .break)]),
           let r = found.first {
            route = r.geometry.map(\.clLocationCoordinate2D)
            if WatchMath.lengthKm(route) > WatchMath.maxRouteKm {
                routeNote = "That drive is longer than \(Units.distance(WatchMath.maxRouteKm * 1000)), the most one watch area can follow."
            }
        } else {
            routeNote = "Could not find the drive from Home to Work right now."
        }
    }

    private func save() async {
        guard let token = await model.account.token() else { showSignIn = true; return }
        saving = true; defer { saving = false }
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Watch area" : name
        let order = WatchText.kinds.map(\.key).filter { kinds.contains($0) }
        let body: [String: Any]
        switch shape {
        case .circle: body = WatchMath.body(name: label, kinds: order, quiet: quiet, push: true, email: false, circle: (center, radiusKm))
        case .route: body = WatchMath.body(name: label, kinds: order, quiet: quiet, push: true, email: false, route: route)
        case .shape: body = WatchMath.body(name: label, kinds: order, quiet: quiet, push: true, email: false, polygon: corners)
        }
        do {
            let (status, data) = try await Backend.send("POST", "api/watch/create", token: token, body: body)
            guard status < 300 else {
                error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    ?? "The server refused the watch area (\(status))."
                return
            }
            withAnimation(DG.spring) { saved = label }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            self.error = Connectivity.isOffline(error) ? OfflineText.retry : error.localizedDescription
        }
    }
}

/// Lays chips out in rows, wrapping like words.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0, x + d.width > w { y += line + spacing; x = 0; line = 0 }
            x += d.width + spacing; line = max(line, d.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(w, widest), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + d.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing; line = max(line, d.height)
        }
    }
}
