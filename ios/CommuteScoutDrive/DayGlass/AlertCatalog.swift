import SwiftUI

/// "Every alert": each kind as its row looks, grouped by how much it
/// asks of the driver, and every message the app itself shows. Opened
/// from Settings > Testing, or with "-csCatalog" ("-csCatalog system"
/// for the messages).
struct AlertCatalog: View {
    enum Page: String { case alerts, system }
    var page: Page = .alerts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if page == .alerts { alerts } else { system }
            }
            .padding(.top, 8).padding(.bottom, 24)
        }
        .background(DG.background.ignoresSafeArea())
        .accessibilityIdentifier("alert-catalog")
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every alert").font(DG.T.listTitle).foregroundStyle(DG.ink).padding(.horizontal, 24)
            ForEach([DGTone.high, .mid, .low], id: \.self) { tone in
                section(tone)
                VStack(spacing: 6) {
                    ForEach(DGKind.allCases.filter { $0.tone == tone }, id: \.self) { k in
                        AlertCatalogRow(sample: .of(k))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func section(_ tone: DGTone) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
            Text(DGKind.allCases.first { $0.tone == tone }?.section ?? "").font(DG.T.section).foregroundStyle(DG.sub)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 6)
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The capsule speaks").font(DG.T.listTitle).foregroundStyle(DG.ink).padding(.horizontal, 24)
            Text("Everything the app says, in the one place it says it.")
                .font(DG.font(14)).foregroundStyle(DG.sub)
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 14)
            VStack(spacing: 8) {
                ForEach(SystemNotes.samples, id: \.title) { n in
                    DGNote(note: n, identifier: "catalog-note-" + n.id.rawValue) { _ in }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// One kind's sample words, as the mockups show them.
struct AlertSample {
    var kind: DGKind
    var title: String
    var sub: String
    var mono = false
    var distance: String
    var eta: String

    static func of(_ k: DGKind) -> AlertSample {
        switch k {
        case .crash: return AlertSample(kind: k, title: "Crash", sub: "Right lane blocked", distance: "0.8 mi", eta: "50 s")
        case .closure: return AlertSample(kind: k, title: "Road closed", sub: "2 right lanes closed", distance: "2.1 mi", eta: "2 min")
        case .chain: return AlertSample(kind: k, title: "Chain control R-2", sub: "I-80 E at Kingvale", distance: "14 mi", eta: "15 min")
        case .fire: return AlertSample(kind: k, title: "Oak Fire", sub: "3 mi east of the route", distance: "6 mi", eta: "7 min")
        case .hazard: return AlertSample(kind: k, title: "Object on road", sub: "Left lane", distance: "1.3 mi", eta: "1 min")
        case .jam: return AlertSample(kind: k, title: "Slow traffic", sub: "US-101 S, Oregon to San Antonio", distance: "1.9 mi", eta: "2 min")
        case .ice: return AlertSample(kind: k, title: "Icy pavement", sub: "SR-17 S at Summit Rd", distance: "9 mi", eta: "11 min")
        case .police: return AlertSample(kind: k, title: "Police reported", sub: "Shoulder, US-101 S", distance: "3.4 mi", eta: "3 min")
        case .sign: return AlertSample(kind: k, title: "Message sign", sub: "SAN JOSE 24 MIN", mono: true, distance: "0.6 mi", eta: "40 s")
        case .camera: return AlertSample(kind: k, title: "Speed camera", sub: "El Camino Real at Page Mill", distance: "0.3 mi", eta: "25 s")
        case .toll: return AlertSample(kind: k, title: "Express lanes", sub: "US-101 S express lanes", distance: "4 mi", eta: "4 min")
        }
    }
}

/// A kind's row: its small drawing, the words and how far.
struct AlertCatalogRow: View {
    var sample: AlertSample

    var body: some View {
        HStack(spacing: 12) {
            LaneDrawing(kind: sample.kind, layout: nil, size: .row)
                .background(.white.opacity(0.8))
                .clipShape(ThumbShape())
                .overlay(ThumbShape().stroke(DG.hair, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(sample.title).font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(1)
                Text(sample.sub)
                    .font(sample.mono ? .system(size: 11.5, weight: .medium, design: .monospaced) : DG.T.rowSub)
                    .foregroundStyle(sample.mono ? DGTone.mid.ink : DG.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(sample.distance).font(DG.font(16, .bold)).foregroundStyle(DG.ink)
                Text(sample.eta).font(DG.T.rowSub).foregroundStyle(DG.sub)
            }
        }
        .padding(.leading, 4).padding(.trailing, 18).padding(.vertical, 4)
        .frame(minHeight: 50)
        .dgGlass(radius: DG.R.cap, tone: sample.kind.tone)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catalog-" + sample.kind.rawValue)
    }
}

/// The row thumbnail's outline: round on the left like the capsule,
/// softer on the right.
struct ThumbShape: Shape {
    func path(in r: CGRect) -> Path {
        let l = min(21, r.height / 2), rr: CGFloat = 11
        var p = Path()
        p.move(to: CGPoint(x: r.minX + l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rr, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + rr), radius: rr)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rr))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rr, y: r.maxY), radius: rr)
        p.addLine(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - l), radius: l)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + l, y: r.minY), radius: l)
        p.closeSubpath()
        return p
    }
}
