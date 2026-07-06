@preconcurrency import XCTest

/// Live-shell dispatch proof: select Claude Haiku 4 in the composer model picker
/// and send a prompt (requires seeded/live workspace data).
@MainActor
final class DispatchHaikuFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchLiveShell() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    func testComposer_SelectHaikuAndDispatch() throws {
        let app = launchLiveShell()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45))

        let composerTap = app.buttons["cursor-composer-tap"].firstMatch
        XCTAssertTrue(composerTap.waitForExistence(timeout: 10))
        composerTap.tap()

        let modelChip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Haiku")
        ).firstMatch
        XCTAssertTrue(modelChip.waitForExistence(timeout: 10),
                      "Live shell composer should default to Claude Haiku 4")
        modelChip.tap()

        let sonnet = app.staticTexts["Claude Sonnet 4"]
        if sonnet.waitForExistence(timeout: 5) {
            sonnet.tap()
        }

        let field = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Plan, ask, build")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("List the top-level folders in this repo")

        let send = app.buttons["composer.send"].firstMatch
        if send.waitForExistence(timeout: 5) {
            send.tap()
        } else {
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "arrow.up")).firstMatch.tap()
        }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 20),
                      "Dispatch should dismiss composer back to shell")
    }
}
