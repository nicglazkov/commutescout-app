import SwiftUI

/// Settings: a home page of categories, each opening a page of its own.
/// A row says what it holds and what it is set to, so most answers are
/// readable without opening anything. Values apply at once; route
/// options apply to the next route.
struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var detent: PresentationDetent = .large

    /// How far the sheet comes down on the Map style page, so the real
    /// map above it shows the style picked.
    static let peek = PresentationDetent.fraction(0.6)

    var body: some View {
        NavigationStack {
            SettingsHome(detent: $detent)
        }
        .presentationDetents([.large, Self.peek], selection: $detent)
        .presentationDragIndicator(.visible)
        .modifier(DGSheetCorner())
    }
}

/// Map layers on its own, from the map's Layers button: the same page
/// as Settings > Map layers, with the sheet's close button.
struct MapLayersSheet: View {
    @State private var detent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            LayersPage(detent: $detent, inSheet: true)
        }
        .presentationDetents([.large, SettingsSheet.peek], selection: $detent)
        .presentationDragIndicator(.visible)
        .modifier(DGSheetCorner())
    }
}

/// The sheet's rounded top in the design's radius, where iOS allows it.
private struct DGSheetCorner: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCornerRadius(DG.R.sheet).presentationBackground(DG.background)
        } else {
            content
        }
    }
}

private struct SettingsHome: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var health = SourcesHealthStore.shared
    @Environment(\.dismiss) private var dismiss
    @Binding var detent: PresentationDetent

    private var prefs: Prefs { model.prefs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings").font(DG.font(30, .bold)).foregroundStyle(DG.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    DGBackButton(symbol: "xmark") { dismiss() }
                }
                .padding(.top, 18).padding(.bottom, 14)

                SettingsLink(id: "account") { AccountPage() } label: { AccountCard(account: model.account) }

                DGSectionLabel("Map and display")
                DGGroup {
                    row("map-style", "Map style", "map.fill", 0x5b6cf0, value: MapStylePage.name(prefs.mapStyle, dark: model.isDark)) {
                        MapStylePage(detent: $detent)
                    }
                    DGDivider()
                    row("units", "Units and region", "ruler.fill", 0x0f9a9a,
                        value: SettingsSummary.units(miles: Units.useMiles, clock24: Units.clock24)) { UnitsPage() }
                }

                DGSectionLabel("Driving")
                DGGroup {
                    row("voice", "Voice", "speaker.wave.2.fill", 0x2f7cf6, value: model.muted ? "Off" : voiceSummary) { VoiceSettings() }
                    DGDivider()
                    row("alerts", "Alerts", "bell.fill", 0xe5484d,
                        value: SettingsSummary.alerts(delivery: prefs.alertDelivery, aheadMeters: prefs.alertAheadMeters,
                                                      advanced: prefs.advancedAlerts, miles: Units.useMiles)) { AlertsPage() }
                    DGDivider()
                    row("route-options", "Route options", "arrow.triangle.turn.up.right.diamond.fill", 0x14a35a,
                        value: SettingsSummary.route(tolls: prefs.avoidTolls, highways: prefs.avoidHighways, ferries: prefs.avoidFerries)) {
                        RouteOptionsPage()
                    }
                }

                DGSectionLabel("Map data")
                DGGroup {
                    SettingsLink(id: "data-sources") { DataSourcesPage() } label: {
                        DGRow(title: "Data sources", leading: { DGTile(symbol: "antenna.radiowaves.left.and.right", color: DG.hex(0x0e1726)) },
                              trailing: { sourcesValue })
                    }
                    DGDivider()
                    row("map-layers", "Map layers", "square.3.layers.3d", 0xee8b0c, value: layersSummary) { LayersPage(detent: $detent) }
                    DGDivider()
                    row("plugins", "Plugins", "puzzlepiece.extension.fill", 0x7c5cf0, value: pluginsSummary) { MarketplaceView() }
                    DGDivider()
                    row("offline-maps", "Offline maps", "arrow.down.to.line", 0x0f9a8c, value: offlineSummary) { OfflineMapsView() }
                    DGDivider()
                    row("saved-places", "Saved places", "star.fill", 0xd9a300, value: placesSummary) { PlaceSettings() }
                }

                DGSectionLabel("Help")
                DGGroup {
                    row("help", "Help and feedback", "questionmark", 0x8a94a6, value: nil) { HelpPage() }
                    DGDivider()
                    row("about", "About and privacy", "info", 0x8a94a6, value: "Version " + AppInfo.version) { AboutPage() }
                    #if DEBUG
                    DGDivider()
                    row("testing", "Testing", "hammer.fill", 0x8a94a6, value: model.simulating ? "Simulating" : nil) { TestingSettings() }
                    #endif
                }

                Text("Not affiliated with any government agency. Check 511 or your state DOT before you drive.")
                    .font(DG.font(13)).foregroundStyle(DG.faint).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, 22).padding(.horizontal, 20)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(DGPageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task { await health.refresh() }
        .task { await model.sources.loadCatalog() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-settings")
    }

    private func row<Page: View>(_ id: String, _ title: String, _ symbol: String, _ color: UInt32, value: String?,
                                 @ViewBuilder page: @escaping () -> Page) -> some View {
        SettingsLink(id: id, page: page) {
            DGRow(title: title, value: value) { DGTile(symbol: symbol, color: DG.hex(color)) }
        }
    }

    @ViewBuilder private var sourcesValue: some View {
        if let r = health.report {
            HStack(spacing: 6) {
                if r.worst != .fresh { Circle().fill(SourcesUI.color(r.worst)).frame(width: 7, height: 7) }
                Text(r.headline).font(DG.font(15, r.worst == .fresh ? .regular : .semibold))
                    .foregroundStyle(r.worst == .fresh ? DG.sub : SourcesUI.ink(r.worst))
            }
        } else if health.busy {
            ProgressView().controlSize(.small)
        }
    }

    private var voiceSummary: String {
        _ = prefs.voiceId   // read so the row follows a new pick
        return Voice.neural?.voice.name ?? Voice.current?.name ?? "System voice"
    }

    private var layersSummary: String {
        "\(Prefs.layerKinds.filter { prefs.isChosen($0.key) }.count) of \(Prefs.layerKinds.count)"
    }

    private var pluginsSummary: String {
        let all = model.sources.catalog.count + model.sources.mine.count
        if all == 0 { return "None" }
        return "\(model.sources.catalog.filter { model.sources.isOn($0.id) }.count + model.sources.mine.count) on"
    }

    private var offlineSummary: String {
        model.mapFiles.files.isEmpty ? "None saved"
            : ByteCountFormatter.string(fromByteCount: model.mapFiles.bytesOnDisk, countStyle: .file)
    }

    private var placesSummary: String {
        let n = model.places.places.count
        return n == 0 ? "None" : "\(n)"
    }
}

