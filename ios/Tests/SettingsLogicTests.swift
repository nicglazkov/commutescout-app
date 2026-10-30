import XCTest

final class SettingsLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    // MARK: data sources

    func testSourcesReportCountsGroupsAndHeadline() {
        let body = json([
            "checked_at": "2027-01-15T08:00:00.123+00:00",
            "summary": ["fresh": 3, "stale": 1, "down": 1, "live": 1, "off": 0, "states": 51],
            "sources": [
                ["name": "Weather alerts", "agency": "National Weather Service", "state": "Nationwide", "group": "national",
                 "status": "fresh", "age_s": 60],
                ["name": "Traffic speeds", "agency": "Live road speeds", "state": "Nationwide", "group": "national", "status": "live"],
                ["name": "Incidents", "agency": "CHP", "state": "California", "group": "state", "state_code": "CA",
                 "status": "fresh", "age_s": 30],
                ["name": "Lane closures", "agency": "Caltrans", "state": "California", "group": "state", "state_code": "CA",
                 "status": "stale", "age_s": 1320],
                ["name": "Events", "agency": "Colorado DOT", "state": "Colorado", "group": "state", "state_code": "CO",
                 "status": "down", "age_s": 3600, "as_of": "2027-01-15T07:58:00+00:00"],
            ],
        ])
        let r = SourcesHealth.parse(body, now: now)!
        XCTAssertEqual(r.fresh, 4)   // fresh plus on-demand
        XCTAssertEqual(r.stale, 1)
        XCTAssertEqual(r.down, 1)
        XCTAssertEqual(r.headline, "1 down")
        XCTAssertEqual(r.worst, .down)
        XCTAssertEqual(r.coverage, "All 50 states and DC")
        XCTAssertEqual(r.national.map(\.title), ["Weather alerts", "Traffic speeds"])
        XCTAssertEqual(r.stateRows.map(\.code), ["CA", "CO"])
        // A state reads as its worst feed, with both agencies named.
        XCTAssertEqual(r.stateRows[0].status, .stale)
        XCTAssertEqual(r.stateRows[0].by, "CHP, Caltrans")
        XCTAssertEqual(r.stateRows[0].ageS, 1320)
        XCTAssertNotNil(r.checkedAt)
    }

    func testOlderServerStatusIsWorkedOut() {
        let body = json(["sources": [
            ["name": "A", "agency": "X", "state": "Texas", "ok": true, "stale": false, "age_s": 100],
            ["name": "B", "agency": "Y", "state": "Texas", "ok": true, "stale": false, "age_s": 10_000],
            ["name": "C", "agency": "Z", "state": "Ohio", "ok": false],
            ["name": "D", "agency": "W", "state": "Nationwide"],
            ["name": "E", "agency": "V", "state": "Utah", "ok": true, "enabled": false],
            ["name": "F", "agency": "U", "state": "Iowa", "ok": true, "age_s": 500, "stale_after_s": 300],
        ]])
        let r = SourcesHealth.parse(body, now: now)!
        XCTAssertEqual(r.fresh, 2)    // A and the on-demand D
        XCTAssertEqual(r.stale, 2)    // B past 90 minutes, F past its own limit
        XCTAssertEqual(r.down, 1)
        XCTAssertEqual(r.states, 3)   // the switched-off feed does not count
        XCTAssertEqual(r.national.first?.status, .live)
        XCTAssertEqual(r.stateRows.map(\.code), ["IA", "OH", "TX"])
        XCTAssertEqual(r.headline, "1 down")
    }

    func testHeadlineAndCoverageWords() {
        let none = SourcesHealth.report([], checkedAt: nil, summary: ["fresh": 5, "stale": 2, "down": 0, "states": 1])
        XCTAssertEqual(none.headline, "2 stale")
        XCTAssertEqual(none.coverage, "1 state")
        let ok = SourcesHealth.report([], checkedAt: nil, summary: ["fresh": 5, "stale": 0, "down": 0, "states": 37])
        XCTAssertEqual(ok.headline, "All fresh")
        XCTAssertEqual(ok.coverage, "37 states")
    }

    func testAgeText() {
        func row(_ s: FeedStatus, _ age: Int?, asOf: Date? = nil) -> FeedRow {
            FeedRow(code: "CA", title: "California", by: "", status: s, ageS: age, asOf: asOf)
        }
        XCTAssertEqual(SourcesHealth.ageText(row(.live, nil)), "Live")
        XCTAssertEqual(SourcesHealth.ageText(row(.fresh, 30)), "30 s ago")
        XCTAssertEqual(SourcesHealth.ageText(row(.fresh, 1320)), "22 min ago")
        XCTAssertEqual(SourcesHealth.ageText(row(.stale, 7200)), "2 h ago")
        XCTAssertEqual(SourcesHealth.ageText(row(.stale, 3 * 86400)), "3 days ago")
        XCTAssertEqual(SourcesHealth.ageText(row(.down, 900, asOf: now), clock: { _ in "7:58 AM" }), "No reply since 7:58 AM")
        XCTAssertEqual(SourcesHealth.ageText(row(.down, nil)), "Not answering")
    }

    func testNotABody() {
        XCTAssertNil(SourcesHealth.parse(Data("nope".utf8)))
        XCTAssertNil(SourcesHealth.parse(json(["summary": [:]])))
    }

    // MARK: API use

    func testUsageFromServer() {
        let body = json([
            "keys": [["id": "a", "tier": "pro", "daily_limit": 10_000], ["id": "b", "tier": "free", "revoked": true]],
            "max_active": 5, "tiers": ["free": 2000, "pro": 10_000],
            "usage": ["day": "2027-01-15", "requests": 1284, "limit": 10_000, "tier": "pro"],
            "keyless_daily": 10_000,
        ])
        let u = ApiUsage.parse(body)!
        XCTAssertEqual(u.requests, 1284)
        XCTAssertEqual(u.limit, 10_000)
        XCTAssertEqual(u.tier, "pro")
        XCTAssertEqual(u.activeKeys, 1)
        XCTAssertEqual(u.keylessDaily, 10_000)
        XCTAssertEqual(u.usedText, "1,284")
        XCTAssertEqual(u.limitText, "of 10,000")
        XCTAssertEqual(u.tierText, "a day with your pro key")
        XCTAssertEqual(u.keysText, "1 key")
        XCTAssertEqual(u.fraction, 0.1284, accuracy: 0.0001)
        XCTAssertFalse(u.full)
    }

    func testUsageFromOlderServer() {
        let u = ApiUsage.parse(json(["keys": []]))!
        XCTAssertEqual(u.limit, 2000)
        XCTAssertEqual(u.requests, 0)
        XCTAssertEqual(u.tier, "free")
        XCTAssertEqual(u.keysText, "None")
        XCTAssertEqual(u.tierText, "a day with a free key")
        XCTAssertNil(u.keylessDaily)
        // A count of 1 is a number, not true.
        let one = ApiUsage.parse(json(["keys": [["tier": "free"]], "usage": ["requests": 1, "limit": 1]]))!
        XCTAssertEqual(one.requests, 1)
        XCTAssertTrue(one.full)
        XCTAssertNil(ApiUsage.parse(json(["usage": [:]])))
    }

    // MARK: alerts

    func testChipsAndDefaults() {
        XCTAssertEqual(AlertChips.keys.count, 10)
        XCTAssertEqual(AlertChips.tiers.map(\.label), ["Act on it", "Heads up", "Good to know"])
        XCTAssertEqual(AlertChips.offByDefault, ["camera", "toll"])
        XCTAssertEqual(AlertChips.key(forKind: "jam"), "traffic")
        XCTAssertEqual(AlertChips.key(forKind: "police"), "hazard")
        XCTAssertEqual(AlertChips.key(forKind: "fire"), "fire")
        XCTAssertEqual(AlertChips.tierIndex(of: "sign"), 2)
    }

    func testApplyDelivery() {
        func run(_ d: AlertDelivery, plugin: Bool = false, speakPlugins: Bool = false, speak: Bool = true,
                 chipOff: Bool = false, pluginOff: Bool = false) -> AlertOutcome {
            AlertChips.apply(enabled: true, speak: speak, plugin: plugin, chipOff: chipOff, pluginOff: pluginOff,
                             delivery: d, speakPlugins: speakPlugins)
        }
        XCTAssertEqual(run(.voice), AlertOutcome(enabled: true, speak: true, chime: false))
        XCTAssertEqual(run(.sound), AlertOutcome(enabled: true, speak: false, chime: true))
        XCTAssertEqual(run(.silent), AlertOutcome(enabled: true, speak: false, chime: false))
        // Plugin alerts chime unless the driver wants them spoken.
        XCTAssertEqual(run(.voice, plugin: true), AlertOutcome(enabled: true, speak: false, chime: true))
        XCTAssertEqual(run(.voice, plugin: true, speakPlugins: true), AlertOutcome(enabled: true, speak: true, chime: false))
        // A kind set not to speak in the advanced rules stays quiet under Voice.
        XCTAssertEqual(run(.voice, speak: false), AlertOutcome(enabled: true, speak: false, chime: false))
        // Chips stop official alerts, plugin switches stop plugin ones, not the other way round.
        XCTAssertFalse(run(.voice, chipOff: true).enabled)
        XCTAssertTrue(run(.voice, plugin: true, chipOff: true).enabled)
        XCTAssertFalse(run(.voice, plugin: true, pluginOff: true).enabled)
    }

    func testAheadSteps() {
        XCTAssertEqual(AlertChips.aheadSteps(miles: true).map(\.label), ["0.5 mi", "1 mi", "2 mi"])
        XCTAssertEqual(AlertChips.aheadSteps(miles: false).map(\.label), ["800 m", "1.5 km", "3 km"])
        // The old default of 1500 m reads as 1 mi, and 3000 m as 2 mi.
        XCTAssertEqual(AlertChips.nearestStep(1500, miles: true), 1609)
        XCTAssertEqual(AlertChips.nearestStep(3000, miles: true), 3219)
        XCTAssertEqual(AlertChips.nearestStep(1609, miles: false), 1500)
    }

    // MARK: summaries and first run

    func testSummaries() {
        XCTAssertEqual(SettingsSummary.alerts(delivery: .voice, aheadMeters: 1500, advanced: false, miles: true), "Voice, 1 mi ahead")
        XCTAssertEqual(SettingsSummary.alerts(delivery: .sound, aheadMeters: 800, advanced: false, miles: false), "Sound, 800 m ahead")
        XCTAssertEqual(SettingsSummary.alerts(delivery: .silent, aheadMeters: 800, advanced: true, miles: true), "Silent, per kind")
        XCTAssertEqual(SettingsSummary.units(miles: true, clock24: false), "Miles, 12-hour")
        XCTAssertEqual(SettingsSummary.units(miles: false, clock24: true), "Kilometers, 24-hour")
        XCTAssertEqual(SettingsSummary.route(tolls: false, highways: false, ferries: false), "Fastest")
        XCTAssertEqual(SettingsSummary.route(tolls: true, highways: false, ferries: true), "Avoids tolls, ferries")
    }

    func testWelcome() {
        XCTAssertEqual(WelcomeStep.allCases.map(\.progress), ["Step 1 of 3", "Step 2 of 3", "Step 3 of 3"])
        XCTAssertTrue(WelcomeStep.shouldShow(done: false, hasOtherPrefs: false))
        XCTAssertFalse(WelcomeStep.shouldShow(done: true, hasOtherPrefs: false))
        // An update from a build without the first run skips it.
        XCTAssertFalse(WelcomeStep.shouldShow(done: false, hasOtherPrefs: true))
        XCTAssertTrue(WelcomeStep.location.body.contains("any route in the US"))
    }
}
