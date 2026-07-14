@preconcurrency import XCTest

/// Regression guard: legacy sidebar-era surfaces must not appear on default
/// navigation paths after the Workspaces-only shell cutover.
@MainActor
final class LegacyUIRemovalTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchDefaultShell(destination: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        if let destination { app.launchEnvironment["LANCER_DESTINATION"] = destination }
        app.launch()
        return app
    }

    private func legacyMarkers() -> [String] {
        [
            "POLICY BRIDGE",
            "GENERAL",
            "relay pairing",
            "E2E Relay",
            "one agent is waiting",
            "nothing pending"
        ]
    }

    func testDefaultLaunch_NoLegacyChrome() throws {
        let app = launchDefaultShell()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "Shell should render Workspaces")
        XCTAssertEqual(app.tabBars.count, 0, "Tab bar / 3-root shell must not return")

        for marker in legacyMarkers() {
            XCTAssertFalse(app.staticTexts[marker].exists,
                           "Legacy UI marker '\(marker)' must not appear on default launch")
        }
    }

    func testSettingsDestination_NoPolicyBridge() throws {
        let app = launchDefaultShell(destination: "settings")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20),
                      "LANCER_DESTINATION=settings should open Settings")
        XCTAssertTrue(app.otherElements["cursor.settings"].waitForExistence(timeout: 5)
                      || app.buttons["cursor.settings.row.trusted-machines"].exists,
                      "Settings chrome should be visible")
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.exists,
                      "Policy must be deferred, not a fake Apply surface")
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists)

        for marker in ["POLICY BRIDGE", "GENERAL", "Security & Trust"] {
            XCTAssertFalse(app.staticTexts[marker].exists,
                           "Legacy settings marker '\(marker)' must not appear")
        }
    }

    func testApprovalDestination_NoLegacyInbox() throws {
        let app = launchDefaultShell(destination: "approval")
        defer { app.terminate() }

        let approve = app.buttons["cursor.approval.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 30),
                      "LANCER_DESTINATION=approval should open in-thread approval card")
        XCTAssertFalse(app.staticTexts["one agent is waiting"].exists,
                       "Legacy Inbox headline must not appear")
        XCTAssertFalse(app.buttons["board.primary"].exists,
                       "Legacy Inbox board cards must not appear")
        XCTAssertFalse(app.buttons["cursor.review.approve"].exists,
                       "Removed review shell Approve ID must not appear")
    }

    func testProfileSettings_NoLegacyBridge() throws {
        let app = launchDefaultShell(destination: "profile")
        defer { app.terminate() }

        let settings = app.buttons["profile.row.settings"].exists
            ? app.buttons["profile.row.settings"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["POLICY BRIDGE"].exists)
        XCTAssertFalse(app.staticTexts["GENERAL"].exists)
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists)
    }

    func testComposerOpensWithRealControls() throws {
        let app = launchDefaultShell(destination: "addRepo")
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
        XCTAssertTrue(agent.waitForExistence(timeout: 15), "Composer Agent picker should exist")
        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Model")).firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5), "Composer Model picker should exist")
        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "Composer Send affordance must stay covered")
        XCTAssertFalse(send.isEnabled, "Send must be disabled before the draft is valid")
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5),
                      "Composer draft TextEditor should be present")
        draft.tap()
        draft.typeText("Inspect the workspace")
        XCTAssertTrue(send.isEnabled,
                      "Seeded absolute repo + non-empty draft should enable the real Send button")
    }
}
