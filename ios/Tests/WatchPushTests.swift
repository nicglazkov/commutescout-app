import XCTest

/// Watch follow-up pushes: the cleared event and the summary.
final class WatchPushTests: XCTestCase {
    private let layout = #"{"total":4,"lanes":[{"n":1,"type":"general","state":"open"},{"n":2,"type":"general","state":"open"},{"n":3,"type":"general","state":"open"},{"n":4,"type":"general","state":"closed"}],"target":3,"basis":"feed"}"#
    private let now = Date(timeIntervalSince1970: 1_793_206_800)

    private func cleared(lanes: String? = nil) -> AlertRef? {
        var info: [AnyHashable: Any] = [
            "url": "https://commutescout.com/watch",
            "event_id": "chp:77", "event_kind": "incident", "event_lat": "37.442", "event_lon": "-122.143",
            "event_title": "Crash on US-101", "event_body": "Two vehicles, right lane blocked.",
            "event_watch": "Home area", "event_status": "cleared", "event_sent_at": "1793205300",
        ]
        if let lanes { info["event_lane_layout"] = lanes }
        return AlertRef.from(userInfo: info)
    }

    func testClearedPushCarriesStatusAndLanes() {
        let ref = cleared(lanes: layout)
        XCTAssertEqual(ref?.isCleared, true)
        XCTAssertEqual(ref?.laneLayout?.total, 4)
        XCTAssertEqual(ref?.watch, "Home area")
    }

    func testBadLaneLayoutIsDropped() {
        let ref = cleared(lanes: "not json")
        XCTAssertNotNil(ref)
        XCTAssertNil(ref?.laneLayout)
    }

    func testAlertPushIsNotCleared() {
        let ref = AlertRef.from(userInfo: ["event_kind": "closure", "event_lat": "37.442", "event_lon": "-122.143"])
        XCTAssertEqual(ref?.isCleared, false)
    }

    func testSummaryPushOpensTheWatchList() {
        let info: [AnyHashable: Any] = ["url": "https://commutescout.com/watch", "event_kind": "summary",
                                        "event_watch": "Home area", "event_count": "3", "event_sent_at": "1793205300"]
        XCTAssertTrue(AlertRef.isSummary(userInfo: info))
        XCTAssertFalse(AlertRef.isSummary(userInfo: ["event_kind": "incident"]))
    }

    func testClearedWords() throws {
        let ref = try XCTUnwrap(cleared(lanes: layout))
        let t = WatchClearedText.make(ref, clearedAt: ref.sentAt, now: now)
        XCTAssertEqual(t.capsule, "The crash on US-101 is over")
        XCTAssertEqual(t.heading, "This crash has cleared")
        XCTAssertTrue(t.since.hasPrefix("Cleared "))
        XCTAssertTrue(t.detail.hasSuffix("All lanes are open."))
        XCTAssertEqual(t.said, "What your alert said")
        let noLanes = WatchClearedText.make(try XCTUnwrap(cleared()), clearedAt: nil, now: now)
        XCTAssertEqual(noLanes.detail, "Cleared.")
    }

    func testLowerFirstKeepsRoadNames() {
        XCTAssertEqual(WatchClearedText.lowerFirst("Crash on US-101"), "crash on US-101")
        XCTAssertEqual(WatchClearedText.lowerFirst("US-101 S closed"), "US-101 S closed")
    }
}
