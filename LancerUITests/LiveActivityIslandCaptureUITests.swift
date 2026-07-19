@preconcurrency import XCTest

/// Captures SpringBoard Dynamic Island / Lock Screen while a Live Activity is
/// running (send a long sleep so the activity stays up for screenshots).
@MainActor
final class LiveActivityIslandCaptureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCaptureIslandWhileRunning() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "composer"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45))
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 20), "composer draft")

        let repoChip = app.buttons["command-center"].firstMatch
        if repoChip.waitForExistence(timeout: 5) {
            repoChip.tap()
            let lancerRow = app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "/Volumes/LancerDev/lancer"))
                .firstMatch
            XCTAssertTrue(lancerRow.waitForExistence(timeout: 10))
            lancerRow.tap()
            XCTAssertTrue(draft.waitForExistence(timeout: 10))
        }

        draft.tap()
        // Long sleep keeps the Live Activity alive after Activity.request —
        // startLiveActivity only runs after startConversation returns, so we
        // must stay foreground until that round-trip completes (prior 4s Home
        // race → ActivityAuthorizationError.visibility).
        let prompt = "Run the shell command `sleep 90` via Bash, then reply with exactly island-capture-ok. Do not use other tools."
        draft.typeText(prompt)
        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5) && send.isEnabled)
        send.tap()

        // Stay foreground long enough for relay startConversation → Activity.request.
        // Host-side log watcher also captures screenshots on "Activity.request succeeded".
        Thread.sleep(forTimeInterval: 25)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let islandShot = XCTAttachment(screenshot: springboard.screenshot())
        islandShot.name = "dynamic-island-springboard"
        islandShot.lifetime = .keepAlways
        add(islandShot)

        // Also lock for Lock Screen Live Activity banner.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 2)
        let lockShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        lockShot.name = "lock-screen-live-activity"
        lockShot.lifetime = .keepAlways
        add(lockShot)
    }
}
