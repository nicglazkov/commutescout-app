import Combine
import CoreLocation
import CryptoKit
import Foundation
import SwiftUI

/// A Flare plugin the app knows about: one from the public catalog on
/// commutescout.com, or a private/unlisted one added here by URL and
/// polled directly from the phone.
struct FlareSource: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var base: String?            // set for direct (private/unlisted) sources
    var token: String?           // bearer token for private plugins
    var refreshS: Int = 60
    var canReport = false
    var canConfirm = false
    var attribution: String?
    var trust: String?
    var tier: String = "unreviewed"
    var count: Int = 0
    var ok: Bool?
    // For the marketplace card (public catalog entries).
    var summary: String? = nil
    var coverage: [Double]? = nil
    var kinds: [String] = []
    var acceptsReports = false
    // A catalog plugin that offers each signed-in person their own session
    // (handshake extensions.user_sessions): the path the phone polls itself.
    var ownSessionPath: String? = nil

    var isDirect: Bool { base != nil && ownSessionPath == nil }

    /// Where the plugin says it covers, in words.
    var coverageLabel: String {
        guard let b = coverage, b.count == 4 else { return "Coverage not stated" }
        let h = b[2] - b[0], w = b[3] - b[1]
        if h >= 20, w >= 50 { return "Whole country" }
        if b[0] >= 32, b[2] <= 36, b[1] >= -121, b[3] <= -114 { return "Southern California" }
        if b[0] >= 32, b[2] <= 42.5, b[1] >= -125, b[3] <= -114 { return "California" }
        return "\(Int(h.rounded()))\u{00B0} by \(Int(w.rounded()))\u{00B0} area"
    }

    /// The kinds it shows, grouped into plain words.
    var kindsLabel: String {
        var groups: [String] = []
        func add(_ g: String) { if !groups.contains(g) { groups.append(g) } }
        for k in kinds {
            if k.hasPrefix("POLICE") { add("police") } else if k.hasPrefix("CRASH") { add("crashes") }
            else if k.hasPrefix("HAZARD") { add("hazards") } else if k.hasPrefix("JAM") { add("jams") }
            else if k.hasPrefix("ROAD_CLOSED") || k.hasPrefix("LANE") { add("closures") }
            else if k.hasPrefix("WEATHER") { add("weather") } else if k.hasPrefix("CAMERA") { add("cameras") }
            else if k.hasPrefix("CHAINS") { add("chain controls") } else { add("other") }
        }
        return groups.joined(separator: ", ")
    }
}

private struct SourcesResponse: Decodable { let sources: [PublicSource] }
private struct PublicSource: Decodable {
    let id: String
    let name: String
    let attribution: Attribution?
    let trust: String?
    let tier: String?
    let count: Int?
    let ok: Bool?
    let description: String?
    let coverage: [Double]?
    let kinds: [String]?
    let capabilities: [String: Bool]?
    let base: String?
    struct Attribution: Decodable { let name: String?; let url: String? }
}

private struct Handshake: Decodable {
    let protocolName: String
    let id: String
    let name: String
    let capabilities: [String: Bool]?
    let refresh_s: Int?
    let attribution: PublicSource.Attribution?
    let auth: String?
    let extensions: Extensions?
    struct Extensions: Decodable { let user_sessions: UserSessions? }
    struct UserSessions: Decodable { let path: String?; let auth: String?; let idle_s: Int?; let poll_s: Int? }
    enum CodingKeys: String, CodingKey { case protocolName = "protocol", id, name, capabilities, refresh_s, attribution, auth, extensions }
}

private struct FlareAlerts: Decodable {
    let alerts: [FlareAlert]
    let ttl_s: Int?
    let session: String?
}

/// An alert record from a plugin, mapped onto the map's marker model.
struct FlareAlert: Decodable {
    let id: String
    let kind: String
    let lat: Double
    let lon: Double
    let description: String?
    let report_ts: String?
    let road_names: [String]?
    let n_confirmations: Int?
    let reliability: Double?
    let source_url: String?

