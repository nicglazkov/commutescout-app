import XCTest

/// Walks the settings pages and saves a picture of each to /tmp on the
/// Mac running the simulator, so a page can be looked at without a
/// phone in hand. Not a test of behaviour; it only fails when a page
/// cannot be reached.
final class PagesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-csSimulate", "-csOpenSettings"]
        app.launch()
    }

    private func shot(_ name: String, _ wait: UInt32 = 2) {
        sleep(wait)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/tmp/cs-page-\(name).png"))
    }

    /// Taps a row by its label. Settings is a lazy Form: a row below the
    /// fold does not exist until it is scrolled to, so swipe for it.
    private func open(_ row: String) {
        let cell = app.staticTexts[row].firstMatch
        for _ in 0 ..< 3 where !(cell.waitForExistence(timeout: 3) && cell.isHittable) { app.swipeUp() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), row)
        cell.tap()
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    func testSettingsPages() {
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 10))
        shot("settings")
        open("Appearance")
        shot("appearance")
        app.buttons["basemap-dark"].firstMatch.tap()
        shot("appearance-dark")
        app.buttons["basemap-auto"].firstMatch.tap()
        back()
        open("Map layers")
        shot("layers-everything")
        app.buttons["Plugins"].firstMatch.tap()
        shot("layers-plugins")
        app.buttons["Official"].firstMatch.tap()
        shot("layers-official")
        app.buttons["Everything"].firstMatch.tap()
        back()
        open("Offline maps")
        shot("offline")
        let trip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trip to'")).firstMatch
        if trip.waitForExistence(timeout: 3) {
            trip.tap()
            shot("offline-detail")
            app.buttons["page-back"].firstMatch.tap(); sleep(1)
        }
        app.buttons["page-back"].firstMatch.tap(); sleep(1)
        open("Saved places")
        shot("places")
        app.buttons["set-home"].firstMatch.tap()
        sleep(1)
        let field = app.textFields["place-search"].firstMatch
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("San Jose City Hall") }
        shot("places-picker", 3)
        app.buttons["Cancel"].firstMatch.tap()
        back()
        open("Plugins")
        shot("plugins", 3)
        if app.staticTexts["Speed and red light cameras"].firstMatch.waitForExistence(timeout: 5) {
            app.staticTexts["Speed and red light cameras"].firstMatch.tap()
            shot("plugin-status", 3)
            let check = app.buttons["plugin-check"].firstMatch
            for _ in 0 ..< 4 where !(check.exists && check.isHittable) { app.swipeUp() }
            if check.isHittable { check.tap() }
            shot("plugin-checked", 5)
            app.buttons["page-back"].firstMatch.tap(); sleep(1)
        }
        app.buttons["page-back"].firstMatch.tap(); sleep(1)
        for row in ["Units", "Navigation", "Alerts", "Help", "About"] {
            let cell = app.staticTexts[row].firstMatch
            if !cell.exists || !cell.isHittable { app.swipeUp() }
            if cell.waitForExistence(timeout: 3) { cell.tap(); shot("page-" + row.lowercased(), 1); back() }
        }
    }

    /// The Voice page in both themes, after picking a voice from the
    /// list and going back to Automatic.
    func testVoicePage() {
        for theme in ["light", "dark"] {
            app.terminate()
            app.launchArguments = ["-csSimulate", "-csOpenSettings", "-cs.theme", theme]
            app.launch()
            // The sheet from -csOpenSettings does not always survive the
            // relaunch; open it by hand when it is not up.
            if !app.staticTexts["Voice"].waitForExistence(timeout: 6) { app.buttons["settings"].firstMatch.tap() }
            open("Voice")
            XCTAssertTrue(app.buttons["voice-automatic"].waitForExistence(timeout: 5))
            shot("voice-\(theme)")
            let accents = app.switches["voice-all-accents"].firstMatch
            if accents.waitForExistence(timeout: 2) {
                accents.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                shot("voice-accents-\(theme)")
            }
            app.swipeUp()
            // The list is lazy: its rows exist once scrolled into view.
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'voice-com.apple.voice'")).firstMatch
            // System voices follow the CommuteScout ones in the same list.
            for _ in 0 ..< 3 where !row.waitForExistence(timeout: 2) { app.swipeUp() }
            XCTAssertTrue(row.exists, "a voice is listed")
            row.tap()
            XCTAssertTrue(row.isSelected, "a tapped voice is the one in use")
            shot("voice-picked-\(theme)", 3)
            app.swipeDown()
            if !app.buttons["voice-automatic"].firstMatch.isHittable { app.swipeDown() }
            app.buttons["voice-automatic"].firstMatch.tap()
            XCTAssertTrue(app.buttons["voice-automatic"].firstMatch.isSelected)
        }
    }

    func testToolsAndTrip() {
        app.terminate()
        app.launchArguments = ["-csSimulate"]
        app.launch()
        sleep(8)
        shot("browse", 1)
        app.buttons["tools"].firstMatch.tap()
        shot("tools", 2)
        // Each tool page is a sheet of its own; a swipe down closes it.
        for tool in ["tool-layers", "tool-directions", "tool-ask", "tool-watches", "tool-marketplace"] {
            let b = app.buttons[tool].firstMatch
            if b.waitForExistence(timeout: 2) {
                b.tap(); shot(tool, 2)
                let done = app.buttons["Done"].firstMatch
                if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
                sleep(1)
                if !app.buttons["tool-layers"].firstMatch.exists { app.buttons["tools"].firstMatch.tap(); sleep(1) }
            }
        }
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() } else { app.swipeDown(velocity: .fast) }
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csAutoDrive"]
        app.launch()
        sleep(45)
        shot("trip", 1)
        sleep(20)
        shot("trip2", 1)
    }

    func testTripPages() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csResetPlaces", "-csReportPreview"]
        app.launch()
        let search = app.textFields["search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        sleep(4)
        search.tap()
        shot("trip-search-empty", 1)
        search.typeText("Palo Alto")
        sleep(4)
        shot("trip-search", 0)
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch
        if pick.waitForExistence(timeout: 15) {
            pick.tap()
            sleep(6)
            shot("trip-place", 0)
            if app.buttons["place-watch"].exists {
                app.buttons["place-watch"].tap()
                sleep(4)
                shot("watch-editor", 0)
                app.buttons["page-close"].firstMatch.tap()
                sleep(1)
            }
            if app.buttons["navigate"].waitForExistence(timeout: 10) {
                app.buttons["navigate"].tap()
                if app.buttons["start"].waitForExistence(timeout: 60) {
                    sleep(3)
                    shot("trip-routes", 0)
                    if app.buttons["leave-later"].exists { app.buttons["leave-later"].tap(); sleep(2); shot("trip-leave-later", 0) }
                    app.buttons["routes-close"].tap()
                }
            }
        }
        if app.buttons["place-close"].exists { app.buttons["place-close"].tap() }
        if app.buttons["report"].waitForExistence(timeout: 10) {
            app.buttons["report"].tap()
            sleep(2)
            shot("trip-report", 0)
            app.buttons["report-CRASH_MAJOR"].tap()
            sleep(2)
            shot("trip-report-confirm", 0)
            app.buttons["report-undo"].tap()
            app.buttons["report-close"].tap()
        }
        app.buttons["tools"].firstMatch.tap()
        if app.buttons["tool-watches"].waitForExistence(timeout: 3) {
            app.buttons["tool-watches"].tap()
            sleep(3)
            shot("watch-areas", 0)
        }
    }

    func testAlertsNearby() {
        app.terminate()
        app.launchArguments = ["-csSimulate"]
        app.launch()
        sleep(8)
        app.buttons["tools"].firstMatch.tap()
        let t0 = Date()
        app.buttons["Alerts nearby"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Alerts nearby"].waitForExistence(timeout: 5))
        shot("alerts-nearby", 2)
        print("CS alerts nearby opened in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    }

    func testCameraCards() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csOpenCamera", "video"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["camera-image"].firstMatch.waitForExistence(timeout: 45))
        shot("camera-video-still")
        app.descendants(matching: .any)["camera-image"].firstMatch.tap()
        shot("camera-video-playing", 6)
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csOpenCamera", "still"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["camera-image"].firstMatch.waitForExistence(timeout: 45))
        shot("camera-still", 3)
    }
}
