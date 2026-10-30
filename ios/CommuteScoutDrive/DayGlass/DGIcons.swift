import SwiftUI

// The design's one icon set (the mockups' shared/icons.js, the same table
// Android draws): every alert kind, every app message and the map's
// controls, on a 24-unit grid with round caps and joins. Circles and
// rectangles are written as paths.

enum DGIcons {
    static let paths: [String: [String]] = [
        "crash": ["M4 15l1.6-4.6A2 2 0 0 1 7.5 9h9a2 2 0 0 1 1.9 1.4L20 15v3a1 1 0 0 1-1 1h-1.5a1 1 0 0 1-1-1v-1h-9v1a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z", "M4 15h16", "M8 5l1.5 2M12 3.5V6M16 5l-1.5 2"],
        "closure": ["M4.5,9h15a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-15a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M7 9l-3 6M12 9l-3 6M17 9l-3 6M21 10.5l-1.5 4.5", "M6 15v5M18 15v5"],
        "hazard": ["M12 3.5l9 16H3z", "M12 10v4.5M12 17.2v.3"],
        "police": ["M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z", "M12 8.5l1.2 2.4 2.6.4-1.9 1.8.5 2.6-2.4-1.3-2.4 1.3.5-2.6-1.9-1.8 2.6-.4z"],
        "traffic": ["M4.5,11h4a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-4a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M15.5,11h4a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-4a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M5 17v2M8 17v2M16 17v2M19 17v2M10 14h4", "M6.5 7.5h11"],
        "chain": ["M5.5,9h2a3,3 0 0 1 3,3v0a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v0a3,3 0 0 1 3,-3z", "M16.5,9h2a3,3 0 0 1 3,3v0a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v0a3,3 0 0 1 3,-3z", "M8.5 12h7"],
        "fire": ["M12 21c4 0 7-2.7 7-6.6 0-3.4-2.3-5.4-3.6-7.4-.5 1.6-1.4 2.6-2.4 3C13 7 11.5 4.5 9.5 3c.2 3-1.8 4.8-3.2 6.6A7.6 7.6 0 0 0 5 14.4C5 18.3 8 21 12 21z", "M12 21c-1.7 0-3-1.2-3-2.9 0-1.9 1.6-2.7 2.3-4.1.9 1.1 3.7 2.2 3.7 4.1 0 1.7-1.3 2.9-3 2.9z"],
        "ice": ["M12 2.5v19M3.8 7.2l16.4 9.6M3.8 16.8l16.4-9.6", "M9.5 3.8L12 6l2.5-2.2M9.5 20.2L12 18l2.5 2.2"],
        "sign": ["M4,4h16a1.5,1.5 0 0 1 1.5,1.5v8a1.5,1.5 0 0 1 -1.5,1.5h-16a1.5,1.5 0 0 1 -1.5,-1.5v-8a1.5,1.5 0 0 1 1.5,-1.5z", "M6 8h6M6 11h9M12 15v5M8.5 20h7"],
        "camera": ["M5,7h9a2,2 0 0 1 2,2v5a2,2 0 0 1 -2,2h-9a2,2 0 0 1 -2,-2v-5a2,2 0 0 1 2,-2z", "M16 10l5-2.5v8L16 13", "M7.2,11.5a2.3,2.3 0 1,0 4.6,0a2.3,2.3 0 1,0 -4.6,0z"],
        "toll": ["M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M14.6 8.8c-.5-.8-1.5-1.3-2.6-1.3-1.5 0-2.7.8-2.7 2.1 0 2.8 5.6 1.6 5.6 4.5 0 1.3-1.2 2.3-2.9 2.3-1.2 0-2.3-.5-2.8-1.4M12 6v1.5M12 16.5V18"],
        "reroute": ["M6 21V11a4 4 0 0 1 4-4h9", "M15.5 3.5L19 7l-3.5 3.5", "M6 21v-3"],
        "confirm": ["M7 11v9H4.5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z", "M7 11l3.6-7c1.5 0 2.4 1.2 2 2.7L12 10h6a2 2 0 0 1 2 2.3l-1.1 6.3A2 2 0 0 1 16.9 20H7"],
        "speed": ["M4 17a8 8 0 1 1 16 0", "M12 17l4.5-5.5", "M10.7,17a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z"],
        "gps": ["M5.5,12a6.5,6.5 0 1,0 13,0a6.5,6.5 0 1,0 -13,0z", "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M4 4l16 16"],
        "offline": ["M2.5 9a14 14 0 0 1 5-3M21.5 9a14 14 0 0 0-8.3-3.9M5.5 12.5a9.5 9.5 0 0 1 3.4-2.1M18.5 12.5a9.4 9.4 0 0 0-2.3-1.6M9 16a4.5 4.5 0 0 1 4.6-1", "M11.2,19.5a0.8,0.8 0 1,0 1.6,0a0.8,0.8 0 1,0 -1.6,0z", "M3 3l18 18"],
        "watch": ["M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M7.5,12a4.5,4.5 0 1,0 9,0a4.5,4.5 0 1,0 -9,0z", "M11,12a1,1 0 1,0 2,0a1,1 0 1,0 -2,0z"],
        "arrive": ["M5 21V4M5 4h11l-2 4 2 4H5"],
        "home": ["M4 11l8-6.5 8 6.5V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z"],
        "work": ["M5,7.5h14a2,2 0 0 1 2,2v8a2,2 0 0 1 -2,2h-14a2,2 0 0 1 -2,-2v-8a2,2 0 0 1 2,-2z", "M9 7.5V5.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5.5v2M3 12.5h18"],
        "recent": ["M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M12 7.5V12l3 2"],
        "search": ["M4,10.5a6.5,6.5 0 1,0 13,0a6.5,6.5 0 1,0 -13,0z", "M15.5 15.5L21 21"],
        "layers": ["M12 3l9 5-9 5-9-5z", "M3 13l9 5 9-5"],
        "locate": ["M3 11l18-8-8 18-2-8z"],
        "report": ["M4 20V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H8z", "M12 7.5v4M12 13.6v.2"],
        "close": ["M6 6l12 12M18 6L6 18"],
        "chevron": ["M6 9l6 6 6-6"],
        "up": ["M6 15l6-6 6 6"],
        "right": ["M6 20V12a3 3 0 0 1 3-3h9", "M14 5l4 4-4 4"],
        "straight": ["M12 21V4M7 9l5-5 5 5"],
        "left": ["M18 20V12a3 3 0 0 0-3-3H6", "M10 5L6 9l4 4"],
        "mute": ["M4 9.5h3.5L12 5v14l-4.5-4.5H4z", "M16 9.5c1 .8 1.5 1.6 1.5 2.5s-.5 1.7-1.5 2.5M18.5 7c1.8 1.4 2.7 3.1 2.7 5s-.9 3.6-2.7 5"],
        "share": ["M12 15V3.5M7.5 8L12 3.5 16.5 8", "M5 12v7a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-7"],
        "nav": ["M12 2.5l8.5 18.5-8.5-4.5-8.5 4.5z"],
        "thumb": ["M7 11v9H4.5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z", "M7 11l3.6-7c1.5 0 2.4 1.2 2 2.7L12 10h6a2 2 0 0 1 2 2.3l-1.1 6.3A2 2 0 0 1 16.9 20H7"],
        "gone": ["M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M8.5 8.5l7 7"],
        "check": ["M5 12.5l4.5 4.5L19 7.5"],
        "plus": ["M12 5v14M5 12h14"],
        "minus": ["M5 12h14"],
        "gear": ["M9,12a3,3 0 1,0 6,0a3,3 0 1,0 -6,0z", "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"],
    ]

