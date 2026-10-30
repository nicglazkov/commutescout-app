import CoreLocation
import XCTest

/// The marketplace, plugin page and offline maps' logic: filters, the
/// count line, who makes a plugin, area sizes and spans, the storage bar
/// and saved-map dates.
final class MoreLogicTests: XCTestCase {
    func testFilterSplitsOfficialFromPluginData() {
        XCTAssertTrue(Market.shows(.all, trust: "official"))
        XCTAssertTrue(Market.shows(.all, trust: nil))
        XCTAssertTrue(Market.shows(.official, trust: "official"))
        XCTAssertFalse(Market.shows(.official, trust: "community"))
        XCTAssertTrue(Market.shows(.plugin, trust: nil))
        XCTAssertFalse(Market.shows(.plugin, trust: "official"))
        XCTAssertEqual(Market.Filter.allCases.map(\.rawValue), ["All", "Official data", "Plugin data"])
    }

    func testAddedIncludesPluginsSwitchedOffForNow() {
        XCTAssertTrue(Market.isAdded("a", hidden: [], paused: []))
        XCTAssertFalse(Market.isAdded("a", hidden: ["a"], paused: []))
        XCTAssertTrue(Market.isAdded("a", hidden: ["a"], paused: ["a"]))
    }

    func testCountLine() {
        XCTAssertEqual(Market.countLine(visible: 6, added: 2), "2 added, 4 more to try")
        XCTAssertEqual(Market.countLine(visible: 3, added: 3), "All 3 added")
        XCTAssertEqual(Market.countLine(visible: 4, added: 0), "4 to try")
        XCTAssertEqual(Market.countLine(visible: 0, added: 0), "Nothing listed here yet")
    }

    func testMakerLine() {
        XCTAssertEqual(Market.maker(name: "Cameras", trust: "official", tier: "approved", attribution: nil), "By CommuteScout")
        XCTAssertEqual(Market.maker(name: "Mine", trust: nil, tier: "private", attribution: "Me"), "Added by you")
        XCTAssertEqual(Market.maker(name: "Cameras", trust: nil, tier: "approved", attribution: "OpenStreetMap"), "By OpenStreetMap")
        XCTAssertEqual(Market.maker(name: "Cameras", trust: nil, tier: "unreviewed", attribution: "Cameras"), "By its community")
    }

    func testGlyphAndPurpose() {
        XCTAssertEqual(Market.glyph(kinds: ["CAMERA_SPEED", "CAMERA_RED_LIGHT"]), "camera")
        XCTAssertEqual(Market.glyph(kinds: ["POLICE", "HAZARD"]), "people")
        XCTAssertEqual(Market.glyph(kinds: ["CHAINS"]), "chain")
        XCTAssertEqual(Market.glyph(kinds: []), "piece")
        XCTAssertEqual(Market.purpose(summary: "  Speed cameras. ", kindsLabel: "cameras"), "Speed cameras.")
        XCTAssertEqual(Market.purpose(summary: nil, kindsLabel: "cameras"), "Shows cameras on your map.")
        XCTAssertEqual(Market.purpose(summary: "", kindsLabel: ""), "Alerts for your map.")
    }

    func testStatusWording() {
        XCTAssertEqual(Market.every(30), "Every 30 s")
        XCTAssertEqual(Market.every(300), "Every 5 min")
        XCTAssertEqual(Market.every(7200), "Every 2 h")
        XCTAssertEqual(Market.alertsNow(0), "None")
        XCTAssertEqual(Market.alertsNow(1), "1 alert")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoMin = ISO8601DateFormatter().string(from: now.addingTimeInterval(-125))
        let a = Market.answering(ok: true, lastOk: twoMin, now: now)
        XCTAssertEqual(a.text, "Yes, 2 min ago")
        XCTAssertEqual(a.good, true)
        XCTAssertEqual(Market.answering(ok: false, lastOk: nil).text, "No")
        XCTAssertNil(Market.answering(ok: nil, lastOk: nil).good)
        XCTAssertEqual(Market.footnote(attribution: "OpenStreetMap"), "Data from OpenStreetMap. Verify an alert before you rely on it.")
    }

    func testUsesNeverIncludePlacesAndSayHowTheyAsk() {
        let viaUs = Market.uses(ownSession: false, direct: false, reports: false)
        XCTAssertEqual(viaUs.first?.title, "The area on your map, through CommuteScout")
        XCTAssertEqual(viaUs.last?.allowed, false)
        let own = Market.uses(ownSession: true, direct: true, reports: true)
        XCTAssertTrue(own.contains { $0.title == "Your sign-in" })
        XCTAssertTrue(own.contains { $0.title == "Reports you choose to send" })
        XCTAssertEqual(own.filter { !$0.allowed }.count, 1)
    }

