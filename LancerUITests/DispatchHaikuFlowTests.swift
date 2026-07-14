@preconcurrency import XCTest

/// Composer chrome + model picker proof against the current NewChatComposerView.
/// Full live dispatch (durable host side-effect) is owner-gated — without a
/// paired machine / send target this suite asserts real controls only.
@MainActor
final class DispatchHaikuFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchLiveShell(destination: String? = "composer") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        if let destination {
            app.launchEnvironment["LANCER_DESTINATION"] = destination
        }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    func testComposer_SelectHaikuControls() throws {
        let app = launchLiveShell(destination: "addRepo")
        defer { app.terminate() }

        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 20), "Add Repo should expose a path field")
        path.tap()
        path.typeText("/tmp/lancer-ui-test-repo")
        let addRepo = app.buttons["Add Repo"].firstMatch
        XCTAssertTrue(addRepo.isEnabled)
        addRepo.tap()

        let openComposer = app.buttons["cursor-composer-tap"].firstMatch
        XCTAssertTrue(openComposer.waitForExistence(timeout: 10))
        openComposer.tap()

        let agent = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Agent")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 20),
                      "Composer should expose Agent picker (Claude Code default)")

        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Model")).firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10),
                      "Claude Code should expose Model picker")
        XCTAssertTrue(
            model.label.lowercased().contains("haiku")
                || app.staticTexts["Haiku"].exists
                || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Haiku")).firstMatch.exists,
            "Default model should be Haiku"
        )

        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5),
                      "Composer draft is a TextEditor (text view), not a text field")
        draft.tap()
        draft.typeText("List the top-level folders in this repo")

        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "Send affordance (composer.send) must remain covered")
        XCTAssertTrue(send.isEnabled,
                      "Seeded absolute repo + non-empty draft should enable the real Send button")

        // Durable dispatch requires a paired host + absolute repo cwd. Without that,
        // do not pretend a thread opened — skip the live send side-effect.
        let env = ProcessInfo.processInfo.environment
        guard env["LANCER_DISPATCH_E2E"] == "1" else {
            throw XCTSkip("Owner-gated live dispatch: set LANCER_DISPATCH_E2E=1 with a paired machine and absolute repo cwd; chrome controls already asserted")
        }

        send.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "List the top-level folders")).firstMatch.waitForExistence(timeout: 30),
            "Live dispatch should open a work thread showing the submitted prompt"
        )
    }
}
