import XCTest

/// The Day Glass+ catalogs: every alert kind and every app message
/// renders, each with its own row.
final class DayGlassUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        // A fresh install asks for location and notifications first.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0 ..< 3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 3) else { break }
            for label in ["Allow While Using App", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
            sleep(1)
        }
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testEveryAlertKindHasARow() {
        let app = launch(["-csCatalog"])
        XCTAssertTrue(app.otherElements["alert-catalog"].waitForExistence(timeout: 10) || app.scrollViews["alert-catalog"].exists)
        for kind in ["crash", "closure", "chain", "fire", "hazard", "jam", "ice", "police", "sign", "camera", "toll"] {
            let row = app.descendants(matching: .any)["catalog-" + kind]
            if !row.exists { app.swipeUp() }
            XCTAssertTrue(row.waitForExistence(timeout: 3), "row for \(kind)")
        }
        attach(app, "every-alert")
    }

    func testEveryAppMessageRenders() {
        let app = launch(["-csCatalog", "system"])
        for id in ["faster", "confirm", "speeding", "gps", "offline", "watch", "arrive"] {
            let note = app.descendants(matching: .any)["catalog-note-" + id]
            if !note.exists { app.swipeUp() }
            XCTAssertTrue(note.waitForExistence(timeout: 5), "message \(id)")
        }
        XCTAssertTrue(app.buttons["note-arrive-primary"].exists)
        XCTAssertTrue(app.buttons["note-confirm-secondary"].exists)
        attach(app, "app-messages")
    }

    /// On a trip: the alert tucked under the card, then swiped away; the
    /// app's message takes the slot under the card once no alert shows.
    func testMessageTakesTheSlotOnceTheAlertLeaves() {
        let app = launch(["-csSimulate", "-csAutoDrive", "-csForceAlert", "crash", "-csForceNote", "gps"])
        let alert = app.descendants(matching: .any)["alert-banner"]
        XCTAssertTrue(alert.waitForExistence(timeout: 60), "an alert under the card")
        XCTAssertFalse(app.descendants(matching: .any)["note-gps"].exists, "no message while an alert is tucked")
        attach(app, "drive-room")
        // Live data may bring more alerts after the forced one: swipe each away.
        for _ in 0 ..< 20 where alert.exists {
            alert.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(app.descendants(matching: .any)["note-gps"].waitForExistence(timeout: 5))
        sleep(2)
        attach(app, "drive-no-room")
    }

    /// Browsing: Home, Work and the recent place in the tray, each opening the place.
    func testPlacesTrayShowsHomeWorkAndRecent() {
        let app = launch(["-csSamplePlaces", "-csSimulate"])
        let notNow = app.buttons["dismiss-trip"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        for id in ["home", "work", "recent"] {
            XCTAssertTrue(app.buttons["places-tray-" + id].waitForExistence(timeout: 10), "tray row \(id)")
        }
        XCTAssertTrue(app.buttons["places-tray-recent"].label.contains("Recent"))
        attach(app, "browse-tray")
        app.buttons["places-tray-work"].tap()
        XCTAssertFalse(app.buttons["places-tray-work"].waitForExistence(timeout: 2) && app.buttons["places-tray-work"].isHittable,
                       "the place card replaces the tray")
    }

    /// A cleared watch push: the capsule says it is over, the sheet shows
    /// the open road and what the alert said; Done closes it.
    func testClearedWatchPushOpensTheClearedView() {
        let app = launch(["-csWatchCleared", "-csSimulate"])
        let capsule = app.descendants(matching: .any)["watch-cleared-capsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["The crash on US-101 is over"].exists)
        XCTAssertTrue(app.staticTexts["This crash has cleared"].exists)
        attach(app, "watch-cleared")
        app.buttons["watch-cleared-done"].tap()
        XCTAssertFalse(capsule.waitForExistence(timeout: 2))
    }

    /// A summary push opens the watch areas.
    func testSummaryPushOpensWatchAreas() {
        let app = launch(["-csWatchSummary", "-csSimulate"])
        XCTAssertTrue(app.navigationBars["Watch areas"].waitForExistence(timeout: 15) || app.staticTexts["Watch areas"].waitForExistence(timeout: 2))
        attach(app, "watch-summary")
    }
}