    func marker(source: FlareSource) -> RoadMarker {
        RoadMarker(kind: "plugin", lat: lat, lon: lon, id: "\(source.id):\(id)", type: nil, cls: nil,
                   label: description ?? kind.replacingOccurrences(of: "_", with: " ").capitalized,
                   location: road_names?.first, route: nil, status: nil, name: nil, flareKind: kind,
                   source: source.name, description: description, area: nil, dir: nil, reported: report_ts,
                   county: nil, delayMin: nil, lanes: nil, since: nil, until: nil, work: nil, facility: nil, tier: "private")
    }
}

/// The catalog and the driver's own sources. Public sources are drawn
/// through commutescout.com (mediated); direct sources are polled here
/// with the tile-snapped center, never the raw position.
@MainActor
final class SourcesStore: ObservableObject {
    @Published private(set) var catalog: [FlareSource] = []
    @Published private(set) var mine: [FlareSource] = []
    @Published private(set) var directMarkers: [RoadMarker] = []
    // Catalog plugins polled by this phone for the signed-in person's own
    // session. Only bases from the commutescout.com catalog ever see the
    // account token; a plugin added by URL never does.
    @Published private(set) var own: [FlareSource] = []
    var ownSessionIds: Set<String> { Set(own.map(\.id)) }
    @Published var hidden: Set<String> = []     // source ids switched off
    @Published var error: String?

    private let mineKey = "cs.flare.mine.v1"
    private let hiddenKey = "cs.flare.hidden.v1"
    private var timers: [String: Timer] = [:]
    private var lastCenter: CLLocationCoordinate2D?
    private var perSource: [String: [RoadMarker]] = [:]

    init() {
        if let d = UserDefaults.standard.data(forKey: mineKey), let list = try? JSONDecoder().decode([FlareSource].self, from: d) {
            mine = list
        }
        hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
        Task { await loadCatalog() }
        for s in mine { schedule(s) }
    }

    func isOn(_ id: String) -> Bool { !hidden.contains(id) }

    func setOn(_ id: String, _ on: Bool) {
        if on { hidden.remove(id) } else { hidden.insert(id) }
        UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
        rebuild()
        pushToAccount()
    }

    // MARK: account sync (Install on one device follows the account)

    /// Set by the app model: the signed-in account's ID token, or nil.
    var tokenProvider: (() async -> String?)?
    private struct MePlugins: Decodable {
        struct P: Decodable { let off: [String]?; let `private`: [Mine]? }
        struct Mine: Decodable { let id: String; let name: String?; let base: String; let token: String?; let refresh_s: Int? }
        let plugins: P
    }

    /// On sign-in: the account's switches replace this phone's, and the
    /// account's private plugins (with their tokens) are added here.
    func pullFromAccount() async {
        guard let token = await tokenProvider?() else { return }
        guard let (status, data) = try? await Backend.send("GET", "api/me/plugins", token: token, body: nil),
              status == 200, let me = try? JSONDecoder().decode(MePlugins.self, from: data) else { return }
        hidden = Set(me.plugins.off ?? [])
        UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
        var added = 0
        for m in me.plugins.private ?? [] where !mine.contains(where: { $0.id == m.id }) {
            let src = FlareSource(id: m.id, name: m.name ?? m.id, base: m.base, token: m.token,
                                  refreshS: max(15, m.refresh_s ?? 60), trust: "private", tier: "private")
            mine.append(src)
            schedule(src)
            added += 1
        }
        if added > 0, let d = try? JSONEncoder().encode(mine) { UserDefaults.standard.set(d, forKey: mineKey) }
        rebuild()
        DriveLog.note("plugins: account has \(hidden.count) switched off, \(added) private plugin(s) added")
    }

    /// After a change: the account learns this phone's switches and its
    /// private plugins, tokens included, so the next device has them too.
    private func pushToAccount() {
        let off = Array(hidden).sorted()
        let mineWire: [[String: Any]] = mine.compactMap { s in
            guard let base = s.base else { return nil }
            var d: [String: Any] = ["id": s.id, "name": s.name, "base": base, "refresh_s": s.refreshS]
            if let t = s.token { d["token"] = t }
            return d
        }
        Task {
            guard let token = await tokenProvider?() else { return }
            _ = try? await Backend.send("PUT", "api/me/plugins", token: token, body: ["off": off, "private": mineWire])
        }
    }