/// A row that pushes a page, with the identifier tests find it by.
struct SettingsLink<Page: View, Label: View>: View {
    var id: String
    @ViewBuilder var page: () -> Page
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink { page() } label: { label() }
            .buttonStyle(DGRowPress())
            .accessibilityIdentifier("settings-" + id)
    }
}

/// A row darkens a little under the finger.
struct DGRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(DG.ink.opacity(configuration.isPressed ? 0.05 : 0))
    }
}

/// The profile card: who is signed in, or the invitation to.
struct AccountCard: View {
    @ObservedObject var account: Account
    var chevron = true
    /// Its own white card; off when it sits inside a group.
    var framed = true

    var body: some View {
        HStack(spacing: 14) {
            AccountAvatar(account: account, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.signedIn ? account.displayName : "Sign in").font(DG.font(18, .semibold)).foregroundStyle(DG.ink).lineLimit(1)
                Text(account.signedIn ? (account.email ?? "Signed in") : "Reports, watch areas and plugins")
                    .font(DG.font(14)).foregroundStyle(DG.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(DG.ink) }
        }
        .padding(14)
        .background(Color.white.opacity(framed ? 0.84 : 0), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(framed ? DG.hair : .clear, lineWidth: 1))
        .shadow(color: DG.ink.opacity(framed ? 0.04 : 0), radius: 8, y: 2)
        .contentShape(Rectangle())
    }
}

