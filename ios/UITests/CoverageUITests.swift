import XCTest

/// Every remaining control a driver can reach: settings rows, pickers,
/// layer switches, the plugins screen, the report sheet, the directions
/// planner, the alert strip, the marker card. Written to run on a real
/// phone as well as the simulator, so anything that depends on being
/// signed in, or on live data being nearby, is tolerated rather than
/// assumed.
final class CoverageUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-csSimulate", "-csResetPlaces", "-csResetPrefs"]
        app.launch()
    }

    // MARK: helpers

    @discardableResult
    private func reveal(_ element: XCUIElement, tries: Int = 16) -> Bool {
        let form = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0 ..< tries {
            if element.exists && element.isHittable { return true }
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
        let ok = element.exists && element.isHittable
        if !ok { print("CS-REVEAL-MISS", element, "\n", app.debugDescription) }
        return ok
    }

    /// A SwiftUI Toggle: tap the switch itself, not its label. A row
    /// half under the screen's edge counts as hittable, so tap the inner
    /// switch where there is one, and check that the value changed.
    private func flip(_ label: String) {
        let sw = app.switches[label]
        XCTAssertTrue(reveal(sw), "switch \(label)")
        let before = sw.value as? String
        let inner = sw.switches.firstMatch
        if inner.exists { inner.tap() } else { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        for _ in 0 ..< 10 where sw.value as? String == before { usleep(200_000) }
        XCTAssertNotEqual(sw.value as? String, before, "switch \(label) flipped")
    }

    private func openSettings() {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
    }

    /// Settings is a home page of categories: open one by its row.
    private func openPage(_ id: String) {
        let row = app.descendants(matching: .any)["settings-\(id)"].firstMatch
        XCTAssertTrue(reveal(row), "settings row \(id)")
        row.tap()
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)   // let the pop finish
    }

    /// Done is on the home page only: step back to it, then close.
    private func closeSettings() {
        for _ in 0 ..< 3 where !app.buttons["Done"].firstMatch.exists { back() }
        app.buttons["Done"].firstMatch.tap()
    }

    private func search(_ text: String) {
        let field = app.textFields["search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText(text)
    }

    private func pickResult(_ prefix: String) {
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "a suggestion for \(prefix)")
        first.tap()
    }

    private var signedIn: Bool {
        // The settings Account section says "Sign in" only when signed out.
        !app.buttons["Sign in"].exists
    }

    // MARK: search

    func testSearchIsLiveWhileTypingAndClears() {
        search("Palo Alt")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8), "suggestions arrive before submit")
        app.buttons["search-clear"].tap()
        XCTAssertEqual(app.textFields["search"].value as? String ?? "", "Where to?", "field cleared")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Search a place'")).firstMatch.exists,
                      "empty-state hint under the field")
    }

    func testNonsenseSearchSaysNothingYet() {
        search("zzqqxxyy")
        let hint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nothing yet'")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        app.buttons["search-clear"].tap()
    }

    func testSaveWorkAndFavoriteThenRemoveInSettings() {
        search("Palo Alto")
        pickResult("Palo Alto")
        XCTAssertTrue(app.buttons["save-menu"].waitForExistence(timeout: 10))
        app.buttons["save-menu"].tap()
        app.buttons["Save as Work"].tap()
        app.buttons["save-menu"].tap()
        app.buttons["Save to favorites"].tap()
        app.buttons["place-close"].tap()
        openSettings()
        openPage("saved-places")
        let work = app.staticTexts["Work"]
        XCTAssertTrue(reveal(work), "Work listed under Saved places")
        // Every place row swipes to Remove.
        app.cells.containing(.staticText, identifier: "Work").firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["Remove"].firstMatch.waitForExistence(timeout: 5), "Remove on a swipe")
        app.buttons["Remove"].firstMatch.tap()
        XCTAssertTrue(app.buttons["set-work"].waitForExistence(timeout: 5), "Work is unset")
        closeSettings()
        // The shortcut list under the field shows what is left (the favorite).
        app.textFields["search"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch.waitForExistence(timeout: 5),
                      "favorite as a shortcut")
    }

    func testQuickPicksOrderAndRemove() {
        // Save Home and a favorite, use a place, then the empty field lists
        // Home, the favorite and the recent, each with a remove button.
        search("Palo Alto")
        pickResult("Palo Alto")
        XCTAssertTrue(app.buttons["save-menu"].waitForExistence(timeout: 10))
        app.buttons["save-menu"].tap(); app.buttons["Save as Home"].tap()
        app.buttons["save-menu"].tap(); app.buttons["Save to favorites"].tap()
        app.buttons["place-close"].tap()
        app.textFields["search"].tap()
        let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home'")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5), "Home first")
        let removes = app.buttons.matching(identifier: "remove-place")
        XCTAssertGreaterThanOrEqual(removes.count, 2, "remove buttons on quick picks: \(removes.count)")
        let before = removes.count
        removes.element(boundBy: 0).tap()   // removes Home
        XCTAssertTrue(app.buttons.matching(identifier: "remove-place").count < before, "one fewer quick pick")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home'")).firstMatch.exists, "Home gone")
        app.buttons["search-clear"].exists ? app.buttons["search-clear"].tap() : ()
    }

    func testUnitsChangeThePlaceCard() {
        openSettings()
        openPage("units")
        XCTAssertTrue(app.buttons["Kilometers"].waitForExistence(timeout: 5))
        app.buttons["Kilometers"].tap()
        closeSettings()
        search("Palo Alto")
        pickResult("Palo Alto")
        let km = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' km away'")).firstMatch
        XCTAssertTrue(km.waitForExistence(timeout: 10), "distance shown in km")
        app.buttons["place-close"].tap()
        openSettings()
        openPage("units")
        XCTAssertTrue(app.buttons["Miles"].waitForExistence(timeout: 5))
        app.buttons["Miles"].tap()
        closeSettings()
    }

    // MARK: settings

    func testAppearancePickersAndPerspective() {
        openSettings()
        openPage("appearance")
        // Theme and base map are segmented controls.
        for label in ["Dark", "Light", "System"] {
            let seg = app.buttons[label].firstMatch
            XCTAssertTrue(reveal(seg), label)
            seg.tap()
            XCTAssertTrue(seg.isSelected, "\(label) selected")
        }
        // Base maps are cards with a picture each; tapping applies at once.
        for raw in ["outdoors", "auto"] {
            let card = app.buttons["basemap-\(raw)"].firstMatch
            XCTAssertTrue(reveal(card), raw)
            card.tap()
        }
        XCTAssertTrue(app.otherElements["basemap-preview"].firstMatch.exists || app.images["basemap-preview"].firstMatch.exists
                      || app.descendants(matching: .any)["basemap-preview"].firstMatch.exists, "live preview on the page")
        let before = app.buttons["perspective"].label   // "2D" while 3D is on
        flip("3D perspective")
        closeSettings()
        XCTAssertNotEqual(app.buttons["perspective"].label, before, "map button reflects the settings toggle")
        app.buttons["perspective"].tap()
        XCTAssertEqual(app.buttons["perspective"].label, before)
    }

    func testRouteOptionsAndDrivingToggles() {
        openSettings()
        openPage("navigation")
        for label in ["Avoid tolls", "Avoid highways", "Avoid ferries", "Voice guidance",
                      "Show speed limit", "Keep the screen on"] {
            flip(label); flip(label)
        }
        back()
        openPage("map-layers")
        flip("Traffic"); flip("Traffic")
        back()
        openPage("alerts")
        flip("Speak road alerts"); flip("Speak road alerts")
        let warn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Warn about alerts'")).firstMatch
        XCTAssertTrue(reveal(warn))
        warn.tap()
        let choices = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mi' OR label CONTAINS 'km'"))
        XCTAssertGreaterThan(choices.count, 1, "distance choices")
        choices.element(boundBy: 1).tap()
        let strip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show the next alert within'")).firstMatch
        XCTAssertTrue(reveal(strip))
        strip.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'mi' OR label CONTAINS 'km'")).element(boundBy: 0).tap()
        back()
        openPage("testing")
        XCTAssertTrue(reveal(app.switches["Simulate driving the route"]), "testing toggle")
        closeSettings()
    }

    func testLayerSwitchesForEveryKind() {
        openSettings()
        openPage("map-layers")
        let header = app.staticTexts["Official sources"]
        XCTAssertTrue(reveal(header))
        // The eight official kinds, then the plugin master switch under
        // Plugins. All nine kinds the server emits, the same nine the
        // website draws.
        let names = ["Incidents", "Closures and lane work", "Chain controls", "Weather stations",
                     "Wildfires", "Toll prices", "Cameras", "Message signs", "Show plugin alerts"]
        var found = 0
        for n in names where app.switches[n].exists || reveal(app.switches[n], tries: 4) {
            flip(n); flip(n); found += 1
        }
        XCTAssertEqual(found, names.count, "every layer kind has a switch: \(found)")
        closeSettings()
    }

    func testHelpLinksAboutAndVersion() {
        openSettings()
        openPage("help")
        for label in ["Live map on the web", "Data sources", "Developers and API", "About CommuteScout", "Contact", "Privacy"] {
            XCTAssertTrue(reveal(app.staticTexts[label]), label)
        }
        back()
        openPage("about")
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), "a version row")
        let number = app.staticTexts.matching(NSPredicate(format: "label MATCHES '.*[0-9]+\\\\.[0-9]+.*'")).firstMatch
        XCTAssertTrue(number.exists, "with a number")
        closeSettings()
    }

    func testAccountSectionSignInSheetOrSignedInRows() {
        openSettings()
        openPage("account")
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        if app.buttons["Sign in"].exists {
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.buttons["Continue with Apple"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Continue with Google"].exists)
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            XCTAssertTrue(app.buttons["Sign out"].exists, "signed in: Sign out offered")
            XCTAssertTrue(app.buttons["Delete account"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Signed in as'")).firstMatch.exists)
            app.buttons["Delete account"].firstMatch.tap()
            let ask = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Delete your account?'")).firstMatch
            XCTAssertTrue(ask.waitForExistence(timeout: 5), "deletion asks first")
            // Dismiss without confirming: a tap outside the dialog.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            XCTAssertTrue(ask.waitForNonExistence(timeout: 5), "dialog dismissed")
            XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5), "still signed in")
        }
        closeSettings()
    }

    func testPluginsScreenTiersAndAddByURL() {
        openSettings()
        openPage("plugins")
        let mine = app.buttons["My plugins and private sources"].firstMatch
        XCTAssertTrue(reveal(mine))
        mine.tap()
        XCTAssertTrue(app.staticTexts["Approved plugins"].waitForExistence(timeout: 8))
        XCTAssertTrue(reveal(app.staticTexts["Public plugins, not reviewed"]))
        XCTAssertTrue(reveal(app.buttons["add-source"]))
        app.buttons["add-source"].tap()
        let url = app.textFields["source-url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("http://example.com")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["The address must start with https://"].waitForExistence(timeout: 5), "plain http refused")
        app.buttons["Cancel"].firstMatch.tap()
        closeSettings()
    }

    // MARK: tools

    func testLayersSheetStylesTrafficAndKinds() {
        app.buttons["tools"].tap()
        app.buttons["tool-layers"].tap()
        XCTAssertTrue(app.staticTexts["Base map"].waitForExistence(timeout: 5))
        for style in ["Light", "Dark", "Outdoors", "Match theme"] where app.buttons[style].exists {
            app.buttons[style].tap()
        }
        flip("Traffic"); flip("Traffic")
        flip("3D perspective"); flip("3D perspective")
        // A medium sheet: the row is below the fold; pull the sheet up, then look.
        app.swipeUp()
        let plugins = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'My plugins and private sources'")).firstMatch
        XCTAssertTrue(reveal(plugins) || plugins.waitForExistence(timeout: 3), "plugins link in the layers sheet")
        app.buttons["Done"].tap()
    }

    func testAlertsNearbyRowCentersOnTheMarker() {
        app.buttons["tools"].tap()
        app.buttons["tool-alerts"].tap()
        XCTAssertTrue(app.navigationBars["Alerts nearby"].waitForExistence(timeout: 8))
        sleep(3)   // markers for the visible area
        let rows = app.collectionViews.firstMatch.buttons
        if rows.count > 0 {
            rows.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Alerts nearby"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tool-alerts"].waitForNonExistence(timeout: 5), "the Tools menu closes with its page")
            XCTAssertTrue(app.buttons["Navigate here"].waitForExistence(timeout: 8), "marker card for the chosen alert")
            app.buttons["Navigate here"].tap()
            XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 8), "place card for the alert")
            app.buttons["navigate"].tap()
            XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 60), "routes to the alert")
            app.buttons["routes-close"].tap()
        } else {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nothing reported'")).firstMatch.exists)
            app.buttons["Done"].firstMatch.tap()
        }
    }

    func testDirectionsFromAnotherPlaceShowsRoutes() {
        app.buttons["tools"].tap()
        app.buttons["tool-directions"].tap()
        XCTAssertTrue(app.navigationBars["Directions"].waitForExistence(timeout: 5))
        let from = app.textFields["Or search a start"]
        from.tap(); from.typeText("Palo Alto")
        let fromPick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch
        XCTAssertTrue(fromPick.waitForExistence(timeout: 15))
        fromPick.tap()
        let to = app.textFields["Search a destination"]
        XCTAssertTrue(reveal(to))
        to.tap(); to.typeText("Palo Alto")
        let toPick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Palo Alto'")).firstMatch
        XCTAssertTrue(toPick.waitForExistence(timeout: 15))
        toPick.tap()
        let show = app.buttons["Show routes"]
        XCTAssertTrue(reveal(show))
        show.tap()
        XCTAssertTrue(app.buttons["tool-directions"].waitForNonExistence(timeout: 5), "the Tools menu closes with its page")
        if !app.buttons["start"].waitForExistence(timeout: 60) { print("CS-ROUTES-MISS", app.debugDescription) }
        XCTAssertTrue(app.buttons["start"].exists, "routes between the two places")
        app.buttons["routes-close"].tap()
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 5))
    }

    func testWatchAreasSignedOutOrList() {
        app.buttons["tools"].tap()
        app.buttons["tool-watches"].tap()
        XCTAssertTrue(app.staticTexts["Watch areas"].firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Sign in"].exists {
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            XCTAssertTrue(app.buttons["watch-new"].waitForExistence(timeout: 15), "new watch area")
            XCTAssertTrue(reveal(app.switches["watch-push"]), "how you hear about it")
        }
        app.buttons["page-close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tool-watches"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
    }


    func testAskAnswersAQuestion() {
        app.buttons["tools"].tap()
        app.buttons["tool-ask"].tap()
        XCTAssertTrue(app.navigationBars["Ask"].waitForExistence(timeout: 5))
        let field = app.textFields["ask-field"].exists ? app.textFields["ask-field"] : app.textViews["ask-field"]
        field.tap()
        field.typeText("Is there anything on US-101 near San Jose right now?")
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'paperplane' OR label CONTAINS[c] 'send'")).firstMatch.tap()
        // Something comes back: an answer, a status line, or an error; never a hang.
        let anyText = app.staticTexts.matching(NSPredicate(format: "label MATCHES '(?s).{40,}'")).firstMatch
        XCTAssertTrue(anyText.waitForExistence(timeout: 60), "an answer or a message")
        app.buttons["Done"].firstMatch.tap()
    }

    func testMarketplaceTilesAndInstall() {
        app.buttons["tools"].tap()
        XCTAssertTrue(app.buttons["tool-marketplace"].waitForExistence(timeout: 5))
        app.buttons["tool-marketplace"].tap()
        XCTAssertTrue(app.navigationBars["Marketplace"].waitForExistence(timeout: 8))
        let cards = app.descendants(matching: .any).matching(identifier: "plugin-card")
        if cards.firstMatch.waitForExistence(timeout: 10) {
            // A tile has an Install or Installed button that toggles.
            let btn = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'install-'")).firstMatch
            if !btn.waitForExistence(timeout: 5) {
                let tree = XCTAttachment(string: cards.firstMatch.debugDescription)
                tree.name = "card-tree"; tree.lifetime = .keepAlways; add(tree)
                print("CSTEST card tree: " + cards.firstMatch.debugDescription.prefix(3000))
            }
            XCTAssertTrue(btn.exists, "install button on the first tile")
            let before = btn.label
            btn.tap()
            XCTAssertNotEqual(btn.label, before, "Install toggles")
            btn.tap()
            XCTAssertEqual(btn.label, before)
        } else {
            XCTAssertTrue(app.staticTexts["No plugin is listed yet."].exists)
        }
        XCTAssertTrue(app.buttons["market-mine"].exists, "link to my plugins")
        app.buttons["Done"].firstMatch.tap()
    }

    func testToolsSheetWebLinkAndLayersShortcut() {
        app.buttons["tools"].tap()
        XCTAssertTrue(app.buttons["tool-layers"].waitForExistence(timeout: 5))
        // The web link is the last row; a shorter screen needs a scroll to reach it.
        if !app.staticTexts["Open the full map on the web"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Open the full map on the web"].waitForExistence(timeout: 5))
        app.buttons["tool-layers"].tap()
        XCTAssertTrue(app.staticTexts["Base map"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    // MARK: reports

    func testReportSheetEveryKindNoteAndCancel() {
        XCTAssertTrue(app.buttons["report"].waitForExistence(timeout: 10))
        app.buttons["report"].tap()
        XCTAssertTrue(app.buttons["report-POLICE_VISIBLE"].waitForExistence(timeout: 5))
        let kinds = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'report-' AND identifier != 'report-close'"))
        XCTAssertEqual(kinds.count, 12, "report kinds on the grid: \(kinds.count)")
        XCTAssertTrue(app.staticTexts["Placed on the road where you are now. Shown to everyone under a pseudonym."].exists)
        // Signed out, a kind asks for an account first.
        app.buttons["report-POLICE_VISIBLE"].tap()
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5), "reports need an account")
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["report-close"].tap()
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 5))
    }

    func testReportConfirmPicksALaneAndUndoes() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csResetPlaces", "-csResetPrefs", "-csReportPreview"]
        app.launch()
        XCTAssertTrue(app.buttons["report"].waitForExistence(timeout: 10))
        app.buttons["report"].tap()
        XCTAssertTrue(app.buttons["report-CRASH_MAJOR"].waitForExistence(timeout: 5))
        app.buttons["report-CRASH_MAJOR"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Report a crash here'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Left lane"].exists && app.buttons["Shoulder"].exists, "lane picker")
        app.buttons["Left lane"].tap()
        let note = app.textFields["Add a note (optional)"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(app.buttons["report-send"].isEnabled)
        app.buttons["report-undo"].tap()   // never send a test report
        XCTAssertTrue(app.buttons["report-POLICE_VISIBLE"].waitForExistence(timeout: 5), "undo goes back to the grid")
        app.buttons["report-close"].tap()
    }

    // MARK: map controls and navigation

    func testMapButtonsWhileBrowsing() {
        XCTAssertTrue(app.buttons["perspective"].waitForExistence(timeout: 10))
        let before = app.buttons["perspective"].label
        app.buttons["perspective"].tap()
        XCTAssertNotEqual(app.buttons["perspective"].label, before)
        app.buttons["perspective"].tap()
        XCTAssertEqual(app.buttons["perspective"].label, before)
        // Pan away, then the locate button brings the map back.
        let map = app.otherElements.firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)))
        app.buttons["locate"].tap()
        // Rotate with two fingers, then the compass appears and faces north again.
        map.rotate(0.8, withVelocity: 1.0)
        if app.buttons["compass"].waitForExistence(timeout: 3) {
            app.buttons["compass"].tap()
            XCTAssertTrue(app.buttons["compass"].waitForNonExistence(timeout: 5), "compass hides when facing north")
        }
        // Pinch in and out.
        map.pinch(withScale: 2.0, velocity: 1.0)
        map.pinch(withScale: 0.5, velocity: -1.0)
        XCTAssertTrue(app.textFields["search"].exists)
    }

    func testNavigationStripCollapsesAndControlsWork() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csResetPlaces", "-csResetPrefs", "-csAutoDrive"]
        app.launch()
        XCTAssertTrue(app.textFields["search"].waitForNonExistence(timeout: 60), "auto drive started")
        XCTAssertTrue(app.buttons["perspective"].waitForExistence(timeout: 10))
        app.buttons["perspective"].tap(); app.buttons["perspective"].tap()
        XCTAssertFalse(app.buttons["locate"].exists, "Ferrostar draws its own recenter while navigating")
        // The strip only shows within the chosen distance; on a live route
        // there may be nothing ahead, and that is correct too.
        if app.otherElements["alert-strip"].waitForExistence(timeout: 45) || app.buttons["alert-collapse"].exists {
            app.buttons["alert-collapse"].tap()
            XCTAssertTrue(app.buttons["alert-pill"].waitForExistence(timeout: 5), "pill after collapse")
            app.buttons["alert-pill"].tap()
            XCTAssertTrue(app.buttons["alert-collapse"].waitForExistence(timeout: 5), "strip back")
        }
        let exit = app.buttons.matching(NSPredicate(format: "identifier == 'end-trip' OR label CONTAINS[c] 'exit' OR label CONTAINS[c] 'stop' OR label CONTAINS[c] 'close'")).firstMatch
        if exit.waitForExistence(timeout: 5) { exit.tap() } else { app.buttons["xmark"].firstMatch.tap() }
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 10), "back to browsing")
    }

    func testRoutesCardAlternatesAndClose() {
        search("Palo Alto")
        pickResult("Palo Alto")
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 10))
        app.buttons["navigate"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 30))
        let routes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route-'"))
        XCTAssertGreaterThanOrEqual(routes.count, 1)
        for i in 0 ..< routes.count { routes.element(boundBy: i).tap() }
        app.buttons["routes-close"].tap()
        XCTAssertTrue(app.buttons["navigate"].waitForExistence(timeout: 5), "back to the place card")
        app.buttons["place-close"].tap()
    }

    func testMarkerCardShareAndClose() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csFocusMarker"]
        app.launch()
        XCTAssertTrue(app.textFields["search"].waitForExistence(timeout: 10))
        sleep(6)
        let map = app.otherElements.firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard app.buttons["Navigate here"].waitForExistence(timeout: 8) else {
            return   // nothing live near the simulated position right now
        }
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share' OR label CONTAINS[c] 'arrow.up'")).firstMatch
        if share.exists {
            share.tap()
            let sheet = app.otherElements["ShareSheet.RemoteContainerView"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 8), "the system share sheet opens")
            // Dismiss it the way a person does: drag it down; tap above it if that is not enough.
            sheet.swipeDown(velocity: .fast)
            if !sheet.waitForNonExistence(timeout: 3) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap() }
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "share sheet closed")
        }
        // Close the card with its X.
        XCTAssertTrue(app.buttons["marker-close"].waitForExistence(timeout: 5))
        app.buttons["marker-close"].tap()
        if !app.buttons["Navigate here"].waitForNonExistence(timeout: 3), app.buttons["marker-close"].exists {
            print("CS-CLOSE-MISS", app.debugDescription)
            app.buttons["marker-close"].tap()   // a tap swallowed by the sheet's dismissal
        }
        XCTAssertTrue(app.buttons["Navigate here"].waitForNonExistence(timeout: 5))
    }
}
