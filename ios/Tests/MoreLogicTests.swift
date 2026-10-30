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

    // The US map file's index entries for three 10 km boxes, cut on
    // 2026-10-29 from build 20261001 (one entry per tile that holds data).
    // The same file put a 40 by 48 km Bay Area box at 48.1 MB, a 40 km
    // box of Nevada desert at 1.2 MB and 40 km of rural Iowa at 8.8 MB.
    static let paloAltoIndex = "vQEAAQcZZpkD4QyHM5nMAeawBpfDGQHcjGYBAQHyspgDAQcBysvhDAEBAQEBGQEBAQEBp66GMwMBAQEBAQEBAQEBAQEBAQQB" +
            "YwEEAQEBAQEBAQEBAQEBAQEDmrmZzAENAQEBAQEBAwEDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQMB" +
            "ARABAwGKAwEBAQEBAQENAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEDAQMBAQEBAQEBAQoB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB64kEybwE8IIExfgDzrkC9oQF9MUDnrUGntII" +
            "y6UKktQGvNQE+KIE9PAEsaoCq+kDk8UDnZkEpf4BzI0DwJwCupoFiaoE/cIEu/oE9oIDnp4B7B3mrwG4pwTPnASP9QHP5QG9" +
            "JuSIAc/GAebEBduvA6ezA7y6As+3A8DgA7OZA8+/Aa7GA7eaBPq6A/7+A5fnAtGLAf71Aax9uQHyEKZMuAmKMtzFAcPnA4Hc" +
            "AouaBLKKBNHXBKPcAoyIA6bUAtmmApm/Aqm7AZsSkw3eHraAAfWNAeIR30uyswGYhgSXngS32wPHxwGGoAK00gGhuQG49QLz" +
            "qwOrggK71wGQXYmqAbemAtLxAbHhAcOYA+DSA8qpA87CA52gA5qrA/b8AsOAA829AvWZAaBGiD71hwGqsgHGjALG4AGVkAPu" +
            "pQPw8wLo3QKl4AKZlgOihQLaxwL70AKvnwPj0gGlnwHQOoYpoA702wKTrALZPbwdvssB3FP3GKoBrAG6AV+4AawBxQTVFfoM" +
            "sE/bLLgBrQGsAbkB/gqyF5gM1g/dHZMg4UaOkAGrugHtowP+9wKN2gLTyQK+jwLqmwHplALO8wHtmAPz6ALu6QL3+gK31wPJ" +
            "lgP44wPtigS/7gOdpQTDswX7ugXx/gK06gGhjgLs7QHnoQHKowKl8gGxnwG/kQL/xwLgkwGRWq7pAfT3AgEAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    static let nevadaIndex = "xwEAAQcZZpkD5AyPM7vMAeuxBqzHGbKdZgHF9ZgDAQEBAQGU1uMMAQUBAwEBAQEBAwHQ2I4zAQEBAQEBARMBAQENAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQ0BAQO94rrMAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQFJAQEBAQEBAQEBAQEBAQEBMQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQMB" +
            "ATUBAQMBAQ0BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAeuJBMm8BPCC" +
            "BMX4A865AvaEBfTxAsfqAe+BAdIxrQjaAqsHgwf4BZMFmQeVBuoQwwO9BocD1wLPAsMD6AO1A4MF8gOBA8MDoAO0AbECtAOz" +
            "Av4EtAXIA74CsgPsAt8B0wH0AewBqQPOAfABngKZA/4B8QGBApABkAH+AqwDpQPiAowDpgSvAqcDvAG7AfEC6QL1ApABvQG4" +
            "AbQBkAGQAZABkAGQAa8C7QLqAs0CkAGQAZABkAHEAqADkAHLA/UD0wL9AsAC9gOaA5kBkAGkAuwB8AG8AYkClgNISNoCqAJI" +
            "jQKIAkhISN8BSL0BvQGvAd8BSEjSAckBSEjeAcwBSPACxQJI1AFISEhItgHqAf0BzgHwAUjbAfsBxwKAAkj3AZgBlQGWAUi1" +
            "AUiUAZABkAGBApABkAGQAZABkAGQAZABkAH1AZABkAGoA4oCjwKvAsQCrwKIArUCqwKmAsICSJcBkAGqAvECkAG9AbIEsgK4" +
            "AbMCgwO+AbgBuwGoAagBqAEBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    static let iowaIndex = "3gEAAQcaZ5wD8AzBM4POAQOLuAYLrOAZLa+BZ7UBu4WcAwHTBQHqlfAMAQEBAQEBAckWAQEBAQEBAabXwDMBBAEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEEAaRaBAEBAQEBAQEFAQEBAQEBAQSZ3YLOAQEBAQEBDQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQQBAwEEAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBDQEBAQEBkekCAQ0BAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEDAQEVAQEDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBDQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
            "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQHriQTJvATwggT3oQWm8QPkvgL60QHt3gHczQK1" +
            "uAH0iQaC0wLKrQSNwAG0kwS7hwKD5wGUtwOI2gKmebkeyjui4gGrc8PcAY6DBPj8AohguHG42QGLzwLaedFfvWnzEosO/hnh" +
            "CcsZoRScXORPoFy8YqhJrxLkJZ9BhD7PJZO8AZt4tcMB7ckC7+gCst8B3l+ngwOrYcIYljW4rAHD1AGZngKmoAKAkwKIgQGQ" +
            "TfFCuBbYML0izUytMIsR4wfvDeoGgwz2CJ4FtwamB7MF/AvaDooLgwqYCoMT/wWABdAX4Cj6TNcjmxqHHJkjvyndJqIl3STm" +
            "J5Ac+yyMK7oszDX/LYUNghCODPwGwwa2Cq8PzwX0GI4bji6CHdwljQzRGbw2w6MB/Gj7HNER/lSYYsdUnVSiYtV6psMB0ewB" +
            "irwC5tAB1KgBzIsB/+UC4qoCw7wBp4YBolrvVOA10Rq9G+o53uIC3twD44ABn7MB2ijaT+Ej4Qm2CN4X2xaSIoQg402RT9h3" +
            "+5sB5hz9MLx+kosBy23SnQHfqAHDwQGcWOx7x58BtbcBz7oBzcAByXuXGOF8xzLRGasaqC2KGowd8Qf1BdgKxA/9E+IImA/D" +
            "DssR1DOrJ+oT4hPOJoIPwg6ZB4MOmgaPCLUEpQXJA9gE8AOSB+oMzQWXBZoCAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    private func measured(_ index: String, _ s: Double, _ w: Double, _ n: Double, _ e: Double) -> Int64? {
        guard let data = Data(base64Encoded: index), let root = PMTilesMath.directory(data),
              let ids = PMTilesMath.tileIds(south: s, west: w, north: n, east: e, maxZoom: 15) else { return nil }
        let r = PMTilesMath.sum(ids: ids, root: root, leaves: [:])
        XCTAssertTrue(r.missing.isEmpty)
        return r.bytes
    }

    func testAreaSizeComesFromTheMapIndex() throws {
        // A city and the desert differ more than tenfold for the same box,
        // so the picker adds up real tiles rather than a state's average.
        let city = try XCTUnwrap(measured(Self.paloAltoIndex, 37.40, -122.20, 37.49, -122.09))
        let farm = try XCTUnwrap(measured(Self.iowaIndex, 41.98, -93.66, 42.07, -93.54))
        let desert = try XCTUnwrap(measured(Self.nevadaIndex, 39.0, -117.0, 39.09, -116.885))
        XCTAssertEqual(city, 7_147_974)
        XCTAssertEqual(farm, 3_127_138)
        XCTAssertEqual(desert, 548_134)
        XCTAssertEqual(AreaMath.aboutText(city), "About 7 MB")
        XCTAssertEqual(AreaMath.aboutText(desert), "About 1 MB")
        XCTAssertGreaterThan(city, desert * 10)
    }

    func testTileIdsMatchTheSpec() {
        XCTAssertEqual(PMTilesMath.tileId(z: 0, x: 0, y: 0), 0)
        XCTAssertEqual([PMTilesMath.tileId(z: 1, x: 0, y: 0), PMTilesMath.tileId(z: 1, x: 0, y: 1),
                        PMTilesMath.tileId(z: 1, x: 1, y: 1), PMTilesMath.tileId(z: 1, x: 1, y: 0)], [1, 2, 3, 4])
        XCTAssertEqual(PMTilesMath.tileId(z: 2, x: 0, y: 0), 5)
        XCTAssertEqual(PMTilesMath.tileId(z: 12, x: 3423, y: 1763), 19_078_479)
        // The 40 by 48 km Bay Area box touches 2,844 tiles from zoom 0 to 15.
        XCTAssertEqual(PMTilesMath.tileIds(south: 37.25, west: -122.36, north: 37.68, east: -121.91, maxZoom: 15)?.count, 2844)
        XCTAssertNil(PMTilesMath.tileIds(south: 30, west: -125, north: 49, east: -66, maxZoom: 15))
    }

    func testDirectoryReadsRunsLeavesAndGzip() throws {
        // Three entries: tile 5, tiles 6-7, and a leaf for 300 on.
        let raw = try XCTUnwrap(Data(base64Encoded: "AwUBpgIBAgBkwLgCiQYBAIkn"))
        let dir = try XCTUnwrap(PMTilesMath.directory(raw))
        XCTAssertEqual(dir, [.init(tileId: 5, runLength: 1, length: 100, offset: 0),
                             .init(tileId: 6, runLength: 2, length: 40_000, offset: 100),
                             .init(tileId: 300, runLength: 0, length: 777, offset: 5000)])
        let zipped = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAACCmNmZVzGxMjEkHJgB1MnGyNDpzoAl8xvUBIAAAA="))
        XCTAssertEqual(PMTilesMath.gunzip(zipped), raw)
        XCTAssertEqual(PMTilesMath.find(7, in: dir)?.length, 40_000)
        XCTAssertNil(PMTilesMath.find(8, in: dir))
        XCTAssertNil(PMTilesMath.find(4, in: dir))
        let r = PMTilesMath.sum(ids: [5, 6, 7, 8, 310], root: dir, leaves: [:])
        XCTAssertEqual(r.bytes, 80_100)
        XCTAssertEqual(r.missing.map(\.offset), [5000])
        let leaf = [PMTilesMath.Entry(tileId: 310, runLength: 1, length: 9, offset: 0)]
        XCTAssertEqual(PMTilesMath.sum(ids: [310], root: dir, leaves: [5000: leaf]).bytes, 9)
        XCTAssertNil(PMTilesMath.directory(Data([0x05, 0x01])))
        XCTAssertNil(PMTilesMath.header(Data(count: 127)))
    }

    func testExtractBoxReachesABufferPastTheSides() {
        let b = AreaMath.extractBox(south: 37.4, west: -122.2, north: 37.5, east: -122.1)
        XCTAssertEqual(b.south, 37.4)
        XCTAssertEqual(b.north, 37.5)
        let km = AreaMath.widthKm(south: b.south, west: b.west, north: b.north, east: -122.2)
        XCTAssertEqual(km, AreaMath.bufferM / 1000, accuracy: 0.05)
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
