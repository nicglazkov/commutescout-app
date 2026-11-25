import FerrostarCore
import FerrostarCoreFFI
import SwiftUI

// Clear Glass: the trip screen's own parts. The ahead line is the rail
// down the left that strings what is on the route between the driver
// and the destination; the trip bar holds the arrival time and the four
// things a driver does mid-trip.

/// One mark on the ahead line.
struct RailMark: Identifiable, Equatable {
    let id: String
    let icon: String
    let tone: DGTone
    let distance: String
    let title: String
    let gapMeters: Double
}

/// The ahead line. `marks` are nearest first. The rail takes the height
/// it is given and places up to three marks on it by distance.
struct AheadRail: View {
    let marks: [RailMark]
    let destination: String
    let toDestination: String?
    let totalMeters: Double
    var stops = 0
    let onMark: (RailMark) -> Void

    private static let width: CGFloat = 34
    private static let top: CGFloat = 26      // the destination's centre, from the rail's top
    private static let bottom: CGFloat = 24   // the driver's centre, from the rail's bottom

    var body: some View {
        GeometryReader { g in
            let span = g.size.height - Self.top - Self.bottom
            let slots = RailLayout.slots(gaps: marks.map(\.gapMeters), total: totalMeters, span: span)
            ZStack(alignment: .topLeading) {
                // The rail itself: a glass capsule with the track down its middle.
                ZStack {
                    Capsule().fill(DG.laneFill).frame(width: 3)
                        .padding(.top, Self.top).padding(.bottom, Self.bottom)
                    VStack(spacing: 0) {
                        DGIconView(name: "mappin", size: 15).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(DG.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, Self.top - 12)
                        Spacer(minLength: 0)
                        Circle().fill(DG.path).frame(width: 10, height: 10)
                            .padding(3).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .padding(.bottom, Self.bottom - 8)
                    }
                }
                .frame(width: Self.width, height: g.size.height)
                .dgGlass(radius: 17)

                RailTag(distance: toDestination ?? "", title: stops > 0 ? "\(destination), \(stops) \(stops == 1 ? "stop" : "stops")" : destination, tone: nil)
                    .offset(x: Self.width + 10, y: Self.top - 22)
                    .accessibilityIdentifier("ahead-destination")

                ForEach(slots, id: \.index) { s in
                    let m = marks[s.index]
                    let y = Self.top + s.y
                    DGIconView(name: m.icon, size: 15, stroke: 2.2).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(m.tone == .clear || m.tone == .low ? DG.sub : m.tone.color, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .offset(x: (Self.width - 26) / 2, y: y - 13)
                        .accessibilityHidden(true)
                    Button { onMark(m) } label: {
                        RailTag(distance: m.distance, title: m.title, tone: m.tone == .high || m.tone == .mid ? m.tone : nil)
                    }
                    .buttonStyle(DGPressStyle())
                    .offset(x: Self.width + 10, y: y - 22)
                    .accessibilityIdentifier("ahead-mark")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ahead-line")
    }
}

private struct RailTag: View {
    let distance: String
    let title: String
    let tone: DGTone?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !distance.isEmpty { Text(distance).font(DG.font(15.5, .bold)).foregroundStyle(DG.ink).monospacedDigit() }
            Text(title).font(DG.font(12.5, .medium)).foregroundStyle(tone?.ink ?? DG.sub)
        }
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: 170, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .dgGlass(radius: 13, tone: tone)
        .accessibilityElement(children: .combine)
    }
}

private func clock(_ secondsFromNow: Double) -> String {
    Date().addingTimeInterval(secondsFromNow).formatted(date: .omitted, time: .shortened)
}

/// Arrival time, what is left, and the three things to do mid-trip. Reporting lives in the Your trip sheet.
struct TripBar: View {
    let state: NavigationState?
    let onExit: (() -> Void)?
    var onAddStop: () -> Void = {}
    var onRoute: () -> Void = {}

    var body: some View {
        let p = state?.currentProgress
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.map { clock($0.durationRemaining) } ?? "--").font(DG.T.eta).foregroundStyle(DG.ink).monospacedDigit()
                    .accessibilityIdentifier("trip-eta")
                Text("arrive").font(DG.T.meta).foregroundStyle(DG.sub)
                Spacer(minLength: 0)
                Text(meta(p)).font(DG.T.meta).foregroundStyle(DG.sub).lineLimit(1)
            }
            .padding(.horizontal, 8)
            HStack(spacing: 8) {
                TripButton(icon: "stop", label: "End", danger: true) { onExit?() }
                    .accessibilityLabel("End trip").accessibilityIdentifier("end-trip")
                TripButton(icon: "mappin", label: "Add stop", action: onAddStop).accessibilityIdentifier("add-stop")
                TripButton(icon: "arrow.triangle.branch", label: "Route", action: onRoute).accessibilityIdentifier("trip-route")
            }
        }
        .padding(12)
        .dgGlass(radius: DG.R.trip)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-bar")
    }

    private func meta(_ p: TripProgress?) -> String {
        guard let p else { return "" }
        let min = Int((p.durationRemaining / 60).rounded())
        let t = min >= 60 ? "\(min / 60) h \(min % 60) min" : "\(max(1, min)) min"
        return "\(t) · \(Units.distance(p.distanceRemaining))"
    }
}

