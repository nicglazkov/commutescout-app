import XCTest

/// The CommuteScout voices section of the Voice page, end to end, on a
/// simulator: preview before download, the real Kokoro download, and
/// picking Harper. It needs the network and a few minutes, so it runs
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
        let download = app.buttons["voices-download-\(pack)"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "the pack offers a download")
        let row = app.buttons["voice-\(pack).af_heart"]
        XCTAssertTrue(row.exists && row.label.contains("Harper") && row.label.contains("Computer-generated voice"), row.label)
        XCTAssertFalse(row.isEnabled, "a voice can be picked only after its pack is downloaded")

        // A preview plays before anything is downloaded.
        let preview = app.buttons["voices-preview-\(pack).af_heart"]
        XCTAssertTrue(preview.exists)
        preview.tap()
        let playing = NSPredicate(format: "label BEGINSWITH 'Stop the sample'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: playing, evaluatedWith: preview)], timeout: 15), .completed,
                       "the sample streams and plays")
        stage("before")

        // The first download, shown in light; the pack is then deleted
        // and downloaded again in dark, which also covers Delete.
        download.tap()
        let progress = app.descendants(matching: .any)["voices-progress-\(pack)"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20), "progress shows while downloading")
        XCTAssertTrue(app.buttons["voices-cancel-\(pack)"].exists)
        stage("downloading-light")

        let delete = app.buttons["voices-delete-\(pack)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 900), "the pack installs")
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting asks first")
        confirm.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 10), "a deleted pack offers its download again")
        stage("dark")
        download.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        stage("downloading-dark")
        XCTAssertTrue(delete.waitForExistence(timeout: 900), "the pack installs again")

        // Every voice of the pack can be picked now; pick Harper.
        XCTAssertTrue(row.isEnabled)
        row.tap()
        XCTAssertTrue(row.isSelected, "Harper is the voice in use")
        let george = app.buttons["voices-preview-\(pack).bm_george"]
        george.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: playing, evaluatedWith: george)], timeout: 15), .completed)
        stage("after")
    }
}
