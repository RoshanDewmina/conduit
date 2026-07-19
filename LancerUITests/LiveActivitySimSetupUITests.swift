@preconcurrency import XCTest

/// One-shot sim setup for Live Activity proof (2026-07-18): add the real
/// lancer workspace so LiveActivityDispatchProofUITests can dispatch.
/// Pairing must already be done out-of-band (`LANCER_RELAY_PAIR_CODE`).
@MainActor
final class LiveActivitySimSetupUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAddLancerRepo() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "addRepo"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        let pathField = app.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 20), "add-repo path field")
        pathField.tap()
        pathField.typeText("/Volumes/LancerDev/lancer")

        let addRepoButton = app.buttons["Add Repo"].firstMatch
        XCTAssertTrue(addRepoButton.waitForExistence(timeout: 5), "Add Repo confirm")
        XCTAssertTrue(addRepoButton.isEnabled, "Add Repo should enable after path entry")
        addRepoButton.tap()

        XCTAssertTrue(
            app.staticTexts["Workspaces"].waitForExistence(timeout: 20)
                || app.staticTexts["lancer"].waitForExistence(timeout: 20),
            "should return to workspaces with lancer present"
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "setup-lancer-repo-added"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