struct AccountAvatar: View {
    @ObservedObject var account: Account
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: account.signedIn ? [DG.hex(0x5fa0ff), DG.hex(0x2f6fe0)] : [DG.hex(0xb7c0cf), DG.hex(0x8a94a6)],
                                         startPoint: .top, endPoint: .bottom))
            if account.signedIn {
                Text(String(account.displayName.prefix(1)).uppercased()).font(DG.font(size * 0.42, .semibold)).foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.4)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: DG.path.opacity(account.signedIn ? 0.3 : 0), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Small pages

private struct RouteOptionsPage: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    private func flag(_ key: ReferenceWritableKeyPath<Prefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: key] }, set: { prefs[keyPath: key] = $0; prefs.objectWillChange.send() })
    }

    var body: some View {
        DGPage(title: "Route options", identifier: "page-route-options") {
            DGGroup {
                DGSwitchRow(title: "Avoid tolls", isOn: flag(\.avoidTolls))
                DGDivider(inset: 14)
                DGSwitchRow(title: "Avoid highways", isOn: flag(\.avoidHighways))
                DGDivider(inset: 14)
                DGSwitchRow(title: "Avoid ferries", isOn: flag(\.avoidFerries))
            }
            .padding(.top, 8)
            DGFootnote("Full road closures are always avoided. Changes apply to the next route.")
            DGSectionLabel("While driving")
            DGGroup {
                DGSwitchRow(title: "Show speed limit", isOn: flag(\.showSpeedLimit))
                DGDivider(inset: 14)
                DGSwitchRow(title: "Keep the screen on", sub: "While a trip runs or the car is moving.", isOn: flag(\.keepAwake))
            }
        }
    }
}

/// What the map shows. Settings > Map layers and the map's Layers button
/// both open this page.
private struct LayersPage: View {
    @EnvironmentObject var model: AppModel
    @Binding var detent: PresentationDetent
    var inSheet = false
    var body: some View { LayersContent(prefs: model.prefs, sources: model.sources, detent: $detent, inSheet: inSheet) }
}

private struct LayersContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var prefs: Prefs
    @ObservedObject var sources: SourcesStore
    @Binding var detent: PresentationDetent
    var inSheet = false

    private var filter: Binding<Prefs.SourceFilter> {
        Binding(get: { prefs.sourceFilter }, set: { prefs.sourceFilter = $0; model.markers.refresh(force: true) })
    }

    private func shown(_ key: String) -> Binding<Bool> {
        Binding(get: { prefs.isChosen(key) }, set: { prefs.setShown(key, $0); model.markers.refresh(force: true) })
    }

    var body: some View {
        DGPage(title: "Map layers", identifier: "page-map-layers", backSymbol: inSheet ? "xmark" : "chevron.left") {
            DGSegmented(options: Prefs.SourceFilter.allCases.map { ($0, $0.label, nil) }, selection: filter, identifier: "layers-filter")
                .padding(.top, 8)
            DGFootnote(footer)
            if prefs.sourceFilter != .plugins {
                DGSectionLabel("Official sources")
                DGGroup {
                    DGSwitchRow(title: "Traffic", isOn: Binding(get: { prefs.traffic }, set: { prefs.traffic = $0; prefs.objectWillChange.send() })) {
                        DGTile(symbol: "car.2.fill", color: DG.hex(0xee8b0c), size: 30)
                    }
                    ForEach(Prefs.layerKinds.filter { $0.key != "plugin" }, id: \.key) { k in
                        DGDivider()
                        DGSwitchRow(title: k.label, isOn: shown(k.key)) {
                            DGTile(symbol: MarkerIcons.name(k.key), color: MarkerIcons.tint(k.key), size: 30)
                        }
                    }
                }
                DGFootnote("Cameras and toll prices start off, the same as the website. Cameras are the densest layer.")
            }
            if prefs.sourceFilter != .official {
                DGSectionLabel("Plugins", trailing: AnyView(DGTag(text: "Not official", color: DG.hex(0x7c5cf0))))
                DGGroup {
                    DGSwitchRow(title: "Show plugin alerts", isOn: shown("plugin")) {
                        DGTile(symbol: "puzzlepiece.extension.fill", color: DG.hex(0x7c5cf0), size: 30)
                    }
                    DGDivider()
                    // Each plugin's own switch is on its page, so it is not repeated here.
                    SettingsLink(id: "layers-plugins-link") { MarketplaceView() } label: {
                        DGRow(title: "Choose plugins", value: sources.catalog.isEmpty ? nil : "\(sources.catalog.filter { sources.isOn($0.id) }.count) on") {
                            EmptyView()
                        }
                    }
                }
                DGFootnote("Plugin alerts are badges in each plugin's own color. Turn a plugin on or off on its page in Plugins.")
            }
            DGGroup {
                SettingsLink(id: "layers-map-style") { MapStylePage(detent: $detent) } label: {
                    DGRow(title: "Map style", value: MapStylePage.name(prefs.mapStyle, dark: model.isDark)) {
                        DGTile(symbol: "map.fill", color: DG.hex(0x5b6cf0), size: 30)
                    }
                }
            }
            .padding(.top, 20)
        }
        .task { await sources.loadCatalog() }
    }

    private var footer: String {
        switch prefs.sourceFilter {
        case .all: "Everything the map can show: agency data and the plugins you installed."
        case .official: "Agency data only: state DOT and 511 feeds, cameras, signs and weather stations."
        case .plugins: "Plugin alerts only."
        }
    }
}

