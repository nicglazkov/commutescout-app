import CoreLocation
import SwiftUI

// The plugin marketplace and a plugin's own page (28-more.html, market
// and plugin). One place for every plugin job: add or remove one, show
// it on the map or switch it off for now, add a private one by its
// address, and see whether it is answering. What a plugin shows follows
// the account that added it, and its data is always marked apart from
// official data.

// MARK: - Shared parts

/// A plugin's picture: its color, a rounded square, the glyph of what it
/// shows. Plugins are rounded squares everywhere; official alerts round.
struct MarketBadge: View {
    var source: FlareSource
    var size: CGFloat = 52

    var body: some View {
        let c = Color(PluginStyle.color(source.id))
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(LinearGradient(colors: [c.mix(.white, 0.2), c], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .overlay(DGMoreIcon(name: Market.glyph(kinds: source.kinds), size: size * 0.5, stroke: 2.1).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: c.opacity(0.35), radius: 7, y: 4)
            .accessibilityHidden(true)
    }
}

/// A pin on the plugin page's map: rounded square for a plugin, round
/// for an official alert, ringed in white.
struct MarketPin: View {
    var color: Color
    var icon: String
    var square: Bool
    var size: CGFloat = 34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: square ? size * 0.3 : size / 2, style: .continuous)
        shape.fill(LinearGradient(colors: [color.mix(.white, 0.15), color], startPoint: .top, endPoint: .bottom))
            .overlay(DGMoreIcon(name: icon, size: size * 0.5, stroke: 2.2).foregroundStyle(.white))
            .frame(width: size, height: size)
            .overlay(shape.strokeBorder(.white, lineWidth: 2.5).padding(-2.5))
            .shadow(color: DG.ink.opacity(0.3), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}

extension FlareSource {
    var marketMaker: String { Market.maker(name: name, trust: trust, tier: tier, attribution: attribution) }
    var marketPurpose: String { Market.purpose(summary: summary, kindsLabel: kindsLabel) }
    var marketCoverage: String { coverage == nil ? (tier == "private" ? "Private" : "Coverage not stated") : coverageLabel }
}

/// The add pill on a card: blue "Add", then green "Added" with a check
/// that springs in.
private struct AddPill: View {
    var added: Bool
    var name: String
    var action: () -> Void
    @State private var pop = false

    var body: some View {
        Button {
            action()
            pop = true
            withAnimation(DG.spring) { pop = false }
        } label: {
            HStack(spacing: 6) {
                if added { DGMoreIcon(name: "check", size: 16, stroke: 2.8).transition(.scale.combined(with: .opacity)) }
                Text(added ? "Added" : "Add").font(DG.font(14.5, .semibold))
            }
            .foregroundStyle(added ? DGTone.good.ink : .white)
            .padding(.horizontal, 18).frame(height: 38)
            .background(added ? AnyShapeStyle(DGTone.good.color.opacity(0.1)) : AnyShapeStyle(DG.path), in: Capsule())
            .overlay(Capsule().strokeBorder(added ? DGTone.good.color.opacity(0.28) : .clear, lineWidth: 1))
            .shadow(color: added ? .clear : DG.path.opacity(0.45), radius: 6, y: 4)
            .scaleEffect(pop ? 0.9 : 1)
            .animation(DG.springSoft, value: added)
            .contentShape(Capsule().inset(by: -4))
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(added ? "Added \(name)" : "Add \(name)")
        .accessibilityAddTraits(added ? .isSelected : [])
    }
}

/// Cards slide up into place one after another when the filter changes.
private struct Stagger: ViewModifier {
    var index: Int
    var token: Market.Filter
    @State private var shown = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.98)
            .onChange(of: token) { _ in
                shown = false
                withAnimation(DG.spring.delay(0.04 * Double(index))) { shown = true }
            }
    }
}

// MARK: - The marketplace

/// The plugin marketplace: cards for every listed plugin and the
/// person's private ones, filtered by where the data comes from.
/// Pushed inside a NavigationStack.
struct MarketplaceView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: Market.Filter = .all
    @State private var open: FlareSource?
    @State private var showAdd = false
    private var sources: SourcesStore { model.sources }

    private var all: [FlareSource] {
        let listed = Set(sources.catalog.map(\.id))
        return sources.catalog + sources.mine.filter { !listed.contains($0.id) }
    }

    private var visible: [FlareSource] { all.filter { Market.shows(filter, trust: $0.trust) } }

