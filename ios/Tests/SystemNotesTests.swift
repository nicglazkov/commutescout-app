import XCTest

/// Which app message shows while driving, and the words it uses.
final class SystemNotesTests: XCTestCase {
    private func input(_ change: (inout SystemNotes.Input) -> Void) -> SystemNotes.Input {
        var i = SystemNotes.Input(navigating: true)
        change(&i)
        return i
    }

    func testNothingWhileBrowsingOrWhenAllIsWell() {
        XCTAssertNil(SystemNotes.pick(SystemNotes.Input(navigating: false, online: false)))
        XCTAssertNil(SystemNotes.pick(input { $0.speed = 65; $0.limit = 65; $0.fixAge = 3 }))
    }

    func testSpeedingNeedsMoreThanFiveOver() {
        XCTAssertNil(SystemNotes.pick(input { $0.speed = 70; $0.limit = 65 }))
        let n = SystemNotes.pick(input { $0.speed = 72; $0.limit = 65 })
        XCTAssertEqual(n?.id, .speeding)
        XCTAssertEqual(n?.detail, "72 in a 65")
        XCTAssertEqual(n?.tone, .high)
        XCTAssertNil(SystemNotes.pick(input { $0.speed = 90; $0.limit = nil }))
    }

    func testLostSignalAfterTwelveSeconds() {
        XCTAssertNil(SystemNotes.pick(input { $0.fixAge = 12 }))
        let n = SystemNotes.pick(input { $0.fixAge = 13; $0.speed = 90; $0.limit = 65 })
        XCTAssertEqual(n?.id, .gps, "a lost signal outranks speeding: the speed is stale")
        XCTAssertEqual(n?.tone, .clear)
    }

    func testOrderArrivalThenOfflineThenReroute() {
        let all = input { $0.arrivedAt = "San Jose Airport"; $0.online = false; $0.rerouting = true; $0.fixAge = 60 }
        XCTAssertEqual(SystemNotes.pick(all)?.id, .arrive)
        XCTAssertEqual(SystemNotes.pick(input { $0.online = false; $0.rerouting = true })?.id, .offline)
        XCTAssertEqual(SystemNotes.pick(input { $0.rerouting = true; $0.fixAge = 60 })?.id, .reroute)
    }

    func testArrivalSitsInlineWithDone() {
        let n = SystemNotes.pick(input { $0.arrivedAt = "San Jose Airport, Terminal B" })
        XCTAssertEqual(n?.primary, "Done")
        XCTAssertEqual(n?.tone, .good)
        XCTAssertTrue(n?.inline ?? false)
    }

    func testConfirmAsksWithTwoButtons() {
        let n = SystemNotes.pick(input { $0.confirmKind = .hazard; $0.confirmAgo = "Reported 4 min ago, 0.1 mi behind you" })
        XCTAssertEqual(n?.title, "Is the object still there?")
        XCTAssertEqual(n?.secondary, "Gone")
        XCTAssertFalse(n?.inline ?? true)
    }

    func testOfflineUsesTheAppsOwnWordsWhenGiven() {
        let n = SystemNotes.pick(input { $0.online = false; $0.offlineWords = ("No signal to reroute", "Head back to the route.") })
        XCTAssertEqual(n?.title, "No signal to reroute")
        XCTAssertEqual(n?.tone, .clear)
        XCTAssertEqual(SystemNotes.confirmTitle(.police), "Are the police still there?")
    }

    func testOfflineSaysHowOldTheDataIs() {
        XCTAssertEqual(SystemNotes.offline(since: "8:14 AM").detail,
                       "Road data from 8:14 AM. Live updates resume when you are back online.")
    }

    func testAWatchAlertTappedOnATripSaysItWaits() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var ref = AlertRef(kind: "incident", lat: 37.442, lon: -122.143, title: "Crash on US-101", watch: "Home area")
        let note = SystemNotes.watch(ref, now: now)
        XCTAssertEqual(note.title, "Home area: crash on US-101")
        XCTAssertEqual(note.detail, "Opens when this trip ends.")
        XCTAssertEqual(note.primary, "Show on map")
        XCTAssertEqual(note.tone, .good)

        ref.status = "cleared"
        ref.sentAt = now.addingTimeInterval(-25 * 60)
        XCTAssertEqual(SystemNotes.watch(ref, now: now).detail, "Cleared 25 min ago. Opens when this trip ends.")

        // Last in line, and only on a trip.
        XCTAssertEqual(SystemNotes.pick(.init(navigating: true, watch: note))?.id, .watch)
        XCTAssertEqual(SystemNotes.pick(.init(navigating: true, rerouting: true, watch: note))?.id, .reroute)
        XCTAssertNil(SystemNotes.pick(.init(navigating: false, watch: note)))
    }

    func testEverySampleHasTheMockupTone() {
        let tones = Dictionary(uniqueKeysWithValues: SystemNotes.samples.map { ($0.id, $0.tone) })
        XCTAssertEqual(tones[.confirm], .mid)
        XCTAssertEqual(tones[.speeding], .high)
        XCTAssertEqual(tones[.gps], .clear)
        XCTAssertEqual(tones[.offline], .clear)
        XCTAssertEqual(tones[.watch], .good)
        XCTAssertEqual(tones[.arrive], .good)
    }
}

/// The room the map makes for a tucked alert.
final class CameraRoomTests: XCTestCase {
    func testRoomOnlyOnATripWithAnAlert() {
        XCTAssertEqual(CameraRoom.target(navigating: false, alertShown: true, opened: false), 0)
        XCTAssertEqual(CameraRoom.target(navigating: true, alertShown: false, opened: true), 0)
        XCTAssertEqual(CameraRoom.target(navigating: true, alertShown: true, opened: false), 84)
        XCTAssertEqual(CameraRoom.target(navigating: true, alertShown: true, opened: true), 104)
    }

    func testRoomLowersThePuckByAsMuch() {
        // The puck is in the middle of the bottom minHeight points.
        let lower = (CameraRoom.minHeight(room: 0) - CameraRoom.minHeight(room: 84)) / 2
        XCTAssertEqual(lower, 84)
    }

    func testEaseOutStartsFastAndEnds() {
        XCTAssertEqual(CameraRoom.ease(0), 0, accuracy: 0.001)
        XCTAssertEqual(CameraRoom.ease(1), 1, accuracy: 0.001)
        XCTAssertGreaterThan(CameraRoom.ease(0.2), 0.6)
        XCTAssertLessThan(CameraRoom.ease(0.5), 1)
    }
}
