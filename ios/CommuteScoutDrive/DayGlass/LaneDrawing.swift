import SwiftUI

/// The road drawn in perspective: lanes, what blocks them, and the blue
/// path to take. `u` runs across the lanes (0 to n), `v` along the road
/// (0 is where you are, 1 the far end). The same drawing makes the
/// alert's thumbnail and the large picture in "see more".
struct RoadSpec {
    struct Block { var lanes: ClosedRange<Int>; var from: Double; var to: Double; var taper = 0.0; var leftSide = false; var tone: DGTone = .high; var ghost = false }
    struct Mark { var u: Double; var v: Double; var icon: String; var tone: DGTone; var r: Double = 11 }
    struct PathSpec { var from: Double; var to: Double; var m0 = 0.25; var m1 = 0.55; var v0 = 0.07; var v1 = 0.86 }
    struct Tick { var v: Double; var text: String; var strong = false }

    var n = 4
    var k = 0.56
    var sh = 0.32
    var padT = 4.0, padB = 6.0, padL = 8.0, padR = 8.0
    var scale = 1.0
    var pathWidth = 4.0
    var surface = Color.white
    var lanesFill = DG.laneFill
    var tint: [(lane: Int, tone: DGTone)] = []
    var frost: [(Double, Double)] = []
    var cars: [(Int, Double)] = []
    var blocks: [Block] = []
    var across: [(v: Double, tone: DGTone)] = []
    var path: PathSpec?
    var marks: [Mark] = []
    var you: Double?
    var ticks: [Tick] = []
}

extension RoadSpec {
    /// What a kind draws when the lanes are not known.
    static func kind(_ k: DGKind) -> RoadSpec {
        var s = RoadSpec()
        switch k {
        case .crash:
            s.blocks = [Block(lanes: 3 ... 3, from: 0.5, to: 0.8)]
            s.marks = [Mark(u: 3.5, v: 0.65, icon: DGIcon.name(.crash), tone: .high)]
            s.you = 3; s.path = PathSpec(from: 3, to: 2, m0: 0.18, m1: 0.5)
        case .closure:
            s.blocks = [Block(lanes: 2 ... 3, from: 0.55, to: 1.05, taper: 0.16)]
            s.marks = [Mark(u: 3, v: 0.76, icon: DGIcon.name(.closure), tone: .high)]
            s.you = 3; s.path = PathSpec(from: 3, to: 1, m0: 0.12, m1: 0.42)
        case .hazard:
            s.marks = [Mark(u: 0.5, v: 0.66, icon: DGIcon.name(.hazard), tone: .mid)]
            s.blocks = [Block(lanes: 0 ... 0, from: 0.6, to: 0.72, tone: .mid)]
            s.you = 0; s.path = PathSpec(from: 0, to: 1, m0: 0.16, m1: 0.48)
        case .police:
            s.sh = 0.7
            s.marks = [Mark(u: 4.35, v: 0.66, icon: DGIcon.name(.police), tone: .low)]
            s.you = 3; s.path = PathSpec(from: 3, to: 2, m0: 0.2, m1: 0.5)
        case .jam:
            s.cars = [(0, 0.5), (0, 0.7), (1, 0.44), (1, 0.64), (1, 0.84), (2, 0.52), (2, 0.72), (3, 0.46), (3, 0.66), (3, 0.86)]
            s.you = 2; s.path = PathSpec(from: 2, to: 2, v1: 0.36)
        case .chain:
            s.across = [(0.6, .high)]
            s.marks = [Mark(u: 2, v: 0.76, icon: DGIcon.name(.chain), tone: .high)]
            s.surface = DG.hex(0xf4f7fa); s.you = 2; s.path = PathSpec(from: 2, to: 2, v1: 0.5)
        case .ice:
            s.frost = [(0.45, 1)]
            s.marks = [Mark(u: 2, v: 0.7, icon: DGIcon.name(.ice), tone: .mid)]
            s.you = 1; s.path = PathSpec(from: 1, to: 1)
        case .camera:
            s.sh = 0.7
            s.marks = [Mark(u: 4.35, v: 0.62, icon: DGIcon.name(.camera), tone: .low)]
            s.you = 2; s.path = PathSpec(from: 2, to: 2)
        case .toll:
            s.tint = [(0, .low)]
            s.marks = [Mark(u: 0.5, v: 0.66, icon: DGIcon.name(.toll), tone: .low)]
            s.you = 1; s.path = PathSpec(from: 1, to: 1)
        case .fire, .sign:
            break   // drawn as a map and a board, not lanes
        }
        return s
    }