    /// Every icon's name.
    static var names: [String] { paths.keys.sorted() }

    /// The SF Symbols the chrome used before the set was ported, so a
    /// caller that still passes one gets the drawn icon instead.
    static let fromSymbol: [String: String] = [
        "car.fill": "crash", "xmark.octagon.fill": "closure", "exclamationmark.triangle.fill": "hazard",
        "shield.lefthalf.filled": "police", "car.2.fill": "traffic", "link": "chain", "flame.fill": "fire",
        "snowflake": "ice", "text.alignleft": "sign", "camera.fill": "camera", "dollarsign.circle.fill": "toll",
        "arrow.triangle.branch": "reroute", "questionmark.bubble.fill": "confirm", "speedometer": "speed",
        "location.slash.fill": "gps", "wifi.slash": "offline", "eye.fill": "watch", "flag.checkered": "arrive",
        "checkmark": "check", "house.fill": "home", "briefcase.fill": "work", "clock": "recent",
        "magnifyingglass": "search", "xmark": "close", "location.fill": "locate", "plus.bubble.fill": "report",
        "square.3.layers.3d": "layers", "gearshape.fill": "gear", "square.and.arrow.up": "share",
        "arrow.turn.up.right": "right", "arrow.turn.up.left": "left", "arrow.up": "straight",
    ]

