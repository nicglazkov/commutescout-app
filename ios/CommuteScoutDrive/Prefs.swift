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

    enum MapStyle: String, CaseIterable, Identifiable {
        case auto, light, dark, outdoors
        var id: String { rawValue }
        var label: String { switch self { case .auto: "Match theme"; case .light: "Light"; case .dark: "Dark"; case .outdoors: "Outdoors" } }
        /// The server's style name for this choice in the given appearance.
        func serverStyle(dark isDark: Bool) -> String {
            switch self {
            case .auto: isDark ? "alidade_smooth_dark" : "alidade_smooth"
            case .light: "alidade_smooth"
            case .dark: "alidade_smooth_dark"
            case .outdoors: "outdoors"
            }
        }
    }

    /// The marker kinds the map can show, in the order of the Layers sheet.
    static let layerKinds: [(key: String, label: String, api: String)] = [
        ("incident", "Incidents", "incident"),
        ("lane_closure", "Closures and lane work", "closure"),
        ("chain_control", "Chain controls", "chain"),
        ("wildfire", "Wildfires", "fire"),
        ("plugin", "Community reports", "plugin"),
    ]

    @AppStorage("cs.theme") var themeRaw: String = Theme.system.rawValue
    @AppStorage("cs.mapstyle") var mapStyleRaw: String = MapStyle.auto.rawValue
    @AppStorage("cs.3d") var is3D: Bool = true
    @AppStorage("cs.traffic") var traffic: Bool = false
    @AppStorage("cs.layers.off") var layersOff: String = ""      // comma-separated kinds hidden
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

    /// How one kind of alert is announced: at what distance, whether it
    /// repeats closer, and whether it is spoken at all. The advanced
    /// mode edits these per kind; the simple mode uses one distance.
    struct AlertRule: Codable, Equatable {
        var enabled = true
        var speak = true
        var firstMeters = 1500.0
        var repeatMeters = 0.0       // 0 = no second warning
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
        if !advancedAlerts { return AlertRule(enabled: true, speak: spokenAlerts, firstMeters: alertAheadMeters, repeatMeters: 0) }
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
        get { MapStyle(rawValue: mapStyleRaw) ?? .auto }
        set { mapStyleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var hiddenKinds: Set<String> {
        get { Set(layersOff.split(separator: ",").map(String.init)) }
        set { layersOff = newValue.sorted().joined(separator: ","); objectWillChange.send() }
    }

    func isShown(_ kind: String) -> Bool { !hiddenKinds.contains(kind) }

    func setShown(_ kind: String, _ on: Bool) {
        var h = hiddenKinds
        if on { h.remove(kind) } else { h.insert(kind) }
        hiddenKinds = h
    }

    /// The kinds parameter for /api/mapdata for what is switched on.
    var apiKinds: String {
        Self.layerKinds.filter { isShown($0.key) }.map(\.api).joined(separator: ",")
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
