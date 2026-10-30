import SwiftUI

/// The bottom sheet: glass, a grab handle, snap heights, and a rubber
/// band past the first and last snap. A tap on the handle goes to the
/// next snap; a drag lands on the nearest one, carried by its speed.
struct DGSheet<Content: View>: View {
    /// Heights the sheet rests at, lowest first.
    var snaps: [CGFloat]
    @Binding var index: Int
    var identifier = "dg-sheet"
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        let base = snaps[min(max(0, index), snaps.count - 1)]
        let h = DGSheetMath.rubber(base - drag, low: snaps.first ?? 0, high: snaps.last ?? 0)
        VStack(spacing: 0) {
            Capsule().fill(DG.ink.opacity(0.18)).frame(width: 40, height: 5)
                .padding(.top, 8).padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(DG.slide) { index = (index + 1) % snaps.count } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(index == snaps.count - 1 ? "Show less" : "Show more")
                .accessibilityIdentifier("\(identifier)-grab")
            content()
                .frame(maxWidth: .infinity, alignment: .top)
            Spacer(minLength: 0)
        }
        .frame(height: h, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(DGCorners(radius: DG.R.sheet, corners: [.topLeft, .topRight]))
        .dgGlass(DGCorners(radius: DG.R.sheet, corners: [.topLeft, .topRight]))
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .updating($drag) { v, s, _ in s = v.translation.height }
                .onEnded { v in
                    let projected = base - v.predictedEndTranslation.height
                    withAnimation(DG.slide) { index = DGSheetMath.nearest(projected, in: snaps) }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The sheet's arithmetic, apart from any view.
enum DGSheetMath {
    /// Past either end the sheet moves at a third of the finger.
    static func rubber(_ h: CGFloat, low: CGFloat, high: CGFloat, factor: CGFloat = 0.35) -> CGFloat {
        if h > high { return high + (h - high) * factor }
        if h < low { return low - (low - h) * factor }
        return h
    }

    static func nearest(_ h: CGFloat, in snaps: [CGFloat]) -> Int {
        snaps.indices.min { abs(snaps[$0] - h) < abs(snaps[$1] - h) } ?? 0
    }
}
