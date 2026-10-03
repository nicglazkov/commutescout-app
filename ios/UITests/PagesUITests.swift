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
            back()
        }
        back(); back()
        open("Saved places")
        shot("places")
        app.buttons["set-home"].firstMatch.tap()
        sleep(1)
        let field = app.textFields["place-search"].firstMatch
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("San Jose City Hall") }
        shot("places-picker", 3)
        app.buttons["Cancel"].firstMatch.tap()
        back()
        open("About")
        shot("about")
    }

    func testCameraCards() {
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csOpenCamera", "video"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["camera-image"].firstMatch.waitForExistence(timeout: 20))
        shot("camera-video-still")
        app.descendants(matching: .any)["camera-image"].firstMatch.tap()
        shot("camera-video-playing", 6)
        app.terminate()
        app.launchArguments = ["-csSimulate", "-csOpenCamera", "still"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["camera-image"].firstMatch.waitForExistence(timeout: 20))
        shot("camera-still", 3)
    }
}