    /// The drawing for known lanes: the closed ones hatched, the path
    /// from the lane you are in to the one to take.
    static func plan(_ p: LanePlan, kind: DGKind) -> RoadSpec {
        var s = RoadSpec()
        s.n = p.count
        let tone = kind.tone == .high ? DGTone.high : kind.tone
        s.tint = p.tinted.map { ($0, DGTone.low) }
        // Closed lanes that touch each other draw as one block.
        var runs: [ClosedRange<Int>] = []
        for l in p.closed.sorted() {
            if let last = runs.last, last.upperBound + 1 == l { runs[runs.count - 1] = last.lowerBound ... l } else { runs.append(l ... l) }
        }
        s.blocks = runs.map { Block(lanes: $0, from: 0.5, to: 0.82, tone: tone) }
        if let run = runs.first {
            s.marks = [Mark(u: Double(run.lowerBound + run.upperBound + 1) / 2, v: 0.65, icon: DGIcon.name(kind), tone: tone)]
        } else {
            s.marks = [Mark(u: p.shoulderLeft ? -0.16 : Double(p.count) + 0.16, v: 0.65, icon: DGIcon.name(kind), tone: tone)]
        }
        s.you = Double(p.from)
        s.path = PathSpec(from: Double(p.from), to: Double(p.to), m0: 0.18, m1: 0.5)
        return s
    }

    /// The same road, cleared: green lanes, the block a dashed ghost.
    func cleared() -> RoadSpec {
        var s = self
        s.lanesFill = DG.hex(0xdcefe3)
        s.blocks = blocks.map { var b = $0; b.ghost = true; b.taper = 0; return b }
        s.marks = marks.map { var m = $0; m.icon = DGIcon.check; m.tone = .good; return m }
        s.cars = []; s.across = []; s.frost = []
        if let y = you { s.path = PathSpec(from: y, to: y) }
        return s
    }

    /// The small drawings: a smaller mark, moved to the far end of the
    /// block it stands on and the block reaching nearer, so the closed
    /// lane still shows beside the mark instead of under it.
    func small(r: Double) -> RoadSpec {
        var s = self
        s.marks = marks.map { m in
            var m = m
            m.r = r
            let under = blocks.first { b in !b.ghost && Double(b.lanes.lowerBound) <= m.u && m.u <= Double(b.lanes.upperBound + 1) && b.from <= m.v && m.v <= b.to }
            if let b = under { m.v = min(0.9, b.to + 0.06) }
            return m
        }
        s.blocks = blocks.map { b in
            var b = b
            if !b.ghost { b.from = max(0.3, b.from - 0.1) }
            return b
        }
        return s
    }

    /// Settings for the large drawing, with the event at `vc` along the
    /// road and distance ticks on the left.
    func large(vc: Double, near: String, half: String) -> RoadSpec {
        var s = self
        s.k = 0.74; s.sh = 0.3; s.padL = 58; s.padR = 22; s.padT = 12; s.padB = 18; s.pathWidth = 5; s.scale = 1.35
        let shift = vc - 0.65
        s.blocks = blocks.map { var b = $0; b.from += shift; b.to = min(1.05, b.to + shift); return b }
        s.marks = marks.map { var m = $0; m.v += shift; m.r = 12; return m }
        if var p = path { p.m0 = 0.1; p.m1 = max(0.2, vc - 0.2); p.v1 = 0.95; s.path = p }
        s.ticks = [Tick(v: 0.02, text: "You", strong: true), Tick(v: (0.02 + vc) / 2, text: half), Tick(v: vc, text: near, strong: true)]
        return s
    }
}

/// Draws a RoadSpec.
struct RoadCanvas: View {
    var spec: RoadSpec

