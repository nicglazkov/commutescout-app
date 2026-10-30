import XCTest

/// The marketplace, a plugin's page, offline maps, the area picker and a
/// saved map, each opened straight at launch with saved-map fixtures.
final class MorePagesUITests: XCTestCase {
    var app: XCUIApplication!

    private func launch(_ screen: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-csSimulate", "-csOpenMore", screen, "-csMoreFixtures"]
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func flipSwitch(_ id: String) {
        let sw = app.switches[id].firstMatch
        for _ in 0 ..< 4 where !(sw.exists && sw.isHittable) { app.swipeUp() }
        XCTAssertTrue(sw.isHittable, id)
        let before = sw.value as? String
        let inner = sw.switches.firstMatch
        if inner.exists { inner.tap() } else { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        for _ in 0 ..< 10 where sw.value as? String == before { usleep(200_000) }
        XCTAssertNotEqual(sw.value as? String, before, "\(id) flipped")
    }

    func testAWatchAreaOpensInTheEditorWithAPauseInItsMenu() {
        launch("watches")
        XCTAssertTrue(any("watch-edit-a").waitForExistence(timeout: 10))
        // The second fixture is paused, so its menu offers Resume.
        XCTAssertTrue(app.staticTexts["Paused"].firstMatch.exists)
        any("watch-menu-a").tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].firstMatch.exists)
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit watch area"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["watch-name"].value as? String, "Home area")
        XCTAssertFalse(any("watch-shape").exists, "an area keeps its kind of shape")
        app.buttons["page-close"].firstMatch.tap()
        any("watch-menu-b").tap()
        XCTAssertTrue(app.buttons["Resume"].firstMatch.waitForExistence(timeout: 5))
    }

    func testMarketplaceFilterAndAdd() {
        launch("market")
        XCTAssertTrue(app.staticTexts["Marketplace"].firstMatch.waitForExistence(timeout: 10))
        let cards = app.descendants(matching: .any).matching(identifier: "plugin-card")
        guard cards.firstMatch.waitForExistence(timeout: 15) else {
            XCTAssertTrue(app.staticTexts["No plugin is listed yet."].exists)
            return
        }
        let all = cards.count
        app.buttons["Official data"].firstMatch.tap()
        sleep(1)
        let official = cards.count
        app.buttons["Plugin data"].firstMatch.tap()
        sleep(1)
        let plugin = cards.count
        XCTAssertEqual(official + plugin, all, "each card is official data or plugin data")
        app.buttons["All"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(cards.count, all)
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'install-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let before = pill.label
        pill.tap()
        XCTAssertNotEqual(pill.label, before, "Add toggles")
        pill.tap()
        XCTAssertEqual(pill.label, before)
    }

    func testPluginPageSwitchAndRemoveAsksFirst() {
        launch("plugin")
        XCTAssertTrue(any("plugin-sheet").waitForExistence(timeout: 15))
        let remove = app.buttons["plugin-remove"].firstMatch
        if !remove.waitForExistence(timeout: 5) {
            // Not added on this simulator: add it first.
            app.buttons["plugin-add"].firstMatch.tap()
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
        }
        flipSwitch("plugin-installed")
        flipSwitch("plugin-installed")
        remove.tap()
        XCTAssertTrue(app.buttons["plugin-keep"].waitForExistence(timeout: 3), "remove asks first")
        XCTAssertTrue(app.buttons["plugin-remove-yes"].exists)
        app.buttons["plugin-keep"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "keep it leaves the plugin added")
    }

    func testOfflineListStatesAndSavedMap() {
        launch("offline")
        XCTAssertTrue(any("offline-storage").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Home and work area"].exists)
        XCTAssertTrue(app.buttons["offline-download-area"].exists)
        let states = app.buttons["offline-states"].firstMatch
        for _ in 0 ..< 3 where !states.isHittable { app.swipeUp() }
        states.tap()
        XCTAssertTrue(app.staticTexts["Whole states"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["page-back"].firstMatch.tap()
        sleep(1)
        for _ in 0 ..< 3 where !app.staticTexts["Home and work area"].isHittable { app.swipeDown() }
        app.staticTexts["Home and work area"].tap()
        XCTAssertTrue(any("saved-status").waitForExistence(timeout: 5))
        app.buttons["saved-update"].tap()
        XCTAssertTrue(app.staticTexts["Updated just now, 312 MB in all"].waitForExistence(timeout: 6), "update finishes")
        app.buttons["saved-delete"].tap()
        XCTAssertTrue(app.buttons["saved-keep"].waitForExistence(timeout: 3), "delete asks first")
        XCTAssertTrue(app.buttons["Delete 312 MB"].exists)
        app.buttons["saved-keep"].tap()
        XCTAssertTrue(app.buttons["saved-delete"].waitForExistence(timeout: 3))
    }

    func testAreaPickerCornerResizes() {
        launch("picker")
        let size = app.staticTexts["picker-size"].firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 10))
        let before = size.label
        let corner = any("picker-corner")
        XCTAssertTrue(corner.exists)
        let from = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: -120, dy: -160)))
        sleep(1)
        XCTAssertNotEqual(size.label, before, "a smaller area takes less room")
        XCTAssertTrue(app.buttons["picker-download"].exists)
        app.buttons["picker-close"].tap()
        XCTAssertTrue(any("offline-storage").waitForExistence(timeout: 5), "back on the list")
    }
}
