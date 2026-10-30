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
        // Each simulator gets its own folder too, so two runs on one Mac
        // do not overwrite each other's pictures.
        if let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] {
            let dir = "/tmp/cs-pages-\(udid)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    /// A fresh install asks for location first; answer so the pages show.
    private func allowAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0 ..< 2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { break }
            for label in ["Allow While Using App", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
            sleep(1)
        }
    }

    /// Taps a row by its label. A row below the fold does not exist
    /// until it is scrolled to, so swipe for it.
    private func open(_ row: String) {
        let cell = app.staticTexts[row].firstMatch
        for _ in 0 ..< 3 where !(cell.waitForExistence(timeout: 3) && cell.isHittable) { app.swipeUp() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), row)
        cell.tap()
    }

    /// Opens a settings page by its row id ("settings-<id>").
    private func page(_ id: String) {
        let row = app.descendants(matching: .any)["settings-\(id)"].firstMatch
        for _ in 0 ..< 4 where !(row.waitForExistence(timeout: 2) && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists, id)
        row.tap()
        sleep(1)
    }

    /// A system form page has a navigation bar; a Day Glass+ page its own
    /// round back button.
    private func back() {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        if bar.exists && bar.isHittable { bar.tap() } else { app.buttons["page-back"].firstMatch.tap() }
        sleep(1)
    }

    func testSettingsPages() {
        allowAlerts()
        XCTAssertTrue(app.descendants(matching: .any)["settings-map-style"].firstMatch.waitForExistence(timeout: 10))
        shot("settings")
        app.swipeUp()
        shot("settings-bottom", 1)
        app.swipeDown()
        page("map-style")
        shot("map-style")
        app.buttons["mapstyle-dark"].firstMatch.tap()
        shot("map-style-dark")
        app.buttons["mapstyle-positron"].firstMatch.tap()
        back()
        page("units")
        XCTAssertTrue(app.buttons["units-phone"].waitForExistence(timeout: 5))
        shot("units")
        back()
        page("voice")
        XCTAssertTrue(app.buttons["voice-automatic"].waitForExistence(timeout: 5))
        shot("voice")
        back()
        page("alerts")
        XCTAssertTrue(app.buttons["chip-crash"].waitForExistence(timeout: 5))
        shot("alerts")
        app.swipeUp()
        shot("alerts-plugins", 1)
        let advanced = app.buttons["advanced-alerts"].firstMatch
        if advanced.waitForExistence(timeout: 3) {
            advanced.tap()
            XCTAssertTrue(app.switches["advanced-toggle"].waitForExistence(timeout: 5))
            shot("alerts-advanced", 1)
            back()
        }
        back()
        page("route-options")
        XCTAssertTrue(app.switches["Avoid tolls"].waitForExistence(timeout: 5))
        shot("route-options", 1)
        back()
        page("data-sources")
        XCTAssertTrue(app.descendants(matching: .any)["sources-count-fresh"].firstMatch.waitForExistence(timeout: 15))
        shot("data-sources", 3)
        back()
        page("map-layers")
        shot("layers-everything")
        app.buttons["Plugins"].firstMatch.tap()
        shot("layers-plugins")
        app.buttons["Official"].firstMatch.tap()
        shot("layers-official")
        app.buttons["Everything"].firstMatch.tap()
        back()
        page("offline-maps")
        shot("offline")
        open("Maps saved on this phone")
        shot("offline-list")
        let trip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trip to'")).firstMatch
        if trip.waitForExistence(timeout: 3) {
            trip.tap()
            shot("offline-detail")
            back()
        }
        back(); back()
        page("saved-places")
        shot("places")
        app.buttons["set-home"].firstMatch.tap()
        sleep(1)
        let field = app.textFields["place-search"].firstMatch
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("San Jose City Hall") }
        shot("places-picker", 3)
        app.buttons["Cancel"].firstMatch.tap()
        back()
        page("plugins")
        shot("plugins", 3)
        if app.staticTexts["Speed and red light cameras"].firstMatch.waitForExistence(timeout: 5) {
            app.staticTexts["Speed and red light cameras"].firstMatch.tap()
            shot("plugin-status", 3)
            app.buttons["plugin-check"].firstMatch.tap()
            shot("plugin-checked", 5)
            back()
        }
        back()
        for id in ["help", "about", "account"] {
            page(id)
            shot("page-" + id, 2)
            back()
        }
        app.buttons["page-close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5), "settings closes")
    }

    /// The first run: three steps over the map, then the map itself.
    func testWelcomeSteps() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csWelcome"]
        app.launch()
        allowAlerts()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 10))
        shot("welcome-1", 3)
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 5))
        shot("welcome-2", 1)
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 5))
        shot("welcome-3", 1)
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForNonExistence(timeout: 5), "the run is done")
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 5))
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
            allowAlerts()
            if !app.descendants(matching: .any)["settings-voice"].firstMatch.waitForExistence(timeout: 6) {
                app.buttons["settings"].firstMatch.tap()
            }
            page("voice")
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
