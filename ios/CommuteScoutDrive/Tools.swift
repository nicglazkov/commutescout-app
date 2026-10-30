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
    @State private var page: Page?

    enum Page: Identifiable { case alerts, watches, ask, directions; var id: Self { self } }

    var body: some View {
        NavigationStack {
            DGPage(title: "Tools", identifier: "page-tools", backSymbol: "xmark") {
                VStack(spacing: 14) {
                    DGGroup {
                        row("Alerts nearby", "exclamationmark.triangle", .alerts, id: "tool-alerts")
                        DGDivider()
                        row("Directions from another place", "arrow.triangle.swap", .directions, id: "tool-directions")
                        DGDivider()
                        row("Watch areas", "eye", .watches, id: "tool-watches")
                        DGDivider()
                        row("Ask about the roads", "bubble.left.and.text.bubble.right", .ask, id: "tool-ask")
                    }
                    DGGroup {
                        Link(destination: URL(string: "https://commutescout.com/map")!) {
                            DGRow(title: "Open the full map on the web", chevron: false, leading: { DGSoftTile(symbol: "safari") },
                                  trailing: { Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.faint) })
                        }
                        .buttonStyle(DGRowPress())
                        .accessibilityIdentifier("tool-web")
                    }
                }
                .padding(.top, 8)
            }
            .sheet(item: $page) { p in
                Group {
                    switch p {
                    case .alerts: AlertsListView()
                    case .watches: WatchesView()
                    case .ask: AskView()
                    case .directions: DirectionsView()
                    }
                }
                .environment(\.dismissTools, { page = nil; dismiss() })
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ p: Page, id: String) -> some View {
        Button { page = p } label: { DGRow(title: title) { DGSoftTile(symbol: symbol) } }
            .buttonStyle(DGRowPress())
            .accessibilityIdentifier(id)
    }
}

// MARK: - Alerts nearby