    func loadCatalog() async {
        guard let r = try? await Backend.get("api/flare/sources", as: SourcesResponse.self) else { return }
        catalog = r.sources.map {
            FlareSource(id: $0.id, name: $0.name, base: nil, token: nil, refreshS: 60, canReport: false, canConfirm: false,
                        attribution: $0.attribution?.name, trust: $0.trust, tier: $0.tier ?? "unreviewed", count: $0.count ?? 0, ok: $0.ok,
                        summary: $0.description, coverage: $0.coverage, kinds: $0.kinds ?? [],
                        acceptsReports: $0.capabilities?["report"] ?? false)
        }
        await discoverOwnSessions(r.sources.compactMap { s in s.base.map { (s.id, $0) } })
    }

    /// Catalog plugins whose handshake offers user sessions get polled here.
    private func discoverOwnSessions(_ bases: [(String, String)]) async {
        var found: [FlareSource] = []
        for (id, base) in bases where base.hasPrefix("https://") {
            guard let url = URL(string: base + "/flare/v1/handshake") else { continue }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await Backend.session.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let h = try? JSONDecoder().decode(Handshake.self, from: data),
                  let us = h.extensions?.user_sessions, let path = us.path, us.auth == "firebase", h.id == id else { continue }
            // An own session goes stale in seconds while the phone moves: its
            // cadence is the extension's poll_s, not the mediated refresh_s.
            found.append(FlareSource(id: h.id, name: h.name, base: base, token: nil, refreshS: max(15, min(us.poll_s ?? 15, 300)),
                                     canReport: h.capabilities?["report"] ?? false, canConfirm: h.capabilities?["confirm"] ?? false,
                                     attribution: h.attribution?.name, trust: "community", ownSessionPath: path))
        }
        own = found
        for s in found { schedule(s) }
        if !found.isEmpty { DriveLog.note("own sessions offered by: " + found.map(\.id).joined(separator: ", ")) }
    }

