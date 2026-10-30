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
    // For the status page.
    var lastOk: String? = nil
    var lastError: String? = nil
    var fails: Int = 0
    var version: String? = nil
    var protocolName: String? = nil
    var contact: String? = nil
    var shared = false

    var isDirect: Bool { base != nil && ownSessionPath == nil }

    /// The one category this plugin shows, when it only ever shows one;
    /// its badge in a list carries that picture, otherwise none.
    var oneCategory: String? {
        let cats = Set(kinds.map { PluginStyle.category($0) })
        return cats.count == 1 ? cats.first : nil
    }

    /// Where the plugin says it covers, in words.
    var coverageLabel: String {
        guard let b = coverage, b.count == 4 else { return "Coverage not stated" }
        let h = b[2] - b[0], w = b[3] - b[1]
        if h >= 20, w >= 50 { return "Nationwide" }
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
    let last_ok: String?
    let last_error: String?
    let fails: Int?
    let version: String?
    let protocolName: String?
    let refresh_s: Int?
    let contact: String?
    let shared: Bool?
    struct Attribution: Decodable { let name: String?; let url: String? }
    enum CodingKeys: String, CodingKey {
        case id, name, attribution, trust, tier, count, ok, description, coverage, kinds, capabilities, base
        case last_ok, last_error, fails, version, protocolName = "protocol", refresh_s, contact, shared
    }
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
    // Added but switched off for now ("Show on my map" off): hidden from
    // the map and not asked, yet still in the person's list. Kept on this
    // phone; the account only knows on and off.
    @Published private(set) var paused: Set<String> = []
    @Published var error: String?

    private let mineKey = "cs.flare.mine.v1"
    private let hiddenKey = "cs.flare.hidden.v1"
    private let pausedKey = "cs.flare.paused.v1"
    // A private plugin's bearer token lives in the keychain under this
    // prefix plus the plugin id; the rest of the record stays in defaults.
    private let tokenPrefix = "plugin-token:"
    private var timers: [String: Timer] = [:]
    // Seconds to wait before the next poll of a source that failed, answered
    // 429 or 5xx: doubles each time up to ten minutes; absent after a success.
    private var backoff: [String: Double] = [:]
    private var lastCenter: CLLocationCoordinate2D?
    private var perSource: [String: [RoadMarker]] = [:]

    init() {
        if let d = UserDefaults.standard.data(forKey: mineKey), let list = try? JSONDecoder().decode([FlareSource].self, from: d) {
            // A record saved by an earlier version still carries its token:
            // move it to the keychain once and rewrite the list without it.
            var moved = false
            mine = list.map { s in
                var s = s
                if let t = s.token { KeychainStore.set(t, for: tokenPrefix + s.id); moved = true }
                s.token = KeychainStore.get(tokenPrefix + s.id)
                return s
            }
            if moved { save() }
        }
        hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
        paused = Set(UserDefaults.standard.stringArray(forKey: pausedKey) ?? [])
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

    private func setPaused(_ id: String, _ on: Bool) {
        if on { paused.insert(id) } else { paused.remove(id) }
        UserDefaults.standard.set(Array(paused), forKey: pausedKey)
    }

    /// In this person's list: shown, or switched off for now.
    func isAdded(_ id: String) -> Bool { Market.isAdded(id, hidden: hidden, paused: paused) }

    /// Add from the marketplace: in the list and on the map.
    func addPlugin(_ id: String) { setPaused(id, false); setOn(id, true) }

    /// Remove: out of the list and off the map. A private plugin is forgotten.
    func removePlugin(_ id: String) {
        setPaused(id, false)
        if let s = mine.first(where: { $0.id == id }) { setOn(id, true); remove(s) } else { setOn(id, false) }
    }

    /// "Show on my map": off keeps the plugin in the list but asks it nothing.
    func setShown(_ id: String, _ on: Bool) { setPaused(id, !on); setOn(id, on) }

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
        if added > 0 { save() }
        rebuild()
        DriveLog.note("plugins: account has \(hidden.count) switched off, \(added) private plugin(s) added")
    }

    /// Signing out: private plugins and their tokens came from, or went
    /// to, the account, so they leave the phone with it; otherwise the
    /// next account to sign in here would inherit them. Own sessions stay
    /// listed and simply stop polling without an account. Nothing is pushed.
    func forgetForSignOut() {
        for s in mine {
            KeychainStore.remove(tokenPrefix + s.id)
            timers[s.id]?.invalidate(); timers[s.id] = nil
            backoff[s.id] = nil
            perSource[s.id] = nil
        }
        mine = []
        hidden = []
        paused = []
        UserDefaults.standard.removeObject(forKey: mineKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: pausedKey)
        rebuild()
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
            FlareSource(id: $0.id, name: $0.name, base: nil, token: nil, refreshS: $0.refresh_s ?? 60, canReport: false,
                        canConfirm: $0.capabilities?["confirm"] ?? false,
                        attribution: $0.attribution?.name, trust: $0.trust, tier: $0.tier ?? "unreviewed", count: $0.count ?? 0, ok: $0.ok,
                        summary: $0.description, coverage: $0.coverage, kinds: $0.kinds ?? [],
                        acceptsReports: $0.capabilities?["report"] ?? false,
                        lastOk: $0.last_ok, lastError: $0.last_error, fails: $0.fails ?? 0, version: $0.version,
                        protocolName: $0.protocolName, contact: $0.contact, shared: $0.shared ?? false)
        }
        await discoverOwnSessions(r.sources.compactMap { s in s.base.map { (s.id, $0) } })
    }

    /// Whether a plugin runs on CommuteScout's own hosts. Only those may
    /// receive the account token: the backend accepts that token for an
    /// hour, so a third-party plugin holding it could act as the person.
    static func isFirstParty(_ base: String) -> Bool {
        guard let c = URLComponents(string: base), c.scheme == "https", c.port == nil, c.user == nil,
              let host = c.host?.lowercased() else { return false }
        return host == "commutescout.com" || host.hasSuffix(".commutescout.com")
            || host.hasSuffix("-15002631928.us-west1.run.app")
    }

    /// The URL an own session is polled at, or nil unless `path` is a plain
    /// absolute path and the whole URL is still first party. The path comes
    /// from the handshake, and one such as "@evil.example/x" would otherwise
    /// move the host, and the account token with it.
    static func ownSessionURL(_ base: String, _ path: String) -> String? {
        let bad = path.contains { $0 == "@" || $0 == "\\" || $0 == "?" || $0 == "#" || $0.isWhitespace }
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !bad else { return nil }
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        let url = b + path
        return isFirstParty(url) ? url : nil
    }

    /// Catalog plugins whose handshake offers user sessions get polled here.
    private func discoverOwnSessions(_ bases: [(String, String)]) async {
        var found: [FlareSource] = []
        for (id, base) in bases where Self.isFirstParty(base) {
            guard let url = URL(string: base + "/flare/v1/handshake") else { continue }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await Backend.session.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let h = try? JSONDecoder().decode(Handshake.self, from: data),
                  let us = h.extensions?.user_sessions, let path = us.path, us.auth == "firebase", h.id == id,
                  Self.ownSessionURL(base, path) != nil else { continue }
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
        KeychainStore.remove(tokenPrefix + src.id)
        timers[src.id]?.invalidate(); timers[src.id] = nil
        backoff[src.id] = nil
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

    /// Polls now, then keeps polling: every refreshS while the plugin
    /// answers, at the backed-off interval while it does not.
    private func schedule(_ src: FlareSource) {
        timers[src.id]?.invalidate(); timers[src.id] = nil
        Task { @MainActor in
            await poll(src)
            scheduleNext(src)
        }
    }

    private func scheduleNext(_ src: FlareSource) {
        // Removed, or replaced by a fresh catalog, while a poll was in flight.
        guard mine.contains(where: { $0.id == src.id }) || own.contains(where: { $0.id == src.id }) else { return }
        timers[src.id]?.invalidate()
        timers[src.id] = Timer.scheduledTimer(withTimeInterval: backoff[src.id] ?? Double(src.refreshS), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.poll(src)
                self.scheduleNext(src)
            }
        }
    }

    /// The plugin failed to answer: the next poll waits twice as long, up to ten minutes.
    private func failed(_ src: FlareSource, _ why: String) {
        let next = min(600, (backoff[src.id] ?? Double(src.refreshS)) * 2)
        backoff[src.id] = next
        DriveLog.note("\(src.id): \(why), next poll in \(Int(next)) s")
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
        let target: String
        if let path = src.ownSessionPath {
            guard let u = Self.ownSessionURL(base, path) else { return }
            target = u
        } else {
            target = base + "/flare/v1/alerts"
        }
        // A plugin URL that does not parse is skipped, never a crash.
        guard var comps = URLComponents(string: target) else { failed(src, "bad URL"); return }
        comps.queryItems = [URLQueryItem(name: "lat", value: String(format: "%.3f", center.latitude)),
                            URLQueryItem(name: "lon", value: String(format: "%.3f", center.longitude)),
                            URLQueryItem(name: "r", value: "50000")]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearer { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let data: Data
        do {
            let (d, resp) = try await Backend.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 || code >= 500 { failed(src, "answered \(code)"); return }
            data = d
        } catch {
            failed(src, error.localizedDescription)
            return
        }
        backoff[src.id] = nil
        guard let res = try? JSONDecoder().decode(FlareAlerts.self, from: data) else { return }
        perSource[src.id] = res.alerts.map { $0.marker(source: src) }
        if src.ownSessionPath != nil { DriveLog.note("\(src.id): \(res.alerts.count) alerts, session=\(res.session ?? "?")") }
        rebuild()
    }

    private func rebuild() {
        directMarkers = (mine + own).filter { isOn($0.id) }.flatMap { perSource[$0.id] ?? [] }
    }

    /// Writes the list to defaults without tokens; each token goes to the keychain.
    private func save() {
        let stripped: [FlareSource] = mine.map { s in
            KeychainStore.set(s.token, for: tokenPrefix + s.id)
            var s = s
            s.token = nil
            return s
        }
        if let d = try? JSONEncoder().encode(stripped) { UserDefaults.standard.set(d, forKey: mineKey) }
    }

    private func persist() {
        save()
        pushToAccount()
    }
}
