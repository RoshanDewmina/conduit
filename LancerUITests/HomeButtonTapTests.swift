@preconcurrency import XCTest

/// Workspaces root chrome — composer (+) and profile → Settings path.
@MainActor
final class HomeButtonTapTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchWorkspaces() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    func testWorkspacesComposerOpens() throws {
        let app = launchWorkspaces()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        let composer = app.buttons["cursor-composer-tap"].exists
            ? app.buttons["cursor-composer-tap"]
            : app.buttons["New Chat"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "New Chat composer entry should exist")
        if composer.isHittable {
            composer.tap()
        } else {
            composer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Agent")).firstMatch.waitForExistence(timeout: 10)
                || app.buttons["Send"].waitForExistence(timeout: 5),
            "Tapping New Chat should present composer controls"
        )
    }

    func testProfileSettingsOpensFromAvatar() throws {
        let app = launchWorkspaces()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        let headerButtons = app.buttons
        XCTAssertGreaterThan(headerButtons.count, 0, "Workspaces header should expose controls")
        headerButtons.element(boundBy: 0).tap()

        let settingsRow = app.buttons["profile.row.settings"].exists
            ? app.buttons["profile.row.settings"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 15),
                      "Profile sheet should list Settings")
        settingsRow.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 15),
                      "Settings row should push Settings on the Profile stack")
        XCTAssertTrue(app.staticTexts["Trusted machines"].waitForExistence(timeout: 10)
                      || app.buttons["cursor.settings.row.trusted-machines"].waitForExistence(timeout: 5),
                      "Settings should expose Trusted machines")
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.waitForExistence(timeout: 5),
                      "Policy & Governance must be an honest deferred state")
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists)
    }
}