    var body: some View {
        Canvas { ctx, size in RoadCanvas.draw(spec, in: &ctx, size: size) }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.13)],
                                 startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }

    static func draw(_ o: RoadSpec, in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, n = Double(o.n), k = o.k, sc = o.scale
        let c = (1 - k) * 1.15
        func g(_ v: Double) -> Double { v * (1 + c) / (1 + c * v) }
        let wb = w - o.padL - o.padR, ub = wb / (n + 2 * o.sh), cx = o.padL + wb / 2
        func sAt(_ v: Double) -> Double { 1 - (1 - k) * g(v) }
        func P(_ u: Double, _ v: Double) -> CGPoint { CGPoint(x: cx + (u - n / 2) * ub * sAt(v), y: h - o.padB - g(v) * (h - o.padT - o.padB)) }
        func quad(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) -> Path {
            Path { p in p.addLines([P(u0, v0), P(u1, v0), P(u1, v1), P(u0, v1)]); p.closeSubpath() }
        }
        func hatch(_ path: Path, _ t: DGTone) {
            ctx.fill(path, with: .color(t.wash))
            var sub = ctx
            sub.clip(to: path)
            let step = 6 * sc
            var stripes = Path()
            var x = -h
            while x < w + h { stripes.move(to: CGPoint(x: x, y: h)); stripes.addLine(to: CGPoint(x: x + h, y: 0)); x += step }
            sub.stroke(stripes, with: .color(t.color.opacity(0.75)), lineWidth: 2.2 * sc)
        }

        ctx.fill(quad(-o.sh, n + o.sh, 0, 1), with: .color(o.surface))
        ctx.fill(quad(0, n, 0, 1), with: .color(o.lanesFill))
        for t in o.tint { ctx.fill(quad(Double(t.lane), Double(t.lane + 1), 0, 1), with: .color(t.tone.wash)) }
        for f in o.frost { hatch(quad(0, n, f.0, f.1), .low) }
        for edge in [0.0, n] {
            ctx.stroke(Path { p in p.move(to: P(edge, 0)); p.addLine(to: P(edge, 1)) }, with: .color(.white), lineWidth: 1.8 * sc)
        }
        for i in 1 ..< max(1, o.n) {
            var dashes = Path()
            var v = 0.0
            while v < 1 { dashes.move(to: P(Double(i), v)); dashes.addLine(to: P(Double(i), min(1, v + 0.05))); v += 0.1 }
            ctx.stroke(dashes, with: .color(.white), style: StrokeStyle(lineWidth: 1.6 * sc, lineCap: .round))
        }
        for (l, v) in o.cars {
            let p = P(Double(l) + 0.5, v), s = sAt(v), cw = ub * s * 0.34, chh = ub * s * 0.5
            ctx.fill(Path(roundedRect: CGRect(x: p.x - cw / 2, y: p.y - chh / 2, width: cw, height: chh), cornerRadius: cw / 3),
                     with: .color(DGTone.mid.color.opacity(0.8)))
        }
        for b in o.blocks {
            let l0 = Double(b.lanes.lowerBound), l1 = Double(b.lanes.upperBound + 1), t = b.taper
            let pts: [CGPoint] = t > 0
                ? (b.leftSide ? [P(l1, b.from), P(l0, b.from - t), P(l0, b.to), P(l1, b.to)]
                    : [P(l0, b.from), P(l1, b.from - t), P(l1, b.to), P(l0, b.to)])
                : [P(l0, b.from), P(l1, b.from), P(l1, b.to), P(l0, b.to)]
            let path = Path { p in p.addLines(pts); p.closeSubpath() }
            if b.ghost {
                ctx.stroke(path, with: .color(DGTone.good.color.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.4 * sc, lineJoin: .round, dash: [3 * sc, 3 * sc]))
            } else {
                hatch(path, b.tone)
                ctx.stroke(path, with: .color(b.tone.color.opacity(0.55)), style: StrokeStyle(lineWidth: sc, lineJoin: .round))
            }
        }
        for a in o.across {
            ctx.stroke(Path { p in p.move(to: P(-o.sh, a.v)); p.addLine(to: P(n + o.sh, a.v)) },
                       with: .color(a.tone.color), style: StrokeStyle(lineWidth: 3 * sc, dash: [5 * sc, 3 * sc]))
        }
        if let ps = o.path {
            func sm(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x) }
            var pts: [CGPoint] = []
            var v = ps.v0
            while v <= ps.v1 + 1e-6 { pts.append(P(ps.from + 0.5 + (ps.to - ps.from) * sm((v - ps.m0) / (ps.m1 - ps.m0)), v)); v += 0.015 }
            let line = Path { p in p.addLines(pts) }
            let lw = o.pathWidth * sc
            ctx.stroke(line, with: .color(DG.path.opacity(0.14)), style: StrokeStyle(lineWidth: ub * k * 0.78, lineCap: .round, lineJoin: .round))
            ctx.stroke(line, with: .color(DG.path), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            if pts.count >= 3 {
                let e = pts[pts.count - 1], q = pts[pts.count - 3]
                let ang = Double(atan2(e.y - q.y, e.x - q.x)), hs = Double(lw) * 2.2
                let ca = Foundation.cos(ang), sa = Foundation.sin(ang)
                let cp = Foundation.cos(ang + .pi / 2), sp = Foundation.sin(ang + .pi / 2)
                let tip = CGPoint(x: Double(e.x) + ca * hs * 0.6, y: Double(e.y) + sa * hs * 0.6)
                let back = CGPoint(x: Double(tip.x) - ca * hs * 1.5, y: Double(tip.y) - sa * hs * 1.5)
                let l = CGPoint(x: Double(back.x) + cp * hs, y: Double(back.y) + sp * hs)
                let r = CGPoint(x: Double(back.x) - cp * hs, y: Double(back.y) - sp * hs)
                ctx.stroke(Path { p in p.addLines([l, tip, r]) }, with: .color(DG.path),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        }
        for m in o.marks {
            let p = P(m.u, m.v), s = max(0.62, sAt(m.v)), R = m.r * sc * s
            let disc = Path(ellipseIn: CGRect(x: p.x - R, y: p.y - R, width: 2 * R, height: 2 * R))
            ctx.fill(disc, with: .color(.white))
            ctx.stroke(disc, with: .color(m.tone.color), lineWidth: 1.6 * sc)
            // The mockups: the icon 1.25 times the radius across, at 2.3 on its grid.
            let side = R * 1.25
            DGIcons.draw(m.icon, in: &ctx, rect: CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side),
                         color: m.tone.color, stroke: 2.3)
        }
        if let y = o.you {
            let p = P(y + 0.5, 0.02), s = 6.5 * sc
            let arrow = Path { a in
                a.move(to: CGPoint(x: p.x, y: p.y - s * 1.5)); a.addLine(to: CGPoint(x: p.x + s, y: p.y + s * 0.9))
                a.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.35)); a.addLine(to: CGPoint(x: p.x - s, y: p.y + s * 0.9)); a.closeSubpath()
            }
            ctx.fill(arrow, with: .color(DG.path))
            ctx.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 1.8 * sc, lineJoin: .round))
        }
        for t in o.ticks {
            let p = P(-o.sh, t.v)
            ctx.stroke(Path { l in l.move(to: CGPoint(x: p.x - 5, y: p.y)); l.addLine(to: CGPoint(x: p.x + 1, y: p.y)) },
                       with: .color(DG.hex(0xaab3be)), lineWidth: 1.2)
            let text = ctx.resolve(Text(t.text).font(DG.font(12, t.strong ? .semibold : .medium))
                .foregroundColor(t.strong ? DG.ink : DG.hex(0x6b7684)))
            ctx.draw(text, at: CGPoint(x: p.x - 9, y: p.y), anchor: .trailing)
        }
    }
}

