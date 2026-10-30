import SwiftUI

/// At the top while a cleared watch alert is open: it is over, and when.
struct WatchClearedCapsule: View {
    var text: WatchClearedText

    var body: some View {
        DGNote(systemImage: DGIcon.check, tone: .good, title: text.capsule, detail: text.since, identifier: "watch-cleared-capsule")
    }
}

/// The sheet for a watch alert whose event has cleared: the event, a
/// green box with the open road, what the alert said (struck through),
/// and Show on map and Done.
struct WatchClearedPanel: View {
    @EnvironmentObject var model: AppModel
    var focus: AlertFocus
    var text: WatchClearedText

    private var kind: DGKind { DGKind(markerKind: focus.ref.kind, title: focus.ref.title) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(DG.ink.opacity(0.18)).frame(width: 40, height: 5).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    over.padding(.top, 14)
                    said.padding(.top, 16)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .frame(maxHeight: 460)
            actions
        }
        .frame(maxWidth: .infinity)
        // The glass runs on under the home indicator to the screen's edge.
        .background(alignment: .top) {
            Color.clear.dgGlass(DGCorners(radius: DG.R.sheet, corners: [.topLeft, .topRight]))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-cleared")
    }

    private var header: some View {
        HStack(spacing: 12) {
            DGDisc(kind: kind, tone: kind.tone, size: 44, ghost: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.ref.title ?? kind.short).font(DG.T.sheetTitle).foregroundStyle(DG.ink).lineLimit(2)
                if let p = text.place { Text(p).font(DG.font(15, .medium)).foregroundStyle(DG.sub).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Button { model.clearMarker() } label: {
                DGIconView(name: "close", size: 18, stroke: 2.4).foregroundStyle(DG.sub)
                    .frame(width: 36, height: 36).background(DG.ink.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("watch-cleared-close")
        }
        .padding(.top, 12)
    }

    private var over: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                DGDisc(systemImage: DGIcon.check, tone: .good, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.heading).font(DG.font(20, .bold)).foregroundStyle(DGTone.good.ink)
                    Text(text.detail).font(DG.font(14)).foregroundStyle(DG.sub)
                }
            }
            RoadCanvas(spec: openRoad)
                .frame(height: 92)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(DGTone.good.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DGTone.good.color.opacity(0.24), lineWidth: 1))
    }

    /// The road with the lanes open: green, the block a dashed ghost, a check.
    private var openRoad: RoadSpec {
        var s = (LanePlan(focus.ref.laneLayout).map { RoadSpec.plan($0, kind: kind) } ?? RoadSpec.kind(kind)).cleared()
        s.k = 0.62; s.sh = 0.3; s.padL = 14; s.padR = 14; s.padT = 6; s.padB = 8; s.scale = 1.1
        s.path = nil; s.you = nil
        s.marks = s.marks.map { var m = $0; m.r = 11; return m }
        return s
    }

    private var said: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DGIconView(name: "watch", size: 14, stroke: 2.2)
                Text(text.said).font(DG.font(13, .medium))
            }
            .foregroundStyle(DG.sub).padding(.horizontal, 4)
            HStack(spacing: 12) {
                LaneDrawing(kind: kind, layout: focus.ref.laneLayout, size: .row)
                    .frame(width: 64, height: 54)
                    .background(.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .grayscale(1).opacity(0.7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.ref.title ?? kind.short).font(DG.font(16, .semibold)).foregroundStyle(DG.sub)
                        .strikethrough(true, color: DG.ink.opacity(0.35))
                    if let b = text.from {
                        Text(b).font(DG.font(14)).foregroundStyle(DG.faint).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
            .background(DG.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { model.focusEvent(focus.ref.coordinate, zoom: 15) } label: {
                HStack(spacing: 8) { DGIconView(name: "nav", size: 18, stroke: 2); Text("Show on map") }
            }
            .buttonStyle(DGButtonStyle(kind: .glass, height: 52))
            .accessibilityIdentifier("watch-cleared-show")
            Button("Done") { model.clearMarker() }
                .buttonStyle(DGButtonStyle(kind: .primary, height: 52))
                .accessibilityIdentifier("watch-cleared-done")
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .overlay(alignment: .top) { Rectangle().fill(DG.hair).frame(height: 0.5) }
    }
}