    func testAreaSizeText() {
        XCTAssertEqual(AreaMath.aboutText(312_000_000), "About 310 MB")
        XCTAssertEqual(AreaMath.aboutText(1_600_000_000), "About 1.6 GB")
        XCTAssertEqual(AreaMath.aboutText(4_200_000), "About 4 MB")
        XCTAssertEqual(AreaMath.aboutText(100), "About 1 MB")
        XCTAssertEqual(AreaMath.spanText(widthKm: 35.4, heightKm: 25.7, miles: true), "22 by 16 mi")
        XCTAssertEqual(AreaMath.spanText(widthKm: 35.4, heightKm: 25.7, miles: false), "35 by 26 km")
    }

    func testAreaFitsAndPathCoversTheBox() {
        let s = 37.34, w = -122.25, n = 37.54, e = -122.05
        XCTAssertTrue(AreaMath.fits(south: s, west: w, north: n, east: e))
        XCTAssertFalse(AreaMath.fits(south: 36, west: -123, north: 39, east: -120))
        XCTAssertFalse(AreaMath.fits(south: .nan, west: w, north: n, east: e))
        XCTAssertTrue(AreaMath.serpentine(south: n, west: w, north: s, east: e).isEmpty)
        let path = AreaMath.serpentine(south: s, west: w, north: n, east: e)
        XCTAssertGreaterThan(path.count, 4)
        for c in path {
            XCTAssertGreaterThanOrEqual(c.latitude, s - 1e-9)
            XCTAssertLessThanOrEqual(c.latitude, n + 1e-9)
        }
        // Rows are two buffers apart, so every point of the box is within one buffer of the path.
        let lats = Set(path.map { ($0.latitude * 1e6).rounded() }).sorted()
        XCTAssertLessThanOrEqual((lats.first! / 1e6 - s) * 110_540, AreaMath.bufferM + 1)
        XCTAssertLessThanOrEqual((n - lats.last! / 1e6) * 110_540, AreaMath.bufferM + 1)
    }

    func testEstimateUsesTheStateDensity() {
        let d = AreaMath.density(stateBytes: 1_000_000_000, south: 0, west: 0, north: 1, east: 1)
        XCTAssertNotNil(d)
        XCTAssertNil(AreaMath.density(stateBytes: nil, south: 0, west: 0, north: 1, east: 1))
        XCTAssertEqual(AreaMath.estimateBytes(widthKm: 10, heightKm: 10, bytesPerSqKm: nil), 25_000_000)
        XCTAssertEqual(AreaMath.estimateBytes(widthKm: 10, heightKm: 10, bytesPerSqKm: 1000), 100_000)
        XCTAssertEqual(AreaMath.estimateBytes(widthKm: .nan, heightKm: 10, bytesPerSqKm: nil), 0)
        XCTAssertEqual(AreaMath.estimateBytes(widthKm: .infinity, heightKm: 10, bytesPerSqKm: nil), 0)
    }

    func testStorageSplitKeepsASliverVisible() {
        XCTAssertEqual(StorageSplit.of(states: 0, areas: 0, trips: 0), StorageSplit(states: 0, areas: 0, trips: 0))
        let s = StorageSplit.of(states: 1_000_000, areas: 0, trips: 1)
        XCTAssertEqual(s.areas, 0)
        XCTAssertGreaterThan(s.trips, 0.025)
        XCTAssertEqual(s.states + s.areas + s.trips, 1, accuracy: 1e-9)
        let even = StorageSplit.of(states: 1, areas: 1, trips: 2)
        XCTAssertEqual(even.trips, 0.5, accuracy: 1e-9)
    }

    func testSavedWhenAndSize() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        let clock: (Date) -> String = { _ in "6:40 AM" }
        XCTAssertEqual(SavedText.when(cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 6, minute: 40))!,
                                      now: now, calendar: cal, clock: clock), "today, 6:40 AM")
        XCTAssertEqual(SavedText.when(cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 21))!,
                                      now: now, calendar: cal, clock: clock), "yesterday, 6:40 AM")
        XCTAssertEqual(SavedText.when(cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!,
                                      now: now, calendar: cal, clock: clock), "Oct 12")
        XCTAssertEqual(SavedText.size(1_400_000_000), "1.4 GB")
        XCTAssertEqual(SavedText.size(312_000_000), "312 MB")
        XCTAssertEqual(SavedText.size(512_000), "512 KB")
    }
}