/// The fire's small map: the route, and the fire's glow beside it.
struct FireMapCanvas: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, x = w * 0.36
            let road = Path { p in
                p.move(to: CGPoint(x: x, y: h + 2))
                p.addCurve(to: CGPoint(x: x, y: -2), control1: CGPoint(x: x - 4, y: h * 0.6), control2: CGPoint(x: x + 6, y: h * 0.4))
            }
            ctx.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            ctx.stroke(road, with: .color(DG.path), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let c = CGPoint(x: w * 0.74, y: h * 0.45), r = h * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(stops: [.init(color: DGTone.high.color.opacity(0.45), location: 0),
                                                            .init(color: DGTone.high.color.opacity(0.16), location: 0.7),
                                                            .init(color: DGTone.high.color.opacity(0), location: 1)]),
                                           center: c, startRadius: 0, endRadius: r))
            let s = min(w, h) * 0.24
            DGIcons.draw("fire", in: &ctx, rect: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s),
                         color: DGTone.high.color, stroke: 2.2)
            let you = Path(ellipseIn: CGRect(x: x - 4, y: h * 0.82 - 4, width: 8, height: 8))
            ctx.fill(you, with: .color(DG.path)); ctx.stroke(you, with: .color(.white), lineWidth: 1.8)
        }
        .accessibilityHidden(true)
    }
}

