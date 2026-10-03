import SwiftUI

/// What the driver sees over the map while moving: the alert ahead as
/// a banner at the top, and the speedometer at the bottom. Both stay
/// clear of the search bar, the instruction card and the side buttons,
/// read at arm's length, and go away with one tap.

/// The next alert, dropped in from the top. Shows from the first
/// warning distance, says what and how far, speaks again on a tap,
/// and leaves with the X, a swipe up, or once the alert is behind.
struct AlertBanner: View {
    @EnvironmentObject var model: AppModel
    let item: AlertsEngine.Upcoming
    let along: Double

    private var color: Color {
        item.marker.kind == "plugin"
            ? Color(PluginStyle.color(PluginStyle.sourceId(item.marker)))
            : MarkerIcons.tint(item.marker.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            MarkerGlyph(marker: item.marker, size: 30)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.marker.displayTitle).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    Text(Units.distance(max(0, item.alongMeters - along)) + " ahead")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(color)
                    if model.alerts.ahead.count > 1 {
                        Text("+\(model.alerts.ahead.count - 1) more").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { model.alerts.dismiss(item.id) } label: {
                Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("alert-dismiss")
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16).fill(color).frame(width: 5).padding(.vertical, 8).padding(.leading, 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { model.alerts.say(item.marker) }
        .gesture(DragGesture(minimumDistance: 20).onEnded { g in if g.translation.height < -20 { model.alerts.dismiss(item.id) } })
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("alert-banner")
    }
}

/// Speed and the posted limit, the way a dashboard shows them: the
/// speed large, the limit as the sign on the road. Red when over.
struct Speedometer: View {
    let speedMps: Double
    let limitKmh: Double?

    private var miles: Bool { Units.useMiles }
    private var speedShown: Int { speedMps < 0 ? 0 : Int((miles ? speedMps * 2.236936 : speedMps * 3.6).rounded()) }
    private var limitShown: Int? { limitKmh.map { Int((miles ? $0 / 1.609344 : $0).rounded()) } }
    private var over: Bool { if let l = limitShown { return speedShown > l + 1 }; return false }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: -2) {
                Text("\(speedShown)")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(over ? Color.red : Color.primary)
                Text(miles ? "mph" : "km/h").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 52)
            if let l = limitShown {
                // The MUTCD sign in the US, the red ring elsewhere.
                if miles {
                    VStack(spacing: 0) {
                        Text("SPEED").font(.system(size: 8, weight: .bold))
                        Text("LIMIT").font(.system(size: 8, weight: .bold))
                        Text("\(l)").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 50)
                    .background(.white, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black, lineWidth: 2))
                } else {
                    Text("\(l)").font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(.white, in: Circle())
                        .overlay(Circle().strokeBorder(.red, lineWidth: 5))
                }
            } else {
                Text("limit\nunknown").font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        .accessibilityIdentifier("speedometer")
    }
}