    var body: some View {
        DGPage(title: "Marketplace", largeTitle: true,
               intro: "Plugins add alerts and places to your map. Everything they show follows your account and no one else's.",
               identifier: "marketplace") {
            VStack(alignment: .leading, spacing: 0) {
                DGSegmented(options: Market.Filter.allCases.map { ($0, $0.rawValue, nil) }, selection: $filter, identifier: "market-filter")
                    .padding(.top, 4)
                let shown = visible
                Text(Market.countLine(visible: shown.count, added: shown.filter { sources.isAdded($0.id) }.count))
                    .font(DG.font(14, .semibold)).foregroundStyle(DG.sub)
                    .padding(.horizontal, 8).padding(.top, 22).padding(.bottom, 8)
                    .accessibilityIdentifier("market-count")
                    .animation(nil, value: filter)
                VStack(spacing: 10) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                        card(s).modifier(Stagger(index: i, token: filter))
                    }
                }
                if all.isEmpty {
                    Text("No plugin is listed yet.").font(DG.font(15)).foregroundStyle(DG.sub).padding(.vertical, 24).padding(.horizontal, 8)
                }
                DGSectionLabel("Your private plugins")
                DGGroup {
                    Button { sources.error = nil; showAdd = true } label: {
                        DGRow(title: "Add a plugin by its address", sub: "A private or unlisted plugin. Only you see it.") {
                            DGMoreIcon(name: "link", size: 19, stroke: 2.1).foregroundStyle(DG.path)
                                .frame(width: 36, height: 36).background(DG.path.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .buttonStyle(DGPressStyle())
                    .accessibilityIdentifier("add-source")
                    DGDivider()
                    Link(destination: URL(string: "https://commutescout.com/plugins")!) {
                        DGRow(title: "Write a plugin", sub: "The protocol and the conformance check") {
                            DGMoreIcon(name: "piece", size: 19, stroke: 2).foregroundStyle(DataTag.pluginInk)
                                .frame(width: 36, height: 36).background(DataTag.pluginWash.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .accessibilityIdentifier("market-write")
                }
                DGFootnote("Official data comes from public agencies and is packaged by CommuteScout. Plugin data comes from the plugin's maker; reviewed plugins say so on their page.")
                    .padding(.top, 8)
            }
        }
        .task { await sources.loadCatalog() }
        .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
            if let s = open { PluginDetailView(sourceId: s.id) }
        }
        .sheet(isPresented: $showAdd) { AddPluginSheet() }
    }

    private func card(_ s: FlareSource) -> some View {
        let added = sources.isAdded(s.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MarketBadge(source: s)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(DG.font(16.5, .semibold)).foregroundStyle(DG.ink).lineLimit(2)
                    Text(s.marketMaker).font(DG.font(13)).foregroundStyle(DG.sub).lineLimit(1)
                }
                Spacer(minLength: 6)
                AddPill(added: added, name: s.name) {
                    if added {
                        // A private plugin is forgotten when removed: that
                        // asks first, on its page.
                        if s.tier == "private" { open = s; return }
                        sources.removePlugin(s.id)
                    } else {
                        sources.addPlugin(s.id)
                    }
                    model.markers.refresh(force: true)
                }
                .accessibilityIdentifier("install-\(s.id)")
            }
            Text(s.marketPurpose).font(DG.font(14.5)).foregroundStyle(DG.ink).lineSpacing(2).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.horizontal, 2)
            HStack(spacing: 8) {
                DataTag.of(trust: s.trust)
                Spacer(minLength: 4)
                Text(s.marketCoverage).font(DG.font(12.5)).foregroundStyle(DG.faint).lineLimit(1)
            }
            .padding(.top, 11)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .dgGlass(radius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { open = s }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plugin-card")
        .accessibilityAction(named: "Open") { open = s }
    }
}

// MARK: - Add by address

/// A private or unlisted plugin, added by its address: the phone asks it
/// who it is, then reads its alerts itself.
struct AddPluginSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var token = ""
    @State private var adding = false
    private var sources: SourcesStore { model.sources }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Cancel") { dismiss() }.font(DG.font(16, .medium)).foregroundStyle(DG.sub)
                Spacer()
                Text("Add a plugin").font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
                Spacer()
                Button(adding ? "Checking" : "Add") { Task { await add() } }
                    .font(DG.font(16, .semibold)).foregroundStyle(base.isEmpty || adding ? DG.faint : DG.path)
                    .disabled(base.isEmpty || adding)
            }
            .padding(.top, 18)
            field("Plugin address", text: $base, prompt: "https://example.com", id: "source-url").keyboardType(.URL)
            field("Token, for a private plugin", text: $token, prompt: "Optional", id: "source-token")
            if let e = sources.error {
                Text(e).font(DG.font(14, .medium)).foregroundStyle(DGTone.high.ink).fixedSize(horizontal: false, vertical: true)
            }
            Text("The app asks the plugin who it is, then reads its alerts around where you're looking. What it shows follows your account and no one else's.")
                .font(DG.font(13)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .background(DGPageBackground())
        .presentationDetents([.medium])
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DG.font(12.5, .medium)).foregroundStyle(DG.sub)
            TextField(prompt, text: text)
                .font(DG.font(16.5, .semibold)).foregroundStyle(DG.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
    }

