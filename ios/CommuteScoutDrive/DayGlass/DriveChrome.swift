import FerrostarCore
import FerrostarCoreFFI
import SwiftUI

// What the driver sees on a trip, in Day Glass+: the maneuver card on
// top, the alert tucked under it, the trip bar, and the speed disc.

/// Ferrostar's instruction slot: the maneuver card with the alert ahead
/// tucked under it. Reports its height so the map and its buttons sit
/// below both; the card always stays on top of the alert.
struct DriveTop: View {
    @EnvironmentObject var model: AppModel
    let state: NavigationState?
    @Binding var size: CGSize
    /// The alert shown last, to ask about once it is passed.
    @State private var lastShown: AlertsEngine.Upcoming?

    var body: some View {
        // Ferrostar asks for this view while browsing too; only a trip has a card.
        if state?.isNavigating == true { card } else { Color.clear.frame(height: 0).onAppear { size = .zero } }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: cardHeight - DriveAlert.tuck)
                    alert
                }
                // The app's own message takes the slot only while no alert
                // is tucked there.
                if !alertShown {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: cardHeight + 8)
                        DriveNoteSlot()
                    }
                }
                ManeuverCard(state: state)
                    .background(GeometryReader { g in Color.clear.preference(key: CardHeight.self, value: g.size.height) })
                    .zIndex(1)
            }
            .onPreferenceChange(CardHeight.self) { cardHeight = $0 }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .background(GeometryReader { g in
                Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 }
            })
            Spacer(minLength: 0)
        }
        .animation(DG.slide, value: model.alerts.banner(within: model.prefs.stripAheadMeters)?.id)
        .animation(DG.slide, value: model.alerts.cleared?.id)
        .onChange(of: model.alerts.banner(within: model.prefs.stripAheadMeters)?.id) { _ in askAboutPassed() }
    }

    private var alertShown: Bool {
        model.alerts.cleared != nil || model.alerts.banner(within: model.prefs.stripAheadMeters) != nil
    }

    /// A report that takes votes went by: ask whether it is still there,
    /// for 15 seconds. Passing anything else says nothing.
    private func askAboutPassed() {
        let next = model.alerts.banner(within: model.prefs.stripAheadMeters)
        defer { lastShown = next }
        guard let p = lastShown, p.id != next?.id, !model.alerts.dismissed.contains(p.id),
              model.canConfirm(p.marker), model.alerts.hereAlong >= p.alongMeters - 80 else { return }
        model.confirmAsk = p
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if model.confirmAsk?.id == p.id { model.confirmAsk = nil }
        }
    }

    @State private var cardHeight: CGFloat = 158

    @ViewBuilder private var alert: some View {
        if let c = model.alerts.cleared {
            DriveAlert(item: c, along: model.alerts.hereAlong, more: .constant(false), cleared: true)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if let next = model.alerts.banner(within: model.prefs.stripAheadMeters) {
            DriveAlert(item: next, along: model.alerts.hereAlong, more: $model.alertMore)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private struct CardHeight: PreferenceKey {
        static var defaultValue: CGFloat = 158
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

/// The next turn: its arrow, how far, the road, then the turn after,
/// and the lanes to be in when the route says.
struct ManeuverCard: View {
    let state: NavigationState?

    var body: some View {
        let vi = state?.currentVisualInstruction
        let dist = state?.currentProgress?.distanceToNextManeuver ?? 0
        let (num, unit) = ManeuverCard.split(Units.distance(dist))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                DGIconView(name: ManeuverCard.symbol(vi?.primaryContent), size: 32, stroke: 2.6)
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [DG.hex(0x4a8ff8), DG.path], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: DG.path.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(num).font(DG.T.maneuverDistance).foregroundStyle(DG.ink).monospacedDigit()
                        Text(unit).font(DG.T.maneuverUnit).foregroundStyle(DG.sub)
                    }
                    Text(vi?.primaryContent.text ?? state?.currentRoadName ?? "Follow the route")
                        .font(DG.T.road).foregroundStyle(DG.ink).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            if let then = thenText {
                Text(then).font(DG.T.then).foregroundStyle(DG.sub).lineLimit(1)
            }
            if let lanes = vi?.subContent?.laneInfo ?? vi?.primaryContent.laneInfo, !lanes.isEmpty {
                LanesRow(lanes: lanes)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgGlass(radius: DG.R.card)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maneuver-card")
    }

    private var thenText: String? {
        if let s = state?.currentVisualInstruction?.secondaryContent?.text, !s.isEmpty { return "Then " + s }
        guard let next = state?.remainingSteps?.dropFirst().first, !next.instruction.isEmpty else { return nil }
        return "Then " + next.instruction.prefix(1).lowercased() + next.instruction.dropFirst()
    }

    static func split(_ s: String) -> (String, String) {
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    static func symbol(_ c: VisualInstructionContent?) -> String {
        guard let c else { return "arrow.up" }
        switch c.maneuverType {
        case .arrive: return "flag.checkered"
        case .roundabout, .rotary, .roundaboutTurn, .exitRoundabout, .exitRotary: return "arrow.triangle.turn.up.right.circle"
        case .merge: return "arrow.merge"
        case .fork: return c.maneuverModifier.map { [.left, .slightLeft, .sharpLeft].contains($0) } == true ? "arrow.up.left" : "arrow.up.right"
        default: break
        }
        return direction(c.maneuverModifier.map { "\($0)" } ?? "straight")
    }

    /// An arrow for "left", "slight right", "slightRight", "uturn"...
    static func direction(_ d: String) -> String {
        let s = d.lowercased().replacingOccurrences(of: " ", with: "")
        if s.contains("uturn") { return "arrow.uturn.down" }
        if s.contains("slightleft") { return "arrow.up.left" }
        if s.contains("slightright") { return "arrow.up.right" }
        if s.contains("left") { return "arrow.turn.up.left" }
        if s.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// The lanes for the coming turn: the ones to use lit blue.
struct LanesRow: View {
    let lanes: [LaneInfo]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, l in
                DGIconView(name: ManeuverCard.direction(l.activeDirection ?? l.directions.first ?? "straight"), size: 20, stroke: 2.4)
                    .foregroundStyle(l.active ? DGTone.low.ink : DG.faint)
                    .frame(maxWidth: 40, minHeight: 30)
                    .background(l.active ? DGTone.low.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(2)
        .frame(height: 34)
        .background(DG.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: DG.R.lanes))
        .accessibilityLabel("Lanes")
    }
}

/// The alert ahead, tucked under the maneuver card: the lane drawing,
/// what it is, what to do, and how far. A tap opens "see more": the
/// large drawing and, when the source takes them, Still there and
/// It's gone. A swipe up puts it away.
struct DriveAlert: View {
    @EnvironmentObject var model: AppModel
    static let tuck: CGFloat = 26
    let item: AlertsEngine.Upcoming
    let along: Double
    @Binding var more: Bool
    var cleared = false
    /// On the browse map there is no card to tuck under.
    var standalone = false
    @State private var thanked = false

    private var kind: DGKind { DGKind(marker: item.marker) }
    private var plugin: Bool { item.marker.kind == "plugin" }
    private var tone: DGTone { cleared ? .good : kind.tone }
    private var gap: Double { max(0, item.alongMeters - along) }
    private var plan: LanePlan? { LanePlan(item.marker.laneLayout) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if more && !cleared { expanded } else { collapsed }
        }
        .padding(.horizontal, 16)
        .padding(.top, standalone ? 14 : Self.tuck + 12)
        .padding(.bottom, 14)
        .frame(maxWidth: standalone ? .infinity : 350)
        .frame(maxWidth: .infinity)
        .dgGlass(DGCorners(radius: 26, corners: standalone ? .allCorners : [.bottomLeft, .bottomRight]), tone: tone)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !cleared else { return }
            withAnimation(DG.spring) { more.toggle() }
            if more { model.alerts.say(item.marker) }
        }
        .gesture(DragGesture(minimumDistance: 20).onEnded { g in
            if g.translation.height < -20 { withAnimation(DG.hide) { more = false; model.alerts.dismiss(item.id) } }
        })
        .animation(DG.tint, value: cleared)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(cleared ? "alert-cleared" : "alert-banner")
    }

    /// Plugin alerts carry their source's badge, so a community report
    /// never passes for an official one.
    private var pluginBadge: some View {
        PluginBadge(sourceId: PluginStyle.sourceId(item.marker), category: PluginStyle.category(item.marker.flareKind), size: 18)
    }

    private var title: String {
        if cleared { return "\(kind.short) has cleared" }
        if plugin, let r = item.marker.road, !r.isEmpty { return kind.short }
        return kind.short
    }

    private var detail: String {
        if cleared { return plan != nil || [.crash, .closure, .hazard].contains(kind) ? "All lanes are open again" : "No longer reported" }
        if let l = item.marker.lanes, !l.isEmpty { return l.prefix(1).uppercased() + l.dropFirst() }
        return item.marker.displayTitle
    }

    private var eta: String? {
        guard model.speedMps > 3 else { return nil }
        let s = Int((gap / model.speedMps).rounded())
        return s < 60 ? "\(max(1, s)) s" : "\(Int((Double(s) / 60).rounded())) min"
    }

    private var collapsed: some View {
        HStack(alignment: .center, spacing: 12) {
            LaneDrawing(kind: kind, layout: item.marker.laneLayout, cleared: cleared,
                        closeness: min(1, max(0, 1 - gap / 1300)))
                .background(.white, in: RoundedRectangle(cornerRadius: DG.R.thumb, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: DG.R.thumb, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DG.R.thumb, style: .continuous).strokeBorder(DG.hair, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if plugin && !cleared { pluginBadge }
                    Text(title).font(DG.T.alertTitle).foregroundStyle(DG.ink).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(detail).font(DG.T.alertBody).foregroundStyle(tone.ink).lineLimit(2).minimumScaleFactor(0.85)
            }
            .id(cleared)
            .transition(.opacity)
            Spacer(minLength: 0)
            if !cleared {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Units.distance(gap)).font(DG.T.alertDistance).foregroundStyle(DG.ink).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let eta { Text(eta).font(DG.T.alertEta).foregroundStyle(DG.sub) }
                    if model.alerts.ahead.count > 1 {
                        Text("+\(model.alerts.ahead.count - 1) more").font(DG.T.alertEta).foregroundStyle(DG.faint)
                    }
                }
            }
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if plugin { pluginBadge }
                        Text(title).font(DG.T.moreTitle).foregroundStyle(DG.ink)
                    }
                    Text(item.marker.displayTitle).font(DG.T.alertBody).foregroundStyle(DG.sub).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Units.distance(gap)).font(DG.T.moreDistance).foregroundStyle(DG.ink).monospacedDigit()
                    if let eta { Text(eta).font(DG.T.alertEta).foregroundStyle(DG.sub) }
                }
            }
            LaneDrawing(kind: kind, layout: item.marker.laneLayout, size: .large,
                        near: Units.distance(gap), half: Units.distance(gap / 2),
                        closeness: min(1, max(0, 1 - gap / 1300)), lines: item.marker.lines ?? [])
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let say = plan?.instruction ?? (item.marker.lanes != nil ? detail : nil) {
                Text(say).font(DG.T.noteTitle).foregroundStyle(tone.ink)
            }
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        if thanked {
            Text("Thanks").font(DG.T.button).foregroundStyle(DGTone.good.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(DGTone.good.color.opacity(0.14), in: Capsule())
        } else {
            HStack(spacing: 8) {
                if model.canConfirm(item.marker) {
                    Button("Still there") { vote("up") }.buttonStyle(.dgPrimary).accessibilityIdentifier("alert-confirm-up")
                    Button("It's gone") { vote("gone") }.buttonStyle(.dgTinted(.high)).accessibilityIdentifier("alert-confirm-gone")
                }
                Button("Dismiss") { withAnimation(DG.hide) { more = false; model.alerts.dismiss(item.id) } }
                    .buttonStyle(.dgGlass).accessibilityIdentifier("alert-dismiss")
            }
        }
    }

    private func vote(_ v: String) {
        Task { await model.vote(item.marker, v) }
        withAnimation(DG.snap) { thanked = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(DG.hide) { more = false; model.alerts.dismiss(item.id) }
        }
    }
}

/// When you arrive, how long, how far, and the way out.
struct TripBar: View {
    let state: NavigationState?
    let onExit: (() -> Void)?

    var body: some View {
        let p = state?.currentProgress
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(arrival(p)).font(DG.T.eta).foregroundStyle(DG.ink).monospacedDigit()
                Text(meta(p)).font(DG.T.meta).foregroundStyle(DG.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { onExit?() } label: {
                DGIconView(name: "close", size: 22, stroke: 2.6)
                    .foregroundStyle(DGTone.high.ink)
                    .frame(width: 52, height: 52)
                    .background(DGTone.high.color.opacity(0.13), in: Circle())
                    .overlay(Circle().strokeBorder(DGTone.high.color.opacity(0.25), lineWidth: 0.5))
            }
            .buttonStyle(DGPressStyle())
            .accessibilityLabel("End trip")
            .accessibilityIdentifier("end-trip")
        }
        .padding(.leading, 22).padding(.trailing, 12)
        .frame(height: 76)
        .dgGlass(radius: DG.R.trip)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-bar")
    }

    private func arrival(_ p: TripProgress?) -> String {
        guard let p else { return "--" }
        return Date().addingTimeInterval(p.durationRemaining).formatted(date: .omitted, time: .shortened)
    }

    private func meta(_ p: TripProgress?) -> String {
        guard let p else { return "" }
        let min = Int((p.durationRemaining / 60).rounded())
        let t = min >= 60 ? "\(min / 60) h \(min % 60) min" : "\(max(1, min)) min"
        return "\(t) · \(Units.distance(p.distanceRemaining))"
    }
}

/// Speed in a glass disc, the posted limit as a sign on its shoulder.
/// The number turns red when over.
struct SpeedDisc: View {
    let speedMps: Double
    let limitKmh: Double?

    private var miles: Bool { Units.useMiles }
    private var speed: Int { speedMps < 0 ? 0 : Int((miles ? speedMps * 2.236936 : speedMps * 3.6).rounded()) }
    private var limit: Int? { limitKmh.map { Int((miles ? $0 / 1.609344 : $0).rounded()) } }
    private var over: Bool { limit.map { speed > $0 + 1 } ?? false }

    var body: some View {
        VStack(spacing: -3) {
            Text("\(speed)").font(DG.font(26, .bold)).monospacedDigit().foregroundStyle(over ? DGTone.high.ink : DG.ink)
            Text(miles ? "mph" : "km/h").font(DG.font(11, .semibold)).foregroundStyle(DG.sub)
        }
        .frame(width: 72, height: 72)
        .dgGlass(Circle(), tone: over ? .high : nil)
        .overlay(alignment: .topTrailing) {
            if let limit {
                Text("\(limit)").font(DG.font(13, .bold)).monospacedDigit().foregroundStyle(DG.ink)
                    .frame(width: 32, height: 32)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(DGTone.high.color, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .offset(x: 6, y: -6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("speedometer")
    }
}

/// A message from the app itself: a faster route, a lost signal, a
/// watch alert, arrival. The mockups' capsule: tinted glass, the icon in
/// a small disc, a bold line and a small one, and up to two actions
/// under them. A short message with no actions hugs its words; one
/// action with a short line sits inline on the right.
struct DGNote<Actions: View>: View {
    var systemImage: String
    var tone: DGTone
    var title: String
    var detail: String?
    var identifier: String = "dg-note"
    var inline = false
    var showsActions = true
    @ViewBuilder var actions: () -> Actions

    private var hasActions: Bool { showsActions && Actions.self != EmptyView.self }
    private var narrow: Bool { !hasActions && (detail?.count ?? 0) <= 30 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                DGDisc(systemImage: systemImage, tone: tone, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DG.T.noteTitle).foregroundStyle(DG.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(DG.T.noteBody).foregroundStyle(DG.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !narrow { Spacer(minLength: 0) }
                if inline && hasActions { HStack(spacing: 8) { actions() }.fixedSize() }
            }
            if !inline && hasActions { HStack(spacing: 8) { actions() } }
        }
        .padding(.leading, 12).padding(.trailing, narrow ? 22 : 18).padding(.vertical, 12)
        .frame(maxWidth: narrow ? nil : .infinity, alignment: .leading)
        .dgGlass(radius: DG.R.cap, tone: tone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension DGNote where Actions == EmptyView {
    init(systemImage: String, tone: DGTone, title: String, detail: String? = nil, identifier: String = "dg-note") {
        self.init(systemImage: systemImage, tone: tone, title: title, detail: detail, identifier: identifier) { EmptyView() }
    }
}

/// What a tap on a system message's button means.
enum SystemNoteAction { case primary, secondary }

extension DGNote where Actions == SystemNoteButtons {
    /// A system message with its buttons; `act` hears which was tapped.
    init(note: SystemNote, identifier: String = "dg-note", act: @escaping (SystemNoteAction) -> Void) {
        self.init(systemImage: note.icon, tone: note.tone, title: note.title, detail: note.detail,
                  identifier: identifier, inline: note.inline, showsActions: note.primary != nil) {
            SystemNoteButtons(note: note, act: act)
        }
    }
}

/// A system message's one or two buttons, 44 points high.
struct SystemNoteButtons: View {
    var note: SystemNote
    var act: (SystemNoteAction) -> Void

    var body: some View {
        if let p = note.primary {
            Button(p) { act(.primary) }
                .buttonStyle(DGButtonStyle(kind: note.tone == .low ? .blue : .primary, height: 44))
                .fixedSize(horizontal: note.inline, vertical: false)
                .accessibilityIdentifier("note-" + note.id.rawValue + "-primary")
            if let s = note.secondary {
                Button(s) { act(.secondary) }
                    .buttonStyle(DGButtonStyle(kind: .glass, height: 44))
                    .accessibilityIdentifier("note-" + note.id.rawValue + "-secondary")
            }
        }
    }
}
