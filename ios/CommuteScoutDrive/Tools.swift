import CoreLocation
import SwiftUI

/// The website's rail, on the phone: everything that is not the search
/// bar or Settings lives behind one button.
/// Pages inside the Tools sheet are sheets themselves. When a page acts on
/// the map (center on an alert, show routes) it must close the Tools sheet
/// too, or the menu stays over the map. Pages call this instead of dismiss.
private struct DismissToolsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dismissTools: () -> Void {
        get { self[DismissToolsKey.self] }
        set { self[DismissToolsKey.self] = newValue }
    }
}

struct ToolsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var showLayers: Bool
    @State private var page: Page?

    enum Page: Identifiable { case alerts, watches, ask, sources, directions, marketplace; var id: Self { self } }

    var body: some View {
        NavigationStack {
            List {
                Button { dismiss(); showLayers = true } label: { Label("Layers and base map", systemImage: "square.3.layers.3d") }
                    .accessibilityIdentifier("tool-layers")
                Button { page = .alerts } label: { Label("Alerts nearby", systemImage: "exclamationmark.triangle") }
                    .accessibilityIdentifier("tool-alerts")
                Button { page = .directions } label: { Label("Directions from another place", systemImage: "arrow.triangle.swap") }
                    .accessibilityIdentifier("tool-directions")
                Button { page = .watches } label: { Label("Watch areas", systemImage: "eye") }
                    .accessibilityIdentifier("tool-watches")
                Button { page = .ask } label: { Label("Ask about the roads", systemImage: "bubble.left.and.text.bubble.right") }
                    .accessibilityIdentifier("tool-ask")
                Button { page = .marketplace } label: { Label("Plugin marketplace", systemImage: "square.grid.2x2") }
                    .accessibilityIdentifier("tool-marketplace")
                Button { page = .sources } label: { Label("My plugins and private sources", systemImage: "antenna.radiowaves.left.and.right") }
                    .accessibilityIdentifier("tool-sources")
                Section {
                    Link(destination: URL(string: "https://commutescout.com/map")!) { Label("Open the full map on the web", systemImage: "safari") }
                }
            }
            .navigationTitle("Tools")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(item: $page) { p in
                Group {
                    switch p {
                    case .alerts: AlertsListView()
                    case .watches: WatchesView()
                    case .ask: AskView()
                    case .sources: SourcesView()
                    case .marketplace: MarketplaceView()
                    case .directions: DirectionsView()
                    }
                }
                .environment(\.dismissTools, { page = nil; dismiss() })
            }
        }
    }
}

// MARK: - Alerts nearby

