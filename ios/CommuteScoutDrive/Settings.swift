import SwiftUI

/// Settings, the way a phone's own Settings app is laid out: a short
/// home page of categories, each opening a page of its own. A row says
/// what it holds and what it is set to, so most answers are readable
/// without opening anything. Values apply at once; route options apply
/// to the next route.
struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false
    @State private var showMarketplace = false

    private var prefs: Prefs { model.prefs }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AccountSettings(showSignIn: $showSignIn) } label: { accountCard }
                        .accessibilityIdentifier("settings-account")
                }
                Section {
                    row("Appearance", "paintpalette.fill", .indigo, value: prefs.theme.label) { AppearanceSettings() }
                    row("Units", "ruler.fill", .teal, value: Units.useMiles ? "Miles" : "Kilometers") { UnitsSettings() }
                }
                Section("Driving") {
                    row("Navigation", "arrow.triangle.turn.up.right.diamond.fill", .blue, value: navigationSummary) { NavigationSettings() }
                    row("Alerts", "bell.badge.fill", .red, value: alertsSummary) { AlertSettings() }
                }
                Section("Map") {
                    row("Map layers", "square.3.layers.3d", .orange, value: layersSummary) { LayerSettings() }
                    row("Plugins", "puzzlepiece.extension.fill", .purple, value: pluginsSummary) { PluginSettings(showMarketplace: $showMarketplace) }
                    row("Offline maps", "arrow.down.circle.fill", .green, value: offlineSummary) { OfflineMapSettings() }
                    row("Saved places", "star.fill", .yellow, value: placesSummary) { PlaceSettings() }
                }
                Section {
                    row("Help", "questionmark.circle.fill", .gray, value: nil) { HelpSettings() }
                    row("About", "info.circle.fill", .gray, value: AppInfo.version) { AboutSettings() }
                    #if DEBUG
                    row("Testing", "hammer.fill", .brown, value: model.simulating ? "Simulating" : nil) { TestingSettings() }
                    #endif
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to report, keep watch areas and manage API keys.") }
            .sheet(isPresented: $showMarketplace) { MarketplaceView() }
        }
    }

    /// The profile card at the top: who is signed in, or the invitation to.
    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(model.account.signedIn ? Color.accentColor.gradient : Color.gray.gradient)
                if model.account.signedIn {
                    Text(String(model.account.displayName.prefix(1)).uppercased())
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill").font(.title2).foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.account.signedIn ? model.account.displayName : "Sign in").font(.headline).lineLimit(1)
                Text(model.account.signedIn ? "Account, sign out" : "Reports, watch areas, sync")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func row<Page: View>(_ title: String, _ symbol: String, _ color: Color, value: String?,
                                 @ViewBuilder page: @escaping () -> Page) -> some View {
        NavigationLink { page() } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, color: color)
                Text(title)
                Spacer(minLength: 8)
                if let value { Text(value).foregroundStyle(.secondary).lineLimit(1).font(.subheadline) }
            }
        }
        .accessibilityIdentifier("settings-" + title.lowercased().replacingOccurrences(of: " ", with: "-"))
    }

    private var navigationSummary: String {
        let avoid = [prefs.avoidTolls ? "tolls" : nil, prefs.avoidHighways ? "highways" : nil, prefs.avoidFerries ? "ferries" : nil].compactMap { $0 }
        return avoid.isEmpty ? (model.muted ? "Voice off" : "Voice on") : "Avoids " + avoid.joined(separator: ", ")
    }

    private var alertsSummary: String {
        if prefs.advancedAlerts { return "Per kind" }
        return (prefs.spokenAlerts ? "Spoken, " : "Silent, ") + Units.distance(prefs.alertAheadMeters) + " ahead"
    }

    private var layersSummary: String {
        let on = Prefs.layerKinds.filter { prefs.isChosen($0.key) }.count
        return "\(on) of \(Prefs.layerKinds.count) on"
    }

    private var pluginsSummary: String {
        let all = model.sources.catalog.count + model.sources.mine.count
        if all == 0 { return "None" }
        let on = model.sources.catalog.filter { model.sources.isOn($0.id) }.count + model.sources.mine.count
        return "\(on) on"
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

/// The colored rounded tile beside a settings row.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient)
            .frame(width: 30, height: 30)
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

// MARK: - Pages

private struct AccountSettings: View {
    @EnvironmentObject var model: AppModel
    @Binding var showSignIn: Bool
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if model.account.signedIn {
                Section {
                    LabeledContent("Signed in as", value: model.account.displayName)
                    if let email = model.account.email, email != model.account.displayName {
                        LabeledContent("Email", value: email)
                    }
                } footer: { Text("The same account as commutescout.com: your places, plugins and watch areas follow it.") }
                Section {
                    Button("Sign out") { model.account.signOut() }
                }
                Section {
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete account", role: .destructive) { Task { _ = await model.account.deleteAccount() } }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("This removes your watches, API keys and reports. It cannot be undone.") }
                } footer: { Text("Deleting removes your watches, API keys and reports from commutescout.com.") }
            } else {
                Section {
                    Button("Sign in") { showSignIn = true }
                } footer: {
                    Text("Sign in to report from the road, keep watch areas, and manage API keys. Same account as the website.")
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: Binding(get: { prefs.theme }, set: { prefs.theme = $0 })) {
                    ForEach(Prefs.Theme.allCases) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            Section("Base map") {
                Picker("Base map", selection: Binding(get: { prefs.mapStyle }, set: { prefs.mapStyle = $0 })) {
                    ForEach(Prefs.MapStyle.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section {
                Toggle("3D perspective", isOn: Binding(get: { prefs.is3D }, set: { _ in model.toggle3D() }))
            } footer: { Text("Tilts the map while you drive, so more of the road ahead is in view.") }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UnitsSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var miles = Units.useMiles

    var body: some View {
        Form {
            Section {
                Picker("Distances", selection: $miles) {
                    Text("Miles").tag(true)
                    Text("Kilometers").tag(false)
                }
                .pickerStyle(.inline).labelsHidden()
                .onChange(of: miles) { v in
                    Units.useMiles = v; model.prefs.unitsRaw = v ? "mi" : "km"; model.prefs.objectWillChange.send()
                }
            } footer: { Text("Used for distances on the map, in guidance and in spoken alerts.") }
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NavigationSettings: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    var body: some View {
        Form {
            Section {
                Toggle("Avoid tolls", isOn: Binding(get: { prefs.avoidTolls }, set: { prefs.avoidTolls = $0; prefs.objectWillChange.send() }))
                Toggle("Avoid highways", isOn: Binding(get: { prefs.avoidHighways }, set: { prefs.avoidHighways = $0; prefs.objectWillChange.send() }))
                Toggle("Avoid ferries", isOn: Binding(get: { prefs.avoidFerries }, set: { prefs.avoidFerries = $0; prefs.objectWillChange.send() }))
            } header: { Text("Route options") } footer: {
                Text("Full road closures are always avoided. Changes apply to the next route.")
            }
            Section("While driving") {
                Toggle("Voice guidance", isOn: Binding(get: { !model.muted }, set: { _ in model.toggleMute() }))
                Toggle("Show speed limit", isOn: Binding(get: { prefs.showSpeedLimit }, set: { prefs.showSpeedLimit = $0; prefs.objectWillChange.send() }))
                Toggle("Keep the screen on", isOn: Binding(get: { prefs.keepAwake }, set: { prefs.keepAwake = $0; prefs.objectWillChange.send() }))
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlertSettings: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    var body: some View {
        Form {
            Section {
                Toggle("Speak road alerts", isOn: Binding(get: { prefs.spokenAlerts }, set: { prefs.spokenAlerts = $0; prefs.objectWillChange.send() }))
                Picker("Warn about alerts", selection: Binding(get: { prefs.alertAheadMeters }, set: { prefs.alertAheadMeters = $0; prefs.objectWillChange.send() })) {
                    Text(Units.useMiles ? "0.5 mi ahead" : "800 m ahead").tag(800.0)
                    Text(Units.useMiles ? "1 mi ahead" : "1.5 km ahead").tag(1500.0)
                    Text(Units.useMiles ? "2 mi ahead" : "3 km ahead").tag(3000.0)
                }
            } footer: { Text("How far before an alert on your route the app warns you.") }
            Section {
                Picker("Show the next alert within", selection: Binding(get: { prefs.stripAheadMeters }, set: { prefs.stripAheadMeters = $0; prefs.objectWillChange.send() })) {
                    Text(Units.useMiles ? "5 mi" : "8 km").tag(8047.0)
                    Text(Units.useMiles ? "10 mi" : "16 km").tag(16093.0)
                    Text(Units.useMiles ? "25 mi" : "40 km").tag(40234.0)
                    Text("Whole route").tag(1e9)
                }
            } footer: { Text("The card under the next turn shows the nearest alert inside this distance.") }
            Section {
                NavigationLink { AdvancedAlertsView() } label: {
                    LabeledContent("Advanced alerts", value: prefs.advancedAlerts ? "On" : "Off")
                }
                .accessibilityIdentifier("advanced-alerts")
            } footer: { Text("A warning distance, a second warning and a voice for each kind of alert.") }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LayerSettings: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    var body: some View {
        Form {
            Section {
                Picker("Sources", selection: Binding(get: { prefs.sourceFilter },
                                                     set: { prefs.sourceFilter = $0; model.markers.refresh(force: true) })) {
                    ForEach(Prefs.SourceFilter.allCases) { f in Text(f.label).tag(f) }
                }
                .pickerStyle(.segmented)
            } footer: { Text("Official is agency data. Plugins are the sources you installed from the marketplace.") }
            Section("On the road") {
                Toggle("Traffic", isOn: Binding(get: { prefs.traffic }, set: { prefs.traffic = $0; prefs.objectWillChange.send() }))
                ForEach(Prefs.layerKinds, id: \.key) { k in
                    Toggle(isOn: Binding(get: { prefs.isChosen(k.key) },
                                         set: { prefs.setShown(k.key, $0); model.markers.refresh(force: true) })) {
                        Label { Text(k.label) } icon: {
                            Image(systemName: MarkerIcons.name(k.key)).foregroundStyle(MarkerIcons.tint(k.key))
                        }
                    }
                }
            }
        }
        .navigationTitle("Map layers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PluginSettings: View {
    @EnvironmentObject var model: AppModel
    @Binding var showMarketplace: Bool

    var body: some View {
        Form {
            Section {
                ForEach(model.sources.catalog) { p in
                    Toggle(isOn: Binding(get: { model.sources.isOn(p.id) },
                                         set: { model.sources.setOn(p.id, $0); model.markers.refresh(force: true) })) {
                        Label { Text(p.name).lineLimit(2) } icon: {
                            PluginBadge(sourceId: p.id, category: p.oneCategory, size: 22)
                        }
                    }
                }
                if model.sources.catalog.isEmpty {
                    Text("No plugin is listed right now.").foregroundStyle(.secondary)
                }
            } header: { Text("Installed") } footer: {
                Text("Plugins add alerts to the map. A plugin's alerts are badges in its own color.")
            }
            Section {
                Button { showMarketplace = true } label: { Label("Browse the marketplace", systemImage: "square.grid.2x2") }
                NavigationLink { SourcesView() } label: { Label("My plugins and private sources", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.sources.loadCatalog() }
    }
}

private struct OfflineMapSettings: View {
    @EnvironmentObject var model: AppModel
    private var prefs: Prefs { model.prefs }

    var body: some View {
        Form {
            Section {
                Toggle("Save the map for each trip on Wi-Fi", isOn: Binding(get: { prefs.mapAutoSave }, set: { prefs.mapAutoSave = $0; prefs.objectWillChange.send() }))
            } footer: { Text("When a trip starts on Wi-Fi, the map along the route is saved, so it draws with no signal.") }
            Section {
                NavigationLink { OfflineMapsView() } label: {
                    LabeledContent("Maps saved on this phone",
                                   value: model.mapFiles.files.isEmpty ? "None yet"
                                   : "\(model.mapFiles.files.count), \(ByteCountFormatter.string(fromByteCount: model.mapFiles.bytesOnDisk, countStyle: .file))")
                }
            } footer: { Text("Trip maps the app saved, and whole states you choose to download.") }
        }
        .navigationTitle("Offline maps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaceSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            if model.places.places.isEmpty {
                Section { Text("Search a place, then save it as Home, Work or a favorite.").foregroundStyle(.secondary) }
            } else {
                Section {
                    if let home = model.places.home { row("Home", "house.fill", home) }
                    if let work = model.places.work { row("Work", "briefcase.fill", work) }
                    ForEach(model.places.saved) { p in row("Saved", "star.fill", p) }
                } footer: { Text("Signed in, these follow your account to the website and your other phone.") }
            }
        }
        .navigationTitle("Saved places")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ symbol: String, _ p: Place) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.shortName).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) { model.places.remove(p) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}

private struct HelpSettings: View {
    var body: some View {
        Form {
            Section {
                Link(destination: URL(string: "https://commutescout.com/contact")!) { Label("Contact", systemImage: "envelope") }
                Link(destination: URL(string: "https://commutescout.com/data-sources")!) { Label("Data sources", systemImage: "list.bullet.rectangle") }
                Link(destination: URL(string: "https://commutescout.com/map")!) { Label("Live map on the web", systemImage: "map") }
            }
            Section {
                Link(destination: URL(string: "https://commutescout.com/developers")!) { Label("Developers and API", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: URL(string: "https://commutescout.com/about")!) { Label("About CommuteScout", systemImage: "info.circle") }
                Link(destination: URL(string: "https://commutescout.com/privacy")!) { Label("Privacy", systemImage: "hand.raised") }
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppInfo.version)
            } footer: {
                Text("Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
private struct TestingSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section { Toggle("Simulate driving the route", isOn: $model.simulating) }
        }
        .navigationTitle("Testing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

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
                Text("Off: every alert uses the one distance in While driving. On: each kind below has its own first warning, an optional second warning closer in, and its own voice.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
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
        .navigationTitle("Advanced alerts")
    }

    private func nearest(_ m: Double) -> Double {
        steps.min { abs($0 - m) < abs($1 - m) } ?? m
    }
}
