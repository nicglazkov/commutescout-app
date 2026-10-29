import XCTest

/// The event sheet's words and the tapped-alert plumbing, without views.
final class EventTextTests: XCTestCase {
    private func marker(_ json: String) -> RoadMarker {
        try! JSONDecoder().decode(RoadMarker.self, from: Data(json.utf8))
    }

    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let ny = TimeZone(identifier: "America/New_York")!
    // Wednesday 2026-10-28 10:00 in California.
    private let now = Date(timeIntervalSince1970: 1_793_206_800)

    func testWatchKindsMapToMarkerKinds() {
        XCTAssertEqual(AlertRef.markerKind("closure"), "lane_closure")
        XCTAssertEqual(AlertRef.markerKind("chain"), "chain_control")
        XCTAssertEqual(AlertRef.markerKind("fire"), "wildfire")
        XCTAssertEqual(AlertRef.markerKind("incident"), "incident")
        XCTAssertEqual(AlertRef.markerKind("lane_closure"), "lane_closure")
    }

    func testPushDataWithTheEvent() {
        let ref = AlertRef.from(userInfo: [
            "url": "https://commutescout.com/?focus=37.44200,-122.14300&k=closure",
            "event_id": "lcs:12", "event_kind": "closure", "event_lat": "37.442", "event_lon": "-122.143",
            "event_title": "I-280 Lane closure", "event_watch": "Home", "event_sent_at": "1793206200",
        ])
        XCTAssertEqual(ref?.id, "lcs:12")
        XCTAssertEqual(ref?.kind, "lane_closure")
        XCTAssertEqual(ref?.title, "I-280 Lane closure")
        XCTAssertEqual(ref?.watch, "Home")
        XCTAssertEqual(ref?.sentAt, Date(timeIntervalSince1970: 1_793_206_200))
    }

    func testOlderPushWithOnlyTheLink() {
        let ref = AlertRef.from(userInfo: [
            "url": "https://commutescout.com/?focus=37.44200,-122.14300&k=fire",
            "aps": ["alert": ["title": "Home: Wildfire: Oak", "body": "120 acres"]],
        ])
        XCTAssertNil(ref?.id)
        XCTAssertEqual(ref?.kind, "wildfire")
        XCTAssertEqual(ref?.lat, 37.442)
        XCTAssertEqual(ref?.title, "Home: Wildfire: Oak")
        XCTAssertNil(AlertRef.from(userInfo: ["url": "https://commutescout.com/watch"]))
    }

