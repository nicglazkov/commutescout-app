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

    static let ink = hex(0x0e1726)
    static let sub = hex(0x586377)
    static let faint = hex(0x8a94a6)
    static let hair = hex(0x0e1726, 0.08)
    static let background = hex(0xf4f6f9)
    static let path = hex(0x2f7cf6)
    static let laneFill = hex(0xdfe5ec)

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

    /// The darker ink for text on a tone's tint.
    static func inkColor(_ t: DGTone) -> Color {
        switch t {
        case .high: return hex(0xb4232b)
        case .mid: return hex(0xa05a00)
        case .low: return hex(0x1f5fcf)
        case .good: return hex(0x0d7a42)
        case .clear: return sub
        }
    }

    /// The pale wash behind a closed lane or a tinted chip.
    static func wash(_ t: DGTone) -> Color {
        switch t {
        case .high: return hex(0xfde6e6)
        case .mid: return hex(0xfdf0dc)
        case .low: return hex(0xe4eefe)
        case .good: return hex(0xe1f4e9)
        case .clear: return hex(0xeef1f5)
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
