@preconcurrency import XCTest

/// Regression guard: legacy sidebar-era surfaces must not appear on default
/// navigation paths after the Cursor shell cutover.
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
                      "Cursor shell should render Workspaces")

        for marker in legacyMarkers() {
            XCTAssertFalse(app.staticTexts[marker].exists,
                           "Legacy UI marker '\(marker)' must not appear on default launch")
        }
    }

    func testSettingsDestination_NoPolicyBridge() throws {
        let app = launchDefaultShell(destination: "settings")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20),
                      "LANCER_DESTINATION=settings should open Cursor Settings")
        XCTAssertTrue(app.otherElements["cursor.settings"].waitForExistence(timeout: 5)
                      || app.staticTexts["Trusted machines"].exists,
                      "Cursor Settings chrome should be visible")

        for marker in ["POLICY BRIDGE", "GENERAL", "Security & Trust"] {
            XCTAssertFalse(app.staticTexts[marker].exists,
                           "Legacy settings marker '\(marker)' must not appear")
        }
    }

    func testApprovalDestination_NoLegacyInbox() throws {
        let app = launchDefaultShell(destination: "inbox")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Review"].waitForExistence(timeout: 20),
                      "LANCER_DESTINATION=inbox should open Cursor Review, not legacy Inbox")
        XCTAssertFalse(app.staticTexts["one agent is waiting"].exists,
                       "Legacy Inbox headline must not appear")
        XCTAssertFalse(app.buttons["board.primary"].exists,
                       "Legacy Inbox board cards must not appear")
    }

    func testProfileSettings_NoLegacyBridge() throws {
        let app = launchDefaultShell()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.11)).tap()

        let appSettings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "App Settings")).firstMatch
        XCTAssertTrue(appSettings.waitForExistence(timeout: 15))
        appSettings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["POLICY BRIDGE"].exists)
        XCTAssertFalse(app.staticTexts["GENERAL"].exists)
    }

    func testComposerOpensFloatingSheet() throws {
        let app = launchDefaultShell()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        let composerTap = app.buttons["cursor-composer-tap"].firstMatch
        XCTAssertTrue(composerTap.waitForExistence(timeout: 10), "Composer tap target should exist")
        if composerTap.isHittable {
            composerTap.tap()
        } else {
            composerTap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // Live shell defaults to ManagedModel.claudeHaiku; mock shell uses "Composer 2.5".
        let modelChip = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Haiku' OR label CONTAINS[c] 'Composer'")
        ).firstMatch
        XCTAssertTrue(modelChip.waitForExistence(timeout: 10),
                      "Expanded composer should show model picker")
        XCTAssertTrue(app.buttons["cloud"].waitForExistence(timeout: 5),
                      "Expanded composer should show run-target cloud picker")
    }
}
