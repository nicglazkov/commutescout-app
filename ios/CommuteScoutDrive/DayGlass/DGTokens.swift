import SwiftUI
import UIKit

/// Day Glass+: the app's look. Colors, type, radii and motion in one
/// place; every surface reads from here.
enum DG {
    // MARK: color

    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255, opacity: a)
    }

    private static func ui(_ v: UInt32, _ a: Double) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }

    /// A color with a day value and a night value. It follows the color
    /// scheme the root view sets from the theme setting.
    static func dyn(_ day: UInt32, _ night: UInt32, _ dayAlpha: Double = 1, _ nightAlpha: Double? = nil) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? ui(night, nightAlpha ?? dayAlpha) : ui(day, dayAlpha) })
    }

    static let ink = dyn(0x0e1726, 0xf1f4f9)
    static let sub = dyn(0x586377, 0xa9b4c6)
    static let faint = dyn(0x8a94a6, 0x7c8799)
    static let hair = dyn(0x0e1726, 0xffffff, 0.08, 0.12)
    static let background = dyn(0xf4f6f9, 0x0b1320)
    static let path = hex(0x2f7cf6)
    static let laneFill = dyn(0xdfe5ec, 0x2a3546)
    /// Lane lines and the road's edge on a lane drawing.
    static let laneLine = dyn(0xffffff, 0x5b677a)
    /// A solid card or sheet: white by day.
    static let surface = dyn(0xffffff, 0x18212f)
    /// The top of a page's own gradient.
    static let sheetTop = dyn(0xf7f9fc, 0x101a28)
    /// A chip lifted off its track: the picked segment.
    static let raised = dyn(0xffffff, 0x34425a)
    /// A solid dark button or tile that carries white words.
    static let solid = dyn(0x0e1726, 0x2d3a50)
    /// Words on a pale blue note.
    static let noteInk = dyn(0x23406f, 0xc3d6f7)
    /// A translucent card: white at `alpha` by day, a raised navy at night.
    static func glass(_ alpha: Double) -> Color { dyn(0xffffff, 0x1e2838, alpha) }
    /// A drop shadow; black at night, where an ink shadow would glow.
    static func shadow(_ alpha: Double) -> Color { dyn(0x0e1726, 0x000000, alpha, min(0.7, alpha * 2)) }

    /// The color a tone paints with: fills, rings, icons.
    static func color(_ t: DGTone) -> Color {
        switch t {
        case .high: return hex(0xe5484d)
        case .mid: return hex(0xee8b0c)
        case .low: return hex(0x2f7cf6)
        case .good: return hex(0x14a35a)
        case .clear: return hex(0x8a94a6)
        }
    }

    /// The ink for text on a tone's tint: darker by day, lighter at night.
    static func inkColor(_ t: DGTone) -> Color {
        switch t {
        case .high: return dyn(0xb4232b, 0xff9396)
        case .mid: return dyn(0xa05a00, 0xffb85c)
        case .low: return dyn(0x1f5fcf, 0x8ab4f8)
        case .good: return dyn(0x0d7a42, 0x5fd597)
        case .clear: return sub
        }
    }

    /// The pale wash behind a closed lane or a tinted chip.
    static func wash(_ t: DGTone) -> Color {
        switch t {
        case .high: return dyn(0xfde6e6, 0x3d2630)
        case .mid: return dyn(0xfdf0dc, 0x3e2f24)
        case .low: return dyn(0xe4eefe, 0x1f3254)
        case .good: return dyn(0xe1f4e9, 0x1a3a37)
        case .clear: return dyn(0xeef1f5, 0x26303f)
        }
    }

    // MARK: radius

    enum R {
        static let cap: CGFloat = 28
        static let card: CGFloat = 28
        static let sheet: CGFloat = 30
        static let trip: CGFloat = 30
        static let box: CGFloat = 18
        static let facts: CGFloat = 16
        static let thumb: CGFloat = 16
        static let button: CGFloat = 24
        static let lanes: CGFloat = 10
    }

    // MARK: motion

    /// The mockup's springs, as SwiftUI springs.
    static let spring = Animation.interpolatingSpring(stiffness: 230, damping: 20)
    static let springSoft = Animation.interpolatingSpring(stiffness: 210, damping: 25)
    static let snap = Animation.interpolatingSpring(stiffness: 220, damping: 24)
    static let slide = Animation.interpolatingSpring(stiffness: 170, damping: 22)
    static let easeOut = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
    static let tilt = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 1.1)
    static let hide = Animation.timingCurve(0.55, 0, 0.25, 1, duration: 0.56)
    static let tint = Animation.easeInOut(duration: 0.6)

    // MARK: type

    /// Onest at a weight. The bundled font is variable, so the weight is
    /// set on the axis; the system font stands in if it failed to load.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font(uiFont(size, weight))
    }

    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        let w = axis(weight)
        let key = "\(size)-\(w)"
        if let f = cache[key] { return f }
        let f: UIFont
        if let base = UIFont(name: "Onest-Regular", size: size) ?? UIFont(name: "Onest", size: size) {
            let wght = 0x7767_6874   // 'wght'
            let d = base.fontDescriptor.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: w],
            ])
            f = UIFont(descriptor: d, size: size)
        } else {
            f = .systemFont(ofSize: size, weight: uiWeight(weight))
        }
        cache[key] = f
        return f
    }

    private static var cache: [String: UIFont] = [:]

    private static func axis(_ w: Font.Weight) -> Double {
        switch w {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        default: return .regular
        }
    }

    /// The type scale, named for where each size is used.
    enum T {
        static let maneuverDistance = DG.font(34, .bold)
        static let maneuverUnit = DG.font(18, .semibold)
        static let road = DG.font(18, .semibold)
        static let then = DG.font(14, .medium)
        static let alertTitle = DG.font(19, .bold)
        static let alertBody = DG.font(14.5, .medium)
        static let alertDistance = DG.font(25, .bold)
        static let alertEta = DG.font(13, .medium)
        static let moreTitle = DG.font(22, .bold)
        static let moreDistance = DG.font(28, .bold)
        static let sheetTitle = DG.font(24, .bold)
        static let lede = DG.font(16.5, .regular)
        static let noteTitle = DG.font(16, .semibold)
        static let noteBody = DG.font(13.5, .medium)
        static let rowTitle = DG.font(15.5, .semibold)
        static let rowSub = DG.font(12.5, .medium)
        static let facts = DG.font(14.5, .regular)
        static let button = DG.font(16, .semibold)
        static let chip = DG.font(13, .semibold)
        static let listTitle = DG.font(28, .bold)
        static let section = DG.font(14, .semibold)
        static let eta = DG.font(26, .bold)
        static let meta = DG.font(14, .medium)
        static let mono = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    }
}

extension DGTone {
    var color: Color { DG.color(self) }
    var ink: Color { DG.inkColor(self) }
    var wash: Color { DG.wash(self) }
}
