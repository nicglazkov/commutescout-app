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
    var count: Int = 0
    var ok: Bool?

    var isDirect: Bool { base != nil }
}

private struct SourcesResponse: Decodable { let sources: [PublicSource] }
private struct PublicSource: Decodable {
    let id: String
    let name: String
    let attribution: Attribution?
    let trust: String?
    let count: Int?
    let ok: Bool?
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
    enum CodingKeys: String, CodingKey { case protocolName = "protocol", id, name, capabilities, refresh_s, attribution, auth }
}

private struct FlareAlerts: Decodable {
    let alerts: [FlareAlert]
    let ttl_s: Int?
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
                   county: nil, delayMin: nil, lanes: nil, since: nil, until: nil, work: nil, facility: nil)
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
    }

    func loadCatalog() async {
        guard let r = try? await Backend.get("api/flare/sources", as: SourcesResponse.self) else { return }
        catalog = r.sources.map {
            FlareSource(id: $0.id, name: $0.name, base: nil, token: nil, refreshS: 60, canReport: false, canConfirm: false,
                        attribution: $0.attribution?.name, trust: $0.trust, count: $0.count ?? 0, ok: $0.ok)
        }
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
                                  canConfirm: h.capabilities?["confirm"] ?? false, attribution: h.attribution?.name, trust: "private")
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
        var comps = URLComponents(string: base + "/flare/v1/alerts")!
        comps.queryItems = [URLQueryItem(name: "lat", value: String(format: "%.3f", center.latitude)),
                            URLQueryItem(name: "lon", value: String(format: "%.3f", center.longitude)),
                            URLQueryItem(name: "r", value: "50000")]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = src.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await Backend.session.data(for: req),
              let res = try? JSONDecoder().decode(FlareAlerts.self, from: data) else { return }
        perSource[src.id] = res.alerts.map { $0.marker(source: src) }
        rebuild()
    }

    private func rebuild() {
        directMarkers = mine.filter { isOn($0.id) }.flatMap { perSource[$0.id] ?? [] }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(mine) { UserDefaults.standard.set(d, forKey: mineKey) }
    }
}

/// The Sources screen: what feeds the community layer, and the driver's
/// own private or unlisted plugins.
struct SourcesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var base = ""
    @State private var token = ""
    @State private var adding = false

    private var sources: SourcesStore { model.sources }

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
                Section("Public plugins") {
                    if sources.catalog.isEmpty {
                        Text("No public plugins are listed right now.").foregroundStyle(.secondary)
                    }
                    ForEach(sources.catalog) { s in
                        Toggle(isOn: Binding(get: { sources.isOn(s.id) }, set: { sources.setOn(s.id, $0); model.markers.refresh(force: true) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name)
                                Text([s.attribution, s.trust, "\(s.count) alerts", s.ok == false ? "not answering" : nil]
                                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
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
            .navigationTitle("Sources")
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