    /// Adds a private or unlisted plugin by its base URL after a handshake.
    func add(base rawBase: String, token: String?) async -> Bool {
        var base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard base.hasPrefix("https://"), let url = URL(string: base + "/flare/v1/handshake") else {
            error = "The address must start with https://"
            return false
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await Backend.session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                error = "The plugin answered \((resp as? HTTPURLResponse)?.statusCode ?? 0) to the handshake."
                return false
            }
            let h = try JSONDecoder().decode(Handshake.self, from: data)
            guard h.protocolName.hasPrefix("flare/1") else { error = "Not a Flare v1 plugin."; return false }
            let src = FlareSource(id: h.id, name: h.name, base: base, token: token?.isEmpty == false ? token : nil,
                                  refreshS: max(15, h.refresh_s ?? 60), canReport: h.capabilities?["report"] ?? false,
                                  canConfirm: h.capabilities?["confirm"] ?? false, attribution: h.attribution?.name, trust: "private", tier: "private")
            mine.removeAll { $0.id == src.id }
            mine.append(src)
            persist()
            schedule(src)
            return true
        } catch {
            self.error = "Could not reach the plugin: \(error.localizedDescription)"
            return false
        }
    }

    func remove(_ src: FlareSource) {
        mine.removeAll { $0.id == src.id }
        timers[src.id]?.invalidate(); timers[src.id] = nil
        perSource[src.id] = nil
        persist()
        rebuild()
    }

    /// The map moved: direct sources are asked around the new center.
    func view(center: CLLocationCoordinate2D) {
        let snapped = CLLocationCoordinate2D(latitude: (center.latitude * 20).rounded() / 20, longitude: (center.longitude * 20).rounded() / 20)
        if let last = lastCenter, abs(last.latitude - snapped.latitude) < 1e-6, abs(last.longitude - snapped.longitude) < 1e-6 { return }
        lastCenter = snapped
        for s in mine { Task { await poll(s) } }
    }

    /// The pseudonym a direct plugin sees: stable per account and plugin, never the person.
    func reporter(for src: FlareSource, uid: String) -> String {
        "r:" + SHA256.hash(data: Data((uid + "|" + src.id).utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
    }

    /// A report straight to a direct plugin that accepts them.
    func report(to src: FlareSource, kind: String, at c: CLLocationCoordinate2D, description: String, uid: String) async throws {
        guard let base = src.base, src.canReport, let url = URL(string: base + "/flare/v1/report") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = src.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["kind": kind, "lat": c.latitude, "lon": c.longitude,
                                   "ts": ISO8601DateFormatter().string(from: Date()),
                                   "reporter": reporter(for: src, uid: uid), "client": "commutescout-ios/\(AppInfo.version)"]
        if !description.isEmpty { body["description"] = description }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await Backend.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 201 || code == 202 else { throw ReportError.refused(code, "\(src.name) refused the report.") }
    }

    private func schedule(_ src: FlareSource) {
        timers[src.id]?.invalidate()
        timers[src.id] = Timer.scheduledTimer(withTimeInterval: Double(src.refreshS), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll(src) }
        }
        Task { await poll(src) }
    }

    private func poll(_ src: FlareSource) async {
        guard let base = src.base, let center = lastCenter, isOn(src.id) else { return }
        // Own session: the account token goes only to a catalog base; signed
        // out, the mediated copy from commutescout.com is what shows.
        var bearer = src.token
        if src.ownSessionPath != nil {
            guard let t = await tokenProvider?() else { perSource[src.id] = nil; rebuild(); return }
            bearer = t
        }
        var comps = URLComponents(string: base + (src.ownSessionPath ?? "/flare/v1/alerts"))!
        comps.queryItems = [URLQueryItem(name: "lat", value: String(format: "%.3f", center.latitude)),
                            URLQueryItem(name: "lon", value: String(format: "%.3f", center.longitude)),
                            URLQueryItem(name: "r", value: "50000")]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearer { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await Backend.session.data(for: req),
              let res = try? JSONDecoder().decode(FlareAlerts.self, from: data) else { return }
        perSource[src.id] = res.alerts.map { $0.marker(source: src) }
        if src.ownSessionPath != nil { DriveLog.note("\(src.id): \(res.alerts.count) alerts, session=\(res.session ?? "?")") }
        rebuild()
    }

    private func rebuild() {
        directMarkers = (mine + own).filter { isOn($0.id) }.flatMap { perSource[$0.id] ?? [] }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(mine) { UserDefaults.standard.set(d, forKey: mineKey) }
        pushToAccount()
    }
}

/// The Sources screen: what feeds the community layer, in the three
/// tiers (approved, public but not reviewed, private).
/// The plugin marketplace: one tile per listed plugin, nothing else.
/// Install turns the plugin on for this phone (the same switch as the
/// Plugins screen); per-account subscriptions come later.
struct MarketplaceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSources = false
    private var sources: SourcesStore { model.sources }
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plugins add alerts to the map. Every one here is free. Approved ones are reviewed by CommuteScout; the others are public but not reviewed, and say so.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if sources.catalog.isEmpty {
                        Text("No plugin is listed yet.").foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sources.catalog) { s in PluginCard(source: s) }
                    }
                    HStack {
                        Button { showSources = true } label: { Label("My plugins and private sources", systemImage: "antenna.radiowaves.left.and.right") }
                            .accessibilityIdentifier("market-mine")
                        Spacer()
                        Link(destination: URL(string: "https://commutescout.com/plugins")!) { Label("Write a plugin", systemImage: "safari") }
                    }
                    .font(.footnote).padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle("Marketplace")
            .toolbar { Button("Done") { dismiss() } }
            .task { await sources.loadCatalog() }
            .sheet(isPresented: $showSources) { SourcesView() }
        }
    }
}