    func testLocalMatchPrefersTheChpIdThenNearest() {
        let ref = AlertRef(id: "chp:A1", kind: "incident", lat: 37.442, lon: -122.143)
        let close = marker(#"{"kind":"incident","id":"OTHER","lat":37.4421,"lon":-122.1431}"#)
        let same = marker(#"{"kind":"incident","id":"A1","lat":37.45,"lon":-122.15}"#)
        XCTAssertEqual(ref.localMatch(in: [close, same])?.id, "A1")
        let fire = AlertRef(id: nil, kind: "wildfire", lat: 37.442, lon: -122.143)
        let near = marker(#"{"kind":"wildfire","lat":37.4425,"lon":-122.1435}"#)
        let far = marker(#"{"kind":"wildfire","lat":37.46,"lon":-122.143}"#)
        XCTAssertEqual(fire.localMatch(in: [far, near])?.lat, 37.4425)
        XCTAssertNil(fire.localMatch(in: [far]))
    }

    func testStatusResolution() {
        let local = marker(#"{"kind":"incident","id":"A1","lat":37.442,"lon":-122.143}"#)
        // No answer: the map's own copy, unconfirmed; nothing at all, unknown.
        XCTAssertEqual(AlertFocus.resolve(nil, local: local).0, .active(confirmed: false))
        XCTAssertEqual(AlertFocus.resolve(nil, local: nil).0, .unknown)
        let decode = { (s: String) in try! JSONDecoder().decode(EventStatusReply.self, from: Data(s.utf8)) }
        let cleared = AlertFocus.resolve(decode(#"""
            {"state":"cleared","cleared_at":"2026-10-28T16:40:00+00:00",
             "nearby":{"kind":"incident","lat":37.442,"lon":-122.143}}
            """#), local: local)
        XCTAssertEqual(cleared.0, .cleared(at: EventContent.date("2026-10-28T16:40:00+00:00")))
        XCTAssertNil(cleared.1, "a cleared event never shows another marker as itself")
        XCTAssertNotNil(cleared.2)
        let changed = AlertFocus.resolve(decode(#"{"state":"changed","event":{"title":"Chain control R-2 on I-80"}}"#), local: nil)
        XCTAssertEqual(changed.0, .changed(nowTitle: "Chain control R-2 on I-80"))
        XCTAssertEqual(AlertFocus.resolve(decode(#"{"state":"gone"}"#), local: local).0, .gone)
    }

    func testClosureCopyAndSchedule() {
        // Scheduled to end tomorrow at 6 AM in California.
        let m = marker(#"""
            {"kind":"lane_closure","lat":37.4,"lon":-122.1,"route":"I-280","county":"Santa Clara",
             "dir":"NB","cls":"full-roadway","lanes":"","work":"PavementRepair","delay_min":15,
             "since":1793199600,"until":1793278800,"label":"FULL CLOSURE // USE SR-85 DETOUR"}
            """#)
        let c = EventContent.make(m, now: now, viewerZone: la)
        XCTAssertEqual(c.chip, "Road closed")
        XCTAssertEqual(c.title, "I-280, Santa Clara")
        XCTAssertEqual(c.warning, "All lanes closed")
        XCTAssertEqual(c.body.first?.text, "Full closure. Use SR-85 detour.")
        XCTAssertEqual(c.facts.map(\.label), ["Work", "Delay"])
        XCTAssertEqual(c.facts.first?.value, "Pavement Repair")
        XCTAssertEqual(c.schedule?.head, "Scheduled to end tomorrow at 6:00 AM PDT (your timezone)")
        XCTAssertEqual(c.schedule?.tail, "That is about 20 hours from now. It started today at 8:00 AM.")
        XCTAssertEqual(c.schedule?.inYourZone, [])
        // Seen from New York the same times are converted.
        let east = EventContent.make(m, now: now, viewerZone: ny)
        XCTAssertEqual(east.schedule?.head, "Scheduled to end tomorrow at 6:00 AM PDT")
        XCTAssertEqual(east.schedule?.inYourZone.count, 2)
    }

    func testPastEndNeverClaimsTheRoadOpened() {
        let m = marker(#"{"kind":"lane_closure","lat":37.4,"lon":-122.1,"cls":"lane","until":1793199600}"#)
        let s = EventContent.make(m, now: now, viewerZone: la).schedule!
        XCTAssertTrue(s.head.hasPrefix("Was scheduled to end today at 8:00 AM"))
        XCTAssertEqual(s.tail, "That was about 2 hours ago. Caltrans has not reported it clear. Assume the restriction is still there.")
    }

    func testIncidentCopy() {
        let m = marker(#"""
            {"kind":"incident","id":"260718GG0075","lat":37.4,"lon":-122.1,"type":"1181-Trfc Collision-Minor Inj",
             "location":"Sr84 E / University Ave Onr","area":"Redwood City","dir":"eastbound",
             "reported":"2026-10-28T16:48:00+00:00","log_n":4}
            """#)
        let c = EventContent.make(m, now: now)
        XCTAssertEqual(c.chip, "Incident")
        XCTAssertEqual(c.ago, "12 min ago")
        XCTAssertEqual(c.title, "1181 Trfc Collision Minor Inj")
        XCTAssertEqual(c.subtitle, "Sr84 E / University Ave Onr")
        XCTAssertTrue(c.body.contains { $0.gloss && $0.text.hasPrefix("Collision with minor injuries") })
        XCTAssertEqual(c.facts, [.init(label: "Direction", value: "Affects the eastbound side")])
        XCTAssertEqual(c.foot, ["Reported 12 min ago", "Source: CHP Redwood City dispatch"])
        XCTAssertEqual(c.dispatch?.count, 4)
    }

    func testChainLegend() {
        let ca = EventContent.make(marker(#"{"kind":"chain_control","lat":39.3,"lon":-120.3,"status":"R2","route":"I-80"}"#), now: now)
        XCTAssertEqual(ca.title, "R-2 on I-80")
        XCTAssertEqual(ca.chain?.active?.0, "R-2")
        XCTAssertEqual(ca.chain?.others.map(\.0), ["R-1", "R-3"])
        let wa = EventContent.make(marker(#"""
            {"kind":"chain_control","lat":47.4,"lon":-121.4,"src":"WSDOT","route":"Snoqualmie Pass",
             "label":"Traction tires advised; Traction tires advised; Oversize vehicles prohibited"}
            """#), now: now)
        XCTAssertEqual(wa.chip, "Pass restriction")
        XCTAssertNil(wa.chain)
        XCTAssertEqual(wa.body.first?.text, "Traction tires advised. Oversize vehicles prohibited.")
    }

    func testShoutingAndRoads() {
        XCTAssertEqual(EventContent.shapeShout("Closed for paving"), "Closed for paving")
        XCTAssertEqual(EventContent.shapeShout("CLOSED DUE TO CRASH//USE US-50"), "Closed due to crash. Use US-50.")
        XCTAssertEqual(EventContent.splitRoad("US 89: Emergency Maintenance").road, "US 89")
        XCTAssertEqual(EventContent.humanize("rightLaneClosed"), "Right Lane Closed")
        XCTAssertEqual(EventContent.humanize("LANE_CLOSED"), "Lane closed")
        XCTAssertEqual(EventContent.chpGloss("SIG Alert"), EventContent.chpCodes[9].1)
        XCTAssertNil(EventContent.chpGloss("Assist CT"))
    }
}
