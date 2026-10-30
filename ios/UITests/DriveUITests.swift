import XCTest

/// Every workflow a driver can do, run against the simulator with a
/// simulated location. The app is launched with `-csSimulate` so routes
/// start from downtown San Jose and driving is simulated.
final class DriveUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-csSimulate", "-csResetPlaces", "-csResetPrefs"]
        app.launch()
    }

    /// Forms are lazy: swipe until the element is on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement, tries: Int = 16) -> Bool {
        let form: XCUIElement = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
            : app.tables.firstMatch.exists ? app.tables.firstMatch : app
        for _ in 0 ..< tries {
            if element.exists && element.isHittable { return true }
            // A third of the form at a time, so no row is skipped: lazy
            // forms only expose rows that are on screen.
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
        let ok = element.exists && element.isHittable
        if !ok { print("CS-REVEAL-MISS", element, "\n", app.debugDescription) }
        return ok
    }

    private func search(_ text: String) {
        let field = app.textFields["search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText(text)
    }

    private func pickFirstResult() {
        // Results are buttons whose title is the place's first line.
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "a suggestion for Palo Alto")
        first.tap()
    }

    func testSearchPinRoutesNavigateAndStop() {
        search("Palo Alto")
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
        let exit = app.buttons.matching(NSPredicate(format: "identifier == 'end-trip' OR label CONTAINS[c] 'exit' OR label CONTAINS[c] 'stop' OR label CONTAINS[c] 'close'")).firstMatch
        if exit.waitForExistence(timeout: 5) {
            exit.tap()
        } else {
            app.buttons["xmark"].firstMatch.tap()
        }
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 10), "back to browsing")
    }

    func testCoordinatesBecomeAPin() {
        search("37.442, -122.143")
        app.textFields["search"].typeText("\n")   // the return key, whatever the keyboard calls it
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 10), "a pin from typed coordinates")
        app.buttons["place-close"].tap()
        XCTAssertFalse(app.buttons["navigate"].exists)
    }

    func testSaveHomeThenUseShortcut() {
        search("Palo Alto")
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
        XCTAssertTrue(app.descendants(matching: .any)["settings-map-style"].firstMatch.waitForExistence(timeout: 5))
        openPage("saved-places")
        // In the list itself: the places tray under the sheet has a "Home" row too.
        XCTAssertTrue(reveal(app.cells.staticTexts["Home"].firstMatch), "Home listed under Saved places")
        back()
        app.buttons["page-close"].firstMatch.tap()
    }

    /// Settings is a home page of categories: open one by its row.
    private func openPage(_ id: String) {
        let row = app.descendants(matching: .any)["settings-\(id)"].firstMatch
        XCTAssertTrue(reveal(row), "settings row \(id)")
        row.tap()
    }

    /// A system form page has a navigation bar; a Day Glass+ page its own
    /// round back button.
    private func back() {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        if bar.exists && bar.isHittable { bar.tap() } else { app.buttons["page-back"].firstMatch.tap() }
        sleep(1)   // let the pop finish
    }

    func testSettingsAndLayers() {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-map-style"].firstMatch.waitForExistence(timeout: 5))
        openPage("units")
        XCTAssertTrue(app.buttons["units-km"].waitForExistence(timeout: 5))
        app.buttons["units-km"].tap()
        app.buttons["units-phone"].tap()
        back()
        openPage("route-options")
        let tolls = app.switches["Avoid tolls"]
        if tolls.waitForExistence(timeout: 5) { tolls.switches.firstMatch.tap(); tolls.switches.firstMatch.tap() }
        back()
        openPage("alerts")
        let advanced = app.buttons["advanced-alerts"].firstMatch
        XCTAssertTrue(reveal(advanced), "advanced alerts row")
        advanced.tap()
        let toggle = app.switches["advanced-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        sleep(1)   // let the push animation finish
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()   // the switch itself, not its label
        XCTAssertTrue(app.staticTexts["Incidents"].waitForExistence(timeout: 5), "per-kind rules appear")
        XCTAssertTrue(reveal(app.staticTexts["Police reports"]), "community kinds have rules too")
        // Back to the top of the screen the simple way: leave and re-enter, then switch it off again.
        back()
        XCTAssertTrue(reveal(advanced))
        advanced.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        sleep(1)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Incidents"].waitForNonExistence(timeout: 5), "rules hidden again")
        back()   // to Alerts
        back()   // to the home page
        openPage("help")
        let link = app.staticTexts["Live map on the web"]
        XCTAssertTrue(reveal(link) || link.exists, "link back to the website")
        back()
        app.buttons["page-close"].firstMatch.tap()
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
        app.buttons["tool-marketplace"].tap()
        XCTAssertTrue(app.staticTexts["Marketplace"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-source"].waitForExistence(timeout: 5))
        app.buttons["page-back"].firstMatch.tap()
        app.buttons["tool-watches"].tap()
        XCTAssertTrue(app.staticTexts["Watch areas"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["page-close"].firstMatch.tap()
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
        // Signed out, a kind leads to sign-in rather than a report.
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["report-close"].tap()
    }

    func testLongPressDropsAPin() {
        // The press only counts once the hook has found the map view and
        // added its recognizer; it names the map when it has.
        let map = app.descendants(matching: .any)["cs-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15), "map hook attached")
        let center = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // A busy simulator can stall the app through the whole hold, and
        // the press then lands as a plain tap. Press again if so.
        var card = false
        for _ in 0 ..< 3 where !card {
            center.press(forDuration: 1.5)
            card = app.buttons["navigate"].waitForExistence(timeout: 6)
        }
        XCTAssertTrue(card, "a dropped pin has a card")
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
