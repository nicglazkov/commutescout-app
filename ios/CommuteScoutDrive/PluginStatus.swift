import SwiftUI

/// One plugin, checked: whether it is answering, how many alerts it
/// holds, when it last answered, what it says about itself, and a
/// button that asks again now. The page for "is this thing working".
struct PluginStatusView: View {
    @EnvironmentObject var model: AppModel
    let sourceId: String
    @State private var checking = false
    @State private var checkedAt: Date?
    @State private var reach: String?

    private var source: FlareSource? { model.sources.catalog.first { $0.id == sourceId } ?? model.sources.mine.first { $0.id == sourceId } }

    var body: some View {
        Form {
            if let s = source {
                Section {
                    HStack(spacing: 12) {
                        PluginBadge(sourceId: s.id, category: s.oneCategory, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.headline)
                            Text(s.trust == "official" ? "Official CommuteScout plugin"
                                 : s.tier == "approved" ? "Reviewed by CommuteScout"
                                 : s.tier == "private" ? "Private, read from this phone only" : "Public, not reviewed")
                                .font(.caption).foregroundStyle(s.tier == "approved" ? .green : .secondary)
                        }
                    }
                    Toggle(isOn: Binding(get: { model.sources.isOn(s.id) }, set: { model.sources.setOn(s.id, $0); model.markers.refresh(force: true) })) {
                        Text(model.sources.isOn(s.id) ? "Installed" : "Not installed")
                    }
                    .accessibilityIdentifier("plugin-installed")
                } footer: {
                    Text(model.sources.isOn(s.id) ? "Turn off to uninstall: its alerts leave the map at once and it is not asked again."
                         : "Turn on to install: its alerts join the map within a minute.")
                }

                Section("Status") {
                    LabeledContent("Answering") {
                        status(s.ok == false ? "No" : s.ok == true ? "Yes" : "Not asked yet",
                               s.ok == false ? "xmark.circle.fill" : s.ok == true ? "checkmark.circle.fill" : "questionmark.circle",
                               s.ok == false ? .red : s.ok == true ? .green : .secondary)
                    }
                    LabeledContent("Alerts on the map now", value: s.count.formatted())
                    if let t = s.lastOk { LabeledContent("Last good answer", value: Self.ago(t)) }
                    if let e = s.lastError, s.ok == false { LabeledContent("Last error") { Text(e).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing) } }
                    if s.fails > 0 { LabeledContent("Failures in a row", value: "\(s.fails)") }
                    if let r = reach { LabeledContent("Reached from this phone", value: r) }
                    Button {
                        Task { await check() }
                    } label: {
                        HStack { if checking { ProgressView().controlSize(.small) }; Text(checking ? "Checking" : "Check now") }
                    }
                    .disabled(checking)
                    .accessibilityIdentifier("plugin-check")
                    if let c = checkedAt { Text("Checked \(c.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }

                Section("What it says about itself") {
                    if let v = s.version { LabeledContent("Version", value: v) }
                    if let p = s.protocolName { LabeledContent("Protocol", value: p) }
                    LabeledContent("Asks for new alerts every", value: Units.duration(Double(s.refreshS)))
                    LabeledContent("Shows", value: s.kindsLabel.isEmpty ? "alerts" : s.kindsLabel)
                    LabeledContent("Coverage", value: s.coverageLabel)
                    LabeledContent("Shared data", value: s.shared ? "Yes: the same for everyone, shown at every zoom" : "No: served around you only")
                    LabeledContent("Accepts reports", value: s.acceptsReports ? "Yes" : "No")
                    if let a = s.attribution { LabeledContent("Data from", value: a) }
                    if let c = s.contact { LabeledContent("Contact", value: c).font(.footnote) }
                    if let b = s.base { LabeledContent("Address", value: b).font(.footnote) }
                }
            } else {
                Text("This plugin is no longer listed.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plugin status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func status(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 6) { Image(systemName: symbol); Text(text) }.foregroundStyle(color)
    }

    /// Ask the server for a fresh catalog (its own poll of the plugin),
    /// and reach the plugin's handshake straight from the phone.
    private func check() async {
        checking = true
        defer { checking = false }
        await model.sources.loadCatalog()
        if let base = source?.base, let url = URL(string: base + "/flare/v1/handshake") {
            let t0 = Date()
            if let (_, resp) = try? await Backend.session.data(from: url), let http = resp as? HTTPURLResponse {
                reach = http.statusCode == 200 ? String(format: "Yes, %.0f ms", Date().timeIntervalSince(t0) * 1000) : "Answered \(http.statusCode)"
            } else {
                reach = "No"
            }
        }
        checkedAt = Date()
    }

    static func ago(_ iso: String) -> String {
        guard let d = Snapshot.date(iso) else { return iso }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}