private struct TripButton: View {
    let icon: String
    let label: String
    var danger = false
    var tint: Color = DG.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                DGIconView(name: icon, size: 22, stroke: 2.1).foregroundStyle(danger ? DGTone.high.ink : tint)
                Text(label).font(DG.font(12.5, .semibold)).foregroundStyle(danger ? DGTone.high.ink : DG.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(danger ? DGTone.high.color.opacity(0.10) : DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(danger ? DGTone.high.color.opacity(0.22) : .clear, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(DGPressStyle())
    }
}

/// The bar that offers a changed trip: the new arrival time, what the
/// change costs, where the trip now goes, and the two answers.
struct TripChangeBar: View {
    let seconds: Double
    let cost: String?
    let line: String
    let confirm: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock(seconds)).font(DG.T.eta).foregroundStyle(DG.ink).monospacedDigit()
                Text("arrive").font(DG.T.meta).foregroundStyle(DG.sub)
                Spacer(minLength: 0)
                if let cost { Text(cost).font(DG.font(14, .semibold)).foregroundStyle(DG.ink).lineLimit(1) }
            }
            .padding(.horizontal, 8)
            Text(line).font(DG.font(12.5, .medium)).foregroundStyle(DG.sub).lineLimit(1)
                .padding(.horizontal, 8).padding(.top, 4)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel).buttonStyle(DGButtonStyle(kind: .glass, height: 54))
                    .frame(maxWidth: 130).accessibilityIdentifier("trip-change-cancel")
                Button(confirm, action: onConfirm).buttonStyle(DGButtonStyle(kind: .blue, height: 54))
                    .accessibilityIdentifier("trip-change-confirm")
            }
            .padding(.top, 12)
        }
        .padding(12)
        .dgGlass(radius: DG.R.trip)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-change")
    }
}

/// End is one tap from Add stop, so it asks first. The question goes
/// away by itself and the trip carries on.
struct EndTripBar: View {
    let destination: String
    let onKeep: () -> Void
    let onEnd: () -> Void
    @State private var left = 5

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("End the trip to \(destination)?").font(DG.font(16.5, .bold)).foregroundStyle(DG.ink).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("Keeps going in \(left) s").font(DG.font(12.5, .medium)).foregroundStyle(DG.sub).monospacedDigit().lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            HStack(spacing: 8) {
                Button("Keep driving", action: onKeep).buttonStyle(DGButtonStyle(kind: .glass, height: 54))
                    .accessibilityIdentifier("end-trip-keep")
                Button(action: onEnd) { Label("End trip", systemImage: "stop") }
                    .buttonStyle(EndStyle()).accessibilityIdentifier("end-trip-confirm")
            }
        }
        .padding(12)
        .dgGlass(radius: DG.R.trip)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("end-trip-ask")
        .task {
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                left -= 1
            }
            onKeep()
        }
    }

    private struct EndStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.font(DG.T.button).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(DGTone.high.color, in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(DG.snap, value: configuration.isPressed)
        }
    }
}

/// A numbered stop, in the purple the design keeps for stops.
struct StopDisc: View {
    let n: Int
    var size: CGFloat = 32

    var body: some View {
        Text("\(n)").font(DG.font(14, .bold)).foregroundStyle(.white)
            .frame(width: size, height: size).background(DG.hex(0x7c5cf0), in: Circle())
    }
}
