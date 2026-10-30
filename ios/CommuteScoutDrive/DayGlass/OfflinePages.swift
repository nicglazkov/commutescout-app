import CoreLocation
import SwiftUI

// Offline maps (28-more.html, offline and savedmap): what is saved on
// the phone and how much room it takes, an area or a whole state to
// download, how saved maps stay current, and one saved map on its own
// map with Update now and Delete.

/// The first 127 bytes of a PMTiles file, read from the file itself:
/// what the file says it holds, as opposed to what the app wrote down
/// when it saved it.
struct PMTilesHeader {
    let version: Int
    let minZoom: Int
    let maxZoom: Int
    let south: Double, west: Double, north: Double, east: Double
    let tileCount: Int

    static func read(_ url: URL) -> PMTilesHeader? {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 127), data.count == 127,
              String(data: data[0 ..< 7], encoding: .ascii) == "PMTiles" else { return nil }
        func u64(_ at: Int) -> Int { data[at ..< at + 8].withUnsafeBytes { Int(truncatingIfNeeded: $0.loadUnaligned(as: UInt64.self)) } }
        func i32(_ at: Int) -> Double { Double(data[at ..< at + 4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }) / 1e7 }
        return PMTilesHeader(version: Int(data[7]), minZoom: Int(data[100]), maxZoom: Int(data[101]),
                             south: i32(106), west: i32(102), north: i32(114), east: i32(110),
                             tileCount: u64(72))
    }
}

enum OfflineColors {
    static let states = DG.hex(0x2f7cf6)
    static let areas = DG.hex(0x7aa9f8)
    static let trips = DG.hex(0xb9c9e6)
}

extension MapFiles.LocalFile {
    var box: [CLLocationCoordinate2D] {
        [.init(latitude: south, longitude: west), .init(latitude: south, longitude: east),
         .init(latitude: north, longitude: east), .init(latitude: north, longitude: west)]
    }
    var line: [CLLocationCoordinate2D] { (path ?? []).map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
    var sizeShort: String { SavedText.size(bytes) }

    /// "312 MB, updated today, 6:40 AM", "1.4 GB, whole state, updated Oct 26".
    var rowSub: String {
        let when = SavedText.when(savedAt)
        switch kind {
        case .area: return "\(sizeShort), updated \(when)"
        case .state: return "\(sizeShort), whole state, updated \(when)"
        case .corridor: return "\(sizeShort), saved for a trip, \(when)"
        }
    }
}

/// Saved maps shown in screenshots and tests, never on a real phone.
enum OfflineFixtures {
    /// Bytes per square km of the Bay Area box measured from the real index
    /// (48.1 MB for 40 by 48 km), so fixture sizes still follow the frame.
    static let bytesPerSqKm = 25_000.0

    static func bytes(widthKm: Double, heightKm: Double) -> Int64 {
        let v = widthKm * heightKm * bytesPerSqKm
        // A frame not laid out yet has no size; never trap on it.
        return v.isFinite && v > 0 ? Int64(min(v, 9e15)) : 0
    }
    static var on: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-csMoreFixtures")
        #else
        return false
        #endif
    }

    static let files: [MapFiles.LocalFile] = {
        let now = Date()
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 6, minute: 40, second: 0, of: now) ?? now
        return [
            MapFiles.LocalFile(id: "fixture-area", kind: .area, name: "Home and work area", bytes: 312_000_000,
                               south: 37.33, west: -122.33, north: 37.56, east: -121.93, savedAt: morning, build: nil),
            MapFiles.LocalFile(id: "fixture-state", kind: .state, name: "Colorado", bytes: 1_400_000_000,
                               south: 36.9, west: -109.2, north: 41.1, east: -101.9, savedAt: cal.date(byAdding: .day, value: -3, to: now)!, build: nil),
            MapFiles.LocalFile(id: "fixture-trip", kind: .corridor, name: "Trip to San Jose Airport", bytes: 86_000_000,
                               south: 37.34, west: -122.2, north: 37.47, east: -121.9, savedAt: cal.date(byAdding: .day, value: -2, to: now)!, build: nil,
                               path: [[37.442, -122.143], [37.42, -122.09], [37.40, -122.03], [37.37, -121.96], [37.363, -121.929]]),
        ]
    }()
}

