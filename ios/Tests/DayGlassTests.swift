import XCTest

/// The Day Glass+ logic: lane layouts, the lane plan, the clearing rule
/// and the kind each marker draws as.
final class DayGlassTests: XCTestCase {
    private func marker(_ json: String) throws -> RoadMarker {
        try JSONDecoder().decode(RoadMarker.self, from: Data(json.utf8))
    }

    private let crash = #"{"total":4,"lanes":[{"n":1,"type":"general","state":"open"},{"n":2,"type":"hov","state":"open"},{"n":3,"type":"general","state":"open"},{"n":4,"type":"general","state":"closed"}],"shoulder":{"left":"open","right":"closed"},"target":3,"basis":"feed"}"#

    func testDecodesAFullLayout() throws {
        let m = try marker(#"{"kind":"incident","lat":37.442,"lon":-122.143,"lane_layout":\#(crash)}"#)
        let l = try XCTUnwrap(m.laneLayout)
        XCTAssertTrue(l.isUsable)
        XCTAssertEqual(l.total, 4)
        XCTAssertEqual(l.closedLanes, [4])
        XCTAssertEqual(l.lanes[1].type, .hov)
        XCTAssertTrue(l.rightShoulderClosed)
        XCTAssertFalse(l.leftShoulderClosed)
        XCTAssertEqual(l.target, 3)
        XCTAssertEqual(l.basis, "feed")
    }

    func testMissingLayoutIsNil() throws {
        let m = try marker(#"{"kind":"incident","lat":37.442,"lon":-122.143}"#)
        XCTAssertNil(m.laneLayout)
        XCTAssertNil(LanePlan(m.laneLayout))
    }

    func testABadLayoutNeverDropsTheMarker() throws {
        for bad in [#""four lanes""#, "42", "[]", #"{"total":"x","lanes":[1,{"n":"a"},{"state":"closed"}]}"#, "null"] {
            let m = try marker(#"{"kind":"incident","lat":37.442,"lon":-122.143,"label":"Crash","lane_layout":\#(bad)}"#)
            XCTAssertEqual(m.label, "Crash", bad)
            XCTAssertNil(LanePlan(m.laneLayout), bad)
        }
    }

    func testCountOnlyFillsOpenLanes() throws {
        let m = try marker(#"{"kind":"lane_closure","lat":37.442,"lon":-122.143,"lane_layout":{"total":3,"lanes":[],"target":null,"basis":"count_only"}}"#)
        let l = try XCTUnwrap(m.laneLayout)
        XCTAssertEqual(l.lanes.count, 3)
        XCTAssertFalse(l.anyLaneClosed)
        let p = try XCTUnwrap(LanePlan(l))
        XCTAssertEqual(p.moves, 0)
        XCTAssertNil(p.instruction)
    }

    func testPlanMovesOutOfTheClosedLane() throws {
        let l = try JSONDecoder().decode(LaneLayout.self, from: Data(crash.utf8))
        let p = try XCTUnwrap(LanePlan(l))
        XCTAssertEqual(p.closed, [3])
        XCTAssertEqual(p.tinted, [1])
        XCTAssertEqual(p.from, 3)
        XCTAssertEqual(p.to, 2)
        XCTAssertEqual(p.instruction, "Move one lane left.")
    }

    func testPlanWithoutTargetPicksTheNearestOpenLane() {
        let l = LaneLayout(total: 4, lanes: [.init(n: 1, closed: true), .init(n: 2, closed: true), .init(n: 3), .init(n: 4)])
        let p = LanePlan(l)
        XCTAssertEqual(p?.from, 0)
        XCTAssertEqual(p?.to, 2)
        XCTAssertEqual(p?.instruction, "Move two lanes right.")
    }

    func testOnlyShouldersClosedHasNoMerge() {
        let l = LaneLayout(total: 3, lanes: [.init(n: 1), .init(n: 2), .init(n: 3)], rightShoulderClosed: true)
        let p = LanePlan(l)
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.moves, 0)
        XCTAssertNil(p?.instruction)
    }

    func testClearedOnlyWhenItVanishesAhead() {
        let seen: [ClearingRule.Seen] = [.init(key: "behind", along: 900), .init(key: "ahead", along: 2500),
                                         .init(key: "far", along: 40000), .init(key: "kept", along: 3000)]
        let now: Set<String> = ["kept"]
        XCTAssertEqual(ClearingRule.vanished(previous: seen, now: now, here: 1000, within: 16093), ["ahead"])
        // Passing an event says nothing, even when it drops off the list.
        XCTAssertEqual(ClearingRule.vanished(previous: [.init(key: "x", along: 1010)], now: [], here: 1000, within: 16093), [])
        XCTAssertEqual(ClearingRule.vanished(previous: seen, now: ["ahead", "kept", "far", "behind"], here: 1000, within: 16093), [])
    }

    func testClearedWordsMatchEveryKind() {
        XCTAssertEqual(DGKind.crash.clearedTitle, "Crash ahead has cleared")
        XCTAssertEqual(DGKind.closure.clearedTitle, "Lanes closed ahead has cleared")
        XCTAssertEqual(DGKind.police.clearedTitle, "Police ahead has cleared")
        XCTAssertEqual(DGKind.fire.clearedTitle, "Wildfire nearby has cleared")
    }

    func testClearingIsSpokenOnlyWhenAllowed() {
        XCTAssertTrue(ClearingRule.speaks(ruleSpeaks: true, muted: false, onRoute: true))
        XCTAssertFalse(ClearingRule.speaks(ruleSpeaks: false, muted: false, onRoute: true), "voice, plugin or per-kind setting off")
        XCTAssertFalse(ClearingRule.speaks(ruleSpeaks: true, muted: true, onRoute: true), "muted")
        XCTAssertFalse(ClearingRule.speaks(ruleSpeaks: true, muted: false, onRoute: false), "free drive")
    }

    func testAnIdlessMarkerWithANewLabelHasNotCleared() throws {
        let was = try marker(#"{"kind":"incident","lat":37.442,"lon":-122.143,"label":"Crash on US-101"}"#)
        let relabeled = try marker(#"{"kind":"incident","lat":37.442,"lon":-122.143,"label":"Crash on US-101, right lane"}"#)
        XCTAssertNotEqual(was.key, relabeled.key)
        XCTAssertTrue(ClearingRule.stillReported(was, among: [relabeled]))
        // Gone from the place, a different kind there, or a real id: it did clear.
        let elsewhere = try marker(#"{"kind":"incident","lat":37.452,"lon":-122.143,"label":"Crash on US-101"}"#)
        let otherKind = try marker(#"{"kind":"lane_closure","lat":37.442,"lon":-122.143}"#)
        let withId = try marker(#"{"id":"a","kind":"incident","lat":37.442,"lon":-122.143}"#)
        XCTAssertFalse(ClearingRule.stillReported(was, among: []))
        XCTAssertFalse(ClearingRule.stillReported(was, among: [elsewhere]))
        XCTAssertFalse(ClearingRule.stillReported(was, among: [otherKind]))
        XCTAssertFalse(ClearingRule.stillReported(withId, among: [relabeled]))
    }

    func testKinds() throws {
        func kind(_ json: String) throws -> DGKind { DGKind(marker: try marker(json)) }
        XCTAssertEqual(try kind(#"{"kind":"incident","lat":0,"lon":0,"type":"Traffic Collision"}"#), .crash)
        XCTAssertEqual(try kind(#"{"kind":"incident","lat":0,"lon":0,"type":"Traffic Hazard"}"#), .hazard)
        XCTAssertEqual(try kind(#"{"kind":"plugin","lat":0,"lon":0,"flare_kind":"police"}"#), .police)
        XCTAssertEqual(try kind(#"{"kind":"lane_closure","lat":0,"lon":0}"#), .closure)
        XCTAssertEqual(try kind(#"{"kind":"chain_control","lat":0,"lon":0}"#), .chain)
        XCTAssertEqual(try kind(#"{"kind":"wildfire","lat":0,"lon":0}"#), .fire)
        XCTAssertEqual(try kind(#"{"kind":"rwis","lat":0,"lon":0}"#), .ice)
        XCTAssertEqual(DGKind.crash.tone, .high)
        XCTAssertEqual(DGKind.jam.section, "Heads up")
        XCTAssertEqual(DGKind.toll.section, "Good to know")
    }
}
