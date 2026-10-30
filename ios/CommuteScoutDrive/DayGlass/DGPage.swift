import SwiftUI

// The parts every settings and "more" page is built from: a page with a
// back button and a title, white groups of rows, colored tiles, switch
// and radio rows, the segmented control and small tags.

/// A pushed page: a round back button, the title centered over it, and
/// the content scrolling under a soft background.
struct DGPage<Content: View>: View {
    var title: String
    /// A large title at the top of the content (the "more" pages), or
    /// only the small centered one (settings pages).
    var largeTitle = false
    var intro: String?
    var identifier: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var scrolled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    Color.clear.preference(key: DGScrollOffset.self, value: g.frame(in: .named("dgpage")).minY)
                }
                .frame(height: 0)
                if largeTitle {
                    Text(title).font(DG.font(30, .bold)).foregroundStyle(DG.ink)
                        .padding(.top, 4).accessibilityAddTraits(.isHeader)
                }
                if let intro {
                    Text(intro).font(DG.font(15)).foregroundStyle(DG.sub)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, largeTitle ? 6 : 4)
                }
                content().padding(.top, intro == nil && !largeTitle ? 0 : 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .coordinateSpace(name: "dgpage")
        .onPreferenceChange(DGScrollOffset.self) { y in
            let s = y < -40
            if s != scrolled { withAnimation(.easeOut(duration: 0.2)) { scrolled = s } }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text(title).font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
                    .opacity(largeTitle && !scrolled ? 0 : 1)
                HStack {
                    DGBackButton { dismiss() }
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
            .background(DG.background.opacity(scrolled ? 0.94 : 0).ignoresSafeArea(edges: .top))
        }
        .background(DGPageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "page-\(title)")
    }
}

struct DGPageBackground: View {
    var body: some View {
        LinearGradient(colors: [DG.hex(0xf7f9fc), DG.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

private struct DGScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The 36-point round back button.
struct DGBackButton: View {
    var symbol = "chevron.left"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(DG.ink)
                .frame(width: 36, height: 36).background(DG.ink.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(symbol == "xmark" ? "Close" : "Back")
        .accessibilityIdentifier(symbol == "xmark" ? "page-close" : "page-back")
    }
}

/// The small label over a group.
struct DGSectionLabel: View {
    var text: String
    var trailing: AnyView?
    init(_ text: String, trailing: AnyView? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(DG.T.section).foregroundStyle(DG.sub)
            if let trailing { trailing }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 20).padding(.bottom, 8)
    }
}

/// A white group of rows with hairlines between them.
struct DGGroup<Content: View>: View {
    var radius: CGFloat = 22
    var tint: Color?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(tint ?? Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
            .shadow(color: DG.ink.opacity(0.04), radius: 8, y: 2)
    }
}

/// The hairline between rows, inset past the tile.
struct DGDivider: View {
    var inset: CGFloat = 60
    var body: some View { Rectangle().fill(DG.hair).frame(height: 1).padding(.leading, inset) }
}

/// A gradient tile with a white symbol, the picture on a settings row.
struct DGTile: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.47, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color.mix(.white, 0.14), color], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
    }
}

/// A light tile in a tone: the picture on a "more" page row.
struct DGSoftTile: View {
    var symbol: String
    var tone: DGTone = .low
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(tone.ink)
            .frame(width: size, height: size)
            .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A row: tile, title, an optional line under it, a value and a chevron.
struct DGRow<Leading: View, Trailing: View>: View {
    var title: String
    var sub: String?
    var value: String?
    var chevron = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                if let sub { Text(sub).font(DG.T.rowSub).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 6)
            trailing()
            if let value { Text(value).font(DG.font(15)).foregroundStyle(DG.sub).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.hex(0xb3bccb)) }
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

extension DGRow where Trailing == EmptyView {
    init(title: String, sub: String? = nil, value: String? = nil, chevron: Bool = true, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, sub: sub, value: value, chevron: chevron, leading: leading, trailing: { EmptyView() })
    }
}

/// A row with a switch, the switch in the path blue.
struct DGSwitchRow<Leading: View>: View {
    var title: String
    var sub: String?
    @Binding var isOn: Bool
    var identifier: String?
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    if let sub { Text(sub).font(DG.T.rowSub).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .tint(DG.path)
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 54)
        .accessibilityIdentifier(identifier ?? title)
    }
}

extension DGSwitchRow where Leading == EmptyView {
    init(title: String, sub: String? = nil, isOn: Binding<Bool>, identifier: String? = nil) {
        self.init(title: title, sub: sub, isOn: isOn, identifier: identifier, leading: { EmptyView() })
    }
}

/// A choice among a few: a check circle that fills when picked.
struct DGRadioRow: View {
    var title: String
    var sub: String?
    var on: Bool
    var identifier: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    if let sub { Text(sub).font(DG.T.rowSub).foregroundStyle(DG.sub) }
                }
                Spacer()
                DGCheck(on: on)
            }
            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The round check: blue and filled when on, an empty ring when off.
struct DGCheck: View {
    var on: Bool
    var size: CGFloat = 24
    var body: some View {
        ZStack {
            Circle().strokeBorder(DG.ink.opacity(0.16), lineWidth: 1.5).opacity(on ? 0 : 1)
            Circle().fill(DG.path).scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: size * 0.48, weight: .heavy)).foregroundStyle(.white)
                .scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(DG.spring, value: on)
    }
}

/// The segmented control: a white thumb that springs between choices.
struct DGSegmented<T: Hashable>: View {
    var options: [(value: T, label: String, symbol: String?)]
    @Binding var selection: T
    var height: CGFloat = 44
    var identifier = "seg"
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.value == selection
                Button { withAnimation(DG.snap) { selection = o.value } } label: {
                    HStack(spacing: 6) {
                        if let s = o.symbol { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
                        Text(o.label).font(DG.font(15, on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? DG.inkColor(.low) : DG.ink.opacity(0.8))
                    .frame(maxWidth: .infinity).frame(height: height - 8)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: (height - 8) / 2, style: .continuous).fill(.white)
                                .shadow(color: DG.ink.opacity(0.12), radius: 4, y: 1.5)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(o.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A small tag: "Free, works offline", "Not official", "Default".
struct DGTag: View {
    var text: String
    var tone: DGTone = .good
    var systemImage: String?
    var color: Color?
    var body: some View {
        let c = color ?? tone.ink
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(DG.font(12, .semibold))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 8).frame(height: 22)
        .background((color ?? tone.color).opacity(0.12), in: Capsule())
    }
}

/// A gray line of help under a group.
struct DGFootnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(DG.font(13)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.top, 8)
    }
}

/// The dark bar pinned to the bottom of a "more" page, over a fade.
struct DGDock<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            .background(LinearGradient(colors: [DG.background.opacity(0), DG.background.opacity(0.94), DG.background],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }
}

/// A plugin's badge: a rounded square in the plugin's color, with a
/// puzzle corner so it never reads as an official round marker.
struct DGPluginBadge: View {
    var symbol: String
    var colors: [Color]
    var size: CGFloat = 52
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .shadow(color: (colors.last ?? .black).opacity(0.3), radius: 5, y: 3)
    }
}