/// A little picture of a saved map: a street grid with the ground it
/// covers in blue, solid when saved, dashed while it downloads.
struct MiniMapThumb: View {
    enum Look { case area, state, trip }
    var look: Look
    var size: CGFloat = 52
    var dashed = false
    var line: [CLLocationCoordinate2D] = []

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(DG.hex(0xeef2f6)))
            var grid = Path()
            for i in 1 ..< 4 {
                let x = w * CGFloat(i) / 4, y = h * CGFloat(i) / 4
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h))
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y))
            }
            ctx.stroke(grid, with: .color(.white), lineWidth: 2.2)
            var road = Path()
            road.move(to: CGPoint(x: w * 0.1, y: h * 0.95)); road.addLine(to: CGPoint(x: w * 0.95, y: h * 0.12))
            ctx.stroke(road, with: .color(.white), lineWidth: 4)
            let blue = DG.path
            let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: dashed ? [3, 3] : [])
            switch look {
            case .area:
                let r = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.62, height: h * 0.6)
                let p = Path(roundedRect: r, cornerRadius: 7)
                ctx.fill(p, with: .color(blue.opacity(0.14)))
                ctx.stroke(p, with: .color(blue), style: style)
            case .state:
                var p = Path()
                p.move(to: CGPoint(x: w * 0.18, y: h * 0.22)); p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.22))
                p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.48)); p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.48))
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.82)); p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.82)); p.closeSubpath()
                ctx.fill(p, with: .color(blue.opacity(0.12)))
                ctx.stroke(p, with: .color(blue), style: style)
            case .trip:
                var p = Path()
                if line.count > 1 {
                    let lats = line.map(\.latitude), lons = line.map(\.longitude)
                    let s = lats.min()!, n = lats.max()!, we = lons.min()!, e = lons.max()!
                    let span = max(n - s, (e - we) * cos(s * .pi / 180), 1e-6)
                    for (i, c) in line.enumerated() {
                        let x = w * 0.15 + w * 0.7 * CGFloat((c.longitude - we) * cos(s * .pi / 180) / span)
                        let y = h * 0.85 - h * 0.7 * CGFloat((c.latitude - s) / span)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                } else {
                    p.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                    p.addCurve(to: CGPoint(x: w * 0.85, y: h * 0.18), control1: CGPoint(x: w * 0.5, y: h * 0.8), control2: CGPoint(x: w * 0.45, y: h * 0.3))
                }
                ctx.stroke(p, with: .color(blue.opacity(0.22)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(blue), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: dashed ? [3, 3] : []))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .accessibilityHidden(true)
    }

    static func look(_ k: MapFiles.LocalFile.Kind) -> Look {
        switch k { case .area: return .area; case .state: return .state; case .corridor: return .trip }
    }
}

/// The little round stop button beside a download.
private struct StopButton: View {
    var id: String
    var body: some View {
        Button { MapFiles.shared.stop(id) } label: {
            DGMoreIcon(name: "close", size: 14, stroke: 2.8).foregroundStyle(DG.sub)
                .frame(width: 30, height: 30).background(DG.ink.opacity(0.06), in: Circle())
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel("Stop download")
        .accessibilityIdentifier("stop-\(id)")
    }
}

/// A thin blue progress line that eases to each new value.
private struct ProgressLine: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(DG.ink.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(DG.path).frame(width: max(4, g.size.width * min(1, max(0, value))))
                        .animation(.linear(duration: 0.6), value: value)
                }
        }
        .frame(height: 4)
    }
}

// MARK: - The list

