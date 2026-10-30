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
}
