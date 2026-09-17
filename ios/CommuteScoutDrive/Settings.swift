import SwiftUI

/// Every setting, grouped the way a driver looks for them. Values apply
/// at once; route options apply to the next route.
struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var miles = Units.useMiles
    @State private var showSignIn = false
    @State private var confirmDelete = false

    private var prefs: Prefs { model.prefs }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if model.account.signedIn {
                        LabeledContent("Signed in as", value: model.account.displayName)
                        Button("Sign out") { model.account.signOut() }
                        Button("Delete account", role: .destructive) { confirmDelete = true }
                        Text("Deleting removes your watches, API keys and reports from commutescout.com.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Sign in") { showSignIn = true }
                        Text("Sign in to report from the road, keep watch areas, and manage API keys. Same account as the website.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { prefs.theme }, set: { prefs.theme = $0 })) {
                        ForEach(Prefs.Theme.allCases) { t in Text(t.label).tag(t) }
                    }
                    Picker("Base map", selection: Binding(get: { prefs.mapStyle }, set: { prefs.mapStyle = $0 })) {
                        ForEach(Prefs.MapStyle.allCases) { s in Text(s.label).tag(s) }
                    }
                    Toggle("3D perspective", isOn: Binding(get: { prefs.is3D }, set: { _ in model.toggle3D() }))
                }
                Section("Distances") {
                    Picker("Units", selection: $miles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: miles) { v in Units.useMiles = v; prefs.unitsRaw = v ? "mi" : "km"; prefs.objectWillChange.send() }
                }
                Section("Route options") {
                    Toggle("Avoid tolls", isOn: Binding(get: { prefs.avoidTolls }, set: { prefs.avoidTolls = $0; prefs.objectWillChange.send() }))
                    Toggle("Avoid highways", isOn: Binding(get: { prefs.avoidHighways }, set: { prefs.avoidHighways = $0; prefs.objectWillChange.send() }))
                    Toggle("Avoid ferries", isOn: Binding(get: { prefs.avoidFerries }, set: { prefs.avoidFerries = $0; prefs.objectWillChange.send() }))
                    Text("Full road closures are always avoided. Changes apply to the next route.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("While driving") {
                    Toggle("Voice guidance", isOn: Binding(get: { !model.muted }, set: { _ in model.toggleMute() }))
                    Toggle("Speak road alerts", isOn: Binding(get: { prefs.spokenAlerts }, set: { prefs.spokenAlerts = $0; prefs.objectWillChange.send() }))
                    Picker("Warn about alerts", selection: Binding(get: { prefs.alertAheadMeters }, set: { prefs.alertAheadMeters = $0; prefs.objectWillChange.send() })) {
                        Text(Units.useMiles ? "0.5 mi ahead" : "800 m ahead").tag(800.0)
                        Text(Units.useMiles ? "1 mi ahead" : "1.5 km ahead").tag(1500.0)
                        Text(Units.useMiles ? "2 mi ahead" : "3 km ahead").tag(3000.0)
                    }
                    Picker("Show the next alert within", selection: Binding(get: { prefs.stripAheadMeters }, set: { prefs.stripAheadMeters = $0; prefs.objectWillChange.send() })) {
                        Text(Units.useMiles ? "5 mi" : "8 km").tag(8047.0)
                        Text(Units.useMiles ? "10 mi" : "16 km").tag(16093.0)
                        Text(Units.useMiles ? "25 mi" : "40 km").tag(40234.0)
                        Text("Whole route").tag(1e9)
                    }
                    NavigationLink { AdvancedAlertsView() } label: {
                        LabeledContent("Advanced alerts", value: prefs.advancedAlerts ? "On" : "Off")
                    }
                    .accessibilityIdentifier("advanced-alerts")
                    Toggle("Show speed limit", isOn: Binding(get: { prefs.showSpeedLimit }, set: { prefs.showSpeedLimit = $0; prefs.objectWillChange.send() }))
                    Toggle("Keep the screen on", isOn: Binding(get: { prefs.keepAwake }, set: { prefs.keepAwake = $0; prefs.objectWillChange.send() }))
                }
                Section("Layers") {
                    Toggle("Traffic", isOn: Binding(get: { prefs.traffic }, set: { prefs.traffic = $0; prefs.objectWillChange.send() }))
                    ForEach(Prefs.layerKinds, id: \.key) { k in
                        Toggle(k.label, isOn: Binding(get: { prefs.isShown(k.key) },
                                                      set: { prefs.setShown(k.key, $0); model.markers.refresh(force: true) }))
                    }
                }
                Section("Places") {
                    if let home = model.places.home { row("Home", home) }
                    if let work = model.places.work { row("Work", work) }
                    ForEach(model.places.saved) { p in row("Saved", p) }
                    if model.places.places.isEmpty {
                        Text("Search a place, then save it as Home, Work or a favorite.").foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                Section("Testing") {
                    Toggle("Simulate driving the route", isOn: $model.simulating)
                }
                #endif
                Section("Community") {
                    NavigationLink("Plugins (community sources)") { SourcesView() }
                }
                Section("Help and docs") {
                    Link(destination: URL(string: "https://commutescout.com/map")!) { Label("Live map on the web", systemImage: "map") }
                    Link(destination: URL(string: "https://commutescout.com/data-sources")!) { Label("Data sources", systemImage: "list.bullet.rectangle") }
                    Link(destination: URL(string: "https://commutescout.com/developers")!) { Label("Developers and API", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: URL(string: "https://commutescout.com/about")!) { Label("About CommuteScout", systemImage: "info.circle") }
                    Link(destination: URL(string: "https://commutescout.com/contact")!) { Label("Contact", systemImage: "envelope") }
                    Link(destination: URL(string: "https://commutescout.com/privacy")!) { Label("Privacy", systemImage: "hand.raised") }
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Text("Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to report, keep watch areas and manage API keys.") }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await model.account.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes your watches, API keys and reports. It cannot be undone.") }
        }
    }

    private func row(_ label: String, _ p: Place) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(p.shortName).lineLimit(1)
            Spacer()
            Button(role: .destructive) { model.places.remove(p) } label: { Image(systemName: "trash") }
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
