import CoreLocation
import XCTest

/// The battery rules (PowerPolicy.swift, docs/battery.md). These numbers
/// are what keep a 20 minute drive from costing a tenth of the battery;
/// a change here should be a deliberate one.
final class PowerPolicyTests: XCTestCase {
    func testTripKeepsNavigationGradeFixesInTheBackground() {
        let s = PowerPolicy.location(navigating: true, driving: true)
        XCTAssertEqual(s.accuracy, kCLLocationAccuracyBestForNavigation)
        XCTAssertTrue(s.background, "voice guidance runs from the pocket")
        // At walking pace and up a fix still comes about every second.
        XCTAssertLessThanOrEqual(s.distanceFilter, 5)
    }

    func testNoTripNeverAsksForNavigationGradeOrBackground() {
        for driving in [false, true] {
            let s = PowerPolicy.location(navigating: false, driving: driving)
            XCTAssertNotEqual(s.accuracy, kCLLocationAccuracyBestForNavigation)
            XCTAssertFalse(s.background)
            XCTAssertGreaterThan(s.distanceFilter, 0)
        }
        // Standing still asks for less than driving does.
        XCTAssertGreaterThan(PowerPolicy.location(navigating: false, driving: false).accuracy,
                             PowerPolicy.location(navigating: false, driving: true).accuracy)
    }

    func testSilenceAtSpeedIsALostSignalSilenceStandingIsAStop() {
        XCTAssertTrue(PowerPolicy.speedUnknownAfterSilence(lastSpeed: 25))
        // The last fix of a car braking for a light.
        XCTAssertFalse(PowerPolicy.speedUnknownAfterSilence(lastSpeed: 5))
        XCTAssertFalse(PowerPolicy.speedUnknownAfterSilence(lastSpeed: 0))
        XCTAssertFalse(PowerPolicy.speedUnknownAfterSilence(lastSpeed: -1))
    }

    func testMapDrawsAtThirtyUnlessTouched() {
        XCTAssertEqual(PowerPolicy.mapFramesPerSecond(touching: false), 30)
        XCTAssertEqual(PowerPolicy.mapFramesPerSecond(touching: true), 0)   // the display's most
    }

    func testCompassIgnoresSmallTurnsButNotTheFirstOne() {
        XCTAssertFalse(PowerPolicy.headingWorthShowing(old: 90, new: 91))
        XCTAssertTrue(PowerPolicy.headingWorthShowing(old: 90, new: 93))
        XCTAssertTrue(PowerPolicy.headingWorthShowing(old: 0, new: 1.5))   // the button appears
        XCTAssertTrue(PowerPolicy.headingWorthShowing(old: 1.5, new: 0))   // and goes
        // Turns are measured the short way round north.
        XCTAssertTrue(PowerPolicy.headingWorthShowing(old: 359, new: 3))
        XCTAssertFalse(PowerPolicy.headingWorthShowing(old: 359, new: 359.5))
    }

    func testBeatsAlignToTheClockSoFetchesLeaveTogether() {
        let now = Date(timeIntervalSince1970: 1_800_000_017)
        let a = PowerPolicy.nextBeat(after: now)
        XCTAssertEqual(a.timeIntervalSince1970.truncatingRemainder(dividingBy: 60), 0)
        XCTAssertGreaterThan(a, now)
        XCTAssertLessThanOrEqual(a.timeIntervalSince(now), 60)
        // Two stores asking at different moments land on the same beat.
        XCTAssertEqual(PowerPolicy.nextBeat(after: now.addingTimeInterval(20)), a)
        let b = PowerPolicy.nextBeat(after: now, every: 120)
        XCTAssertEqual(b.timeIntervalSince1970.truncatingRemainder(dividingBy: 120), 0)
    }

    func testPluginCadenceIsRoundedUpOntoTheBeat() {
        XCTAssertEqual(PowerPolicy.pluginEvery(requested: 15), 60)
        XCTAssertEqual(PowerPolicy.pluginEvery(requested: 60), 60)
        XCTAssertEqual(PowerPolicy.pluginEvery(requested: 90), 120)
    }

    func testSnapshotIsReadLessOftenOnTheMove() {
        XCTAssertGreaterThan(PowerPolicy.snapshotEvery(moving: true), PowerPolicy.snapshotEvery(moving: false))
        XCTAssertGreaterThanOrEqual(PowerPolicy.snapshotEvery(moving: false), 5 * 60)
    }

    func testGridBoxHoldsTheViewWithACellToSpare() {
        let b = PowerPolicy.gridBox(south: 37.331, west: -121.901, north: 37.342, east: -121.880)
        XCTAssertLessThanOrEqual(b.s, 37.331 - PowerPolicy.cell + 1e-9)
        XCTAssertGreaterThanOrEqual(b.n, 37.342 + PowerPolicy.cell - 1e-9)
        XCTAssertLessThanOrEqual(b.w, -121.901 - PowerPolicy.cell + 1e-9)
        XCTAssertGreaterThanOrEqual(b.e, -121.880 + PowerPolicy.cell - 1e-9)
        // Snapped: a view moved a few hundred metres asks for the same box.
        let c = PowerPolicy.gridBox(south: 37.333, west: -121.903, north: 37.344, east: -121.882)
        XCTAssertEqual(b.s, c.s, accuracy: 1e-9)
        XCTAssertEqual(b.n, c.n, accuracy: 1e-9)
        XCTAssertEqual(b.w, c.w, accuracy: 1e-9)
        XCTAssertEqual(b.e, c.e, accuracy: 1e-9)
    }

    func testRouteWindowCoversTheRoadAheadNotTheWholeRoute() {
        // A 300 km route, a vertex every kilometre.
        let cum = (0 ... 300).map { Double($0) * 1000 }
        let start = PowerPolicy.routeWindow(cumulative: cum, here: 0)!
        XCTAssertEqual(start.lowerBound, 0)
        XCTAssertEqual(cum[start.upperBound], 51_000)
        let mid = PowerPolicy.routeWindow(cumulative: cum, here: 120_000)!
        XCTAssertLessThanOrEqual(cum[mid.lowerBound], 119_000)
        XCTAssertGreaterThan(cum[mid.upperBound], 170_000)
        XCTAssertLessThan(cum[mid.upperBound], 172_000)
        // Near the end the window stops at the destination.
        let end = PowerPolicy.routeWindow(cumulative: cum, here: 290_000)!
        XCTAssertEqual(end.upperBound, cum.count - 1)
        // A short commute fits in one window.
        let short = [0.0, 500, 9_000, 28_000]
        XCTAssertEqual(PowerPolicy.routeWindow(cumulative: short, here: 0), 0 ... 3)
        XCTAssertNil(PowerPolicy.routeWindow(cumulative: [0], here: 0))
    }
}
