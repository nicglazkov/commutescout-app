import XCTest

/// Not a test of behaviour: attaches to the app as it is on the phone and
/// saves a screenshot into the result bundle, so what a driver sees can be
/// read from a paired Mac without relaunching anything.
final class ScreenshotUITests: XCTestCase {
    func testScreenshotOfTheRunningApp() {
        let app = XCUIApplication(bundleIdentifier: "com.commutescout.drive")
        app.activate()   // foreground, no relaunch
        sleep(2)
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "screen"
        att.lifetime = .keepAlways
        add(att)
        // The accessibility tree, for anything a screenshot does not say.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