    /// The icon a name means: one of the set's own names, or a symbol
    /// the set replaces. Nil for anything else.
    static func resolve(_ name: String) -> String? {
        paths[name] != nil ? name : fromSymbol[name]
    }

    private static var cache: [String: Path] = [:]

    /// The icon's strokes on the 24-unit grid.
    static func unitPath(_ name: String) -> Path {
        let key = resolve(name) ?? "hazard"
        if let p = cache[key] { return p }
        var all = Path()
        for d in paths[key] ?? [] { all.addPath(SVGPath.parse(d)) }
        cache[key] = all
        return all
    }

    /// The icon scaled into the square centered in `rect`.
    static func path(_ name: String, in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        return unitPath(name).applying(CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                                         tx: rect.midX - 12 * s, ty: rect.midY - 12 * s))
    }

    /// Strokes the icon onto a canvas. `stroke` is in grid units, as in the mockups.
    static func draw(_ name: String, in ctx: inout GraphicsContext, rect: CGRect, color: Color, stroke: Double = 2) {
        let s = min(rect.width, rect.height) / 24
        ctx.stroke(path(name, in: rect), with: .color(color),
                   style: StrokeStyle(lineWidth: stroke * s, lineCap: .round, lineJoin: .round))
    }
}

/// One icon from the set as a shape, on its 24-unit grid.
struct DGIconShape: Shape {
    var name: String
    func path(in rect: CGRect) -> Path { DGIcons.path(name, in: rect) }
}

/// One icon from the set, stroked in the current color. A name the set
/// does not have falls back to the SF Symbol of that name.
struct DGIconView: View {
    var name: String
    var size: CGFloat = 24
    var stroke: CGFloat = 2
    var filled = false

    var body: some View {
        if DGIcons.resolve(name) != nil {
            ZStack {
                if filled { DGIconShape(name: name).fill() }
                DGIconShape(name: name)
                    .stroke(style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: size * 0.8, weight: .semibold))
                .frame(width: size, height: size)
        }
    }
}