private struct HelpPage: View {
    var body: some View {
        DGPage(title: "Help and feedback", identifier: "page-help") {
            DGGroup {
                link("Contact", "envelope.fill", 0x2f7cf6, "https://commutescout.com/contact")
                DGDivider()
                link("Data sources", "list.bullet.rectangle.fill", 0x0e1726, "https://commutescout.com/data-sources")
                DGDivider()
                link("Live map on the web", "map.fill", 0x5b6cf0, "https://commutescout.com/map")
                DGDivider()
                link("Developers and API", "chevron.left.forwardslash.chevron.right", 0x7c5cf0, "https://commutescout.com/developers")
            }
            .padding(.top, 8)
            DGGroup {
                ShareLink(item: DriveLog.url) {
                    DGRow(title: "Share the drive log", chevron: false) { DGTile(symbol: "doc.text.fill", color: DG.hex(0x8a94a6)) }
                }
                .buttonStyle(DGRowPress())
                .disabled(!FileManager.default.fileExists(atPath: DriveLog.url.path))
            }
            .padding(.top, 20)
            DGFootnote("What the app noted while driving: fixes, alerts, reroutes, fetches. No account details. Send it along with a report of something that went wrong.")
        }
    }

    private func link(_ title: String, _ symbol: String, _ color: UInt32, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            DGRow(title: title, chevron: false, leading: { DGTile(symbol: symbol, color: DG.hex(color)) },
                  trailing: { Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.faint) })
        }
        .buttonStyle(DGRowPress())
    }
}

private struct AboutPage: View {
    var body: some View {
        DGPage(title: "About and privacy", identifier: "page-about") {
            DGGroup {
                DGRow(title: "Version", value: AppInfo.version, chevron: false) { EmptyView() }
                DGDivider(inset: 14)
                NavigationLink { VoiceLicensesView() } label: { DGRow(title: "Voice licenses") { EmptyView() } }
                    .buttonStyle(DGRowPress())
                    .accessibilityIdentifier("about-voice-licenses")
                DGDivider(inset: 14)
                Link(destination: URL(string: "https://commutescout.com/about")!) { DGRow(title: "About CommuteScout", chevron: false) { EmptyView() } }
                    .buttonStyle(DGRowPress())
                DGDivider(inset: 14)
                Link(destination: URL(string: "https://commutescout.com/privacy")!) { DGRow(title: "Privacy", chevron: false) { EmptyView() } }
                    .buttonStyle(DGRowPress())
            }
            .padding(.top, 8)
            DGFootnote("Routing and address lookup by Stadia Maps. Map data (c) OpenStreetMap contributors, drawn from files CommuteScout hosts and from OpenFreeMap. Road data from the agencies listed on commutescout.com. Not affiliated with any government agency. Verify before you drive.")
        }
    }
}

