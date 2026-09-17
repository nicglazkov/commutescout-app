import XCTest

/// Every workflow a driver can do, run against the simulator with a
/// simulated location. The app is launched with `-csSimulate` so routes
/// start from downtown San Jose and driving is simulated.
final class DriveUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-csSimulate", "-csResetPlaces"]
        app.launch()
    }

    /// Forms are lazy: swipe until the element is on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement, tries: Int = 8) -> Bool {
        for _ in 0 ..< tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func search(_ text: String) {
        let field = app.textFields["search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText(text)
    }

    private func pickFirstResult() {
        // Results are buttons whose title is the place's first line.
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Los Altos'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "a suggestion for Los Altos")
        first.tap()
    }

    func testSearchPinRoutesNavigateAndStop() {
        search("Los Altos")
        pickFirstResult()
        let navigate = app.buttons["navigate"]
        XCTAssertTrue(navigate.waitForExistence(timeout: 10), "place card with Navigate")
        navigate.tap()
        let start = app.buttons["start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "routes card with Start")
        XCTAssertTrue(app.buttons["route-1"].exists, "an alternate route")
        app.buttons["route-1"].tap()
        app.buttons["route-0"].tap()
        start.tap()
        // Navigation: the trip bar has an exit button; the search bar is gone.
        XCTAssertTrue(app.textFields["search"].waitForNonExistence(timeout: 10), "search hidden while navigating")
        let perspective = app.buttons["perspective"]
        XCTAssertTrue(perspective.waitForExistence(timeout: 5))
        perspective.tap()
        perspective.tap()
        // Ferrostar's exit control is the X in the trip bar.
        let exit = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'exit' OR label CONTAINS[c] 'stop' OR label CONTAINS[c] 'close'")).firstMatch
        if exit.waitForExistence(timeout: 5) {
            exit.tap()
        } else {
            app.buttons["xmark"].firstMatch.tap()
        }
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 10), "back to browsing")
    }

    func testCoordinatesBecomeAPin() {
        search("37.372, -122.110")
        app.keyboards.buttons["search"].firstMatch.tap()
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 10), "a pin from typed coordinates")
        app.buttons["place-close"].tap()
        XCTAssertFalse(app.buttons["navigate"].exists)
    }

    func testSaveHomeThenUseShortcut() {
        search("Los Altos")
        pickFirstResult()
        XCTAssertTrue(app.buttons["save-menu"].waitForExistence(timeout: 10))
        app.buttons["save-menu"].tap()
        app.buttons["Save as Home"].tap()
        app.buttons["place-close"].tap()
        app.textFields["search"].tap()
        let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home'")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5), "Home shortcut under the search field")
        home.tap()
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 5))
        // And it is listed in Settings, where it can be removed.
        app.buttons["place-close"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app.staticTexts["Home"]), "Home listed under Places")
        app.buttons["Done"].tap()
    }

    func testSettingsAndLayers() {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        app.buttons["Kilometers"].tap()
        app.buttons["Miles"].tap()
        let tolls = app.switches["Avoid tolls"]
        if tolls.exists { tolls.tap(); tolls.tap() }
        XCTAssertTrue(reveal(app.descendants(matching: .any)["Live map on the web"]), "link back to the website")
        XCTAssertTrue(reveal(app.buttons["advanced-alerts"]), "advanced alerts row")
        app.buttons["advanced-alerts"].tap()
        XCTAssertTrue(app.switches["advanced-toggle"].waitForExistence(timeout: 5))
        app.switches["advanced-toggle"].tap()
        XCTAssertTrue(app.staticTexts["Police reports"].waitForExistence(timeout: 5), "per-kind rules appear")
        app.switches["advanced-toggle"].tap()
        app.navigationBars.buttons.firstMatch.tap()   // back
        app.buttons["Done"].tap()
        app.buttons["tools"].tap()
        app.buttons["tool-layers"].tap()
        XCTAssertTrue(app.staticTexts["Base map"].waitForExistence(timeout: 5))
        app.buttons["Dark"].tap()
        app.buttons["Match theme"].tap()
        let traffic = app.switches["Traffic"]
        if traffic.exists { traffic.tap(); traffic.tap() }
        app.buttons["Done"].tap()
        // Map controls exist while browsing.
        XCTAssertTrue(app.buttons["perspective"].exists)
        XCTAssertTrue(app.buttons["locate"].exists)
        app.buttons["perspective"].tap()
        app.buttons["locate"].tap()
    }

    func testToolsMenuOpensEachTool() {
        app.buttons["tools"].tap()
        XCTAssertTrue(app.buttons["tool-alerts"].waitForExistence(timeout: 5))
        app.buttons["tool-alerts"].tap()
        XCTAssertTrue(app.navigationBars["Alerts nearby"].waitForExistence(timeout: 8))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["tool-ask"].tap()
        XCTAssertTrue(app.navigationBars["Ask"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["tool-sources"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-source"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["tool-watches"].tap()
        XCTAssertTrue(app.navigationBars["Watch areas"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        app.buttons["tool-directions"].tap()
        XCTAssertTrue(app.navigationBars["Directions"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
    }

    func testReportSheetAsksForSignIn() {
        XCTAssertTrue(app.buttons["report"].waitForExistence(timeout: 10))
        app.buttons["report"].tap()
        XCTAssertTrue(app.buttons["report-POLICE_VISIBLE"].waitForExistence(timeout: 5))
        app.buttons["report-POLICE_VISIBLE"].tap()
        XCTAssertTrue(app.buttons["Sign in"].exists, "signed-out reports ask for an account")
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testLongPressDropsAPin() {
        let map = app.otherElements.firstMatch
        let center = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        center.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 10), "a dropped pin has a card")
        app.buttons["place-close"].tap()
    }

    func testMarkerTapOpensCard() {
        // The app is asked to center on the nearest live marker; a tap on
        // the center of the screen then hits it.
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csFocusMarker"]
        app.launch()
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 10))
        sleep(6)
        let map = app.otherElements.firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Navigate here"].waitForExistence(timeout: 8), "marker card")
    }
}
