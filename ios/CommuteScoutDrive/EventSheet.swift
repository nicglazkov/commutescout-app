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
            Capsule().fill(DG.ink.opacity(0.18)).frame(width: 40, height: 5)
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
                    .font(DG.T.button).foregroundStyle(DG.inkColor(.low))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 8)
                .accessibilityIdentifier("event-more")
            }
            actions(marker)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        }
        .background(
            // Day Glass: the sheet's glass, its bottom corners under the
            // screen edge.
            Color.clear
                .dgGlass(DGCorners(radius: DG.R.sheet, corners: [.topLeft, .topRight]))
                .padding(.bottom, -40)
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
                }
                .buttonStyle(.dgPrimary)
                if marker.kind == "plugin" { ConfirmButtons(marker: marker) }
                ShareLink(item: marker.webURL) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DG.ink).frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.7), in: Circle())
                        .overlay(Circle().strokeBorder(DG.hair, lineWidth: 1))
                }
                .buttonStyle(DGPressStyle())
                .accessibilityLabel("Share")
            } else if let focus = model.alertFocus {
                Button {
                    model.focusEvent(focus.ref.coordinate, zoom: 15)
                } label: {
                    Label("Show on map", systemImage: "map")
                }
                .buttonStyle(.dgGlass)
                if let nearby = focus.nearby {
                    Button { model.select(nearby) } label: {
                        Text("Another \(AlertRef.noun(nearby.kind)) is reported here")
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.dgPrimary)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                disc
                VStack(alignment: .leading, spacing: 2) {
                    Text(content?.title ?? Self.chip(kind)).font(DG.T.sheetTitle).foregroundStyle(DG.ink)
                        .lineLimit(expanded ? nil : 3).fixedSize(horizontal: false, vertical: true)
                    if let sub = content?.subtitle {
                        Text(sub).font(DG.font(15)).foregroundStyle(DG.sub).lineLimit(expanded ? nil : 2)
                    }
                }
                Spacer(minLength: 6)
                Button { model.clearMarker() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(DG.sub)
                        .frame(width: 36, height: 36).background(DG.ink.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("marker-close")
            }
            // A crash says what it is in its title; the other kinds need
            // the chip, which tells a closed road from a closed lane and
            // marks a plugin's report as a plugin's.
            if let content, kind != "incident" {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 9, height: 9)
                        Text(content.chip).font(DG.T.chip).foregroundStyle(accent).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: Capsule())
                    if let ago = content.ago { Text(ago).font(DG.T.noteBody).foregroundStyle(DG.sub) }
                }
            }
        }
    }

    @ViewBuilder private var disc: some View {
        if let m = marker, m.kind == "plugin" {
            MarkerGlyph(marker: m, size: 28).frame(width: 44, height: 44).background(accent.opacity(0.14), in: Circle())
        } else {
            let k = marker.map { DGKind(marker: $0) } ?? DGKind(markerKind: kind, title: focus?.ref.title)
            DGDisc(kind: k, tone: k.tone, size: 44)
        }
    }

    static func chip(_ kind: String) -> String {
        ["incident": "Incident", "lane_closure": "Closure", "chain_control": "Chain control",
         "wildfire": "Wildfire"][kind] ?? "Alert"
    }

    @ViewBuilder private func details(_ c: EventContent, _ m: RoadMarker) -> some View {
        if let warning = c.warning {
            Label(warning, systemImage: "exclamationmark.octagon.fill")
                .font(DG.font(15, .bold)).foregroundStyle(DG.inkColor(.high))
        }
        // A camera's picture and a sign's board are the point of them:
        // shown collapsed too.
        if m.kind == "camera" { CameraView(marker: m) }
        if m.kind == "sign" { SignBoard(marker: m) }
        let lines = expanded ? c.body : Array(c.body.prefix(Self.collapsedLines(c)))
        ForEach(lines, id: \.self) { line in
            if line.gloss, kind == "incident" {
                PlainWords(text: line.text)
            } else {
                Text(line.text).font(line.gloss ? DG.font(15) : DG.T.lede)
                    .lineLimit(expanded ? nil : 3)
                    .foregroundStyle(line.gloss ? DG.sub : DG.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        let away = model.here.map { EventContent.Fact(label: "From you", value: Units.distance(AlertsEngine.meters($0, m.coordinate))) }
        let facts = (expanded ? c.facts : Array(c.facts.prefix(away == nil ? 3 : 2))) + [away].compactMap { $0 }
        if !facts.isEmpty { FactList(facts: facts) }
        if expanded {
            if let s = c.schedule { ScheduleBox(schedule: s, accent: accent) }
            if let chain = c.chain { ChainBox(levels: chain, accent: accent) }
            if m.kind == "toll" { TollRates(marker: m) }
            if let d = c.dispatch { DispatchLogView(chpId: d.id) }
            if !c.foot.isEmpty {
                Text(c.foot.joined(separator: ". ") + ".").font(DG.font(12.5)).foregroundStyle(DG.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The first sentence, and its plain-words box when it has one.
    private static func collapsedLines(_ c: EventContent) -> Int {
        c.body.count > 1 && c.body[1].gloss ? 2 : 1
    }

    static func hasMore(_ c: EventContent, _ m: RoadMarker) -> Bool {
        c.body.count > collapsedLines(c) || c.facts.count > 2 || c.schedule != nil || c.chain != nil || c.dispatch != nil
            || !c.foot.isEmpty || m.kind == "toll"
    }
}

/// The status line at the top of the sheet.
struct StatusBanner: View {
    enum Tone { case active, info, quiet, warn, busy }
    let tone: Tone
    let headline: String
    let detail: String?
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if tone == .busy {
                ProgressView().controlSize(.small).frame(width: 22)
            } else {
                Circle().fill(dgTone.color).frame(width: 10, height: 10)
                    .frame(width: 22, height: 22).background(dgTone.color.opacity(0.18), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(DG.font(16, .bold)).foregroundStyle(dgTone.ink)
                if let detail { Text(detail).font(DG.font(14)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true) }
                if let retry {
                    Button("Try again", action: retry).font(DG.T.chip).foregroundStyle(DG.inkColor(.low)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(dgTone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(dgTone.color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("event-status")
    }

    /// Still there is the alert color: the event has not gone away.
    private var dgTone: DGTone {
        switch tone {
        case .active: .high
        case .info: .low
        case .quiet, .busy: .clear
        case .warn: .mid
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
                ? StatusBanner(tone: .active, headline: "Still active",
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
            Text("YOUR ALERT").font(DG.font(11.5, .bold)).foregroundStyle(DG.sub)
            if let watch = ref.watch {
                Label(watch, systemImage: "scope").font(DG.T.chip).foregroundStyle(DG.sub)
            }
            Text(ref.title ?? "Watch alert").font(DG.T.sheetTitle).foregroundStyle(DG.sub)
                .fixedSize(horizontal: false, vertical: true)
            if let text = ref.body {
                Text(text).font(DG.font(15)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
            }
            if let sent = ref.sentAt {
                Text("Sent " + sent.formatted(date: .abbreviated, time: .shortened)).font(DG.T.rowSub).foregroundStyle(DG.faint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DG.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
    }
}

/// A CHP call type, said the way a person would.
private struct PlainWords: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("In plain words").font(DG.font(13, .bold)).foregroundStyle(DG.inkColor(.low))
            Text(text).font(DG.font(15)).foregroundStyle(DG.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DGTone.low.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DGTone.low.color.opacity(0.2), lineWidth: 1))
    }
}

/// Label and value rows in a grouped box, as a settings list draws them.
private struct FactList: View {
    let facts: [EventContent.Fact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { i, f in
                if i > 0 { DGDivider(inset: 0) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(f.label).font(DG.font(14.5)).foregroundStyle(DG.sub)
                    Spacer(minLength: 8)
                    Text(f.value).font(DG.font(14.5, .semibold)).foregroundStyle(DG.ink)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
        }
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
    }
}

/// When a closure is scheduled to end, said the careful way.
private struct ScheduleBox: View {
    let schedule: EventContent.Schedule
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(schedule.head, systemImage: "calendar.badge.clock").font(DG.T.rowTitle)
            Text(schedule.tail).font(DG.font(15)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
            if !schedule.inYourZone.isEmpty {
                Text("In your timezone:").font(DG.font(12.5, .semibold)).padding(.top, 4)
                ForEach(schedule.inYourZone, id: \.self) { Text($0).font(DG.T.rowSub).foregroundStyle(DG.sub) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
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
                    Text("Caltrans reports \(active.0) here").font(DG.T.rowTitle)
                    Text(active.1).font(DG.font(15)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: DG.R.facts, style: .continuous))
                Text("The other chain control levels:").font(DG.font(12.5, .semibold)).foregroundStyle(DG.sub)
            }
            ForEach(Array(levels.others.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.0).font(DG.font(13, .bold)).foregroundStyle(accent)
                    Text(row.1).font(DG.T.noteBody).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A CHP call's dispatch log, fetched when the panel is pulled up: the
/// entries newest first with the shorthand translated, then one line per unit.
private struct DispatchLogView: View {
    let chpId: String
    @State private var log: DispatchReply.Log?
    @State private var state = "idle"   // idle, loading, failed, ended

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let log {
                section("Dispatch log", key: "Newest first. Each CHP line, then what it means.")
                ForEach(Array(log.log.enumerated()), id: \.offset) { i, row in
                    if i > 0 { DGDivider(inset: 0) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.time).font(DG.font(13, .medium).monospacedDigit()).foregroundStyle(DG.faint).frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            if let plain = row.plain {
                                Text(plain).font(DG.font(15, .semibold)).foregroundStyle(DG.ink).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(row.text).font(.system(size: 12, design: .monospaced)).foregroundStyle(DG.sub)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                if !log.units.isEmpty {
                    section("CHP units on this call (\(log.units.count))",
                            key: "One line per unit. \"Cleared to leave\" means the unit finished its part and left the scene. CHP does not name units in the public feed.")
                    ForEach(log.units, id: \.unit) { u in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Unit \(u.unit)").font(DG.font(13.5, .bold)).foregroundStyle(DG.ink).frame(width: 62, alignment: .leading)
                            Text(u.steps.map { "\($0.status) \($0.time)" }.joined(separator: ", ") + (u.done ? "" : ". Still working the scene"))
                                .font(DG.T.noteBody).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if log.log.isEmpty && log.units.isEmpty { Text("No shared entries yet.").font(DG.T.noteBody).foregroundStyle(DG.sub) }
            } else {
                HStack(spacing: 8) {
                    if state == "loading" || state == "idle" { ProgressView().controlSize(.small) }
                    Text(label).font(DG.T.noteBody).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("dispatch-log")
            }
        }
        .task(id: chpId) {
            guard log == nil else { return }
            await load()
        }
    }

    private var label: String {
        switch state {
        case "failed": "Log unavailable right now"
        case "ended": "The dispatch log ends when CHP clears the call."
        default: "Loading the dispatch log"
        }
    }

    private func section(_ title: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DG.font(17, .bold)).foregroundStyle(DG.ink)
            Text(key).font(DG.T.rowSub).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
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
