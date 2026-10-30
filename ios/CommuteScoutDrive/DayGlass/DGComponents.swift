import SwiftUI

// MARK: - Buttons

/// The pill buttons: ink for the main act, blue for go, green for a
/// done thing, a tone's tint for a choice, and plain glass.
struct DGButtonStyle: ButtonStyle {
    enum Kind { case primary, blue, done, tinted(DGTone), glass }
    var kind: Kind = .primary
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DG.T.button)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(ring, lineWidth: 0.5))
            .shadow(color: shadow, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DG.snap, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .blue: return .white
        case .done: return DGTone.good.ink
        case let .tinted(t): return t.ink
        case .glass: return DG.ink
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(DG.ink)
        case .blue: return AnyShapeStyle(LinearGradient(colors: [DG.hex(0x4a8ff8), DG.hex(0x2f7cf6)], startPoint: .top, endPoint: .bottom))
        case .done: return AnyShapeStyle(DGTone.good.color.opacity(0.14))
        case let .tinted(t): return AnyShapeStyle(t.color.opacity(0.13))
        case .glass: return AnyShapeStyle(Color.white.opacity(0.8))
        }
    }

    private var ring: Color {
        switch kind {
        case .primary, .blue: return .white.opacity(0.2)
        case .done: return DGTone.good.color.opacity(0.3)
        case let .tinted(t): return t.color.opacity(0.3)
        case .glass: return DG.hair
        }
    }

    private var shadow: Color {
        switch kind {
        case .primary: return DG.ink.opacity(0.25)
        case .blue: return DG.path.opacity(0.35)
        default: return .clear
        }
    }
}

extension ButtonStyle where Self == DGButtonStyle {
    static var dgPrimary: DGButtonStyle { DGButtonStyle(kind: .primary) }
    static var dgBlue: DGButtonStyle { DGButtonStyle(kind: .blue) }
    static var dgDone: DGButtonStyle { DGButtonStyle(kind: .done) }
    static var dgGlass: DGButtonStyle { DGButtonStyle(kind: .glass) }
    static func dgTinted(_ t: DGTone) -> DGButtonStyle { DGButtonStyle(kind: .tinted(t)) }
}

/// A round glass map button, 50 across.
struct DGRoundButton<Label: View>: View {
    var size: CGFloat = 50
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DG.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .dgGlass(Circle())
        }
        .buttonStyle(DGPressStyle())
    }
}

/// Shrinks a little under the finger.
struct DGPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(DG.snap, value: configuration.isPressed)
    }
}

// MARK: - Chips and discs

/// A small rounded label: the kind chip on a card, a filter.
struct DGChip: View {
    var text: String
    var tone: DGTone = .clear
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { DGIconView(name: systemImage, size: 14, stroke: 2.4) }
            Text(text).font(DG.T.chip)
        }
        .foregroundStyle(tone == .clear ? DG.sub : tone.ink)
        .padding(.horizontal, 10).frame(height: 26)
        .background((tone == .clear ? DG.ink : tone.color).opacity(tone == .clear ? 0.06 : 0.12), in: Capsule())
    }
}

/// The colored disc that carries a kind's icon.
struct DGDisc: View {
    var kind: DGKind?
    var systemImage: String?
    var tone: DGTone
    var size: CGFloat = 44
    var ghost = false

    var body: some View {
        let c = tone.color
        DGIconView(name: systemImage ?? kind.map(DGIcon.name) ?? "hazard", size: size * 0.5, stroke: 2.2)
            .foregroundStyle(ghost ? DG.faint : .white)
            .frame(width: size, height: size)
            .background {
                if ghost {
                    // The mockups' ghost disc: a pale gray well, for what is over.
                    Circle().fill(DG.ink.opacity(0.05)).overlay(Circle().strokeBorder(DG.hair, lineWidth: 1))
                } else {
                    Circle().fill(LinearGradient(colors: [c.mix(.white, 0.12), c], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear],
                                                                      startPoint: .top, endPoint: .center), lineWidth: 1))
                        .shadow(color: c.opacity(0.4), radius: 6, y: 3)
                }
            }
    }
}

extension Color {
    /// This color with a share of another mixed in.
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(.sRGB, red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t), opacity: Double(a1 + (a2 - a1) * t))
    }
}

// MARK: - Icons

/// Each kind's icon and the app messages' icons, by their names in the
/// design's set (DGIcons). Views that take a `systemImage` draw these.
enum DGIcon {
    /// The set's name for a kind's icon.
    static func name(_ k: DGKind) -> String {
        k == .jam ? "traffic" : k.rawValue
    }

    /// Kept for callers that still ask by the old name; the same as `name`.
    static func symbol(_ k: DGKind) -> String { name(k) }

    /// The system messages' icons.
    static let reroute = "reroute"
    static let confirm = "confirm"
    static let speed = "speed"
    static let gps = "gps"
    static let offline = "offline"
    static let watch = "watch"
    static let arrive = "arrive"
    static let check = "check"
}

// MARK: - 2D and 3D

/// The 2D / 3D pill on the map: one control, both states shown, the
/// current one lit. A tap switches; its label names what a tap does.
struct DGModesPill: View {
    var is3D: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                seg("3D", on: is3D)
                seg("2D", on: !is3D)
            }
            .padding(3)
            .dgGlass(radius: 25)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(is3D ? "2D" : "3D")
        .accessibilityIdentifier("perspective")
    }

    private func seg(_ t: String, on: Bool) -> some View {
        Text(t).font(DG.font(14, .bold))
            .foregroundStyle(on ? DGTone.low.ink : DG.sub)
            .frame(width: 42, height: 44)
            .background(on ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: on ? .black.opacity(0.1) : .clear, radius: 3, y: 1)
            .animation(DG.snap, value: on)
    }
}

/// The big blue Report button.
struct DGReportButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            DGIconView(name: "report", size: 24, stroke: 2.2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(LinearGradient(colors: [DG.hex(0x4a8ff8), DG.hex(0x2f7cf6)],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: DG.path.opacity(0.45), radius: 10, y: 6)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel("Report")
    }
}