    private func add() async {
        adding = true
        sources.error = nil
        if await sources.add(base: base, token: token) {
            model.markers.refresh(force: true)
            dismiss()
        }
        adding = false
    }
}

// MARK: - A plugin's page

/// Kept for older links: a plugin's page.
typealias PluginStatusView = PluginDetailView

/// One plugin: its pins on a map, and a sheet with what it adds, what it
/// can use, whether it is answering, the switch for the map and Remove.
struct PluginDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceId: String
    @State private var sheet = 0
    @State private var step: Step = .idle
    @State private var checking = false
    @State private var reach: String?

    enum Step { case idle, confirm, removed }

    private var sources: SourcesStore { model.sources }
    private var source: FlareSource? { sources.catalog.first { $0.id == sourceId } ?? sources.mine.first { $0.id == sourceId } }
    private var shown: Bool { sources.isAdded(sourceId) && sources.isOn(sourceId) }

    private var center: CLLocationCoordinate2D {
        model.viewCenter ?? model.here ?? CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143)
    }

    var body: some View {
        GeometryReader { g in
            let full = CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            let snaps = [min(592, full.height * 0.68), full.height * 0.9]
            ZStack(alignment: .bottom) {
                pinsMap(size: full, lift: snaps[0])
                if let s = source {
                    DGSheet(snaps: snaps, index: $sheet, identifier: "plugin-sheet") { sheetBody(s) }
                } else {
                    DGGroup {
                        Text("This plugin is no longer listed.").font(DG.font(15)).foregroundStyle(DG.sub).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16).padding(.bottom, g.safeAreaInsets.bottom)
                }
            }
            .frame(width: full.width, height: full.height)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                DGBackButton { dismiss() }
                    .background(Circle().fill(.white.opacity(0.85)).shadow(color: DG.ink.opacity(0.12), radius: 6, y: 2))
                    .padding(.leading, 16).padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plugin-page")
    }

    // MARK: map

    /// The plugin's own markers around the map's center, as rounded
    /// squares, with the official alerts nearby round beside them.
    private func pinsMap(size: CGSize, lift: CGFloat) -> some View {
        // The map's center sits in the strip above the sheet.
        let zoom = 13.2
        let probe = Mercator(center: center, zoom: zoom, size: size)
        let shift = (size.height - lift) / 2 + 20 - size.height / 2
        let mapCenter = probe.coordinate(CGPoint(x: size.width / 2, y: size.height / 2 - shift))
        let m = Mercator(center: mapCenter, zoom: zoom, size: size)
        let visibleTop = size.height - lift + 10
        func inView(_ p: CGPoint) -> Bool { p.x > 20 && p.x < size.width - 20 && p.y > 70 && p.y < visibleTop }
        let mine = model.allMarkers.filter { $0.kind == "plugin" && PluginStyle.sourceId($0) == sourceId }
            .map { ($0, m.point($0.coordinate)) }.filter { inView($0.1) }.prefix(12)
        let official = model.allMarkers.filter { $0.kind != "plugin" && $0.isEvent }
            .map { ($0, m.point($0.coordinate)) }.filter { inView($0.1) }.prefix(2)
        let color = Color(PluginStyle.color(sourceId))
        let glyph = Market.glyph(kinds: source?.kinds ?? [])
        return ZStack(alignment: .topLeading) {
            StillMap(center: mapCenter, zoom: zoom)
            ForEach(Array(official.enumerated()), id: \.offset) { _, o in
                let k = DGKind(marker: o.0)
                MarketPin(color: k.tone.color, icon: DGIcon.name(k), square: false).position(o.1)
            }
            ForEach(Array(mine.enumerated()), id: \.offset) { i, o in
                MarketPin(color: color, icon: glyph, square: true)
                    .position(o.1)
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : 0.4)
                    .animation(DG.spring.delay(0.05 * Double(i)), value: shown)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: sheet

    @ViewBuilder private func sheetBody(_ s: FlareSource) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        MarketBadge(source: s, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(DG.font(24, .bold)).foregroundStyle(DG.ink).lineLimit(2)
                                .accessibilityAddTraits(.isHeader)
                            Text(s.marketMaker).font(DG.font(14.5, .medium)).foregroundStyle(DG.sub)
                        }
                    }
                    .padding(.horizontal, 18)
                    tags(s).padding(.horizontal, 18).padding(.top, 14)
                    if sources.isAdded(s.id) || step == .removed { showSwitch(s).padding(.top, 16) }
                    mineBox.padding(.top, 14)
                    section("What it adds")
                    adds(s)
                    section("What it can use")
                    uses(s)
                    section("Status")
                    status(s)
                    Text(Market.footnote(attribution: s.attribution))
                        .font(DG.font(12.5)).foregroundStyle(DG.faint).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.top, 12)
                }
                .padding(.top, 2).padding(.bottom, 24)
            }
            acts(s)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(DG.font(17, .bold)).foregroundStyle(DG.ink)
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 8)
    }

    private func tags(_ s: FlareSource) -> some View {
        HStack(spacing: 6) {
            DataTag.of(trust: s.trust)
            if s.tier == "approved" || s.trust == "official" { DataTag(text: "Reviewed", style: .good, icon: "check") }
            else if s.tier == "private" { DataTag(text: "Private", style: .plain, icon: "lock") }
            else { DataTag(text: "Not reviewed", style: .plain) }
            DataTag(text: s.marketCoverage, style: .plain)
        }
    }

    private func showSwitch(_ s: FlareSource) -> some View {
        DGGroup(radius: 20) {
            DGSwitchRow(title: "Show on my map", sub: Market.showSub(shown),
                        isOn: Binding(get: { shown }, set: { on in
                            if step == .removed { sources.addPlugin(s.id); step = .idle } else { sources.setShown(s.id, on) }
                            model.markers.refresh(force: true)
                        }),
                        identifier: "plugin-installed")
        }
        .padding(.horizontal, 14)
    }

    private var mineBox: some View {
        HStack(alignment: .top, spacing: 10) {
            DGMoreIcon(name: "lock", size: 20, stroke: 2.2).foregroundStyle(DGTone.low.ink).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("Only you see this").font(DG.font(15, .bold)).foregroundStyle(DGTone.low.ink)
                Text("What this plugin shows follows the account that added it. It never reaches anyone else, and it never sees who else uses it.")
                    .font(DG.font(14.5)).foregroundStyle(DG.hex(0x23406f)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(DG.path.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DG.path.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private func iconTile(_ name: String) -> some View {
        DGMoreIcon(name: name, size: 19, stroke: 2.1).foregroundStyle(DG.path)
            .frame(width: 36, height: 36).background(DG.path.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func adds(_ s: FlareSource) -> some View {
        DGGroup(radius: 20) {
            DGRow(title: "On the map", sub: s.marketPurpose, chevron: false) { iconTile("map") }
            DGDivider(inset: 0)
            DGRow(title: "In alerts", sub: Market.inAlerts(tier: s.tier), chevron: false) { iconTile("bell") }
            DGDivider(inset: 0)
            DGRow(title: "Its marker", sub: "Plugins are rounded squares. Official alerts are round.", chevron: false) {
                iconTile("eye")
            } trailing: {
                HStack(spacing: 10) {
                    MarketPin(color: Color(PluginStyle.color(s.id)), icon: Market.glyph(kinds: s.kinds), square: true, size: 28)
                    MarketPin(color: DGTone.high.color, icon: "crash", square: false, size: 28)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 14)
    }

    private func uses(_ s: FlareSource) -> some View {
        let list = Market.uses(ownSession: s.ownSessionPath != nil, direct: s.isDirect, reports: s.acceptsReports)
        return DGGroup(radius: 20) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, u in
                if i > 0 { DGDivider(inset: 0) }
                DGRow(title: u.title, sub: u.sub, chevron: false) {
                    DGMoreIcon(name: u.allowed ? "check" : "nope", size: 16, stroke: u.allowed ? 2.8 : 2.4)
                        .foregroundStyle(u.allowed ? DGTone.good.ink : DG.sub)
                        .frame(width: 30, height: 30)
                        .background((u.allowed ? DGTone.good.color.opacity(0.1) : DG.ink.opacity(0.05)), in: Circle())
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func status(_ s: FlareSource) -> some View {
        let a = Market.answering(ok: s.ok, lastOk: s.lastOk)
        let onMap = model.allMarkers.filter { $0.kind == "plugin" && PluginStyle.sourceId($0) == s.id }.count
        return VStack(spacing: 0) {
            fact("Answering", a.text, color: a.good == true ? DGTone.good.ink : a.good == false ? DGTone.high.ink : DG.ink)
            if s.ok == false, let e = s.lastError { DGDivider(inset: 0); fact("Last error", e, color: DGTone.high.ink) }
            DGDivider(inset: 0)
            fact("On your map now", shown ? Market.alertsNow(onMap) : "None")
            DGDivider(inset: 0)
            fact("Checks for new data", Market.every(s.refreshS))
            if let v = s.version { DGDivider(inset: 0); fact("Version", v) }
            if let r = reach { DGDivider(inset: 0); fact("Reached from this phone", r) }
            DGDivider(inset: 0)
            Button { Task { await check() } } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView().controlSize(.small) } else { DGMoreIcon(name: "refresh", size: 17, stroke: 2.2) }
                    Text(checking ? "Checking" : "Check now").font(DG.font(15, .semibold))
                    Spacer()
                }
                .foregroundStyle(DG.path).padding(.horizontal, 14).frame(height: 46).contentShape(Rectangle())
            }
            .buttonStyle(DGPressStyle())
            .disabled(checking)
            .accessibilityIdentifier("plugin-check")
        }
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .padding(.horizontal, 14)
    }

    private func fact(_ k: String, _ v: String, color: Color = DG.ink) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(k).font(DG.font(14.5)).foregroundStyle(DG.sub)
            Spacer(minLength: 8)
            Text(v).font(DG.font(14.5, .semibold)).foregroundStyle(color).multilineTextAlignment(.trailing).lineLimit(3)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: acts

    @ViewBuilder private func acts(_ s: FlareSource) -> some View {
        HStack(spacing: 8) {
            switch step {
            case .removed:
                Button {} label: { Label { Text("Removed") } icon: { DGMoreIcon(name: "check", size: 19, stroke: 2.6) } }
                    .buttonStyle(.dgDone).disabled(true)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            case .confirm:
                Button("Keep it") { withAnimation(DG.snap) { step = .idle } }
                    .buttonStyle(.dgGlass).accessibilityIdentifier("plugin-keep")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                Button("Remove") {
                    sources.removePlugin(s.id)
                    model.markers.refresh(force: true)
                    withAnimation(DG.snap) { step = .removed }
                    // A forgotten private plugin has no page to stay on.
                    if s.tier == "private" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() } }
                }
                .buttonStyle(DangerButtonStyle(solid: true)).accessibilityIdentifier("plugin-remove-yes")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .idle:
                if sources.isAdded(s.id) {
                    Button { withAnimation(DG.snap) { step = .confirm } } label: {
                        Label { Text("Remove plugin") } icon: { DGMoreIcon(name: "trash", size: 19, stroke: 2.1) }
                    }
                    .buttonStyle(DangerButtonStyle(solid: false)).accessibilityIdentifier("plugin-remove")
                } else {
                    Button {
                        sources.addPlugin(s.id)
                        model.markers.refresh(force: true)
                    } label: {
                        Label { Text("Add plugin") } icon: { DGMoreIcon(name: "plus", size: 19, stroke: 2.4) }
                    }
                    .buttonStyle(.dgBlue).accessibilityIdentifier("plugin-add")
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 30)
        .background(Color.white.opacity(0.6).overlay(alignment: .top) { Rectangle().fill(DG.hair).frame(height: 1) })
        .onChange(of: step) { st in
            guard st == .removed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if step == .removed { withAnimation(DG.snap) { step = .idle } } }
        }
    }

    /// Ask the server for a fresh catalog (its own poll of the plugin),
    /// and reach the plugin's handshake straight from the phone.
    private func check() async {
        checking = true
        defer { checking = false }
        await sources.loadCatalog()
        if let base = source?.base, let url = URL(string: base + "/flare/v1/handshake") {
            let t0 = Date()
            if let (_, resp) = try? await Backend.session.data(from: url), let http = resp as? HTTPURLResponse {
                reach = http.statusCode == 200 ? String(format: "Yes, %.0f ms", Date().timeIntervalSince(t0) * 1000) : "Answered \(http.statusCode)"
            } else {
                reach = "No"
            }
        }
    }
}

/// The red pill: pale with a red ring to ask, solid red to confirm.
struct DangerButtonStyle: ButtonStyle {
    var solid: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DG.font(15.5, .semibold))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(solid ? .white : DGTone.high.ink)
            .background(solid ? DGTone.high.color : DGTone.high.color.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(solid ? .clear : DGTone.high.color.opacity(0.24), lineWidth: 1))
            .shadow(color: solid ? DGTone.high.color.opacity(0.45) : .clear, radius: 7, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DG.snap, value: configuration.isPressed)
    }
}
