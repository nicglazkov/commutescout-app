import XCTest

/// CommuteScout voices on the Voice page, end to end, on a simulator:
/// a tap on Harper plays the sample and offers the download, the real
/// Kokoro download, Delete, and picking voices once they are on the
/// phone. It needs the network and a few minutes, so it runs
/// only when asked: `CS_NEURAL_UI=1` in the test environment
/// (`TEST_RUNNER_CS_NEURAL_UI=1` on the xcodebuild command line).
///
/// With `CS_SHOT_DIR` set, it stops at each stage and waits for
/// `<dir>/go-<stage>`, so a script on the Mac can take light and dark
/// screenshots of the page with `simctl`.
final class NeuralVoiceUITests: XCTestCase {
    private let pack = "kokoro-en-v1_0"
    private let env = ProcessInfo.processInfo.environment

    private func stage(_ name: String) {
        guard let dir = env["CS_SHOT_DIR"] else { return }
        FileManager.default.createFile(atPath: "\(dir)/at-\(name)", contents: nil)
        let go = "\(dir)/go-\(name)"
        let end = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: go), Date() < end { usleep(200_000) }
    }

    func testDownloadPreviewAndPickHarper() throws {
        try XCTSkipUnless(env["CS_NEURAL_UI"] == "1", "set CS_NEURAL_UI=1 to run")
        let app = XCUIApplication()
        app.launchArguments += ["-csOpenSettings"]
        app.launch()

        let voiceRow = app.buttons["settings-voice"].firstMatch
        // A fresh install asks for location and notifications first.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0 ..< 3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 4) else { break }
            for label in ["Allow While Using App", "Allow", "Don\u{2019}t Allow", "Don't Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
            sleep(1)
        }
        // The sheet from -csOpenSettings may be gone by now; open it by
        // hand if so.
        for _ in 0 ..< 4 where !voiceRow.waitForExistence(timeout: 5) {
            let gear = app.buttons["settings"].firstMatch
            if gear.waitForExistence(timeout: 5) && gear.isHittable { gear.tap() }
        }
        XCTAssertTrue(voiceRow.waitForExistence(timeout: 5), app.debugDescription)
        voiceRow.tap()
        let row = app.buttons["voice-\(pack).af_heart"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Harper is in the one voice list")
        XCTAssertTrue(row.label.contains("Harper") && row.label.contains("CommuteScout voice") && row.label.contains("MB download"), row.label)
        XCTAssertFalse(app.buttons["voices-delete-\(pack)"].exists, "nothing is downloaded yet")

        // A tap plays the sample and offers the download.
        let offer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download'")).firstMatch
        func choose() {
            row.tap()
            XCTAssertTrue(offer.waitForExistence(timeout: 10), "a voice not on the phone offers its download")
        }
        choose()
        let playing = NSPredicate(format: "label CONTAINS 'Playing a sample'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: playing, evaluatedWith: row)], timeout: 15), .completed,
                       "the sample streams and plays")
        stage("before")

        // The first download, shown in light; the pack is then deleted
        // and downloaded again in dark, which also covers Delete.
        offer.tap()
        let progress = app.descendants(matching: .any)["voices-progress-\(pack)"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20), "progress shows while downloading")
        XCTAssertTrue(app.buttons["voices-cancel-\(pack)"].exists)
        XCTAssertTrue(row.isSelected, "Harper is chosen while the set downloads")
        stage("downloading-light")

        let delete = app.buttons["voices-delete-\(pack)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 900), "the pack installs")
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting asks first")
        confirm.tap()
        XCTAssertTrue(app.buttons["voice-automatic"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-automatic"].isSelected, "deleting the set in use goes back to Automatic")
        stage("dark")
        choose()
        offer.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        stage("downloading-dark")
        XCTAssertTrue(delete.waitForExistence(timeout: 900), "the pack installs again")

        // Every voice of the set is picked with one tap now.
        XCTAssertTrue(row.isSelected)
        let george = app.buttons["voice-\(pack).bm_george"]
        if !george.exists { app.switches["voice-all-accents"].firstMatch.tap() }
        george.tap()
        XCTAssertTrue(george.isSelected, "George is the voice in use")
        XCTAssertFalse(offer.exists, "a voice on the phone is picked with no question")
        stage("after")
    }
}
