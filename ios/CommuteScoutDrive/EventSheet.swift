import SwiftUI

/// An event, as the phone shows it: a panel on the bottom edge, the way
/// a maps app shows a place. Collapsed it says what and where, and the
/// facts that matter most; pulled up it holds everything the website's
/// popup holds, the schedule, the chain levels and the dispatch log.
///
/// Opened from a tapped watch alert it also says what became of the
/// event since the alert went out: still active, changed, cleared, or no
/// longer reported. It is a panel rather than a sheet so the map stays
/// usable under it and it never fights the app's other sheets.
struct EventPanel: View {
    @EnvironmentObject var model: AppModel
    /// The space the panel may use, from the screen it sits on.
    let available: CGFloat
    // "-csEventExpanded" opens it pulled up, for screenshots.
    @State private var expanded = ProcessInfo.processInfo.arguments.contains("-csEventExpanded")
    @State private var drag: CGFloat = 0
    /// The content's own height, so the panel is never taller than it.
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        let marker = model.selectedMarker
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5)
                .padding(.top, 8).padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(duration: 0.35)) { expanded.toggle() } }
                .accessibilityLabel(expanded ? "Show less" : "Show more")
                .accessibilityAddTraits(.isButton)
            ScrollView {
                content(marker)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ContentHeight.self, value: g.size.height)
                    })
            }
            .scrollDisabled(!expanded || contentHeight <= cap)
            .frame(height: min(contentHeight, cap))
            .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
            // Outside the scrolling part, so a long first paragraph never
            // pushes it out of sight.
            if !expanded, let marker, let c = Optional(EventContent.make(marker)), EventBody.hasMore(c, marker) {
                Button { withAnimation(.spring(duration: 0.35)) { expanded = true } } label: {
                    HStack(spacing: 4) {
                        Text(c.dispatch != nil ? "More details and the dispatch log" : "More details")
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .accessibilityIdentifier("event-more")
            }
            actions(marker)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                // The bottom corners sit under the screen edge.
                .padding(.bottom, -40)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -2)
        )
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { g in
                    let dy = g.predictedEndTranslation.height
                    withAnimation(.spring(duration: 0.35)) {
                        drag = 0
                        if dy < -80 { expanded = true }
                        else if dy > 80 { if expanded { expanded = false } else { model.clearMarker() } }
                    }
                }
        )
        .onChange(of: marker?.key) { _ in expanded = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-sheet")
    }

    /// The most the scrolling part may take: under half the screen
    /// collapsed, most of it pulled up.
    private var cap: CGFloat { (expanded ? 0.85 : 0.55) * available - 130 }

    @ViewBuilder private func content(_ marker: RoadMarker?) -> some View {
        EventBody(marker: marker, focus: model.alertFocus, vanished: model.selectedVanished, expanded: expanded)
            .padding(.horizontal, 16)
    }

    @ViewBuilder private func actions(_ marker: RoadMarker?) -> some View {
        HStack(spacing: 8) {
            if let marker {
                Button {
                    model.show(Place(name: marker.displayTitle, coordinate: marker.coordinate, kind: .recent))
                } label: {
                    Label("Navigate here", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                if marker.kind == "plugin" { ConfirmButtons(marker: marker) }
                ShareLink(item: marker.webURL) {
                    Image(systemName: "square.and.arrow.up").padding(.vertical, 8).padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Share")
            } else if let focus = model.alertFocus {
                Button {
                    model.focusEvent(focus.ref.coordinate, zoom: 15)
                } label: {
                    Label("Show on map", systemImage: "map").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                if let nearby = focus.nearby {
                    Button { model.select(nearby) } label: {
                        Text("Another \(AlertRef.noun(nearby.kind)) is reported here")
                            .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// Everything above the buttons.
struct EventBody: View {
    @EnvironmentObject var model: AppModel
    let marker: RoadMarker?
    let focus: AlertFocus?
    let vanished: Bool
    let expanded: Bool

    private var kind: String { marker?.kind ?? focus?.ref.kind ?? "incident" }
    private var accent: Color {
        if let m = marker, m.kind == "plugin" { return Color(PluginStyle.color(PluginStyle.sourceId(m))) }
        if kind == "lane_closure", marker?.cls == "full-roadway" { return Color(red: 0.50, green: 0.11, blue: 0.11) }
        return MarkerIcons.tint(kind)
    }

    var body: some View {
        let content = marker.map { EventContent.make($0) }
        VStack(alignment: .leading, spacing: 12) {
            header(content)
            if let banner = StatusBanner.make(focus: focus, vanished: vanished, hasMarker: marker != nil,
                                              retry: { model.recheckAlert() }) {
                banner
            }
            if let content, let marker {
                details(content, marker)
            } else if let focus {
                AlertBlock(ref: focus.ref)
            }
        }
        .padding(.bottom, 4)
    }

    private func header(_ content: EventContent?) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(content?.chip ?? Self.chip(kind)).font(.footnote.weight(.semibold)).foregroundStyle(accent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(accent.opacity(0.12), in: Capsule())
            if let ago = content?.ago {
                Text(ago).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.clearMarker() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30).background(Color.secondary.opacity(0.14), in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("marker-close")
        }
    }

    static func chip(_ kind: String) -> String {
        ["incident": "Incident", "lane_closure": "Closure", "chain_control": "Chain control",
         "wildfire": "Wildfire"][kind] ?? "Alert"
    }

    @ViewBuilder private func details(_ c: EventContent, _ m: RoadMarker) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.title).font(.title3.weight(.bold)).lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = c.subtitle {
                Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
            }
        }
        if let warning = c.warning {
            Label(warning, systemImage: "exclamationmark.octagon.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(.red)
        }
        // A camera's picture and a sign's board are the point of them:
        // shown collapsed too.
        if m.kind == "camera" { CameraView(marker: m) }
        if m.kind == "sign" { SignBoard(marker: m) }
        let lines = expanded ? c.body : Array(c.body.prefix(1))
        ForEach(lines, id: \.self) { line in
            Text(line.text).font(line.gloss ? .subheadline.italic() : .body)
                .lineLimit(expanded ? nil : 3)
                .foregroundStyle(line.gloss ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let facts = expanded ? c.facts : Array(c.facts.prefix(3))
        if !facts.isEmpty { FactList(facts: facts) }
        if expanded {
            if let s = c.schedule { ScheduleBox(schedule: s, accent: accent) }
            if let chain = c.chain { ChainBox(levels: chain, accent: accent) }
            if m.kind == "toll" { TollRates(marker: m) }
            if let d = c.dispatch { DispatchLogView(chpId: d.id, count: d.count) }
            VStack(alignment: .leading, spacing: 2) {
                if let here = model.here {
                    Text(Units.distance(AlertsEngine.meters(here, m.coordinate)) + " from you")
                }
                ForEach(c.foot, id: \.self) { Text($0) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    static func hasMore(_ c: EventContent, _ m: RoadMarker) -> Bool {
        c.body.count > 1 || c.facts.count > 3 || c.schedule != nil || c.chain != nil || c.dispatch != nil
            || !c.foot.isEmpty || m.kind == "toll"
    }
}

/// The status line at the top of the sheet.
struct StatusBanner: View {
    enum Tone { case good, info, quiet, warn, busy }
    let tone: Tone
    let headline: String
    let detail: String?
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if tone == .busy {
                ProgressView().controlSize(.small).padding(.top, 2)
            } else {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let retry {
                    Button("Try again", action: retry).font(.footnote.weight(.semibold)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("event-status")
    }

    private var icon: String {
        switch tone {
        case .good: "checkmark.circle.fill"
        case .info: "arrow.triangle.2.circlepath"
        case .quiet: "checkmark.seal.fill"
        case .warn: "wifi.exclamationmark"
        case .busy: ""
        }
    }

    private var color: Color {
        switch tone {
        case .good: .green
        case .info: .blue
        case .quiet, .busy: .gray
        case .warn: .orange
        }
    }

    static func make(focus: AlertFocus?, vanished: Bool, hasMarker: Bool, retry: @escaping () -> Void) -> StatusBanner? {
        let now = Date()
        guard let focus else {
            return vanished ? StatusBanner(tone: .quiet, headline: "No longer reported",
                                           detail: "It ended or the agency stopped reporting it. The last report is below.") : nil
        }
        let ref = focus.ref
        let sent = ref.sentAt.map { "Alert sent " + EventContent.ago($0, now: now) + "." }
        let clock = ref.sentAt.map { $0.formatted(date: .omitted, time: .shortened) }
        let below = hasMarker ? "The last report is below." : (clock.map { "Your alert from \($0) is below." } ?? "Your alert is below.")
        switch focus.status {
        case .loading:
            return StatusBanner(tone: .busy, headline: "Checking the latest status", detail: sent)
        case let .active(confirmed):
            return confirmed
                ? StatusBanner(tone: .good, headline: "Still active",
                               detail: ["Checked just now.", sent].compactMap { $0 }.joined(separator: " "))
                : StatusBanner(tone: .warn, headline: "Still active",
                               detail: ["Couldn't confirm it just now, but it is still on the map.", sent]
                                   .compactMap { $0 }.joined(separator: " "), retry: retry)
        case let .changed(nowTitle):
            return StatusBanner(tone: .info, headline: "Changed since your alert",
                                detail: "Now: \(nowTitle)." + (ref.title.map { " Your alert said: \($0)." } ?? ""))
        case let .cleared(at):
            return StatusBanner(tone: .quiet, headline: at.map { "Cleared " + EventContent.ago($0, now: now) } ?? "Cleared",
                                detail: "This \(AlertRef.noun(ref.kind)) is no longer reported. " + below)
        case .gone:
            return StatusBanner(tone: .quiet, headline: "No longer reported",
                                detail: "It ended or the agency stopped reporting it. " + below)
        case .unknown:
            return StatusBanner(tone: .warn, headline: "Couldn't check the status",
                                detail: "Showing what the alert said.", retry: retry)
        }
    }
}

/// What the alert itself said, when the event is no longer on the map.
private struct AlertBlock: View {
    let ref: AlertRef

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR ALERT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if let watch = ref.watch {
                Label(watch, systemImage: "scope").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(ref.title ?? "Watch alert").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let text = ref.body {
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let sent = ref.sentAt {
                Text("Sent " + sent.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Label and value rows in a grouped box, as a settings list draws them.
private struct FactList: View {
    let facts: [EventContent.Fact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { i, f in
                if i > 0 { Divider().padding(.leading, 12) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(f.label).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(f.value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// When a closure is scheduled to end, said the careful way.
private struct ScheduleBox: View {
    let schedule: EventContent.Schedule
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(schedule.head, systemImage: "calendar.badge.clock").font(.subheadline.weight(.semibold))
            Text(schedule.tail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !schedule.inYourZone.isEmpty {
                Text("In your timezone:").font(.caption.weight(.semibold)).padding(.top, 4)
                ForEach(schedule.inYourZone, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The chain control level in force, and the others for reference.
private struct ChainBox: View {
    let levels: EventContent.ChainLevels
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = levels.active {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caltrans reports \(active.0) here").font(.subheadline.weight(.semibold))
                    Text(active.1).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("The other chain control levels:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array(levels.others.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.0).font(.footnote.weight(.bold).monospaced()).foregroundStyle(accent)
                    Text(row.1).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A CHP call's dispatch log, fetched when asked for: the entries newest
/// first with the shorthand translated, then one line per unit.
private struct DispatchLogView: View {
    let chpId: String
    let count: Int
    @State private var log: DispatchReply.Log?
    @State private var state = "idle"   // idle, loading, failed, ended

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let log {
                section("Dispatch log (newest first)", key: "Blue text is a rough translation of the CHP shorthand.")
                ForEach(Array(log.log.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.text).font(.footnote.monospaced()).fixedSize(horizontal: false, vertical: true)
                            if let plain = row.plain {
                                Text(plain).font(.footnote).foregroundStyle(.blue).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !log.units.isEmpty {
                    section("CHP units on this call (\(log.units.count))",
                            key: "One line per unit. \"Cleared to leave\" means the unit finished its part and left the scene. CHP does not name units in the public feed.")
                    ForEach(log.units, id: \.unit) { u in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Unit \(u.unit)").font(.footnote.weight(.bold)).frame(width: 62, alignment: .leading)
                            Text(u.steps.map { "\($0.status) \($0.time)" }.joined(separator: ", ") + (u.done ? "" : ". Still working the scene"))
                                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if log.log.isEmpty && log.units.isEmpty { Text("No shared entries yet.").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Button { Task { await load() } } label: {
                    HStack(spacing: 8) {
                        if state == "loading" { ProgressView().controlSize(.small) }
                        Text(label).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(state != "idle")
                .accessibilityIdentifier("dispatch-log")
            }
        }
    }

    private var label: String {
        switch state {
        case "loading": "Loading the dispatch log"
        case "failed": "Log unavailable right now"
        case "ended": "The dispatch log ends when CHP clears the call."
        default: "Show dispatch log (\(count))"
        }
    }

    private func section(_ title: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(key).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func load() async {
        state = "loading"
        do {
            log = try await EventAPI.dispatch(chpId).dispatch ?? DispatchReply.Log(log: [], units: [])
            state = "idle"
        } catch BackendError.status(404) {
            state = "ended"
        } catch {
            state = "failed"
        }
    }
}

private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