/// Offline maps: the storage card, the saved maps, whole states, and the
/// two switches that keep them current. Pushed inside a NavigationStack.
struct OfflineMapsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var files = MapFiles.shared
    @State private var picking = OfflineLaunch.wanted == "picker"
    @State private var opened: MapFiles.LocalFile?
    @State private var showStates = false
    @State private var free: Int64?

    private var all: [MapFiles.LocalFile] {
        let real = files.files
        let extra = OfflineFixtures.on ? OfflineFixtures.files.filter { f in !real.contains { $0.id == f.id } } : []
        let order: [MapFiles.LocalFile.Kind] = [.area, .state, .corridor]
        return (extra + real).sorted {
            let a = order.firstIndex(of: $0.kind)!, b = order.firstIndex(of: $1.kind)!
            return a != b ? a < b : $0.savedAt > $1.savedAt
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DGPage(title: "Offline maps", largeTitle: true,
                   intro: "With no signal, the map, search and the last road alerts come from maps saved here. Guidance works either way.",
                   identifier: "offline-maps") {
                VStack(alignment: .leading, spacing: 0) {
                    storage
                    DGSectionLabel("Saved maps")
                    saved
                    DGSectionLabel("Keep them current")
                    DGGroup {
                        DGSwitchRow(title: "Update on Wi-Fi", sub: "Saved maps refresh when a newer map is out, never on mobile data",
                                    isOn: Binding(get: { files.wifiUpdates }, set: { files.setWifiUpdates($0) }),
                                    identifier: "offline-wifi-update") { tile("wifi") }
                        DGDivider()
                        DGSwitchRow(title: "Save each trip's map", sub: "When a trip starts on Wi-Fi",
                                    isOn: Binding(get: { model.prefs.mapAutoSave },
                                                  set: { model.prefs.mapAutoSave = $0; model.prefs.objectWillChange.send() }),
                                    identifier: "offline-autosave") { tile("route") }
                    }
                    Text("A whole state can take a few gigabytes. Download the areas you drive in.")
                        .font(DG.font(12.5)).foregroundStyle(DG.faint).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.top, 10)
                }
            }
            DGDock {
                Button { picking = true } label: {
                    Label { Text("Download an area") } icon: { DGMoreIcon(name: "download", size: 20, stroke: 2.3) }
                }
                .buttonStyle(.dgPrimary)
                .disabled(!model.online && !OfflineFixtures.on)
                .accessibilityIdentifier("offline-download-area")
            }
        }
        .task {
            await files.refreshManifest()
            free = Self.freeBytes()
            if OfflineLaunch.wanted == "savedmap" { opened = all.first { $0.kind == .area } ?? all.first }
            OfflineLaunch.wanted = nil
        }
        .onChange(of: files.lastNotice) { n in if let n { model.toast = n; files.lastNotice = nil } }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let f = opened { SavedMapDetail(file: f) }
        }
        .navigationDestination(isPresented: $showStates) { StatesPage() }
        .fullScreenCover(isPresented: $picking) { AreaPickerView() }
    }

    private func tile(_ icon: String) -> some View {
        DGMoreIcon(name: icon, size: 19, stroke: 2.1).foregroundStyle(DG.path)
            .frame(width: 36, height: 36).background(DG.path.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: storage

    private var storage: some View {
        let list = all
        let states = list.filter { $0.kind == .state }.reduce(Int64(0)) { $0 + $1.bytes }
        let areas = list.filter { $0.kind == .area }.reduce(Int64(0)) { $0 + $1.bytes }
        let trips = list.filter { $0.kind == .corridor }.reduce(Int64(0)) { $0 + $1.bytes }
        let split = StorageSplit.of(states: states, areas: areas, trips: trips)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(states + areas + trips == 0 ? "Nothing" : SavedText.size(states + areas + trips))
                    .font(DG.font(28, .bold)).foregroundStyle(DG.ink)
                Text(states + areas + trips == 0 ? "saved yet" : "on this phone").font(DG.font(14.5, .medium)).foregroundStyle(DG.sub)
                Spacer(minLength: 6)
                if let free { Text("\(SavedText.size(free)) free").font(DG.font(13.5)).foregroundStyle(DG.sub) }
            }
            GeometryReader { g in
                let gaps = CGFloat([split.states, split.areas, split.trips].filter { $0 > 0 }.count - 1) * 2
                let w = max(0, g.size.width - max(0, gaps))
                HStack(spacing: 2) {
                    if split.states > 0 { OfflineColors.states.frame(width: w * split.states) }
                    if split.areas > 0 { OfflineColors.areas.frame(width: w * split.areas) }
                    if split.trips > 0 { OfflineColors.trips.frame(width: w * split.trips) }
                    Spacer(minLength: 0)
                }
                .animation(DG.easeOut, value: split)
            }
            .frame(height: 10)
            .background(DG.ink.opacity(0.07))
            .clipShape(Capsule())
            .padding(.top, 12)
            HStack(spacing: 16) {
                key("States", OfflineColors.states); key("Areas", OfflineColors.areas); key("Trips", OfflineColors.trips)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .shadow(color: DG.ink.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-storage")
    }

    private func key(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(c).frame(width: 10, height: 10)
            Text(t).font(DG.font(12.5)).foregroundStyle(DG.sub)
        }
    }

    // MARK: saved maps

    private var saved: some View {
        let list = all
        let downloading = files.progress.keys.filter { id in !list.contains { $0.id == id } }.sorted()
        return DGGroup {
            if list.isEmpty && downloading.isEmpty {
                Text("None yet. Download an area you drive in, or a whole state.")
                    .font(DG.font(14)).foregroundStyle(DG.sub).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                DGDivider(inset: 0)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                if i > 0 { DGDivider(inset: 76) }
                savedRow(f)
            }
            ForEach(Array(downloading.enumerated()), id: \.element) { i, id in
                if !list.isEmpty || i > 0 { DGDivider(inset: 76) }
                downloadingRow(id)
            }
            if !(list.isEmpty && downloading.isEmpty) { DGDivider(inset: 0) }
            Button { showStates = true } label: {
                DGRow(title: "Download a whole state", sub: "Every street in a state, a few gigabytes each") {
                    DGMoreIcon(name: "map", size: 19, stroke: 2.1).foregroundStyle(DG.path)
                        .frame(width: 52, height: 40)
                }
            }
            .buttonStyle(DGPressStyle())
            .accessibilityIdentifier("offline-states")
        }
    }

    private func savedRow(_ f: MapFiles.LocalFile) -> some View {
        let p = files.progress[f.id]
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                MiniMapThumb(look: MiniMapThumb.look(f.kind), line: f.line)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).font(DG.font(15.5, .semibold)).foregroundStyle(DG.ink).lineLimit(1)
                    Text(p.map { "Updating, \(Int($0 * 100))%" } ?? f.rowSub).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(2)
                    if let p { ProgressLine(value: p).padding(.top, 5) }
                }
                Spacer(minLength: 4)
                if p != nil { StopButton(id: f.id) } else {
                    DGMoreIcon(name: "next", size: 18, stroke: 2.2).foregroundStyle(DG.faint)
                }
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10).frame(minHeight: 72)
            .contentShape(Rectangle())
            .onTapGesture { if p == nil { opened = f } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-\(f.id)")
        .accessibilityAction(named: "Open") { opened = f }
    }

    private func downloadingRow(_ id: String) -> some View {
        let p = files.progress[id] ?? 0
        let state = files.manifest?.states.first { "state-\($0.code)" == id }
        let look: MiniMapThumb.Look = state != nil ? .state : id.hasPrefix("area") ? .area : .trip
        let total = state?.bytes.map(SavedText.size)
        return HStack(spacing: 12) {
            MiniMapThumb(look: look, dashed: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state?.name ?? (look == .area ? "New area" : "Trip map")).font(DG.font(15.5, .semibold)).foregroundStyle(DG.ink).lineLimit(1)
                Text("Downloading, \(Int(p * 100))%" + (total.map { " of \($0)" } ?? "")).font(DG.T.rowSub).foregroundStyle(DG.sub)
                ProgressLine(value: p).padding(.top, 5)
            }
            Spacer(minLength: 4)
            StopButton(id: id)
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10).frame(minHeight: 72)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloading-\(id)")
    }

    static func freeBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }
}

