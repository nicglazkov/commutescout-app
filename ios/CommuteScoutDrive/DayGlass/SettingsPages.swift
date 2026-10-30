import SwiftUI

// The Day Glass+ settings pages with logic of their own: map style,
// units and region, alerts, data sources and account. Their pure parts
// (feed health, API use, chips, summaries) are in SettingsLogic.swift.

// MARK: - Map style

/// Map style: a card per style, with a picture of it. The sheet comes
/// down while this page is open, so the real map above shows the pick.
struct MapStylePage: View {
    @EnvironmentObject var model: AppModel
    @Binding var detent: PresentationDetent

    private var prefs: Prefs { model.prefs }

    struct Look { var style: Prefs.MapStyle; var name: String; var about: String }

    /// In the website's order. Gray is the style stored as "outdoors".
    static let looks: [Look] = [
        Look(style: .positron, name: "Positron", about: "Soft and light, so alerts stand out"),
        Look(style: .bright, name: "Bright", about: "More color for roads, parks and water"),
        Look(style: .slate, name: "Slate", about: "Cool blue-gray, easy on the eyes"),
        Look(style: .outdoors, name: "Gray", about: "Neutral, with no color but alerts"),
    ]

    /// The look picked. The default is Positron, which the map draws
    /// dark when the app is dark.
    static func shown(_ s: Prefs.MapStyle, dark: Bool) -> Prefs.MapStyle {
        s == .auto ? .positron : s
    }

    static func name(_ s: Prefs.MapStyle, dark: Bool) -> String {
        let v = shown(s, dark: dark)
        return looks.first { $0.style == v }?.name ?? "Positron"
    }

