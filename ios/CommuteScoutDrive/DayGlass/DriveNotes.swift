import SwiftUI

/// The app's own message on a trip, in the capsule under the maneuver
/// card: arrival, no connection, rerouting, a lost signal, speeding, a
/// question about a report just passed, or a watch alert tapped during
/// the trip. It takes the place of the
/// tucked alert's slot only while no alert shows, so the two never
/// overlap. "-csForceNote <id>" shows one, for screenshots and tests.
struct DriveNoteSlot: View {
    @EnvironmentObject var model: AppModel
    /// The arrival slot at the top once the trip's card is gone; the
    /// slot under the card shows everything else.
    var arrival = false

    var body: some View {
        // The fix age only matters to the second, so a slow clock is enough.
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            if let n = note(now: ctx.date) {
                DGNote(note: n, identifier: "note-" + n.id.rawValue) { act(n, $0) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(n.id)
            }
        }
        .animation(DG.slide, value: note(now: Date())?.id)
    }

    static let forced: SystemNote.ID? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-csForceNote"), i + 1 < a.count else { return nil }
        return SystemNote.ID(rawValue: a[i + 1])
    }()

    private func note(now: Date) -> SystemNote? {
        guard let n = pick(now: now) else { return nil }
        return (n.id == .arrive) == arrival ? n : nil
    }

    private func pick(now: Date) -> SystemNote? {
        if let f = Self.forced {
            return SystemNotes.samples.first { $0.id == f }
                ?? SystemNotes.pick(SystemNotes.Input(navigating: true, rerouting: f == .reroute))
        }
        var i = SystemNotes.Input(navigating: model.state.isNavigating)
        if model.arrived, case let .navigating(place) = model.state { i.arrivedAt = place.shortName }
        i.online = model.online
        i.offlineWords = model.offlineNotice
        i.rerouting = model.coreState?.isCalculatingNewRoute == true
        // Only a trip's own fixes count: one from before it says nothing.
        if model.coreState?.isNavigating == true { i.fixAge = model.lastFixAt.map { now.timeIntervalSince($0) } ?? 0 }
        if model.speedMps >= 0 {
            i.speed = Int((Units.useMiles ? model.speedMps * 2.236936 : model.speedMps * 3.6).rounded())
        }
        if let l = model.limitKmh { i.limit = Int((Units.useMiles ? l / 1.609344 : l).rounded()) }
        if let c = model.confirmAsk {
            i.confirmKind = DGKind(marker: c.marker)
            i.confirmAgo = c.marker.reported.flatMap { EventContent.ago($0, now: now) }.map { "Reported \($0), just behind you" }
        }
        i.watch = model.parkedAlertNote(now: now)
        return SystemNotes.pick(i)
    }

    private func act(_ n: SystemNote, _ a: SystemNoteAction) {
        switch n.id {
        case .arrive: model.stop()
        case .confirm:
            guard let c = model.confirmAsk else { return }
            model.confirmAsk = nil
            model.alerts.dismiss(c.id)
            Task { await model.vote(c.marker, a == .primary ? "up" : "gone") }
        case .watch: model.showParkedAlert()
        default: break
        }
    }
}