/// Which "more" screen a screenshot run wants open (debug launch
/// argument "-csOpenMore market|plugin|offline|picker|savedmap").
enum OfflineLaunch {
    static var wanted: String? = {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-csOpenMore"), i + 1 < a.count { return a[i + 1] }
        #endif
        return nil
    }()
}

/// Opens the "more" page a screenshot run asked for, in its own stack.
struct MorePagesLauncher: View {
    @EnvironmentObject var model: AppModel
    let screen: String

    var body: some View {
        NavigationStack {
            switch screen {
            case "market": MarketplaceView()
            case "plugin": PluginDetailView(sourceId: model.sources.catalog.first?.id ?? "osm-cameras")
            default: OfflineMapsView()
            }
        }
    }
}

// MARK: - Whole states

/// Every state's map, to download whole: each says its size first and
/// asks in place before anything comes down.
struct StatesPage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var files = MapFiles.shared
    @State private var confirming: String?

    var body: some View {
        DGPage(title: "Whole states", identifier: "offline-states-page") {
            VStack(alignment: .leading, spacing: 0) {
                Text("A whole state is every street at full detail, which can be a few gigabytes. Download on Wi-Fi, and only the states you drive in.")
                    .font(DG.font(14)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.bottom, 12)
                DGGroup {
                    if let m = files.manifest {
                        ForEach(Array(m.states.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { DGDivider(inset: 14) }
                            row(s)
                        }
                    } else {
                        Text(model.online ? "The list of states is loading." : "The list of states needs a signal.")
                            .font(DG.font(14)).foregroundStyle(DG.sub).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task { await files.refreshManifest() }
    }

    private func sizeText(_ s: MapFiles.Manifest.StateFile) -> String { s.bytes.map(SavedText.size) ?? "Size unknown" }

    @ViewBuilder private func row(_ s: MapFiles.Manifest.StateFile) -> some View {
        let id = "state-\(s.code)"
        let p = files.progress[id]
        let saved = files.has(state: s.code)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    Text(p.map { "Downloading, \(Int($0 * 100))% of \(sizeText(s))" } ?? (saved.map { "Saved, \($0.sizeShort)" } ?? sizeText(s)))
                        .font(DG.T.rowSub).foregroundStyle(saved != nil && p == nil ? DGTone.good.ink : DG.sub)
                    if let p { ProgressLine(value: p).padding(.top, 5) }
                }
                Spacer(minLength: 6)
                if p != nil {
                    StopButton(id: id)
                } else if saved != nil {
                    DGMoreIcon(name: "check", size: 18, stroke: 2.6).foregroundStyle(DGTone.good.ink).frame(width: 44, height: 44)
                } else {
                    Button { withAnimation(DG.snap) { confirming = confirming == s.code ? nil : s.code } } label: {
                        DGMoreIcon(name: "download", size: 18, stroke: 2.3).foregroundStyle(DG.path)
                            .frame(width: 36, height: 36).background(DG.path.opacity(0.1), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(DGPressStyle())
                    .disabled(!model.online)
                    .accessibilityLabel("Download \(s.name)")
                    .accessibilityIdentifier("download-\(s.code)")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 58)
            if confirming == s.code {
                HStack(spacing: 8) {
                    Button("Cancel") { withAnimation(DG.snap) { confirming = nil } }.buttonStyle(.dgGlass)
                    Button("Download \(sizeText(s))") {
                        withAnimation(DG.snap) { confirming = nil }
                        Task { await files.downloadState(s) }
                    }
                    .buttonStyle(.dgBlue).accessibilityIdentifier("download-yes-\(s.code)")
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Choosing an area

/// Choose an area: a frame over the map with a corner to drag, and under
/// it what the area would take on the phone. Drag the map to move it,
/// pinch to zoom.
struct AreaPickerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var files = MapFiles.shared
    @State private var center: CLLocationCoordinate2D?
    @State private var zoom: Double?
    @State private var frameSize: CGSize?
    @State private var panStart: CLLocationCoordinate2D?
    @State private var zoomStart: Double?
    @State private var sizeStart: CGSize?
    @State private var grabbed = false
    @StateObject private var sizer = MapSizer()

    private var start: CLLocationCoordinate2D {
        if OfflineFixtures.on { return CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143) }
        return model.here ?? model.places.home?.coordinate ?? model.viewCenter ?? AppModel.defaultCenter
    }

    var body: some View {
        GeometryReader { g in
            let full = CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            let top = g.safeAreaInsets.top + 90
            let left: CGFloat = 30
            let maxW = max(90, full.width - left - 30), maxH = max(160, full.height - top - g.safeAreaInsets.bottom - 230)
            let fs = frameSize ?? CGSize(width: maxW, height: min(maxH, maxW * 1.22))
            let c = center ?? start
            let z = zoom ?? Mercator.zoom(fitting: 40_000, in: Double(fs.width), at: c.latitude)
            // The frame sits in the open map; the map is centered on it.
            let frame = CGRect(x: left, y: top, width: fs.width, height: fs.height)
            let merc = Mercator(center: c, zoom: z, size: full)
            let shiftY = frame.midY - full.height / 2
            let mapCenter = merc.coordinate(CGPoint(x: full.width / 2, y: full.height / 2 - shiftY))
            let m = Mercator(center: mapCenter, zoom: z, size: full)
            let nw = m.coordinate(CGPoint(x: frame.minX, y: frame.minY)), se = m.coordinate(CGPoint(x: frame.maxX, y: frame.maxY))
            let box = (s: se.latitude, w: nw.longitude, n: nw.latitude, e: se.longitude)
            let wKm = AreaMath.widthKm(south: box.s, west: box.w, north: box.n, east: box.e)
            let hKm = AreaMath.heightKm(south: box.s, north: box.n)
            let cut = AreaMath.extractBox(south: box.s, west: box.w, north: box.n, east: box.e)
            let boxKey = String(format: "%.3f,%.3f,%.3f,%.3f", cut.south, cut.west, cut.north, cut.east)
            let fits = AreaMath.fits(south: box.s, west: box.w, north: box.n, east: box.e)
            ZStack(alignment: .topLeading) {
                StillMap(center: mapCenter, zoom: z)
                    .frame(width: full.width, height: full.height)
                    .contentShape(Rectangle())
                    .gesture(pan(m))
                    .simultaneousGesture(pinch(z))
                dim(frame: frame, size: full).allowsHitTesting(false)
                handle(frame: frame, maxW: maxW, maxH: maxH, fs: fs)
                topBar.padding(.horizontal, 14).padding(.top, g.safeAreaInsets.top + 6)
                VStack { Spacer(); card(bytes: OfflineFixtures.on ? OfflineFixtures.bytes(widthKm: wKm, heightKm: hKm) : sizer.bytes(for: boxKey), wKm: wKm, hKm: hKm, fits: fits, box: box) }
                    .padding(.horizontal, 10).padding(.bottom, g.safeAreaInsets.bottom + 6)
            }
            .frame(width: full.width, height: full.height)
            .ignoresSafeArea()
            .task(id: boxKey) {
                guard !OfflineFixtures.on, fits else { return }
                // Wait for the drag to settle before reading the map's index.
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await sizer.measure(key: boxKey, south: cut.south, west: cut.west, north: cut.north, east: cut.east,
                                    url: files.manifest?.us.url ?? MapFiles.defaultUS)
            }
        }
        .background(DG.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area-picker")
    }

    private func pan(_ m: Mercator) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                let base = panStart ?? (center ?? start)
                if panStart == nil { panStart = base }
                let mm = Mercator(center: base, zoom: m.zoom, size: m.size)
                let mid = CGPoint(x: m.size.width / 2, y: m.size.height / 2)
                center = mm.coordinate(CGPoint(x: mid.x - v.translation.width, y: mid.y - v.translation.height))
            }
            .onEnded { _ in panStart = nil }
    }

    private func pinch(_ z: Double) -> some Gesture {
        MagnificationGesture()
            .onChanged { s in
                if zoomStart == nil { zoomStart = z }
                zoom = min(14, max(6, (zoomStart ?? z) + log2(Double(s))))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func dim(frame: CGRect, size: CGSize) -> some View {
        ZStack {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: frame, cornerSize: CGSize(width: 22, height: 22), style: .continuous)
            }
            .fill(DG.hex(0xecf1f6, 0.55), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DG.path, lineWidth: 2)
                .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(DG.path.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: frame.width - 12, height: frame.height - 12).position(x: frame.midX, y: frame.midY)
        }
    }

    private func handle(frame: CGRect, maxW: CGFloat, maxH: CGFloat, fs: CGSize) -> some View {
        Circle().fill(.white).frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(DG.path, lineWidth: 3))
            .shadow(color: DG.ink.opacity(0.3), radius: 6, y: 3)
            .scaleEffect(grabbed ? 1.2 : 1)
            .animation(DG.spring, value: grabbed)
            .frame(width: 48, height: 48).contentShape(Circle())
            .position(x: frame.maxX, y: frame.maxY)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    grabbed = true
                    let base = sizeStart ?? fs
                    if sizeStart == nil { sizeStart = base }
                    frameSize = CGSize(width: min(maxW, max(90, base.width + v.translation.width)),
                                       height: min(maxH, max(90, base.height + v.translation.height)))
                }
                .onEnded { _ in sizeStart = nil; grabbed = false })
            .accessibilityElement()
            .accessibilityLabel("Resize the area")
            .accessibilityIdentifier("picker-corner")
            .accessibilityAdjustableAction { dir in
                let d: CGFloat = dir == .increment ? 20 : -20
                frameSize = CGSize(width: min(maxW, max(90, fs.width + d)), height: min(maxH, max(90, fs.height + d)))
            }
    }

    private var topBar: some View {
        ZStack {
            Text("Choose an area").font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
            HStack {
                Button { dismiss() } label: {
                    DGMoreIcon(name: "close", size: 20, stroke: 2.4).foregroundStyle(DG.ink)
                        .frame(width: 44, height: 44).background(DG.ink.opacity(0.05), in: Circle())
                }
                .buttonStyle(DGPressStyle())
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("picker-close")
                Spacer()
            }
        }
        .padding(.horizontal, 5).frame(height: 54)
        .dgGlass(radius: 27)
    }

    private func card(bytes: Int64?, wKm: Double, hKm: Double, fits: Bool,
                      box: (s: Double, w: Double, n: Double, e: Double)) -> some View {
        let span = AreaMath.spanText(widthKm: wKm, heightKm: hKm, miles: Units.useMiles)
        return VStack(alignment: .leading, spacing: 0) {
            Text(!fits ? "Too big to save at once" : bytes.map(AreaMath.aboutText) ?? "Adding up the size")
                .font(DG.font(19, .bold)).foregroundStyle(fits ? DG.ink : DGTone.high.ink)
                .accessibilityIdentifier("picker-size")
            Text(span + (fits ? ". Drag the corner to change it." : ". Drag the corner in, or zoom in."))
                .font(DG.font(14)).foregroundStyle(DG.sub).padding(.top, 2)
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }.buttonStyle(.dgGlass)
                Button {
                    let name = areaName(box)
                    Task { await MapFiles.shared.saveArea(south: box.s, west: box.w, north: box.n, east: box.e, name: name) }
                    dismiss()
                } label: {
                    Label { Text("Download") } icon: { DGMoreIcon(name: "download", size: 19, stroke: 2.3) }
                }
                .buttonStyle(.dgPrimary)
                .disabled(!fits || !model.online)
                .accessibilityIdentifier("picker-download")
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgGlass(radius: 30)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picker-card")
    }

    private func areaName(_ b: (s: Double, w: Double, n: Double, e: Double)) -> String {
        func inside(_ c: CLLocationCoordinate2D?) -> Bool {
            guard let c else { return false }
            return c.latitude >= b.s && c.latitude <= b.n && c.longitude >= b.w && c.longitude <= b.e
        }
        let h = inside(model.places.home?.coordinate), w = inside(model.places.work?.coordinate)
        if h && w { return "Home and work area" }
        if h { return "Home and around" }
        if w { return "Work and around" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return "Area saved " + f.string(from: Date())
    }
}

// MARK: - One saved map

/// One saved map, on a map of the ground it covers: whether it is here
/// and current, its facts, what is in it, and Update now and Delete,
/// which asks first in place.
struct SavedMapDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var files = MapFiles.shared
    let file: MapFiles.LocalFile
    @State private var current: MapFiles.LocalFile?
    @State private var check: MapFiles.Check?
    @State private var phase: Phase = .idle
    @State private var sheet = 0

    enum Phase { case idle, updating, updated, confirm, deleted }

    private var f: MapFiles.LocalFile { current ?? file }
    private var fixture: Bool { OfflineFixtures.on && file.id.hasPrefix("fixture") }
    private var here: Bool { fixture || check?.exists == true || check == nil }

    var body: some View {
        GeometryReader { g in
            let full = CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            let snaps = [min(500, full.height * 0.6), full.height * 0.9]
            ZStack(alignment: .bottom) {
                areaMap(full: full, lift: snaps[0], topInset: g.safeAreaInsets.top)
                DGSheet(snaps: snaps, index: $sheet, identifier: "saved-map-sheet") { sheetBody }
            }
            .frame(width: full.width, height: full.height)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                DGBackButton { dismiss() }
                    .background(Circle().fill(.white.opacity(0.85)).shadow(color: DG.ink.opacity(0.12), radius: 6, y: 2))
                    .padding(.leading, 16).padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: f.savedAt) { if !fixture { check = await files.check(f) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-map")
    }

    // MARK: map

    private func areaMap(full: CGSize, lift: CGFloat, topInset: CGFloat) -> some View {
        let room = CGRect(x: 0, y: topInset + 56, width: max(120, full.width), height: max(120, full.height - lift - topInset - 56 - 18))
        let mid = CLLocationCoordinate2D(latitude: (f.south + f.north) / 2, longitude: (f.west + f.east) / 2)
        let wM = AreaMath.widthKm(south: f.south, west: f.west, north: f.north, east: f.east) * 1000
        let hM = AreaMath.heightKm(south: f.south, north: f.north) * 1000
        let z = min(15, max(3, min(Mercator.zoom(fitting: wM, in: Double(room.width) * 0.8, at: mid.latitude),
                                   Mercator.zoom(fitting: hM, in: Double(room.height) * 0.82, at: mid.latitude))))
        let probe = Mercator(center: mid, zoom: z, size: full)
        let mapCenter = probe.coordinate(CGPoint(x: full.width / 2, y: full.height / 2 + (full.height / 2 - room.midY)))
        let m = Mercator(center: mapCenter, zoom: z, size: full)
        let a = m.point(CLLocationCoordinate2D(latitude: f.north, longitude: f.west))
        let b = m.point(CLLocationCoordinate2D(latitude: f.south, longitude: f.east))
        let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        let gone = phase == .deleted
        return ZStack(alignment: .topLeading) {
            StillMap(center: mapCenter, zoom: z, line: f.kind == .corridor ? f.line : [])
            if f.kind != .corridor {
                RoundedRectangle(cornerRadius: min(26, rect.width / 4), style: .continuous)
                    .fill(DG.path.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: min(26, rect.width / 4), style: .continuous).strokeBorder(DG.path, lineWidth: 2))
                    .frame(width: max(8, rect.width), height: max(8, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(gone ? 0 : 1)
                    .scaleEffect(gone ? 0.96 : 1)
                    .animation(DG.easeOut, value: gone)
            }
        }
        .frame(width: full.width, height: full.height)
        .allowsHitTesting(false)
    }

    // MARK: sheet

    private var kindLine: String {
        let day = SavedText.when(file.savedAt)
        let short = day.hasPrefix("today") || day.hasPrefix("yesterday") ? String(day.split(separator: ",").first ?? "") : day
        switch f.kind {
        case .state: return "A whole state, saved \(short)"
        case .area: return "An area you chose, saved \(short)"
        case .corridor: return "A trip's map, saved \(short)"
        }
    }

    private var sheetBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        DGMoreIcon(name: "map", size: 22, stroke: 2.1).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(LinearGradient(colors: [DG.path.mix(.white, 0.12), DG.path], startPoint: .top, endPoint: .bottom), in: Circle())
                            .shadow(color: DG.path.opacity(0.4), radius: 6, y: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(DG.font(22, .bold)).foregroundStyle(DG.ink).lineLimit(2).accessibilityAddTraits(.isHeader)
                            Text(kindLine).font(DG.font(14.5, .medium)).foregroundStyle(DG.sub)
                        }
                    }
                    .padding(.horizontal, 18)
                    statusBox.padding(.horizontal, 14).padding(.top, 14)
                    facts.padding(.horizontal, 14).padding(.top, 12)
                    Text("What's included").font(DG.font(17, .bold)).foregroundStyle(DG.ink)
                        .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 8)
                    DGGroup(radius: 20) {
                        DGRow(title: "Roads and the map", sub: "Streets, names and places", value: f.sizeShort, chevron: false) { tile("map") }
                        DGDivider(inset: 0)
                        DGRow(title: "Last road alerts", sub: "From the last time you had a signal", chevron: false) { tile("hazard") }
                    }
                    .padding(.horizontal, 14)
                    Text("Offline, alerts can be out of date. Live alerts come back as soon as you have a signal.")
                        .font(DG.font(12.5)).foregroundStyle(DG.faint).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18).padding(.top, 12)
                }
                .padding(.top, 2).padding(.bottom, 24)
            }
            acts
        }
    }

    private func tile(_ name: String) -> some View {
        DGMoreIcon(name: name, size: 19, stroke: 2.1).foregroundStyle(DG.path)
            .frame(width: 36, height: 36).background(DG.path.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder private var statusBox: some View {
        let stale = !fixture && files.stale().contains { $0.id == f.id }
        let (title, sub, good): (String, String, Bool) = {
            if phase == .deleted || !here { return ("Not on this phone", "The map needs a signal here now", false) }
            if phase == .updated { return ("Up to date", "Updated just now, \(f.sizeShort) in all", true) }
            if stale { return ("A newer map is out", "Update now, or it updates on its own on Wi-Fi", false) }
            let on = Connectivity.shared.onWifi ? ", on Wi-Fi" : ""
            let when = SavedText.when(f.savedAt).replacingOccurrences(of: ", ", with: " at ")
            return ("Up to date", "Updated \(when)\(on)", true)
        }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(good ? DGTone.good.color : DGTone.clear.color).frame(width: 10, height: 10).padding(.horizontal, 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DG.font(16, .bold)).foregroundStyle(good ? DGTone.good.ink : DG.ink)
                    Text(sub).font(DG.font(14)).foregroundStyle(DG.sub)
                }
                Spacer(minLength: 0)
            }
            if let p = files.progress[f.id] { ProgressLine(value: p).padding(.top, 10) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(good ? DGTone.good.color.opacity(0.08) : DG.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(good ? DGTone.good.color.opacity(0.22) : DG.hair, lineWidth: 1))
        .animation(DG.springSoft, value: phase)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saved-status")
    }

    private var facts: some View {
        let wKm = AreaMath.widthKm(south: f.south, west: f.west, north: f.north, east: f.east)
        let hKm = AreaMath.heightKm(south: f.south, north: f.north)
        let detail = check?.header.map { $0.maxZoom >= 14 ? "Every street and address" : "Main roads and towns" } ?? "Every street and address"
        let next: String = f.kind == .corridor ? "Saved again on your next trip"
            : files.wifiUpdates ? "On Wi-Fi, when it changes" : "When you update it"
        let rows: [(String, String)] = [("Size", f.sizeShort), ("Covers", "About " + AreaMath.spanText(widthKm: wKm, heightKm: hKm, miles: Units.useMiles)),
                                        ("Detail", detail), ("Next update", next)]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i > 0 { DGDivider(inset: 0) }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(r.0).font(DG.font(14.5)).foregroundStyle(DG.sub)
                    Spacer(minLength: 8)
                    Text(r.1).font(DG.font(14.5, .semibold)).foregroundStyle(DG.ink).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
    }

    // MARK: acts

    private var acts: some View {
        HStack(spacing: 8) {
            switch phase {
            case .confirm:
                Button("Keep it") { withAnimation(DG.snap) { phase = .idle } }
                    .buttonStyle(.dgGlass).accessibilityIdentifier("saved-keep")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                Button("Delete \(f.sizeShort)") {
                    if !fixture { files.delete(f) }
                    withAnimation(DG.snap) { phase = .deleted }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { dismiss() }
                }
                .buttonStyle(DangerButtonStyle(solid: true)).accessibilityIdentifier("saved-delete-yes")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .deleted:
                Button {} label: { Label { Text("Deleted") } icon: { DGMoreIcon(name: "check", size: 19, stroke: 2.6) } }
                    .buttonStyle(.dgDone).allowsHitTesting(false)
            default:
                Button { update() } label: {
                    Label {
                        Text(phase == .updating ? "Checking for changes" : phase == .updated ? "Updated" : "Update now")
                    } icon: {
                        DGMoreIcon(name: phase == .updated ? "check" : "refresh", size: 18, stroke: 2.3)
                    }
                }
                .buttonStyle(UpdateButtonStyle(phase: phase, progress: files.progress[f.id]))
                .disabled(phase == .updating || (!model.online && !fixture))
                .accessibilityIdentifier("saved-update")
                Button { withAnimation(DG.snap) { phase = .confirm } } label: {
                    Label { Text("Delete") } icon: { DGMoreIcon(name: "trash", size: 18, stroke: 2.1) }
                }
                .buttonStyle(DangerButtonStyle(solid: false))
                .disabled(phase == .updating)
                .accessibilityIdentifier("saved-delete")
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 30)
        .background(Color.white.opacity(0.6).overlay(alignment: .top) { Rectangle().fill(DG.hair).frame(height: 1) })
    }

    private func update() {
        guard phase == .idle || phase == .updated else { return }
        withAnimation(DG.snap) { phase = .updating }
        Task {
            let done: MapFiles.LocalFile?
            if fixture {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                var copy = f
                copy = MapFiles.LocalFile(id: copy.id, kind: copy.kind, name: copy.name, bytes: copy.bytes, south: copy.south, west: copy.west,
                                          north: copy.north, east: copy.east, savedAt: Date(), build: copy.build, path: copy.path)
                done = copy
            } else {
                done = await files.update(f)
            }
            withAnimation(DG.snap) {
                if let done { current = done; phase = .updated } else { phase = .idle }
            }
        }
    }
}

/// Update now: ink, filling with blue while it checks, green once done.
private struct UpdateButtonStyle: ButtonStyle {
    var phase: SavedMapDetail.Phase
    var progress: Double?

    func makeBody(configuration: Configuration) -> some View {
        let done = phase == .updated
        configuration.label
            .font(DG.T.button).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(done ? DGTone.good.ink : .white)
            .background {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(done ? AnyShapeStyle(DGTone.good.color.opacity(0.14)) : AnyShapeStyle(DG.ink))
                        if phase == .updating {
                            Capsule().fill(DG.path)
                                .frame(width: max(48, g.size.width * (progress ?? 0.15)))
                                .animation(.linear(duration: 0.6), value: progress)
                        }
                    }
                }
            }
            .overlay(Capsule().strokeBorder(done ? DGTone.good.color.opacity(0.3) : .white.opacity(0.2), lineWidth: 0.5))
            .shadow(color: done ? .clear : DG.ink.opacity(0.25), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DG.snap, value: configuration.isPressed)
            .animation(DG.springSoft, value: done)
    }
}

