import Combine
import Foundation
import SwiftUI

/// Everything a driver can set. Stored per device in UserDefaults; the
/// keys are stable so nothing is lost across updates.
@MainActor
final class Prefs: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
        var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    }

    /// The same base maps the website offers, in its order. Positron and
    /// Bright are OpenFreeMap's styles, read from its tiles while online;
    /// without a signal the map falls back to Light, drawn from the file
    /// saved on the phone. The other four are CommuteScout's own styles,
    /// drawn from CommuteScout's file online and from the saved one
    /// offline. "outdoors" is the old raw value for Grayscale, kept so a
    /// saved choice still reads.
    enum MapStyle: String, CaseIterable, Identifiable {
        case auto, positron, bright, slate, outdoors
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: "Match theme"; case .positron: "Positron"; case .bright: "Bright"; case .slate: "Slate"
            case .outdoors: "Grayscale"
            }
        }
        /// The bundled style for this choice in the given appearance.
        func flavor(dark isDark: Bool) -> String {
            switch self {
            case .auto: isDark ? "dark" : "positron"
            case .positron: "positron"
            case .bright: "bright"
            case .slate: "slate"
            case .outdoors: "grayscale"
            }
        }
        /// Whether this style needs a signal (its tiles are OpenFreeMap's).
        var online: Bool { self == .positron || self == .bright }
    }

    /// The marker kinds the map can show, in the order of the Layers
    /// sheet, with the name /api/mapdata knows each by. Query name and
    /// emitted kind differ for three of them: `closure` comes back as
    /// `lane_closure`, `chain` as `chain_control` and `fire` as
    /// `wildfire`. The other six use one name on both sides.
    static let layerKinds: [(key: String, label: String, api: String)] = [
        ("incident", "Incidents", "incident"),
        ("lane_closure", "Closures and lane work", "closure"),
        ("chain_control", "Chain controls", "chain"),
        ("rwis", "Weather stations", "rwis"),
        ("wildfire", "Wildfires", "fire"),
        ("toll", "Toll prices", "toll"),
        ("plugin", "Plugin alerts", "plugin"),
        ("camera", "Cameras", "camera"),
        ("sign", "Message signs", "sign"),
    ]

    /// The layers a new install starts with switched off, the same two
    /// the website leaves unchecked. Cameras are the densest layer by
    /// far, and toll lines run along the road where most driving
    /// happens. Everything else starts on.
    static let layersOffByDefault = "camera,toll"

    @AppStorage("cs.theme") var themeRaw: String = Theme.system.rawValue
    @AppStorage("cs.mapstyle") var mapStyleRaw: String = MapStyle.auto.rawValue
    @AppStorage("cs.3d") var is3D: Bool = false   // 2D until the driver picks 3D
    /// Save the map along a route when a trip starts, on Wi-Fi.
    @AppStorage("cs.map.autosave") var mapAutoSave: Bool = true
    @AppStorage("cs.traffic") var traffic: Bool = false
    @AppStorage("cs.layers.off") var layersOff: String = Prefs.layersOffByDefault   // comma-separated kinds hidden
    @AppStorage("cs.layers.sources") var sourceFilterRaw: String = "all"
    @AppStorage("cs.spokenalerts") var spokenAlerts: Bool = true
    @AppStorage("cs.alertahead") var alertAheadMeters: Double = 1500
    @AppStorage("cs.speedlimit") var showSpeedLimit: Bool = true
    @AppStorage("cs.keepawake") var keepAwake: Bool = true
    @AppStorage("cs.avoid.tolls") var avoidTolls: Bool = false
    @AppStorage("cs.avoid.highways") var avoidHighways: Bool = false
    @AppStorage("cs.avoid.ferries") var avoidFerries: Bool = false
    @AppStorage("cs.units") var unitsRaw: String = ""              // "", "mi" or "km"
    @AppStorage("cs.alerts.rules") var alertRulesRaw: String = ""   // JSON, per kind
    @AppStorage("cs.alerts.advanced") var advancedAlerts: Bool = false
    @AppStorage("cs.alerts.strip") var stripAheadMeters: Double = 16093   // the strip shows the next alert within this
    /// The voice for everything spoken, by identifier; "" picks the best
    /// installed one. Speed and pitch on AVSpeechUtterance's own scales.
    /// `Voice` reads the same keys.
    @AppStorage(Voice.idKey) var voiceId: String = ""
    @AppStorage(Voice.rateKey) var voiceRate: Double = Voice.defaultRate
    @AppStorage(Voice.pitchKey) var voicePitch: Double = Voice.defaultPitch

    /// How one kind of alert is announced: at what distance, whether it
    /// repeats closer, and whether it is spoken at all. The advanced
    /// mode edits these per kind; the simple mode uses one distance.
    struct AlertRule: Codable, Equatable {
        var enabled = true
        var speak = true
        var firstMeters = 1500.0
        var repeatMeters = 0.0       // 0 = no second warning
        /// A short chime when it is not spoken (the Sound delivery, and
        /// plugin alerts that are not spoken). Never stored.
        var chime = false

        init(enabled: Bool = true, speak: Bool = true, firstMeters: Double = 1500, repeatMeters: Double = 0, chime: Bool = false) {
            self.enabled = enabled; self.speak = speak; self.firstMeters = firstMeters
            self.repeatMeters = repeatMeters; self.chime = chime
        }

        private enum CodingKeys: String, CodingKey { case enabled, speak, firstMeters, repeatMeters }

        /// Tolerant: a rule saved by an older build, or missing a field, still reads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            speak = try c.decodeIfPresent(Bool.self, forKey: .speak) ?? true
            firstMeters = try c.decodeIfPresent(Double.self, forKey: .firstMeters) ?? 1500
            repeatMeters = try c.decodeIfPresent(Double.self, forKey: .repeatMeters) ?? 0
        }
    }

    /// How alerts reach the driver. Unset, it follows the old "speak
    /// road alerts" switch: on is Voice, off is Silent.
    @AppStorage("cs.alerts.delivery") var alertDeliveryRaw: String = ""
    /// Official alert chips that do not alert, by AlertChips key. Their
    /// markers still show on the map.
    @AppStorage("cs.alerts.chips.off") var alertChipsOffRaw: String = AlertChips.offByDefault.sorted().joined(separator: ",")
    /// Plugins, by source id, whose alerts do not alert.
    @AppStorage("cs.alerts.plugins.off") var pluginAlertsOffRaw: String = ""
    /// Plugin alerts are spoken too; off, they chime.
    @AppStorage("cs.alerts.plugins.speak") var speakPluginAlerts: Bool = false
    /// The first run is done or skipped.
    @AppStorage("cs.welcome.done") var welcomeDone: Bool = false

    var alertDelivery: AlertDelivery {
        get { AlertDelivery(rawValue: alertDeliveryRaw) ?? (spokenAlerts ? .voice : .silent) }
        set { alertDeliveryRaw = newValue.rawValue; spokenAlerts = newValue == .voice; objectWillChange.send() }
    }

    var alertChipsOff: Set<String> {
        get { Set(alertChipsOffRaw.split(separator: ",").map(String.init)) }
        set { alertChipsOffRaw = newValue.sorted().joined(separator: ","); objectWillChange.send() }
    }

    var pluginAlertsOff: Set<String> {
        get { Set(pluginAlertsOffRaw.split(separator: ",").map(String.init)) }
        set { pluginAlertsOffRaw = newValue.sorted().joined(separator: ","); objectWillChange.send() }
    }

    /// Whether the first run should show, decided once at launch: never
    /// on an install that was set up before it existed, and never in a
    /// test run ("-cs..." arguments) unless "-csWelcome" asks for it.
    static let welcomeIsDue: Bool = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-csWelcome") { return true }
        if args.contains(where: { $0.hasPrefix("-cs") }) { return false }
        let d = UserDefaults.standard
        let others = d.dictionaryRepresentation().keys.contains { $0.hasPrefix("cs.") && $0 != "cs.welcome.done" }
        return WelcomeStep.shouldShow(done: d.bool(forKey: "cs.welcome.done"), hasOtherPrefs: others)
    }()

    /// One marker's rule after the Alerts page: its kind's rule, then the
    /// chips, the plugin switches and the delivery.
    func ruleFor(_ m: RoadMarker) -> AlertRule {
        var r = rule(for: Self.ruleKind(for: m))
        let plugin = m.kind == "plugin"
        let chip = plugin ? "" : AlertChips.key(forKind: DGKind(marker: m).rawValue)
        let o = AlertChips.apply(enabled: r.enabled, speak: r.speak, plugin: plugin,
                                 chipOff: alertChipsOff.contains(chip),
                                 pluginOff: plugin && pluginAlertsOff.contains(PluginStyle.sourceId(m)),
                                 delivery: alertDelivery, speakPlugins: speakPluginAlerts)
        r.enabled = o.enabled; r.speak = o.speak; r.chime = o.chime
        return r
    }

    /// The kinds a rule can be set for: the road data kinds plus the
    /// community report groups drivers care about most.
    static let alertKinds: [(key: String, label: String)] = [
        ("incident", "Incidents"),
        ("lane_closure", "Closures and lane work"),
        ("chain_control", "Chain controls"),
        ("wildfire", "Wildfires"),
        ("police", "Police reports"),
        ("hazard", "Hazard and crash reports"),
        ("plugin", "Other community reports"),
    ]

    var alertRules: [String: AlertRule] {
        get {
            guard let d = alertRulesRaw.data(using: .utf8), let r = try? JSONDecoder().decode([String: AlertRule].self, from: d) else { return [:] }
            return r
        }
        set {
            if let d = try? JSONEncoder().encode(newValue), let s = String(data: d, encoding: .utf8) { alertRulesRaw = s }
            objectWillChange.send()
        }
    }

    func rule(for kind: String) -> AlertRule {
        if !advancedAlerts { return AlertRule(enabled: true, speak: true, firstMeters: alertAheadMeters, repeatMeters: 0) }
        return alertRules[kind] ?? AlertRule()
    }

    func setRule(_ r: AlertRule, for kind: String) {
        var all = alertRules
        all[kind] = r
        alertRules = all
    }

    /// The rule group for a marker: community reports split by what they are.
    static func ruleKind(for m: RoadMarker) -> String {
        if m.kind == "plugin" {
            let k = (m.flareKind ?? "").uppercased()
            if k.hasPrefix("POLICE") { return "police" }
            if k.hasPrefix("HAZARD") || k.hasPrefix("CRASH") { return "hazard" }
            return "plugin"
        }
        return m.kind
    }

    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var mapStyle: MapStyle {
        get { MapStyle(rawValue: MapStyleChoice.stored(mapStyleRaw)) ?? .auto }
        set { mapStyleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var hiddenKinds: Set<String> {
        get { Set(layersOff.split(separator: ",").map(String.init)) }
        set { layersOff = newValue.sorted().joined(separator: ","); objectWillChange.send() }
    }

    /// Official sources, plugins, or both: one choice over the layer
    /// switches, which keep what they were set to.
    enum SourceFilter: String, CaseIterable, Identifiable {
        case all, official, plugins
        var id: String { rawValue }
        var label: String { switch self { case .all: "Everything"; case .official: "Official"; case .plugins: "Plugins" } }
        func allows(_ kind: String) -> Bool {
            switch self { case .all: true; case .official: kind != "plugin"; case .plugins: kind == "plugin" }
        }
    }

    var sourceFilter: SourceFilter {
        get { SourceFilter(rawValue: sourceFilterRaw) ?? .all }
        set { sourceFilterRaw = newValue.rawValue; objectWillChange.send() }
    }

    /// The layer's own switch, whatever the source filter says.
    func isChosen(_ kind: String) -> Bool { !hiddenKinds.contains(kind) }

    /// Whether the kind is drawn: its switch is on and the filter lets it through.
    func isShown(_ kind: String) -> Bool { isChosen(kind) && sourceFilter.allows(kind) }

    func setShown(_ kind: String, _ on: Bool) {
        var h = hiddenKinds
        if on { h.remove(kind) } else { h.insert(kind) }
        hiddenKinds = h
    }

    /// The kinds parameter for /api/mapdata for what is switched on.
    var apiKinds: String {
        Self.layerKinds.filter { isShown($0.key) }.map(\.api).joined(separator: ",")
    }

    /// The kind a marker comes back as, from the name it was asked by.
    static func emittedKind(_ api: String) -> String {
        layerKinds.first { $0.api == api }?.key ?? api
    }

    /// Valhalla costing options from the route settings; empty when defaults.
    var costingOptions: [String: Any] {
        var auto: [String: Any] = [:]
        if avoidTolls { auto["use_tolls"] = 0 }
        if avoidHighways { auto["use_highways"] = 0 }
        if avoidFerries { auto["use_ferry"] = 0 }
        return auto.isEmpty ? [:] : ["auto": auto]
    }

    /// A fingerprint of everything that changes how routes are asked for.
    var routingKey: String { "\(avoidTolls)|\(avoidHighways)|\(avoidFerries)|\(Units.useMiles)" }
}
