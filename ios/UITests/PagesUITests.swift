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

    private func shot(_ name: String) {
        sleep(2)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/tmp/cs-page-\(name).png"))
    }

    private func open(_ row: String) {
        let cell = app.staticTexts[row].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8), row)
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
        open("Maps saved on this phone")
        shot("offline-list")
        let trip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trip to'")).firstMatch
        if trip.waitForExistence(timeout: 3) {
            trip.tap()
            shot("offline-detail")
        }
    }
}