/// What a box of the map weighs: the same tiles the server copies out of
/// the US file (every zoom, up to its most detailed), added up from the
/// file's own index with a few small range reads. Leaves stay cached.
@MainActor
final class MapSizer: ObservableObject {
    @Published private var known: [String: Int64] = [:]
    private var url: String?
    private var header: PMTilesMath.Header?
    private var root: [PMTilesMath.Entry] = []
    private var leaves: [UInt64: [PMTilesMath.Entry]] = [:]

    func bytes(for key: String) -> Int64? { known[key] }

    func measure(key: String, south: Double, west: Double, north: Double, east: Double, url: String) async {
        guard known[key] == nil else { return }
        do {
            if self.url != url || header == nil {
                guard let h = PMTilesMath.header(try await read(url, 0, 127)) else { return }
                let raw = try await read(url, h.rootOffset, h.rootLength)
                guard let r = PMTilesMath.directory(h.gzipped ? (PMTilesMath.gunzip(raw) ?? Data()) : raw) else { return }
                (self.url, header, root, leaves) = (url, h, r, [:])
            }
            guard let h = header,
                  let ids = PMTilesMath.tileIds(south: south, west: west, north: north, east: east, maxZoom: h.maxZoom) else { return }
            for _ in 0 ..< 4 {
                let (bytes, missing) = PMTilesMath.sum(ids: ids, root: root, leaves: leaves)
                if missing.isEmpty { known[key] = bytes; return }
                try await withThrowingTaskGroup(of: (UInt64, [PMTilesMath.Entry]?).self) { group in
                    for e in missing.prefix(40) {
                        group.addTask {
                            let raw = try await Self.fetch(url, h.leafOffset + e.offset, UInt64(e.length))
                            return (e.offset, PMTilesMath.directory(h.gzipped ? (PMTilesMath.gunzip(raw) ?? Data()) : raw))
                        }
                    }
                    for try await (off, dir) in group { leaves[off] = dir ?? [] }
                }
                if Task.isCancelled { return }
            }
        } catch {
            DriveLog.note("map: size unavailable: \(error)")
        }
    }

    private func read(_ url: String, _ offset: UInt64, _ length: UInt64) async throws -> Data {
        try await Self.fetch(url, offset, length)
    }

    nonisolated private static func fetch(_ url: String, _ offset: UInt64, _ length: UInt64) async throws -> Data {
        guard let u = URL(string: url), length > 0 else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 206, data.count == Int(length) else { throw URLError(.badServerResponse) }
        return data
    }
}