/// A message sign on its posts, or its real lines when known.
struct BoardCanvas: View {
    var lines: [String] = []
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, bw = w * 0.8, bh = h * 0.5, y = h * 0.14
            ZStack(alignment: .topLeading) {
                HStack(spacing: 15) {
                    Rectangle().fill(DG.hex(0xb9c2cc)).frame(width: 2.5)
                    Rectangle().fill(DG.hex(0xb9c2cc)).frame(width: 2.5)
                }
                .frame(height: h - y - bh).offset(x: w / 2 - 10, y: y + bh)
                VStack(alignment: .leading, spacing: bh * 0.12) {
                    if lines.isEmpty {
                        Capsule().fill(DG.hex(0xf3c66b)).frame(width: bw * 0.76, height: 2.4)
                        Capsule().fill(DG.hex(0xf3c66b)).frame(width: bw * 0.5, height: 2.4)
                    } else {
                        ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, l in
                            Text(l).font(.system(size: max(6, bh * 0.2), weight: .bold, design: .monospaced))
                                .foregroundStyle(DG.hex(0xf3c66b)).lineLimit(1).minimumScaleFactor(0.4)
                        }
                    }
                }
                .padding(.horizontal, bw * 0.1)
                .frame(width: bw, height: bh, alignment: .leading)
                .background(DG.hex(0x26303c), in: RoundedRectangle(cornerRadius: 4))
                .offset(x: (w - bw) / 2, y: y)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The lane drawing for an event: the real lanes when the server sends
/// `lane_layout`, otherwise the kind's own picture. `cleared` turns it
/// green with a check.
struct LaneDrawing: View {
    /// The alert's thumbnail, a catalog row's smaller one, and see more.
    enum Size { case thumb, row, large }

    var kind: DGKind
    var layout: LaneLayout?
    var size: Size = .thumb
    var cleared = false
    /// The large drawing's distance labels: to the event, and halfway.
    var near = ""
    var half = ""
    /// How close the event is, 0 far to 1 on it; moves it down the road.
    var closeness: Double = 0
    var lines: [String] = []

    var body: some View {
        Group {
            if kind == .fire && LanePlan(layout) == nil {
                FireMapCanvas()
            } else if kind == .sign && LanePlan(layout) == nil {
                BoardCanvas(lines: size == .large ? lines : [])
            } else {
                RoadCanvas(spec: spec)
            }
        }
        .frame(width: size == .thumb ? 76 : size == .row ? 60 : nil,
               height: size == .thumb ? 64 : size == .row ? 42 : 150)
        .frame(maxWidth: size == .large ? 326 : nil)
    }

    var spec: RoadSpec {
        var s = LanePlan(layout).map { RoadSpec.plan($0, kind: kind) } ?? RoadSpec.kind(kind)
        if cleared { s = s.cleared() }
        if size == .thumb || size == .row { s = s.small(r: size == .thumb ? 9 : 8) }
        if size == .row { s.padT = 3; s.padB = 4; s.scale = 0.85 }
        if size == .large { s = s.large(vc: 0.28 + 0.46 * (1 - closeness), near: near, half: half) }
        return s
    }
}
