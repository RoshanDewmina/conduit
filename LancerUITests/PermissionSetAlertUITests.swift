@preconcurrency import XCTest

/// Focused SET-failure alert proof with daemon already stopped out-of-band.
@MainActor
final class PermissionSetAlertUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSetFailureShowsAlertWhenDaemonDown() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45))
        let lancer = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "lancer,"))
            .firstMatch
        XCTAssertTrue(lancer.waitForExistence(timeout: 15))
        lancer.tap()

        let recent = app.staticTexts["live-activity-dispatch-ok"].firstMatch
        if recent.waitForExistence(timeout: 8) {
            recent.tap()
        } else {
            app.cells.firstMatch.tap()
        }

        let plus = app.buttons["Add context"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        let permission = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Permission"))
            .firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        permission.tap()

        // Pick a different preset than "Auto-approve safe writes"
        let alwaysAsk = app.buttons["Always ask"].firstMatch
        XCTAssertTrue(alwaysAsk.waitForExistence(timeout: 5))
        alwaysAsk.tap()

        let alert = app.alerts["Couldn't change permission mode"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 12), "SET with daemon down must alert")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "goal3-set-alert-daemon-down"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