/// The website's Alerts tool: what is on the map, closest first.
struct AlertsListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissTools) private var dismissTools

    private var sorted: [RoadMarker] {
        let here = model.here ?? model.viewCenter
        return model.allMarkers.filter { model.prefs.isShown($0.kind) }.sorted {
            guard let here else { return false }
            return AlertsEngine.meters(here, $0.coordinate) < AlertsEngine.meters(here, $1.coordinate)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sorted.isEmpty {
                    Text("Nothing reported in the area on screen. Zoom out or move the map to see more.").foregroundStyle(.secondary)
                }
                ForEach(sorted) { m in
                    Button {
                        model.selectedMarker = m
                        model.camera = .center(m.coordinate, zoom: 14, pitch: 0, direction: 0)
                        dismissTools()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: MarkerIcons.name(m.kind)).foregroundStyle(MarkerIcons.tint(m.kind)).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayTitle).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                if let l = m.detailLines.first { Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            if let here = model.here {
                                Text(Units.distance(AlertsEngine.meters(here, m.coordinate))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alerts nearby")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

// MARK: - Directions from another place

/// The website's From/To planner: pick a start other than where you are.
struct DirectionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissTools) private var dismissTools
    @State private var fromText = ""
    @State private var toText = ""
    @State private var fromResults: [Suggestion] = []
    @State private var toResults: [Suggestion] = []
    @State private var from: Place?
    @State private var to: Place?
    private enum Field { case from, to }
    @FocusState private var focus: Field?   // a pick drops the keyboard so Show routes is reachable

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Button { from = nil; fromText = "" } label: {
                        Label(from == nil ? "My location" : from!.shortName, systemImage: from == nil ? "location.fill" : "mappin")
                    }
                    field("Or search a start", text: $fromText, results: $fromResults) { from = $0; fromText = $0.shortName; fromResults = []; focus = nil }
                        .focused($focus, equals: .from)
                }
                Section("To") {
                    if let to { Label(to.shortName, systemImage: "mappin.and.ellipse") }
                    field("Search a destination", text: $toText, results: $toResults) { to = $0; toText = $0.shortName; toResults = []; focus = nil }
                        .focused($focus, equals: .to)
                }
                Section {
                    Button {
                        guard let to else { return }
                        model.origin = from
                        dismissTools()
                        Task { await model.routes(to: to) }
                    } label: { Label("Show routes", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity) }
                    .disabled(to == nil)
                    Text("Route options (tolls, highways, ferries) are in Settings. Full closures are always avoided.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Directions")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, results: Binding<[Suggestion]>, pick: @escaping (Place) -> Void) -> some View {
        TextField(placeholder, text: text)
            .autocorrectionDisabled()
            .onChange(of: text.wrappedValue) { q in
                let t = q.trimmingCharacters(in: .whitespaces)
                if let c = SearchBar.parseCoordinates(t) { results.wrappedValue = [Suggestion(name: c.pretty, lat: c.latitude, lon: c.longitude)]; return }
                guard t.count >= 2 else { results.wrappedValue = []; return }
                Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if let r = try? await Search.suggest(t, near: model.here), text.wrappedValue.trimmingCharacters(in: .whitespaces) == t {
                        results.wrappedValue = r
                    }
                }
            }
        ForEach(results.wrappedValue) { s in
            Button(s.name) { pick(Place(name: s.name, coordinate: s.coordinate, kind: .recent)) }.font(.subheadline)
        }
    }
}

// MARK: - Watch areas

struct Watch: Decodable, Identifiable {
    let id: String
    let name: String?
    let type: String?
    let center: Center?
    let radius_km: Double?
    let kinds: [String]?
    let active: Bool?
    struct Center: Decodable { let lat: Double; let lon: Double }
}

private struct MeResponse: Decodable { let email: String?; let watches: [Watch] }

/// The website's Watch tool: areas that alert you by push or email when
/// something happens inside them. Managed on the site; created here
/// around a place.
struct WatchesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var watches: [Watch] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSignIn = false
    @State private var name = ""
    @State private var radius = 8.0
    @State private var kinds: Set<String> = ["incident", "closure", "chain", "fire"]

    private let kindLabels = [("incident", "Incidents"), ("closure", "Closures"), ("chain", "Chain controls"), ("fire", "Fires")]

    var body: some View {
        NavigationStack {
            Form {
                if !model.account.signedIn {
                    Section {
                        Text("Watch areas need an account, the same one as the website.")
                        Button("Sign in") { showSignIn = true }
                    }
                } else {
                    Section("Your watch areas") {
                        if loading { ProgressView() }
                        if !loading, watches.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                        ForEach(watches) { w in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name ?? "Watch area")
                                Text([w.type, w.radius_km.map { "\(Units.distance($0 * 1000)) radius" }, w.kinds?.joined(separator: ", ")]
                                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions { Button("Delete", role: .destructive) { Task { await delete(w) } } }
                        }
                    }
                    Section("New watch around \(anchorName)") {
                        TextField("Name", text: $name)
                        Stepper("Radius \(Units.distance(radius * 1000))", value: $radius, in: 1 ... 40, step: 1)
                        ForEach(kindLabels, id: \.0) { k in
                            Toggle(k.1, isOn: Binding(get: { kinds.contains(k.0) }, set: { if $0 { kinds.insert(k.0) } else { kinds.remove(k.0) } }))
                        }
                        Button("Create watch") { Task { await create() } }.disabled(kinds.isEmpty || anchor == nil)
                        Text("Push and email delivery, polygons and route watches are set up on commutescout.com.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Link(destination: URL(string: "https://commutescout.com/watch")!) { Label("Manage on the website", systemImage: "safari") }
                }
            }
            .navigationTitle("Watch areas")
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
            .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to keep watch areas.") }
            .alert("Watch areas", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var anchor: CLLocationCoordinate2D? {
        if case let .found(p) = model.state { return p.coordinate }
        return model.here ?? model.viewCenter
    }

    private var anchorName: String {
        if case let .found(p) = model.state { return p.shortName }
        return "you"
    }

    private func load() async {
        guard let token = await model.account.token() else { return }
        loading = true; defer { loading = false }
        if let (status, data) = try? await Backend.send("GET", "api/watch/me", token: token), status == 200,
           let me = try? JSONDecoder().decode(MeResponse.self, from: data) {
            watches = me.watches
        }
    }

    private func create() async {
        guard let token = await model.account.token(), let c = anchor else { return }
        let body: [String: Any] = ["type": "circle", "name": name.isEmpty ? "Around \(anchorName)" : name,
                                   "center": ["lat": c.latitude, "lon": c.longitude], "radius_km": radius,
                                   "kinds": Array(kinds), "channels": ["push": false, "email": true]]
        do {
            let (status, data) = try await Backend.send("POST", "api/watch/create", token: token, body: body)
            guard status < 300 else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                error = msg ?? "The server refused the watch (\(status))."
                return
            }
            name = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ w: Watch) async {
        guard let token = await model.account.token() else { return }
        _ = try? await Backend.send("DELETE", "api/watch/\(w.id)", token: token)
        await load()
    }
}

// MARK: - Ask

/// The website's Ask tool: a question about the roads, answered by the
/// same assistant, streamed as it is written.
struct AskView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var status = ""
    @State private var prior: (q: String, a: String)?
    @State private var running = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if answer.isEmpty, !running {
                            Text("Ask about closures, chain controls, fires or traffic, for example \"Is 80 over Donner open?\" or \"Anything between here and Tahoe?\"")
                                .foregroundStyle(.secondary)
                        }
                        if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                        if !answer.isEmpty { Text(LocalizedStringKey(answer)).textSelection(.enabled) }
                        if running { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                HStack {
                    TextField("Ask about the roads", text: $question, axis: .vertical).lineLimit(1 ... 3)
                        .textFieldStyle(.roundedBorder).onSubmit { Task { await ask() } }
                        .accessibilityIdentifier("ask-field")
                    Button { Task { await ask() } } label: { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.borderedProminent).disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || running)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .navigationTitle("Ask")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        running = true; answer = ""; status = ""
        defer { running = false }
        var body: [String: Any] = ["question": q, "tz": TimeZone.current.identifier]
        // Three decimals (about 100 m), the same as every other request.
        if let here = model.here { body["location"] = ["lat": (here.latitude * 1000).rounded() / 1000, "lon": (here.longitude * 1000).rounded() / 1000] }
        if let prior { body["prior"] = ["question": prior.q, "answer": prior.a] }
        var req = URLRequest(url: Backend.base.appendingPathComponent("api/ask"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, resp) = try await Backend.session.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { answer = "The assistant is not available right now."; return }
            for try await line in bytes.lines {
                guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                      let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let t = msg["text"] as? String { answer += t; status = "" }
                if let tool = msg["tool"] as? String { status = "Looking up " + tool.replacingOccurrences(of: "_", with: " ") }
            }
            prior = (q, answer)
            question = ""
        } catch {
            answer = "Could not reach the assistant: \(error.localizedDescription)"
        }
    }
}