    var body: some View {
        DGPage(title: "Map style", identifier: "page-map-style") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Self.looks, id: \.name) { l in card(l) }
            }
            .padding(.top, 6)
            DGFootnote("The map above shows the style you pick. Alerts, your route and the car look the same in every style.")
            DGSectionLabel("Light and dark")
            DGSegmented(options: [(Prefs.Theme.system, "Match my phone", nil), (.light, "Light", nil), (.dark, "Dark", nil)],
                        selection: Binding(get: { prefs.theme }, set: { prefs.theme = $0 }), identifier: "theme")
            DGFootnote("Positron, the default style, turns dark when the app is dark.")
        }
        .onAppear { withAnimation(DG.spring) { detent = SettingsSheet.peek } }
        .onDisappear { withAnimation(DG.spring) { detent = .large } }
    }

    private func card(_ l: Look) -> some View {
        let on = Self.shown(prefs.mapStyle, dark: model.isDark) == l.style
        return Button {
            // Positron is the default: picking it goes back to following the phone.
            withAnimation(DG.snap) { prefs.mapStyle = l.style == .positron ? .auto : l.style }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail(l.style.flavor(dark: false))
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 96).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(l.name).font(DG.font(16, .semibold)).foregroundStyle(DG.ink)
                        if l.style == .positron { Text("Default").font(DG.font(12, .semibold)).foregroundStyle(DG.sub) }
                        Spacer(minLength: 0)
                        if on { DGCheck(on: true, size: 22) }
                    }
                    Text(l.about).font(DG.font(13)).foregroundStyle(DG.sub).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .top)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(on ? DG.path : DG.hair, lineWidth: on ? 2 : 1))
            .shadow(color: DG.ink.opacity(on ? 0.1 : 0.04), radius: on ? 10 : 6, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityIdentifier("mapstyle-\(l.style.rawValue)")
        .accessibilityLabel(l.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func thumbnail(_ flavor: String) -> Image {
        let url = Bundle.main.resourceURL!.appendingPathComponent("Map/thumbs/\(flavor).webp")
        if let img = UIImage(contentsOfFile: url.path) { return Image(uiImage: img) }
        return Image(systemName: "map")
    }
}

// MARK: - Units and region

struct UnitsPage: View {
    @EnvironmentObject var model: AppModel
    /// Bumped on every change so the page reads the new values.
    @State private var tick = 0

    private var d: UserDefaults { .standard }

    var body: some View {
        let _ = tick
        DGPage(title: "Units and region", identifier: "page-units") {
            preview.padding(.top, 8)
            group("Distance", key: "cs.units", match: (Units.phoneMiles ? "Miles" : "Kilometers") + ", from your region",
                  choices: [("mi", "Miles"), ("km", "Kilometers")], id: "units")
            group("Clock", key: Units.clockKey, match: (Units.phone24h ? "24-hour" : "12-hour") + ", from your region",
                  choices: [("12", "12-hour"), ("24", "24-hour")], id: "clock")
            group("Temperature", key: Units.temperatureKey, match: (Units.phoneMiles ? "Fahrenheit" : "Celsius") + ", from your region",
                  choices: [("f", "Fahrenheit"), ("c", "Celsius")], id: "temp")
            DGFootnote("Units are used on the map, in directions and in spoken alerts.")
        }
    }

    /// How the app reads now: a distance, a time and a temperature.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How the app reads").font(DG.font(13, .semibold)).foregroundStyle(DG.inkColor(.low))
            HStack(alignment: .top, spacing: 22) {
                sample(Units.distance(Units.useMiles ? 644 : 600), "Next turn")
                sample(Units.time(Self.sampleArrival), "Arrival")
                sample(Units.temperature(celsius: -0.5), "Pavement")
                Spacer(minLength: 0)
            }
            Text("Your phone is set to \(Self.phoneLocale).").font(DG.font(13)).foregroundStyle(DG.sub)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DG.path.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DG.path.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("units-preview")
    }

    private func sample(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(DG.font(22, .bold)).foregroundStyle(DG.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(DG.font(12)).foregroundStyle(DG.sub)
        }
    }

    static var sampleArrival: Date {
        Calendar.current.date(bySettingHour: 8, minute: 42, second: 0, of: Date()) ?? Date()
    }

    /// "English, United States".
    static var phoneLocale: String {
        let l = Locale.current
        let en = Locale(identifier: "en_US")
        let lang = l.language.languageCode.flatMap { en.localizedString(forLanguageCode: $0.identifier) } ?? "English"
        let region = l.region.flatMap { en.localizedString(forRegionCode: $0.identifier) }
        return region.map { "\(lang), \($0)" } ?? lang
    }

    private func group(_ title: String, key: String, match: String, choices: [(String, String)], id: String) -> some View {
        let current = d.string(forKey: key) ?? ""
        let isMatch = !choices.contains { $0.0 == current }
        return VStack(alignment: .leading, spacing: 0) {
            DGSectionLabel(title)
            DGGroup {
                DGRadioRow(title: "Match my phone", sub: match, on: isMatch, identifier: "\(id)-phone") { set(key, nil) }
                ForEach(choices, id: \.0) { c in
                    DGDivider(inset: 14)
                    DGRadioRow(title: c.1, on: current == c.0, identifier: "\(id)-\(c.0)") { set(key, c.0) }
                }
            }
        }
    }

    private func set(_ key: String, _ value: String?) {
        if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        if key == "cs.units" { model.prefs.unitsRaw = value ?? "" }
        model.prefs.objectWillChange.send()
        withAnimation(DG.snap) { tick += 1 }
    }
}

// MARK: - Alerts

struct AlertsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        AlertsContent(prefs: model.prefs, sources: model.sources)
    }
}

