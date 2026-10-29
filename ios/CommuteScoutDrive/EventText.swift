import Foundation

/// What an event card says, worked out from a marker without any view
/// code, so it can be tested. The rules and the words come from the
/// website's popups (`popupFor` in the web map's map-app.js): the phone
/// shows the same detail the desktop does, laid out for a phone.
struct EventContent: Equatable {
    struct Fact: Equatable, Hashable { let label: String; let value: String }
    /// A plain sentence, or a quieter explanation of one.
    struct Line: Equatable, Hashable { let text: String; var gloss = false }
    /// The closure schedule: a bold head, the sentence under it, and the
    /// same times in the viewer's zone when the road's zone differs.
    struct Schedule: Equatable { let head: String; let tail: String; let inYourZone: [String] }
    /// Chain control: the level in force, and the others for reference.
    struct ChainLevels: Equatable { let active: (String, String)?; let others: [(String, String)]
        static func == (a: Self, b: Self) -> Bool {
            a.active?.0 == b.active?.0 && a.others.map(\.0) == b.others.map(\.0)
        }
    }

    var chip: String
    var ago: String?
    var title: String
    var subtitle: String?
    var warning: String?
    var body: [Line] = []
    var facts: [Fact] = []
    var schedule: Schedule?
    var chain: ChainLevels?
    var foot: [String] = []
    /// The CHP id and the number of log entries, when the feed shares a log.
    var dispatch: (id: String, count: Int)?

    static func == (a: Self, b: Self) -> Bool {
        a.chip == b.chip && a.title == b.title && a.subtitle == b.subtitle && a.warning == b.warning
            && a.body == b.body && a.facts == b.facts && a.schedule == b.schedule && a.chain == b.chain
            && a.foot == b.foot && a.dispatch?.id == b.dispatch?.id
    }

    // MARK: per kind

