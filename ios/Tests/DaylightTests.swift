import XCTest
import CoreLocation

/// The sun's height for the "Dark after sunset" theme.
final class DaylightTests: XCTestCase {
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ zone: String) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    private let la = "America/Los_Angeles"

    func testNoonIsDayAndMidnightIsNight() {
        XCTAssertTrue(Daylight.isDay(here: sf, at: at(2026, 6, 21, 12, 0, la)))
        XCTAssertFalse(Daylight.isDay(here: sf, at: at(2026, 6, 21, 0, 0, la)))
        XCTAssertTrue(Daylight.isDay(here: london, at: at(2026, 12, 21, 12, 0, "Europe/London")))
        XCTAssertFalse(Daylight.isDay(here: london, at: at(2026, 12, 21, 18, 0, "Europe/London")))
    }

    func testItTurnsAtSunsetForThePlace() {
        // San Francisco, 21 June 2026: sunset is about 8:35 in the evening.
        XCTAssertTrue(Daylight.isDay(here: sf, at: at(2026, 6, 21, 20, 20, la)))
        XCTAssertFalse(Daylight.isDay(here: sf, at: at(2026, 6, 21, 20, 50, la)))
        // And 21 December: sunrise about 7:21, sunset about 4:55.
        XCTAssertFalse(Daylight.isDay(here: sf, at: at(2026, 12, 21, 7, 5, la)))
        XCTAssertTrue(Daylight.isDay(here: sf, at: at(2026, 12, 21, 7, 40, la)))
        XCTAssertTrue(Daylight.isDay(here: sf, at: at(2026, 12, 21, 16, 40, la)))
        XCTAssertFalse(Daylight.isDay(here: sf, at: at(2026, 12, 21, 17, 10, la)))
    }

    func testTheSunIsHighestNearLocalNoon() {
        XCTAssertEqual(Daylight.sunElevation(lat: sf.latitude, lon: sf.longitude, at: at(2026, 6, 21, 13, 11, la)), 75.7, accuracy: 0.5)
    }

    func testWithoutAPositionItGoesByTheClock() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        XCTAssertTrue(Daylight.isDay(here: nil, at: at(2026, 3, 3, 7, 0, "America/Chicago"), calendar: c))
        XCTAssertTrue(Daylight.isDay(here: nil, at: at(2026, 3, 3, 18, 59, "America/Chicago"), calendar: c))
        XCTAssertFalse(Daylight.isDay(here: nil, at: at(2026, 3, 3, 19, 0, "America/Chicago"), calendar: c))
        XCTAssertFalse(Daylight.isDay(here: nil, at: at(2026, 3, 3, 6, 59, "America/Chicago"), calendar: c))
    }
}