/// SVG path data to a SwiftUI Path: every command, relative and
/// absolute, with arcs turned into curves.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var p = Path()
        let chars = Array(d.utf8)
        var i = 0
        var cmd: UInt8 = 0
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        var lastWasCubic = false, lastWasQuad = false

        func skip() { while i < chars.count, chars[i] == 32 || chars[i] == 44 || chars[i] == 10 || chars[i] == 9 { i += 1 } }
        func isNumStart(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 }
        func num() -> CGFloat {
            skip()
            let s = i
            if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
            var dot = false
            while i < chars.count {
                let c = chars[i]
                if c >= 48 && c <= 57 { i += 1 } else if c == 46 && !dot { dot = true; i += 1 } else { break }
            }
            if i < chars.count, chars[i] == 101 || chars[i] == 69 {
                i += 1
                if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
                while i < chars.count, chars[i] >= 48 && chars[i] <= 57 { i += 1 }
            }
            return CGFloat(Double(String(decoding: chars[s ..< i], as: UTF8.self)) ?? 0)
        }
        func flag() -> Bool {
            skip()
            guard i < chars.count else { return false }
            let c = chars[i]; i += 1
            return c == 49
        }
        func pt(_ base: CGPoint) -> CGPoint { let x = num(); let y = num(); return CGPoint(x: base.x + x, y: base.y + y) }
        func mirror() -> CGPoint { CGPoint(x: 2 * cur.x - (lastCtrl?.x ?? cur.x), y: 2 * cur.y - (lastCtrl?.y ?? cur.y)) }

        while true {
            skip()
            guard i < chars.count else { break }
            let c = chars[i]
            if !isNumStart(c) { cmd = c; i += 1 } else if cmd == 0 { break }
            let rel = cmd >= 97
            let base = rel ? cur : .zero
            var cubic = false, quad = false
            switch cmd | 0x20 {
            case 109: // m: later pairs are line-tos
                let q = pt(base)
                p.move(to: q); cur = q; start = q
                cmd = rel ? 108 : 76
            case 108: // l
                let q = pt(base); p.addLine(to: q); cur = q
            case 104: // h
                let x = num(); cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); p.addLine(to: cur)
            case 118: // v
                let y = num(); cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); p.addLine(to: cur)
            case 99: // c
                let c1 = pt(base), c2 = pt(base), q = pt(base)
                p.addCurve(to: q, control1: c1, control2: c2); lastCtrl = c2; cur = q; cubic = true
            case 115: // s
                let c1 = lastWasCubic ? mirror() : cur
                let c2 = pt(base), q = pt(base)
                p.addCurve(to: q, control1: c1, control2: c2); lastCtrl = c2; cur = q; cubic = true
            case 113: // q
                let c1 = pt(base), q = pt(base)
                p.addQuadCurve(to: q, control: c1); lastCtrl = c1; cur = q; quad = true
            case 116: // t
                let c1 = lastWasQuad ? mirror() : cur
                let q = pt(base)
                p.addQuadCurve(to: q, control: c1); lastCtrl = c1; cur = q; quad = true
            case 97: // a
                let rx = num(), ry = num(), rot = num()
                let large = flag(), sweep = flag()
                let q = pt(base)
                arc(&p, from: cur, to: q, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = q
            case 122: // z
                p.closeSubpath(); cur = start
            default:
                return p
            }
            lastWasCubic = cubic; lastWasQuad = quad
        }
        return p
    }

    /// An SVG elliptical arc as cubic curves (SVG 1.1, appendix F.6).
    static func arc(_ p: inout Path, from a: CGPoint, to b: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                    rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, a != b else { p.addLine(to: b); return }
        let phi = rotation * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { let s = sqrt(lam); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = sqrt(max(0, num / den))
        if large == sweep { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = cp * cx1 - sp * cy1 + (a.x + b.x) / 2, cy = sp * cx1 + cp * cy1 + (a.y + b.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let s: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let d = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
            return s * acos(max(-1, min(1, d)))
        }
        let t1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var dt = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, dt > 0 { dt -= 2 * .pi } else if sweep, dt < 0 { dt += 2 * .pi }
        let segs = max(1, Int(ceil(abs(dt) / (.pi / 2) - 1e-9)))
        let step = dt / CGFloat(segs)
        let alpha = 4 / 3 * tan(step / 4)
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cp - ry * sin(t) * sp, y: cy + rx * cos(t) * sp + ry * sin(t) * cp)
        }
        func deriv(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cp - ry * cos(t) * sp, y: -rx * sin(t) * sp + ry * cos(t) * cp)
        }
        var t = t1
        for n in 0 ..< segs {
            let t2 = t + step
            let p1 = point(t), p2 = n == segs - 1 ? b : point(t2)
            let d1 = deriv(t), d2 = deriv(t2)
            p.addCurve(to: p2, control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                       control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y))
            t = t2
        }
    }
}