/// The website's Alerts tool: what is on the map, closest first.
struct AlertsListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissTools) private var dismissTools
    @State private var sorted: [RoadMarker] = []
    @State private var ready = false

    /// The nearest hundred events, worked out off the main thread. The
    /// whole country's markers are held now, and sorting them all by
    /// distance on every redraw froze the sheet for a second.
    private func rank() async {
        let here = model.here ?? model.viewCenter
        // Cameras and weather stations are on the map to look at, not
        // things that happened, so they stay out of this list.
        let shown = model.allMarkers.filter { model.prefs.isShown($0.kind) && $0.isEvent }
        let ranked: [RoadMarker] = await Task.detached(priority: .userInitiated) {
            guard let here else { return Array(shown.prefix(100)) }
            // One row per thing: a closure recorded per lane, or a sign
            // per panel, shows once, nearest copy first.
            var seen = Set<String>()
            return shown.map { ($0, AlertsEngine.meters(here, $0.coordinate)) }
                .filter { $0.1 <= 160_000 }
                .sorted { $0.1 < $1.1 }
                .filter { seen.insert("\($0.0.kind)|\($0.0.displayTitle)|\(Int($0.1 / 300))").inserted }
                .prefix(100).map(\.0)
        }.value
        sorted = ranked
        ready = true
    }

    var body: some View {
        NavigationStack {
            DGPage(title: "Alerts nearby", identifier: "page-alerts", backSymbol: "xmark") {
                VStack(alignment: .leading, spacing: 0) {
                    if !ready {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking around you").font(DG.font(15)).foregroundStyle(DG.sub)
                        }
                        .padding(.vertical, 12)
                    } else if sorted.isEmpty {
                        Text("Nothing reported within 100 miles of you.").font(DG.font(15)).foregroundStyle(DG.sub).padding(.vertical, 12)
                    } else {
                        DGGroup {
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, m in
                                if i > 0 { DGDivider(inset: 50) }
                                row(m)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .task(id: model.markers.stamp) { await rank() }
        }
    }

    private func row(_ m: RoadMarker) -> some View {
        Button {
            model.select(m)
            model.focusEvent(m.coordinate)
            dismissTools()
        } label: {
            HStack(spacing: 12) {
                MarkerGlyph(marker: m, size: 22).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.displayTitle).font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if let l = m.detailLines.first { Text(l).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if let here = model.here {
                    Text(Units.distance(AlertsEngine.meters(here, m.coordinate))).font(DG.font(13, .medium)).foregroundStyle(DG.sub)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(DGRowPress())
        .accessibilityIdentifier("alert-row")
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
            DGPage(title: "Directions", identifier: "page-directions", backSymbol: "xmark") {
                VStack(alignment: .leading, spacing: 0) {
                    DGSectionLabel("From")
                    Button { from = nil; fromText = "" } label: {
                        DGGroup {
                            DGRow(title: from?.shortName ?? "My location", chevron: false) {
                                DGSoftTile(symbol: from == nil ? "location.fill" : "mappin")
                            }
                        }
                    }
                    .buttonStyle(DGPressStyle())
                    field("Or search a start", text: $fromText, results: $fromResults) { from = $0; fromText = $0.shortName; fromResults = []; focus = nil }
                        .focused($focus, equals: .from)
                        .padding(.top, 10)
                    DGSectionLabel("To")
                    if let to {
                        DGGroup {
                            DGRow(title: to.shortName, chevron: false) { DGSoftTile(symbol: "mappin.and.ellipse") }
                        }
                        .padding(.bottom, 10)
                    }
                    field("Search a destination", text: $toText, results: $toResults) { to = $0; toText = $0.shortName; toResults = []; focus = nil }
                        .focused($focus, equals: .to)
                    Button {
                        guard let to else { return }
                        model.origin = from
                        dismissTools()
                        Task { await model.routes(to: to) }
                    } label: { Label("Show routes", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    .buttonStyle(.dgBlue)
                    .disabled(to == nil)
                    .opacity(to == nil ? 0.5 : 1)
                    .padding(.top, 20)
                    DGFootnote("Route options (tolls, highways, ferries) are in Settings. Full closures are always avoided.")
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, results: Binding<[Suggestion]>, pick: @escaping (Place) -> Void) -> some View {
        DGField(placeholder: placeholder, text: text)
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
        if !results.wrappedValue.isEmpty {
            DGGroup {
                ForEach(Array(results.wrappedValue.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { DGDivider(inset: 14) }
                    Button { pick(Place(name: s.name, coordinate: s.coordinate, kind: .recent)) } label: {
                        Text(s.name).font(DG.font(15, .medium)).foregroundStyle(DG.ink).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(DGRowPress())
                }
            }
            .padding(.top, 8)
        }
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
            ZStack(alignment: .bottom) {
                DGPage(title: "Ask", identifier: "page-ask", backSymbol: "xmark") {
                    VStack(alignment: .leading, spacing: 10) {
                        if answer.isEmpty, !running {
                            Text("Ask about closures, chain controls, fires or traffic anywhere in the country, for example \"Is I-70 open through the Eisenhower Tunnel?\", \"Any crashes on I-95 near Richmond?\" or \"Chains on US-2 over Stevens Pass?\"")
                                .font(DG.font(15)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        if !status.isEmpty { Text(status).font(DG.T.rowSub).foregroundStyle(DG.sub) }
                        if !answer.isEmpty {
                            Text(LocalizedStringKey(answer)).font(DG.font(16)).foregroundStyle(DG.ink).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if running { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                DGDock {
                    HStack(spacing: 10) {
                        DGField(placeholder: "Ask about the roads", text: $question, axis: .vertical)
                            .lineLimit(1 ... 3).onSubmit { Task { await ask() } }
                            .accessibilityIdentifier("ask-field")
                        Button { Task { await ask() } } label: {
                            Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 48, height: 48).background(DG.path, in: Circle())
                        }
                        .buttonStyle(DGPressStyle())
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || running)
                        .opacity(question.trimmingCharacters(in: .whitespaces).isEmpty || running ? 0.5 : 1)
                        .accessibilityLabel("Send")
                    }
                }
            }
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