    static func make(_ m: RoadMarker, now: Date = Date(), viewerZone: TimeZone = .current) -> EventContent {
        switch m.kind {
        case "incident": return incident(m, now: now)
        case "lane_closure": return closure(m, now: now, viewerZone: viewerZone)
        case "chain_control": return chain(m, now: now)
        case "wildfire": return wildfire(m, now: now)
        case "camera":
            return EventContent(chip: "Camera", title: m.name ?? "Roadside camera",
                                subtitle: m.whereLine.isEmpty ? nil : m.whereLine,
                                foot: ["Source: " + (m.src.map { $0 + " camera network" } ?? "Caltrans CCTV")])
        case "sign":
            let road = [m.route, m.direction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            var c = EventContent(chip: "Message sign", title: road.isEmpty ? "Changeable sign" : road,
                                 subtitle: (m.near ?? "").isEmpty ? nil : m.near,
                                 foot: ["Source: " + (m.src.map { $0 + " message signs" } ?? "Caltrans CMS")])
            if m.blank == true || m.signLines.isEmpty { c.body = [Line(text: "This sign is blank right now.", gloss: true)] }
            return c
        case "rwis": return weather(m)
        case "toll":
            return EventContent(chip: "Toll", title: m.corridor ?? m.name ?? "Toll",
                                subtitle: m.priceRange + (m.tollType == "required" ? ", all lanes tolled" : ", optional express lane"),
                                foot: [m.src.map { "Prices provided by " + $0 }].compactMap { $0 })
        case "plugin": return plugin(m, now: now)
        default:
            return EventContent(chip: m.kind.capitalized, title: m.displayTitle)
        }
    }

    static func incident(_ m: RoadMarker, now: Date) -> EventContent {
        let parts = splitRoad(m.label ?? "")
        var c = EventContent(chip: "Incident", ago: m.reported.flatMap { ago($0, now: now) },
                             title: humanize(m.type) ?? "Incident",
                             subtitle: nonEmpty(m.location) ?? parts.road)
        // Out-of-state feeds send a clean sentence; the templated label
        // only fills in when there is nothing better.
        if let d = nonEmpty(m.detail), d != m.label {
            c.body.append(Line(text: shapeShout(d)))
        } else if let l = nonEmpty(m.label), l != m.location {
            c.body.append(Line(text: parts.rest))
        }
        if let g = chpGloss(m.type) { c.body.append(Line(text: g, gloss: true)) }
        c.facts = [
            parts.road != nil && nonEmpty(m.location) == nil ? Fact(label: "Road", value: parts.road!) : nil,
            nonEmpty(m.dir).map { Fact(label: "Direction", value: "Affects the \($0) side") },
            nonEmpty(m.lanes).map { Fact(label: "Lanes", value: $0) },
        ].compactMap { $0 }
        c.foot = [
            m.reported.flatMap { ago($0, now: now) }.map { "Reported " + $0 } ?? "Live report",
            "Source: " + (nonEmpty(m.src).map { $0 + " data feed" }
                          ?? "CHP " + (nonEmpty(m.area).map { $0 + " " } ?? "") + "dispatch"),
        ]
        if let id = m.id, let n = m.logN, n > 0 { c.dispatch = (id, n) }
        return c
    }

    static func closureChip(_ cls: String?) -> String {
        // The web map's classes: alternating, moving and traffic-break
        // work all leave one lane for both directions or a rolling stop.
        if cls == "full-roadway" { return "Road closed" }
        if cls == "ramp" { return "Ramp closed" }
        if let cls, cls.range(of: "one-way|alternating|moving|traffic-break", options: .regularExpression) != nil {
            return "One-way traffic"
        }
        return "Lanes closed"
    }

    static func closure(_ m: RoadMarker, now: Date, viewerZone: TimeZone) -> EventContent {
        let route = [m.route, m.county].compactMap(nonEmpty).joined(separator: ", ")
        var c = EventContent(chip: closureChip(m.cls), title: route.isEmpty ? "Closure" : route,
                             subtitle: nonEmpty(m.dir))
        let allLanes = m.cls == "full-roadway" || (m.lanes ?? "").range(of: "all lanes", options: .caseInsensitive) != nil
        c.warning = allLanes ? "All lanes closed" : nonEmpty(m.lanes)
        if let prose = nonEmpty(m.detail) ?? nonEmpty(m.label) { c.body.append(Line(text: shapeShout(prose))) }
        c.facts = [
            nonEmpty(m.work).flatMap(humanize).map { Fact(label: "Work", value: $0) },
            m.delayMin.flatMap { $0 > 0 ? Fact(label: "Delay", value: "~\(Int($0)) min expected") : nil },
            m.cls == "ramp" ? nonEmpty(m.facility).map { Fact(label: "Facility", value: $0) } : nil,
            m.windows.flatMap { $0 > 1 ? Fact(label: "Windows", value: "\($0 - 1) more scheduled at this spot") : nil },
        ].compactMap { $0 }
        c.schedule = schedule(m, now: now, viewerZone: viewerZone)
        c.foot = ["Source: " + (nonEmpty(m.src).map { $0 + " data feed" } ?? "Caltrans lane closure system")]
        return c
    }

    static let chainLevels: [(String, String)] = [
        ("R-1", "Chains or approved snow tires required. Carry chains even with snow tires."),
        ("R-2", "Chains required on every vehicle, except 4WD/AWD with snow tires on all four wheels. Even those must carry chains."),
        ("R-3", "Chains required on every vehicle, no exceptions. Plan for a full closure."),
    ]

    static func chain(_ m: RoadMarker, now: Date) -> EventContent {
        let updated = m.updated.flatMap { ago($0, now: now) }
        // The R system is California's. Other agencies publish free text:
        // shown as written, with no R legend.
        if let src = nonEmpty(m.src) {
            var seen = Set<String>()
            let parts = (m.label ?? "").components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
            var c = EventContent(chip: "Pass restriction", ago: updated,
                                 title: nonEmpty(m.route) ?? nonEmpty(m.status) ?? "Mountain pass")
            if (m.label ?? "").range(of: "no current information", options: .caseInsensitive) != nil {
                c.body = [Line(text: src + " has not posted current restrictions for this pass.", gloss: true)]
            } else if let last = parts.last {
                let joined = parts.joined(separator: ". ")
                c.body = [Line(text: joined + (".!?".contains(last.last ?? " ") ? "" : "."))]
            }
            c.foot = ["Source: " + src + " mountain pass reports"]
            return c
        }
        var norm = (m.status ?? "").uppercased()
        if norm.count == 2, norm.hasPrefix("R"), norm.last!.isNumber { norm = "R-" + String(norm.last!) }
        let active = chainLevels.first { $0.0 == norm }
        var c = EventContent(chip: "Chain control", ago: updated,
                             title: (norm.isEmpty ? (m.status ?? "Chain control") : norm)
                                + (nonEmpty(m.route).map { " on " + $0 } ?? ""),
                             subtitle: nonEmpty(m.label) ?? nonEmpty(m.location))
        c.chain = ChainLevels(active: active, others: chainLevels.filter { $0.0 != norm })
        c.foot = [updated.map { "Status set " + $0 }, "Source: Caltrans chain control feed"].compactMap { $0 }
        return c
    }

    static func wildfire(_ m: RoadMarker, now: Date) -> EventContent {
        var c = EventContent(chip: "Wildfire", ago: m.discovered.flatMap { ago($0, now: now) },
                             title: (m.name ?? "Wildfire") + " Fire")
        c.body = [Line(text: (m.poly ?? []).isEmpty
                       ? "No mapped perimeter yet. The dot marks the reported origin."
                       : "The outline is the mapped burn footprint.", gloss: true)]
        c.facts = [
            m.acres.flatMap { $0 > 0 ? Fact(label: "Size", value: "\(Int($0.rounded()).formatted()) acres") : nil },
            m.contained.map { Fact(label: "Contained", value: "\(Int($0))% contained") },
            m.discovered.flatMap { ago($0, now: now) }.map { Fact(label: "Discovered", value: $0) },
            nonEmpty(m.county).map { Fact(label: "County", value: $0) },
        ].compactMap { $0 }
        c.foot = ["Source: WFIGS national fire data, with CAL FIRE perimeters"]
        return c
    }

    static func weather(_ m: RoadMarker) -> EventContent {
        let calm = (m.wind.map { $0.rounded() < 1 }) ?? false
        let dir = (m.windDir?.text).flatMap { calm || $0.isEmpty ? nil : $0 }
        var wind: String?
        if let w = m.wind {
            wind = "\(Int(w.rounded())) mph" + (dir.map { " from the " + $0 } ?? "")
                + (m.gust.map { ", gusts \(Int($0.rounded())) mph" } ?? "")
        } else if let g = m.gust {
            wind = "gusts \(Int(g.rounded())) mph" + (dir.map { " from the " + $0 } ?? "")
        }
        var c = EventContent(chip: "Road weather", title: m.station ?? m.name ?? "Weather station",
                             subtitle: nonEmpty(m.route))
        c.facts = [
            m.airC.map { Fact(label: "Air", value: Units.temperature(celsius: $0)) },
            m.paveC.map { Fact(label: "Pavement", value: Units.temperature(celsius: $0)) },
            wind.map { Fact(label: "Wind", value: $0) },
            m.rh.map { Fact(label: "Humidity", value: "\(Int($0.rounded()))%") },
            nonEmpty(m.precip).flatMap(humanize).map { Fact(label: "Precip", value: $0) },
            nonEmpty(m.surface).map { Fact(label: "Surface", value: $0) },
            m.visM.flatMap { $0 < 5000 ? Fact(label: "Visibility", value: "\(Int($0.rounded())) m") : nil },
        ].compactMap { $0 }
        if c.facts.isEmpty { c.body = [Line(text: "This station is online. It has no readings right now.", gloss: true)] }
        c.foot = ["Source: " + (nonEmpty(m.src).map { $0 + " weather station" } ?? "Caltrans roadside weather station")]
        return c
    }

    static func plugin(_ m: RoadMarker, now: Date) -> EventContent {
        let cameras = ["CAMERA_SPEED": "Speed camera", "CAMERA_RED_LIGHT": "Red light camera"]
        let camera = cameras[m.flareKind ?? ""]
        let kind = camera ?? humanize((m.flareKind ?? "OTHER").lowercased().replacingOccurrences(of: "_", with: " ")) ?? "Report"
        var about = m.label ?? m.description ?? ""
        if let camera, about.lowercased().hasPrefix(camera.lowercased()) {
            about = String(about.dropFirst(camera.count)).trimmingCharacters(in: CharacterSet(charactersIn: ",. "))
            about = about.prefix(1).uppercased() + about.dropFirst()
        }
        // Something fixed in place was not "reported 38 minutes ago".
        let fixed = (m.ttlS ?? 0) >= 86_400
        var c = EventContent(chip: m.source ?? "Plugin", ago: fixed ? nil : m.reported.flatMap { ago($0, now: now) },
                             title: kind, subtitle: about.isEmpty ? nil : about)
        let n = m.confirmations ?? 0
        c.facts = [
            nonEmpty(m.road).map { Fact(label: "Road", value: $0) },
            n > 0 ? Fact(label: "Confirmed", value: "\(n) " + (n == 1 ? "time" : "times")) : nil,
            !fixed ? m.reliability.map { Fact(label: "Reliability", value: "\(Int(($0 * 100).rounded()))%") } : nil,
            nonEmpty(m.data).map { Fact(label: "Data from", value: $0) },
        ].compactMap { $0 }
        let tier = m.tier == "approved" ? " (approved by CommuteScout)"
            : m.tier == "unreviewed" ? " (public, not reviewed)"
            : m.tier == "private" ? " (your private plugin)"
            : nonEmpty(m.trust).map { " (\($0))" } ?? ""
        c.foot = ["Source: " + (m.source ?? "community plugin") + tier]
        return c
    }

    // MARK: closure schedule

    /// Times are told in the road's zone. Every source maps to its
    /// state's zone; no source means California.
    static let zoneBySource: [String: String] = [
        "WSDOT": "America/Los_Angeles", "Oregon DOT (TripCheck)": "America/Los_Angeles",
        "NDOT": "America/Los_Angeles", "511.org": "America/Los_Angeles", "BATA": "America/Los_Angeles",
        "GGB": "America/Los_Angeles", "Alaska DOT&PF": "America/Anchorage", "HDOT": "Pacific/Honolulu",
        "ITD": "America/Boise", "UDOT": "America/Denver", "CDOT": "America/Denver", "ADOT": "America/Phoenix",
        "WisDOT": "America/Chicago", "MnDOT": "America/Chicago", "KDOT": "America/Chicago",
        "MoDOT": "America/Chicago", "ODOT (OK)": "America/Chicago", "Louisiana DOTD": "America/Chicago",
        "City of Austin": "America/Chicago", "Iowa DOT": "America/Chicago",
        "TravelMidwest (IDOT)": "America/Chicago", "MDOT Traffic (MS)": "America/Chicago",
        "TDOT SmartWay": "America/Chicago", "ALGO Traffic (ALDOT)": "America/Chicago",
        "NTTA": "America/Chicago", "HCTRA": "America/Chicago", "MDOT MiDrive": "America/Detroit",
        "511NY": "America/New_York", "NJDOT": "America/New_York", "MDOT SHA": "America/New_York",
        "MDOT CHART": "America/New_York", "KYTC": "America/New_York", "DelDOT": "America/New_York",
        "FDOT": "America/New_York", "FDOT (WZDx)": "America/New_York", "NCDOT": "America/New_York",
        "CTDOT": "America/New_York", "MaineDOT": "America/New_York", "NHDOT": "America/New_York",
        "VTrans": "America/New_York", "VDOT": "America/New_York", "OHGO": "America/New_York",
        "INDOT": "America/Indiana/Indianapolis",
    ]

    static func roadZone(_ m: RoadMarker) -> TimeZone {
        TimeZone(identifier: m.src.flatMap { zoneBySource[$0] } ?? "America/Los_Angeles") ?? .current
    }

    /// "tomorrow at 6:00 AM PDT": the day in words near today, the clock,
    /// and the zone. zoneMode 2 adds "(your timezone)" when it is.
    static func whenPhrase(_ epoch: Double, zone: TimeZone, zoneMode: Int, now: Date, viewerZone: TimeZone) -> String {
        let t = Date(timeIntervalSince1970: epoch)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let clock = format(t, "h:mm a", zone)
        let gap = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: t)).day ?? 0
        let day: String
        switch gap {
        case 0: day = cal.component(.hour, from: t) >= 18 ? "tonight" : "today"
        case 1: day = "tomorrow"
        case -1: day = "yesterday"
        default:
            day = format(t, "EEEE", zone) + (abs(gap) > 6 ? ", " + format(t, "MMM d", zone) : "")
                + (abs(gap) > 300 ? ", " + format(t, "yyyy", zone) : "")
        }
        var s = day + " at " + clock
        if zoneMode > 0 {
            s += " " + format(t, "zzz", zone)
            if zoneMode == 2, sameClock(t, zone, viewerZone) { s += " (your timezone)" }
        }
        return s
    }

    static func spanPhrase(_ epoch: Double, now: Date) -> String {
        let mins = Int((abs(now.timeIntervalSince1970 - epoch) / 60).rounded())
        if mins < 60 { return "\(mins) minutes" }
        if mins < 60 * 36 {
            let h = Int((Double(mins) / 60).rounded())
            return "about \(h) " + (h == 1 ? "hour" : "hours")
        }
        let d = Int((Double(mins) / 1440).rounded())
        return "about \(d) " + (d == 1 ? "day" : "days")
    }

    /// Never promotes a schedule into an observation: "scheduled to end"
    /// survives every state, and a past end says the agency has not
    /// reported it clear.
    static func schedule(_ m: RoadMarker, now: Date, viewerZone: TimeZone) -> Schedule {
        let agency = nonEmpty(m.src) ?? "Caltrans"
        let zone = roadZone(m)
        let full = m.cls == "full-roadway"
        let started = m.since.map { " It started " + whenPhrase($0, zone: zone, zoneMode: 0, now: now, viewerZone: viewerZone) + "." } ?? ""
        let head: String, tail: String
        if let until = m.until, until < now.timeIntervalSince1970 {
            head = "Was scheduled to end " + whenPhrase(until, zone: zone, zoneMode: 2, now: now, viewerZone: viewerZone)
            tail = "That was " + spanPhrase(until, now: now) + " ago. "
                + (full ? agency + " has not reported it open. Assume the road is still closed."
                        : agency + " has not reported it clear. Assume the restriction is still there.")
        } else if let until = m.until {
            head = "Scheduled to end " + whenPhrase(until, zone: zone, zoneMode: 2, now: now, viewerZone: viewerZone)
            tail = "That is " + spanPhrase(until, now: now) + " from now." + started
        } else {
            head = "No scheduled end"
            tail = (full ? "The road stays closed until " + agency + " reports it open."
                         : "The restriction stays until " + agency + " reports it clear.") + started
        }
        // The same times in the viewer's zone, only when it differs.
        let rows = [("Start", m.since), ("Scheduled end", m.until)].compactMap { r in r.1.map { (r.0, $0) } }
        let differs = rows.contains { !sameClock(Date(timeIntervalSince1970: $0.1), zone, viewerZone) }
        let converted = differs ? rows.map { $0.0 + ": " + format(Date(timeIntervalSince1970: $0.1), "EEEE, MMM d 'at' h:mm a zzz", viewerZone) } : []
        return Schedule(head: head, tail: tail, inYourZone: converted)
    }

    // MARK: wording helpers, as the website has them

    /// CHP dispatch codes, decoded for people who don't speak scanner.
    static let chpCodes: [(String, String)] = [
        ("^1125", "A traffic hazard is on or near the road: debris, an animal, or a stalled vehicle. These usually clear quickly. Expect brief slowing."),
        ("^1179", "Collision with injuries. An ambulance is on the way. Lanes can be blocked while crews work."),
        ("^1181", "Collision with minor injuries reported. Expect brief lane blockage while crews clear the scene."),
        ("^1182", "Collision, property damage only. No injuries are reported. Vehicles can be on the shoulder."),
        ("^1183", "Collision reported, details still coming in. CHP has the call but no injury assessment yet."),
        ("^20001", "Hit and run with injuries (felony). CHP is investigating. The scene can block lanes."),
        ("^20002", "Hit and run, property damage only. Usually a short stop on the shoulder."),
        ("^23114", "A load has spilled from a vehicle onto the road. Lanes can close briefly for cleanup."),
        ("^1166", "A traffic signal is defective. Treat the intersection as an all-way stop."),
        ("(?i)SIG", "A SIG Alert: a major incident expected to block lanes for 30 minutes or more. Avoid the area if you can."),
        ("(?i)fire", "A fire reported on or near the road. Smoke can cut visibility. Expect crews and closures."),
        ("(?i)ped", "A pedestrian is involved or on the road. Slow down and give the scene room."),
        ("(?i)animal", "A live or struck animal on the road. Expect brief slowing."),
    ]

    static func chpGloss(_ type: String?) -> String? {
        let t = type ?? ""
        return chpCodes.first { t.range(of: $0.0, options: .regularExpression) != nil }?.1
    }

    /// "rightLaneClosed" or "LANE_CLOSED" as "Right lane closed".
    static func humanize(_ t: String?) -> String? {
        guard let t, !t.isEmpty else { return nil }
        var s = t.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        s = s == s.uppercased() ? s.lowercased() : s.prefix(1).lowercased() + s.dropFirst()
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// ALL-CAPS operator text ("CLOSED DUE TO X//USE Y") read as shouting:
    /// sentence case, the slash chains split into sentences, route
    /// numbers kept in capitals.
    static func shapeShout(_ t: String) -> String {
        let letters = t.filter(\.isLetter)
        let caps = letters.filter(\.isUppercase)
        guard !letters.isEmpty, Double(caps.count) / Double(letters.count) >= 0.8 else { return t }
        let routes = try! NSRegularExpression(pattern: "\\b(us|i|sr|nv|ca|az|ut|wa|or|id|co|nm|mt|wy|nd|sd)-?(\\d+[a-z]*)\\b")
        return t.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { seg -> String in
                var s = seg.lowercased()
                let ns = s as NSString
                for m in routes.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                    let p = ns.substring(with: m.range(at: 1)).uppercased(), n = ns.substring(with: m.range(at: 2)).uppercased()
                    s = (s as NSString).replacingCharacters(in: m.range, with: p + "-" + n)
                }
                return s.prefix(1).uppercased() + s.dropFirst() + (".!?".contains(s.last ?? " ") ? "" : ".")
            }.joined(separator: " ")
    }

    /// "US 89: Emergency maintenance, NB State St" as the road and the rest.
    static func splitRoad(_ label: String) -> (road: String?, rest: String) {
        let rx = try! NSRegularExpression(pattern: "^([A-Z]{1,3}[- ]?\\d+[A-Z]?(?:/[A-Z0-9-]+)?)\\s*[:-]\\s*(.+)$")
        let ns = label as NSString
        guard let m = rx.firstMatch(in: label, range: NSRange(location: 0, length: ns.length)) else { return (nil, label) }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }

    /// "12 min ago", "3 hours ago", the way the website says it.
    static func ago(_ iso: String, now: Date) -> String? {
        guard let d = date(iso) else { return nil }
        return ago(d, now: now)
    }

    static func ago(_ d: Date, now: Date) -> String {
        let mins = Int((now.timeIntervalSince(d) / 60).rounded())
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        if mins < 48 * 60 {
            let h = Int((Double(mins) / 60).rounded())
            return "\(h) " + (h == 1 ? "hour ago" : "hours ago")
        }
        return "\(Int((Double(mins) / 1440).rounded())) days ago"
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    private static func format(_ d: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = pattern
        return f.string(from: d)
    }

    private static func sameClock(_ t: Date, _ a: TimeZone, _ b: TimeZone) -> Bool {
        a.secondsFromGMT(for: t) == b.secondsFromGMT(for: t)
    }
}
