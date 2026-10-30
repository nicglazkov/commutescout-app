import CoreLocation
import XCTest

/// The trip and watch pages' logic: leave-later bars, the time and unit
/// overrides, watch shapes and the report wording.
final class PageLogicTests: XCTestCase {
    private let defaults = UserDefaults.standard

    override func tearDown() {
        defaults.removeObject(forKey: Units.clockKey)
        defaults.removeObject(forKey: Units.temperatureKey)
        defaults.removeObject(forKey: "cs.units")
        super.tearDown()
    }

    private func leaveLater(_ json: String) throws -> LeaveLater {
        try JSONDecoder().decode(LeaveLater.self, from: Data(json.utf8))
    }

    func testLeaveLaterBarsScaleBetweenQuickestAndSlowest() throws {
        let l = try leaveLater("""
        {"checked_at":"2026-10-29T16:00:00Z","departures":[
          {"depart_at":"2026-10-29T16:00:00+00:00","now":true,"drive_min":40,"delay_min":12},
          {"depart_at":"2026-10-29T16:10:00+00:00","now":false,"drive_min":36,"delay_min":8},
          {"depart_at":"2026-10-29T16:20:00+00:00","now":false,"drive_min":30,"delay_min":2}],
         "best":{"depart_at":"2026-10-29T16:20:00+00:00","drive_min":30,"saving_min":10},
         "reason":"Traffic should ease by then"}
        """)
        let bars = l.bars(maxHeight: 76, minHeight: 22)
        XCTAssertEqual(bars.map(\.minutes), [40, 36, 30])
        XCTAssertEqual(bars[0].height, 76, accuracy: 0.001)
        XCTAssertEqual(bars[2].height, 22, accuracy: 0.001)
        XCTAssertTrue(bars[0].isNow)
        XCTAssertEqual(bars.map(\.isBest), [false, false, true])
        XCTAssertEqual(bars[0].label, "Now")
        XCTAssertEqual(l.now?.delay_min, 12)
    }

    func testLeaveLaterHeadlineFollowsTheClock() throws {
        let l = try leaveLater("""
        {"departures":[{"depart_at":"2026-10-29T16:00+00:00","now":true,"drive_min":40}],
         "best":{"depart_at":"2026-10-29T16:20+00:00","drive_min":30,"saving_min":10},"reason":null}
        """)
        defaults.set("24", forKey: Units.clockKey)
        let d = try XCTUnwrap(LeaveLater.date("2026-10-29T16:20+00:00"))
        XCTAssertEqual(l.headline, "Leave at \(Units.time(d)) to save 10 min")
        XCTAssertFalse(Units.time(d).contains("M"))
        defaults.set("12", forKey: Units.clockKey)
        XCTAssertTrue(Units.time(d).hasSuffix("AM") || Units.time(d).hasSuffix("PM"))
    }

    func testNoBestMeansNoHeadline() throws {
        let l = try leaveLater(#"{"departures":[],"best":null,"reason":"Leaving now is as quick as any time in the next hour"}"#)
        XCTAssertNil(l.headline)
        XCTAssertTrue(l.bars().isEmpty)
    }

    func testDatesParseWithAndWithoutSeconds() {
        XCTAssertNotNil(LeaveLater.date("2026-10-29T16:20:00Z"))
        XCTAssertNotNil(LeaveLater.date("2026-10-29T16:20:00.123Z"))
        XCTAssertNotNil(LeaveLater.date("2026-10-29T16:20-07:00"))
        XCTAssertNil(LeaveLater.date("soon"))
    }

    func testOverridesWinOverThePhone() {
        defaults.set("c", forKey: Units.temperatureKey)
        XCTAssertEqual(Units.temperature(celsius: 20), "20\u{00B0}C")
        defaults.set("f", forKey: Units.temperatureKey)
        XCTAssertEqual(Units.temperature(celsius: 20), "68\u{00B0}F")
        defaults.set("", forKey: "cs.units")
        XCTAssertEqual(Units.useMiles, Units.phoneMiles)
        defaults.set("km", forKey: "cs.units")
        XCTAssertFalse(Units.useMiles)
    }

    func testCircleBodyClampsTheRadius() throws {
        let c = CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143)
        let b = WatchMath.body(name: "Home area", kinds: ["incident"], quiet: true, push: true, email: false, circle: (c, 90))
        XCTAssertEqual(b["type"] as? String, "circle")
        XCTAssertEqual(b["radius_km"] as? Double, WatchMath.maxRadiusKm)
        XCTAssertEqual(b["quiet_hours"] as? Bool, true)
        let small = WatchMath.body(name: "x", kinds: [], quiet: false, push: true, email: false, circle: (c, 0.2))
        XCTAssertEqual(small["radius_km"] as? Double, WatchMath.minRadiusKm)
    }

