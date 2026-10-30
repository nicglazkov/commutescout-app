import SwiftUI

/// The glass every floating surface is made of: frosted material under a
/// white wash, a bright top edge, a hairline ring and two soft shadows.
/// A tone tints it (alerts, the status box) and colors its shadow.
struct DGGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tone: DGTone?
    var strong = true

    func body(content: Content) -> some View {
        let tint = tone?.color
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(
                        colors: tint == nil
                            ? [.white.opacity(strong ? 0.86 : 0.7), .white.opacity(strong ? 0.76 : 0.6)]
                            : [.white.opacity(0.88), .white.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0.04)],
                                                  startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .overlay {
                ZStack {
                    // The light catching the top edge, then the inner rim.
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                       startPoint: .top, endPoint: .center), lineWidth: 1)
                    shape.inset(by: 1).strokeBorder(.white.opacity(0.55), lineWidth: 1)
                    shape.strokeBorder((tint ?? DG.ink).opacity(tint == nil ? 0.1 : 0.26), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: (tint ?? .black).opacity(tint == nil ? 0.08 : 0.12), radius: 3, y: 2)
            .shadow(color: (tint ?? DG.ink).opacity(tint == nil ? 0.16 : 0.22), radius: 18, y: 14)
    }
}

extension View {
    /// A glass surface with rounded corners.
    func dgGlass(radius: CGFloat = DG.R.cap, tone: DGTone? = nil) -> some View {
        modifier(DGGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tone: tone))
    }

    /// A glass surface of any shape.
    func dgGlass<S: InsettableShape>(_ shape: S, tone: DGTone? = nil) -> some View {
        modifier(DGGlass(shape: shape, tone: tone))
    }

    /// A pale box washed in a tone: the status line, "In plain words".
    func dgTintBox(_ tone: DGTone, radius: CGFloat = DG.R.box) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tone.color.opacity(0.18), lineWidth: 0.5))
    }
}

/// Corners rounded on chosen sides only (iOS 16 has no
/// UnevenRoundedRectangle).
struct DGCorners: InsettableShape {
    var radius: CGFloat
    var corners: UIRectCorner
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return Path(UIBezierPath(roundedRect: r, byRoundingCorners: corners,
                                 cornerRadii: CGSize(width: max(0, radius - inset), height: max(0, radius - inset))).cgPath)
    }

    func inset(by amount: CGFloat) -> DGCorners { var c = self; c.inset += amount; return c }
}
