import SwiftUI

// The icons the "more" pages add to the design's set (28-more.html), on
// the same 24-unit grid with round caps and joins. Anything not here is
// drawn from DGIcons.

enum MoreIcons {
    static let paths: [String: [String]] = [
        "back": ["M15 5l-7 7 7 7"],
        "next": ["M9 5l7 7-7 7"],
        "bolt": ["M13.5 2.5L5.5 13.5h6l-1 8 8-11h-6z"],
        "people": ["M5.8,8a3.2,3.2 0 1,0 6.4,0a3.2,3.2 0 1,0 -6.4,0z", "M3 20a6 6 0 0 1 12 0", "M14.5,9a2.5,2.5 0 1,0 5,0a2.5,2.5 0 1,0 -5,0z", "M16.2 14.2a5 5 0 0 1 5.3 5"],
        "light": ["M11,2.5h2a3,3 0 0 1 3,3v10a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v-10a3,3 0 0 1 3,-3z", "M10.7,6.6a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M10.7,10.5a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M10.7,14.4a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M12 18.5V22"],
        "lock": ["M7.5,10.5h9a2.5,2.5 0 0 1 2.5,2.5v5a2.5,2.5 0 0 1 -2.5,2.5h-9a2.5,2.5 0 0 1 -2.5,-2.5v-5a2.5,2.5 0 0 1 2.5,-2.5z", "M8 10.5V8a4 4 0 0 1 8 0v2.5"],
        "route": ["M3.8,18a2.2,2.2 0 1,0 4.4,0a2.2,2.2 0 1,0 -4.4,0z", "M15.8,6a2.2,2.2 0 1,0 4.4,0a2.2,2.2 0 1,0 -4.4,0z", "M8.2 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h6.8"],
        "bell": ["M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z", "M10 21.2h4"],
        "wifi": ["M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M9 16a4.5 4.5 0 0 1 6 0", "M11.1,19.5a0.9,0.9 0 1,0 1.8,0a0.9,0.9 0 1,0 -1.8,0z"],
        "download": ["M12 4v11M7.5 10.5L12 15l4.5-4.5", "M5 19.5h14"],
        "trash": ["M4.5 6.5h15M9.5 6.5v-2h5v2M6.5 6.5l1 13a1.5 1.5 0 0 0 1.5 1.4h6a1.5 1.5 0 0 0 1.5-1.4l1-13", "M10 10.5v6.5M14 10.5v6.5"],
        "refresh": ["M19.5 12a7.5 7.5 0 1 1-2.2-5.3", "M19.6 4v4.6H15"],
        "map": ["M3 6.5l6-2.5 6 2.5 6-2.5v13.5l-6 2.5-6-2.5-6 2.5z", "M9 4v13.5M15 6.5V20"],
        "store": ["M4 9.5L5.5 4h13L20 9.5", "M4 9.5a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0", "M5.5 12.5V20h13v-7.5"],
        "shield": ["M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z", "M8.8 12l2.2 2.2 4.2-4.4"],
        "piece": ["M10 4.5a2 2 0 0 1 4 0V6h3.5a1 1 0 0 1 1 1v3.5H17a2 2 0 0 0 0 4h1.5V18a1 1 0 0 1-1 1H14v-1.5a2 2 0 0 0-4 0V19H6.5a1 1 0 0 1-1-1v-3.5H7a2 2 0 0 0 0-4H5.5V7a1 1 0 0 1 1-1H10z"],
        "eye": ["M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z", "M9.2,12a2.8,2.8 0 1,0 5.6,0a2.8,2.8 0 1,0 -5.6,0z"],
        "nope": ["M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M6 6l12 12"],
        "phone": ["M9,2.5h6a2.5,2.5 0 0 1 2.5,2.5v14a2.5,2.5 0 0 1 -2.5,2.5h-6a2.5,2.5 0 0 1 -2.5,-2.5v-14a2.5,2.5 0 0 1 2.5,-2.5z", "M10.5 18.5h3"],
    ]

    private static var cache: [String: Path] = [:]

    static func unitPath(_ name: String) -> Path? {
        if let p = cache[name] { return p }
        guard let list = paths[name] else { return nil }
        var all = Path()
        for d in list { all.addPath(SVGPath.parse(d)) }
        cache[name] = all
        return all
    }
}

private struct MoreIconShape: Shape {
    var name: String
    func path(in rect: CGRect) -> Path {
        guard let p = MoreIcons.unitPath(name) else { return DGIcons.path(name, in: rect) }
        let s = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: rect.midX - 12 * s, ty: rect.midY - 12 * s))
    }
}

/// One icon from the "more" pages' set or the design's set, stroked in
/// the current color.
struct DGMoreIcon: View {
    var name: String
    var size: CGFloat = 24
    var stroke: CGFloat = 2

    var body: some View {
        if MoreIcons.paths[name] != nil || DGIcons.resolve(name) != nil {
            MoreIconShape(name: name)
                .stroke(style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: size * 0.8, weight: .semibold)).frame(width: size, height: size)
        }
    }
}

/// The mockups' tags: official data (a shield, green), plugin data (a
/// piece, indigo), and plain gray ones.
struct DataTag: View {
    enum Style { case official, plugin, good, plain }
    var text: String
    var style: Style
    var icon: String?

    static func of(trust: String?) -> DataTag {
        Market.data(trust: trust) == .official
            ? DataTag(text: "Official data", style: .official, icon: "shield")
            : DataTag(text: "Plugin data", style: .plugin, icon: "piece")
    }

    static let pluginInk = DG.hex(0x4a4f9e)
    static let pluginWash = DG.hex(0x5b5bd6)

    var body: some View {
        HStack(spacing: 5) {
            if let icon { DGMoreIcon(name: icon, size: 14, stroke: icon == "check" ? 2.6 : 2.2) }
            Text(text).font(DG.font(12.5, .semibold)).lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.leading, icon == nil ? 10 : 8).padding(.trailing, 10).frame(height: 26)
        .background(wash, in: Capsule())
        .fixedSize()
    }

    private var ink: Color {
        switch style {
        case .official, .good: return DGTone.good.ink
        case .plugin: return Self.pluginInk
        case .plain: return DG.sub
        }
    }

    private var wash: Color {
        switch style {
        case .official, .good: return DGTone.good.color.opacity(0.09)
        case .plugin: return Self.pluginWash.opacity(0.09)
        case .plain: return DG.ink.opacity(0.05)
        }
    }
}