    func testRouteBodySamplesAndKeepsTheEnd() throws {
        let pts = (0 ..< 500).map { CLLocationCoordinate2D(latitude: 37.4 + Double($0) * 0.0005, longitude: -122.1) }
        let b = WatchMath.body(name: "Drive", kinds: ["closure"], quiet: true, push: true, email: false, route: pts)
        let sent = try XCTUnwrap(b["points"] as? [[Double]])
        XCTAssertLessThanOrEqual(sent.count, 90)
        XCTAssertEqual(sent.last, [pts.last!.latitude, pts.last!.longitude])
        XCTAssertEqual(b["buffer_km"] as? Double, WatchMath.bufferKm)
    }

    func testPolygonArea() {
        // A 10 km square is 100 sq km, give or take the projection.
        let c = CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143)
        let dLat = 5 / 110.574, dLon = 5 / (111.32 * cos(c.latitude * .pi / 180))
        let sq = [(-1.0, -1.0), (-1, 1), (1, 1), (1, -1)].map {
            CLLocationCoordinate2D(latitude: c.latitude + $0.0 * dLat, longitude: c.longitude + $0.1 * dLon)
        }
        XCTAssertEqual(WatchMath.polygonSqKm(sq), 100, accuracy: 1)
        XCTAssertEqual(WatchMath.polygonSqKm(Array(sq.prefix(2))), 0)
    }

    func testMercatorRoundTripsAndScales() {
        let c = CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143)
        let m = Mercator(center: c, zoom: 11, size: CGSize(width: 390, height: 500))
        let mid = m.point(c)
        XCTAssertEqual(mid.x, 195, accuracy: 0.01)
        XCTAssertEqual(mid.y, 250, accuracy: 0.01)
        let back = m.coordinate(CGPoint(x: 300, y: 100))
        let again = m.point(back)
        XCTAssertEqual(again.x, 300, accuracy: 0.01)
        XCTAssertEqual(again.y, 100, accuracy: 0.01)
        // 12 mi of radius in 140 points.
        let z = Mercator.zoom(fitting: 19_312, in: 140, at: c.latitude)
        let at = Mercator(center: c, zoom: z, size: .zero)
        XCTAssertEqual(at.pointsPerMeter * 19_312, 140, accuracy: 0.01)
    }

    func testReportWording() {
        XCTAssertEqual(ReportGrid.bound(180), "southbound")
        XCTAssertEqual(ReportGrid.bound(350), "northbound")
        XCTAssertEqual(ReportGrid.bound(95), "eastbound")
        XCTAssertNil(ReportGrid.bound(-1))
        XCTAssertNil(ReportGrid.bound(nil))
        XCTAssertEqual(ReportGrid.description(note: "  ", lane: .left), "Left lane")
        XCTAssertEqual(ReportGrid.description(note: "Two cars", lane: .shoulder), "Shoulder. Two cars")
        XCTAssertEqual(ReportGrid.description(note: "Two cars", lane: nil), "Two cars")
        let l = ReportGrid.layout(.right)
        XCTAssertEqual(l.lanes.filter(\.closed).map(\.n), [4])
        XCTAssertTrue(ReportGrid.layout(.shoulder).rightShoulderClosed)
    }
}
