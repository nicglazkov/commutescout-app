import XCTest

/// The ahead line's layout and the arithmetic of a trip changed mid-drive.
final class TripPlanTests: XCTestCase {
    func testRailGivesTheNextMileMostOfTheRoom() {
        let s = RailLayout.slots(gaps: [500, 8000], total: 32000, span: 300)
        XCTAssertEqual(s.map(\.index), [0, 1])
        XCTAssertEqual(s[0].y, 240, accuracy: 0.01)   // would be 262.5, held clear of the driver
        XCTAssertEqual(s[1].y, 150, accuracy: 0.01)   // sqrt(1/4) of the way up
    }

    func testRailKeepsMarksApartAndClearOfTheEnds() {
        let s = RailLayout.slots(gaps: [100, 120, 140, 160], total: 10000, span: 300)
        XCTAssertEqual(s.map(\.y), [240, 180, 120])
        XCTAssertEqual(RailLayout.slots(gaps: [100, 120, 140], total: 10000, span: 150).count, 1)
        XCTAssertTrue(RailLayout.slots(gaps: [100], total: 10000, span: 100).isEmpty)
    }

    func testRailDropsWhatIsBehindOrPastTheDestination() {
        XCTAssertEqual(RailLayout.slots(gaps: [-50, 2000, 9000], total: 8000, span: 300).map(\.index), [1])
        XCTAssertTrue(RailLayout.slots(gaps: [100], total: 0, span: 300).isEmpty)
    }

    func testRoutesThroughStopsThenTheDestination() {
        let same: (String, String) -> Bool = { $0 == $1 }
        XCTAssertEqual(TripPlan.through(stops: [], add: "gas", destination: "sjc", same: same), ["gas", "sjc"])
        XCTAssertEqual(TripPlan.through(stops: ["gas"], add: "coffee", destination: "sjc", same: same), ["gas", "coffee", "sjc"])
        XCTAssertEqual(TripPlan.through(stops: ["gas"], add: "gas", destination: "sjc", same: same), ["gas", "sjc"])
        XCTAssertEqual(TripPlan.through(stops: [], add: "sjc", destination: "sjc", same: same), ["sjc"])
        XCTAssertEqual(TripPlan.through(stops: ["gas", "coffee"], add: nil, destination: "gas", same: same), ["coffee", "gas"])
    }

    func testSaysWhatAChangeCosts() {
        XCTAssertEqual(TripPlan.cost(250), "+4 min")
        XCTAssertEqual(TripPlan.cost(-110), "2 min faster")
        XCTAssertEqual(TripPlan.cost(20), "No extra time")
        XCTAssertNil(TripPlan.cost(nil))
        XCTAssertEqual(TripPlan.line(stops: ["Peet's Coffee"], destination: "SJC Airport"), "Peet's Coffee, then SJC Airport")
        XCTAssertEqual(TripPlan.line(stops: [], destination: "SJC Airport"), "SJC Airport")
    }

    func testCountsStopsStillAhead() {
        XCTAssertEqual(TripPlan.stopsLeft(planned: 2, remainingWaypoints: 3), 2)
        XCTAssertEqual(TripPlan.stopsLeft(planned: 2, remainingWaypoints: 2), 1)
        XCTAssertEqual(TripPlan.stopsLeft(planned: 2, remainingWaypoints: 1), 0)
        XCTAssertEqual(TripPlan.stopsLeft(planned: 0, remainingWaypoints: 1), 0)
        XCTAssertEqual(TripPlan.stopsLeft(planned: 1, remainingWaypoints: 5), 1)
    }
}