#if DEBUG
private struct TestingSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section { Toggle("Simulate driving the route", isOn: $model.simulating) }
            Section("Design") {
                NavigationLink("Every alert") { AlertCatalog(page: .alerts) }
                NavigationLink("App messages") { AlertCatalog(page: .system) }
            }
        }
        .navigationTitle("Testing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

private struct PlaceSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var picking: Place.Kind?

    var body: some View {
        Form {
            Section {
                slot("Home", "house.fill", model.places.home, kind: .home)
                slot("Work", "briefcase.fill", model.places.work, kind: .work)
            } footer: {
                Text("Home and Work are one each; setting a new one replaces the old.")
            }
            Section {
                ForEach(model.places.saved) { p in row(p.name, "star.fill", p) }
                Button { picking = .saved } label: { Label("Add a favorite", systemImage: "plus.circle.fill") }
                    .accessibilityIdentifier("add-favorite")
            } header: { Text("Favorites") }
            if !model.places.recents.isEmpty {
                Section {
                    ForEach(model.places.recents) { p in row(p.name, "clock", p) }
                } header: { Text("Recent destinations") } footer: {
                    Text("The last twenty places you navigated to. Swipe to remove one.")
                }
            }
            Section {
                Text(model.account.user == nil
                     ? "Sign in and these follow your account to the website and your other phone."
                     : "Signed in: these follow your account to the website and your other phone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved places")
        .navigationBarTitleDisplayMode(.inline)
        .dgFormPage()
        .sheet(item: $picking) { kind in PlacePickerSheet(kind: kind) }
    }

    /// Home or Work: the place, or the way to set it.
    @ViewBuilder private func slot(_ label: String, _ symbol: String, _ p: Place?, kind: Place.Kind) -> some View {
        if let p {
            HStack {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    Text(p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Change") { picking = kind }.font(.subheadline).buttonStyle(.borderless)
            }
            .swipeActions { Button(role: .destructive) { model.places.remove(p) } label: { Label("Remove", systemImage: "trash") } }
        } else {
            Button { picking = kind } label: {
                Label("Set \(label)", systemImage: symbol)
            }
            .accessibilityIdentifier("set-\(label.lowercased())")
        }
    }

    private func row(_ title: String, _ symbol: String, _ p: Place) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(title).lineLimit(2)
            Spacer()
        }
        .swipeActions { Button(role: .destructive) { model.places.remove(p) } label: { Label("Remove", systemImage: "trash") } }
    }
}

extension Place.Kind: Identifiable {
    public var id: String { rawValue }
}

/// Find a place and save it as Home, Work or a favorite, from Settings.
/// The same lookup the search bar uses: saved places match at once,
/// the server is asked after a pause, coordinates are accepted as typed.
struct PlacePickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: Place.Kind
    @State private var text = ""
    @State private var results: [Suggestion] = []
    @State private var searching = false
    @State private var seq = 0
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var title: String {
        switch kind { case .home: "Set Home"; case .work: "Set Work"; default: "Add a favorite" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search a place or address", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.search)
                        .onChange(of: text) { new in schedule(new) }
                        .accessibilityIdentifier("place-search")
                }
                if let here = model.here, kind != .saved {
                    Section {
                        Button { pick(Place(name: here.pretty, coordinate: here, kind: kind)) } label: {
                            Label("Use my current location", systemImage: "location.fill")
                        }
                    }
                }
                if searching { Section { HStack { ProgressView(); Text("Searching").foregroundStyle(.secondary) } } }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { r in
                            Button { pick(Place(name: r.name, coordinate: r.coordinate, kind: kind)) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name.split(separator: ",").first.map(String.init) ?? r.name)
                                    Text(r.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                let recents = model.places.recents.filter { text.isEmpty || $0.name.lowercased().contains(text.lowercased()) }
                if !recents.isEmpty, results.isEmpty {
                    Section("Recent destinations") {
                        ForEach(recents) { p in
                            Button { pick(Place(name: p.name, coordinate: p.coordinate, kind: kind)) } label: {
                                Label(p.name, systemImage: "clock").lineLimit(2)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func pick(_ p: Place) {
        model.places.set(kind, name: p.name, coordinate: p.coordinate)
        dismiss()
    }

    private func schedule(_ q: String) {
        task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if let coord = SearchBar.parseCoordinates(trimmed) {
            results = [Suggestion(name: coord.pretty, lat: coord.latitude, lon: coord.longitude)]
            return
        }
        guard trimmed.count >= 2 else { results = []; return }
        seq += 1
        let mine = seq
        task = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            defer { if mine == seq { searching = false } }
            if let found = try? await Search.suggest(trimmed, near: model.here ?? model.viewCenter), mine == seq {
                results = found
            }
        }
    }
}

/// Highway Radar-style control: per kind, at what distance the first
/// warning comes, whether it repeats closer, and whether it is spoken.
struct AdvancedAlertsView: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    private var steps: [Double] {
        Units.useMiles ? [402, 805, 1609, 2414, 3219, 4828, 8047] : [300, 500, 1000, 1500, 2000, 3000, 5000, 8000]
    }

    var body: some View {
        Form {
            Section {
                Toggle("Set alerts per kind", isOn: Binding(get: { prefs.advancedAlerts }, set: { prefs.advancedAlerts = $0; prefs.objectWillChange.send() }))
                    .accessibilityIdentifier("advanced-toggle")
                Text("Off: every alert uses the one distance on the Alerts page. On: each kind below has its own first warning, an optional second warning closer in, and its own voice.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Picker("Show the next alert within", selection: Binding(get: { prefs.stripAheadMeters }, set: { prefs.stripAheadMeters = $0; prefs.objectWillChange.send() })) {
                    Text(Units.useMiles ? "5 mi" : "8 km").tag(8047.0)
                    Text(Units.useMiles ? "10 mi" : "16 km").tag(16093.0)
                    Text(Units.useMiles ? "25 mi" : "40 km").tag(40234.0)
                    Text("Whole route").tag(1e9)
                }
            } footer: { Text("The card under the next turn shows the nearest alert inside this distance.") }
            if prefs.advancedAlerts {
                ForEach(Prefs.alertKinds, id: \.key) { k in
                    Section(k.label) {
                        let rule = prefs.alertRules[k.key] ?? Prefs.AlertRule()
                        Toggle("Warn", isOn: Binding(get: { rule.enabled }, set: { var r = rule; r.enabled = $0; prefs.setRule(r, for: k.key) }))
                        if rule.enabled {
                            Picker("First warning", selection: Binding(get: { nearest(rule.firstMeters) }, set: { var r = rule; r.firstMeters = $0; if r.repeatMeters >= $0 { r.repeatMeters = 0 }; prefs.setRule(r, for: k.key) })) {
                                ForEach(steps, id: \.self) { m in Text(Units.distance(m) + " ahead").tag(m) }
                            }
                            Picker("Second warning", selection: Binding(get: { rule.repeatMeters == 0 ? 0 : nearest(rule.repeatMeters) }, set: { var r = rule; r.repeatMeters = $0; prefs.setRule(r, for: k.key) })) {
                                Text("None").tag(0.0)
                                ForEach(steps.filter { $0 < nearest(rule.firstMeters) }, id: \.self) { m in Text(Units.distance(m) + " ahead").tag(m) }
                            }
                            Toggle("Speak it", isOn: Binding(get: { rule.speak }, set: { var r = rule; r.speak = $0; prefs.setRule(r, for: k.key) }))
                        }
                    }
                }
                Section {
                    Button("Reset to defaults") { prefs.alertRules = [:] }
                }
            }
        }
        .navigationTitle("Warnings for each kind")
        .navigationBarTitleDisplayMode(.inline)
        .dgFormPage()
    }

    private func nearest(_ m: Double) -> Double {
        steps.min { abs($0 - m) < abs($1 - m) } ?? m
    }
}

extension View {
    /// A system form page that sits with the Day Glass+ pages: the same
    /// soft background, with the system navigation bar.
    func dgFormPage() -> some View {
        scrollContentBackground(.hidden)
            .background(DGPageBackground())
            .toolbar(.visible, for: .navigationBar)
    }
}