private struct AlertsContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var prefs: Prefs
    @ObservedObject var sources: SourcesStore

    private static let plug = DG.hex(0x7c5cf0)
    private static let plugInk = DG.hex(0x5a3cc8)

    /// The plugins whose alerts can reach this driver: the installed ones.
    private var plugins: [FlareSource] {
        sources.catalog.filter { sources.isOn($0.id) } + sources.mine
    }

    var body: some View {
        DGPage(title: "Alerts", identifier: "page-alerts") {
            DGGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerts reach you by").font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    DGSegmented(options: [(AlertDelivery.voice, "Voice", "speaker.wave.2"), (.sound, "Sound", "bell"), (.silent, "Silent", nil)],
                                selection: Binding(get: { prefs.alertDelivery }, set: { prefs.alertDelivery = $0 }),
                                identifier: "alert-delivery")
                }
                .padding(14)
                DGDivider(inset: 0)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Warn me ahead by").font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                        Spacer()
                        Text(prefs.advancedAlerts ? "Set for each kind" : "On your route").font(DG.font(13)).foregroundStyle(DG.sub)
                    }
                    DGSegmented(options: AlertChips.aheadSteps(miles: Units.useMiles).map { ($0.meters, $0.label, nil) },
                                selection: Binding(get: { AlertChips.nearestStep(prefs.alertAheadMeters, miles: Units.useMiles) },
                                                   set: { prefs.alertAheadMeters = $0; prefs.objectWillChange.send() }),
                                identifier: "alert-ahead")
                        .disabled(prefs.advancedAlerts).opacity(prefs.advancedAlerts ? 0.5 : 1)
                }
                .padding(14)
            }
            .padding(.top, 8)

            DGSectionLabel("Official alerts")
            DGGroup {
                ForEach(Array(AlertChips.tiers.enumerated()), id: \.offset) { i, tier in
                    if i > 0 { DGDivider(inset: 0) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Circle().fill(Self.tone(i).color).frame(width: 7, height: 7)
                            Text(tier.label).font(DG.font(14, .semibold)).foregroundStyle(DG.ink.opacity(0.85))
                        }
                        DGFlow(spacing: 8) {
                            ForEach(tier.chips, id: \.key) { c in chip(c, tone: Self.tone(i)) }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            DGFootnote("From state DOTs, 511 feeds, CHP, the National Weather Service and fire agencies. A kind you turn off still shows on the map.")

            DGSectionLabel("Plugin alerts", trailing: AnyView(DGTag(text: "Not official", systemImage: "puzzlepiece.extension.fill", color: Self.plug)))
            DGGroup(tint: Self.plug.opacity(0.05)) {
                if plugins.isEmpty {
                    Text("No plugin is installed. Plugins you install from the marketplace list here.")
                        .font(DG.font(14)).foregroundStyle(DG.sub).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(plugins) { p in
                    DGSwitchRow(title: p.name, sub: p.kinds.isEmpty ? nil : p.kindsLabel.prefix(1).uppercased() + p.kindsLabel.dropFirst(),
                                isOn: Binding(get: { !prefs.pluginAlertsOff.contains(p.id) },
                                              set: { on in var s = prefs.pluginAlertsOff; if on { s.remove(p.id) } else { s.insert(p.id) }; prefs.pluginAlertsOff = s }),
                                identifier: "plugin-alerts-\(p.id)") {
                        PluginBadge(sourceId: p.id, category: p.oneCategory, size: 30)
                    }
                    DGDivider()
                }
                DGSwitchRow(title: "Speak plugin alerts", sub: "Off by default. Plugin alerts chime instead.",
                            isOn: Binding(get: { prefs.speakPluginAlerts }, set: { prefs.speakPluginAlerts = $0; prefs.objectWillChange.send() }),
                            identifier: "speak-plugin-alerts") {
                    DGTile(symbol: "speaker.wave.2.fill", color: Self.plug, size: 30)
                }
                .tint(Self.plug)
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Self.plug.opacity(0.18), lineWidth: 1))
            DGFootnote("Plugin alerts appear as badges in the plugin's own color, never in the official colors, so you can always tell them apart.")

            DGGroup {
                NavigationLink { AdvancedAlertsView() } label: {
                    DGRow(title: "Set warnings for each kind", sub: "A first and second warning and a voice per kind",
                          value: prefs.advancedAlerts ? "On" : "Off") { EmptyView() }
                }
                .buttonStyle(DGRowPress())
                .accessibilityIdentifier("advanced-alerts")
            }
            .padding(.top, 20)
        }
        .task { await sources.loadCatalog() }
    }

    static func tone(_ tier: Int) -> DGTone { tier == 0 ? .high : tier == 1 ? .mid : .low }

    private func chip(_ c: AlertChips.Chip, tone: DGTone) -> some View {
        let on = !prefs.alertChipsOff.contains(c.key)
        return Button {
            withAnimation(DG.snap) {
                var s = prefs.alertChipsOff
                if on { s.insert(c.key) } else { s.remove(c.key) }
                prefs.alertChipsOff = s
            }
        } label: {
            HStack(spacing: 8) {
                DGIconView(name: c.key, size: 15, stroke: 2.3)
                    .foregroundStyle(on ? .white : DG.faint)
                    .frame(width: 26, height: 26)
                    .background(on ? tone.color : DG.ink.opacity(0.05), in: Circle())
                Text(c.label).font(DG.font(15, .semibold)).foregroundStyle(on ? DG.ink : DG.faint)
            }
            .padding(.leading, 5).padding(.trailing, 13).frame(height: 36)
            .background(on ? tone.color.opacity(0.1) : Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? tone.color.opacity(0.28) : DG.hair, lineWidth: 1))
        }
        .buttonStyle(DGPressStyle())
        .accessibilityIdentifier("chip-\(c.key)")
        .accessibilityLabel(c.label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Lays its children out in rows, wrapping when a row is full.
struct DGFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let h = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            var r = rows[rows.count - 1]
            if !r.items.isEmpty, r.width + spacing + s.width > width {
                let y = r.y + r.height + spacing
                rows.append(Row(y: y))
                r = rows[rows.count - 1]
            }
            r.width += (r.items.isEmpty ? 0 : spacing) + s.width
            r.height = max(r.height, s.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

// MARK: - Data sources

/// The app's copy of /api/sources, fetched when Settings opens and on Refresh.
@MainActor
final class SourcesHealthStore: ObservableObject {
    static let shared = SourcesHealthStore()

    @Published private(set) var report: SourcesReport?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    private var fetchedAt: Date?

    func refresh(force: Bool = false) async {
        if busy { return }
        if !force, let f = fetchedAt, Date().timeIntervalSince(f) < 60 { return }
        busy = true
        defer { busy = false }
        do {
            var req = URLRequest(url: Backend.base.appendingPathComponent("api/sources"))
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await Backend.session.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200, let r = SourcesHealth.parse(data) {
                report = r
                failed = false
                fetchedAt = Date()
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}

enum SourcesUI {
    static func color(_ s: FeedStatus) -> Color {
        switch s {
        case .fresh, .live: DG.color(.good)
        case .stale: DG.color(.mid)
        case .down: DG.color(.high)
        case .off: DG.faint
        }
    }

    static func ink(_ s: FeedStatus) -> Color {
        switch s {
        case .fresh, .live: DG.inkColor(.good)
        case .stale: DG.inkColor(.mid)
        case .down: DG.inkColor(.high)
        case .off: DG.sub
        }
    }
}

struct DataSourcesPage: View {
    @ObservedObject private var store = SourcesHealthStore.shared

    var body: some View {
        DGPage(title: "Data sources", identifier: "page-data-sources") {
            healthCard.padding(.top, 8)
            if let r = store.report {
                if !r.national.isEmpty {
                    DGSectionLabel("National")
                    DGGroup { rows(r.national) }
                }
                if !r.stateRows.isEmpty {
                    DGSectionLabel("States")
                    DGGroup { rows(r.stateRows) }
                }
            }
            DGFootnote("Fresh means updated within the feed's normal interval. Stale means late. Down means the agency is not answering, so the map keeps its last data and marks it.")
        }
        .task { await store.refresh() }
    }

    private var checkedText: String {
        if store.busy { return "Checking every feed" }
        if let r = store.report {
            if let at = r.checkedAt {
                return Date().timeIntervalSince(at) < 60 ? "Checked just now" : "Checked at " + Units.time(at)
            }
            return "Checked just now"
        }
        return store.failed ? "Could not reach CommuteScout. Try again." : "Checking every feed"
    }

    private var healthCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "globe.americas.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(SourcesUI.color(store.report?.worst ?? .fresh), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.report?.coverage ?? "Every state").font(DG.font(17, .semibold)).foregroundStyle(DG.ink)
                    Text(checkedText).font(DG.font(13)).foregroundStyle(DG.sub)
                }
                Spacer()
                Button { Task { await store.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .bold)).foregroundStyle(DG.inkColor(.low))
                        .rotationEffect(.degrees(store.busy ? 360 : 0))
                        .animation(store.busy ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.busy)
                        .frame(width: 42, height: 42).background(DG.path.opacity(0.1), in: Circle())
                }
                .buttonStyle(DGPressStyle())
                .accessibilityLabel("Refresh")
                .accessibilityIdentifier("sources-refresh")
            }
            HStack(spacing: 8) {
                count(store.report?.fresh, "Fresh", .good)
                count(store.report?.stale, "Stale", .mid)
                count(store.report?.down, "Down", .high)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .shadow(color: DG.ink.opacity(0.04), radius: 8, y: 2)
    }

    private func count(_ n: Int?, _ label: String, _ tone: DGTone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n.map(String.init) ?? "–").font(DG.font(22, .bold)).foregroundStyle(tone.ink).monospacedDigit()
            Text(label).font(DG.font(13)).foregroundStyle(DG.sub)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tone.color.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sources-count-\(label.lowercased())")
    }

    @ViewBuilder private func rows(_ list: [FeedRow]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { i, row in
            if i > 0 { DGDivider(inset: 56) }
            HStack(spacing: 12) {
                Text(row.code).font(DG.font(13, .bold)).foregroundStyle(DG.sub)
                    .frame(width: 32, height: 32).background(DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(DG.font(16, .medium)).foregroundStyle(DG.ink).lineLimit(1)
                    if !row.by.isEmpty { Text(row.by).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1) }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(SourcesUI.color(row.status)).frame(width: 7, height: 7)
                        Text(row.status == .live ? "Fresh" : row.status.word).font(DG.font(14, .semibold)).foregroundStyle(SourcesUI.ink(row.status))
                    }
                    Text(SourcesHealth.ageText(row)).font(DG.font(13)).foregroundStyle(DG.faint).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 56)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Account

/// Today's API use for the signed-in account.
@MainActor
final class AccountUsageStore: ObservableObject {
    @Published private(set) var usage: ApiUsage?
    @Published private(set) var failed = false

    func load(_ account: Account) async {
        guard account.signedIn, let t = await account.token() else { usage = nil; return }
        do {
            let (code, data) = try await Backend.send("GET", "api/keys", token: t)
            if code == 200, let u = ApiUsage.parse(data) { usage = u; failed = false } else { failed = true }
        } catch {
            failed = true
        }
    }
}

struct AccountPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View { AccountContent(account: model.account) }
}

private struct AccountContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var account: Account
    @StateObject private var store = AccountUsageStore()
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        DGPage(title: "Account", identifier: "page-account") {
            DGGroup {
                AccountCard(account: account, chevron: false, framed: false)
                DGDivider(inset: 0)
                if account.signedIn {
                    Button { confirmSignOut = true } label: {
                        DGRow(title: "Sign out") { DGTile(symbol: "rectangle.portrait.and.arrow.right", color: DG.hex(0x8a94a6)) }
                    }
                    .buttonStyle(DGRowPress())
                    .accessibilityIdentifier("account-sign-out")
                } else {
                    Button("Sign in") { showSignIn = true }
                        .buttonStyle(.dgPrimary).padding(14)
                        .accessibilityIdentifier("account-sign-in")
                }
            }
            .padding(.top, 8)
            DGFootnote(account.signedIn
                       ? "Signing out clears your places, watch areas and plugin data from this phone. They stay in your account. You can always drive without signing in."
                       : "The same account as commutescout.com. You can always drive without signing in.")

            DGSectionLabel("Your account adds")
            DGGroup {
                perk("Reports from the road", "Tell other drivers what you see", "exclamationmark.bubble.fill", 0x2f7cf6)
                DGDivider()
                perk("Watch areas on every device", "Synced with the website and your other phones", "eye.fill", 0x0f9a9a)
                DGDivider()
                perk("Plugins", "Install them once, use them anywhere", "puzzlepiece.extension.fill", 0x7c5cf0)
                DGDivider()
                perk("API keys", "For your own apps and scripts", "key.fill", 0xee8b0c)
            }

            if !account.signedIn {
                DGFootnote("Without a key, the API allows 10,000 requests a day from each address. " + ApiUsage.footnote)
            }
            if account.signedIn {
                DGSectionLabel("API use today")
                usageCard
                DGFootnote(ApiUsage.footnote)

                DGGroup {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete account").font(DG.font(16, .medium)).foregroundStyle(DG.inkColor(.high))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(minHeight: 54)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DGRowPress())
                    .accessibilityIdentifier("account-delete")
                }
                .padding(.top, 20)
                DGFootnote("Deleting removes your watch areas, API keys and reports for good.")
            }
        }
        .task(id: account.signedIn) { await store.load(account) }
        .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to report, keep watch areas and manage API keys.") }
        .confirmationDialog("Sign out on this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your places, watch areas and plugin data are cleared from this phone. They stay in your account.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { _ = await account.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your watch areas, API keys and reports for good. It cannot be undone.")
        }
    }

    private func perk(_ title: String, _ sub: String, _ symbol: String, _ color: UInt32) -> some View {
        DGRow(title: title, sub: sub, chevron: false, leading: { DGTile(symbol: symbol, color: DG.hex(color)) }, trailing: {
            if account.signedIn {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(DG.color(.good))
            }
        })
        .padding(.vertical, 4)
    }

    private var usageCard: some View {
        let u = store.usage
        return DGGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Requests").font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    Spacer()
                    if let u {
                        (Text(u.usedText).font(DG.font(15, .bold)).foregroundColor(u.full ? DG.inkColor(.high) : DG.ink)
                         + Text(" " + u.limitText).font(DG.font(15)).foregroundColor(DG.sub))
                    } else if store.failed {
                        Text("Not available").font(DG.font(15)).foregroundStyle(DG.sub)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DG.ink.opacity(0.06))
                        Capsule().fill(LinearGradient(colors: u?.full == true ? [DG.color(.high)] : [DG.hex(0x5fa0ff), DG.path],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(u?.requests ?? 0 > 0 ? 8 : 0, g.size.width * (u?.fraction ?? 0)))
                    }
                }
                .frame(height: 8)
                .animation(DG.easeOut, value: u?.fraction ?? 0)
            }
            .padding(14)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("api-usage")
            DGDivider(inset: 0)
            HStack(spacing: 0) {
                limitCell(u?.keylessDaily.map(ApiUsage.n) ?? "10,000", "a day per address, no key", tint: DG.ink)
                Rectangle().fill(DG.hair).frame(width: 1)
                limitCell(ApiUsage.n(u?.limit ?? ApiUsage.freeDaily), u?.tierText ?? "a day with a free key", tint: DG.inkColor(.low))
            }
            .fixedSize(horizontal: false, vertical: true)
            DGDivider(inset: 0)
            Link(destination: URL(string: "https://commutescout.com/watch")!) {
                DGRow(title: "Manage API keys", value: u?.keysText) { EmptyView() }
            }
            .buttonStyle(DGRowPress())
            .accessibilityIdentifier("manage-api-keys")
        }
    }

    private func limitCell(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DG.font(19, .bold)).foregroundStyle(tint)
            Text(label).font(DG.font(13)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