/// One marketplace tile.
struct PluginCard: View {
    @EnvironmentObject var model: AppModel
    let source: FlareSource
    private var installed: Bool { model.sources.isOn(source.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(source.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Text(source.tier == "approved" ? "Approved" : "Not reviewed")
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(source.tier == "approved" ? Color.green.opacity(0.18) : Color.orange.opacity(0.18), in: Capsule())
            }
            Text(source.summary ?? (source.kindsLabel.isEmpty ? "Community alerts for the map." : "Shows \(source.kindsLabel)."))
                .font(.caption).foregroundStyle(.secondary).lineLimit(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.coverageLabel)
                Text(source.ok == false ? "Not answering" : "\(source.count) alerts now")
                if let a = source.attribution { Text(a).lineLimit(1) }
                Text(source.acceptsReports ? "Accepts reports" : "Read only")
                Text("Free")
            }
            .font(.caption2).foregroundStyle(.secondary)
            Button {
                model.sources.setOn(source.id, !installed)
                model.markers.refresh(force: true)
            } label: {
                Text(installed ? "Installed" : "Install").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .installStyle(installed)
            .accessibilityIdentifier("install-\(source.id)")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("plugin-card")
    }
}

private extension View {
    @ViewBuilder func installStyle(_ installed: Bool) -> some View {
        if installed { buttonStyle(.bordered) } else { buttonStyle(.borderedProminent) }
    }
}

struct SourcesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var base = ""
    @State private var token = ""
    @State private var adding = false

    private var sources: SourcesStore { model.sources }

    private func catalogRow(_ s: FlareSource) -> some View {
        Toggle(isOn: Binding(get: { sources.isOn(s.id) }, set: { sources.setOn(s.id, $0); model.markers.refresh(force: true) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                Text([s.attribution, "\(s.count) alerts", s.ok == false ? "not answering" : nil]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Community reports come from Flare plugins. Public ones are checked by CommuteScout; private ones you add here are read straight from your phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://commutescout.com/plugins")!) {
                        Label("How to write a plugin", systemImage: "safari")
                    }
                }
                Section {
                    if sources.catalog.filter({ $0.tier == "approved" }).isEmpty {
                        Text("No approved plugin is listed right now.").foregroundStyle(.secondary)
                    }
                    ForEach(sources.catalog.filter { $0.tier == "approved" }) { s in catalogRow(s) }
                } header: { Text("Approved plugins") } footer: {
                    Text("Reviewed by CommuteScout. Drawn by default and may speak.")
                }
                Section {
                    if sources.catalog.filter({ $0.tier != "approved" }).isEmpty {
                        Text("None listed right now.").foregroundStyle(.secondary)
                    }
                    ForEach(sources.catalog.filter { $0.tier != "approved" }) { s in catalogRow(s) }
                } header: { Text("Public plugins, not reviewed") } footer: {
                    Text("Anyone who passes the conformance check can be listed. Drawn and labelled; voice only if you turn it on in Advanced alerts.")
                }
                Section("My plugins") {
                    ForEach(sources.mine) { s in
                        Toggle(isOn: Binding(get: { sources.isOn(s.id) }, set: { sources.setOn(s.id, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name)
                                Text([s.base, s.canReport ? "accepts reports" : nil, "every \(s.refreshS) s"]
                                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { sources.remove(s) } }
                    }
                    Button { showAdd = true } label: { Label("Add a private or unlisted plugin", systemImage: "plus.circle") }
                        .accessibilityIdentifier("add-source")
                }
            }
            .navigationTitle("Plugins")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section("Plugin address") {
                            TextField("https://example.com", text: $base)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("source-url")
                            TextField("Token (private plugins only)", text: $token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        Section {
                            Text("The app asks the plugin who it is (its handshake), then reads its alerts around where you are looking. Only you see them unless the plugin is public.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let e = sources.error { Text(e).foregroundStyle(.red).font(.footnote) }
                    }
                    .navigationTitle("Add plugin")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(adding ? "Checking" : "Add") {
                                Task {
                                    adding = true
                                    sources.error = nil
                                    if await sources.add(base: base, token: token) { showAdd = false; base = ""; token = "" }
                                    adding = false
                                }
                            }
                            .disabled(base.isEmpty || adding)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
