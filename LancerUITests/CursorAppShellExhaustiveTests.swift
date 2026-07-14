@preconcurrency import XCTest

/// Workspaces-only shell chrome + reachable destinations (no mock 3-tab shell,
/// no restored CursorStyle IDs, no fake review/inbox roots).
@MainActor
final class CursorAppShellExhaustiveTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSkipOnboarding(destination: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        if let destination { app.launchEnvironment["LANCER_DESTINATION"] = destination }
        app.launch()
        return app
    }

    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launch()
        return app
    }

    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: 1. Cold launch → Workspaces-only root
    // AppRoot currently presents Workspaces directly (no in-app onboarding gate).

    func testColdLaunch_LandsOnWorkspacesRoot() throws {
        let app = launchOnboarding()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "Cold launch should land on Workspaces")
        XCTAssertEqual(app.tabBars.count, 0, "Workspaces-only root must not restore a tab bar")
        XCTAssertFalse(app.buttons["Home"].exists, "Home tab must not return")
        snapshot("01-cold-launch-workspaces", app: app)
    }

    // MARK: 2. Workspaces root chrome

    func testWorkspacesRoot_NoTabBar() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.tabBars.count, 0, "No Home/Workspaces/Settings tab shell")
        XCTAssertFalse(app.buttons["Home"].exists, "Home tab must not return")
        XCTAssertTrue(app.buttons["cursor-composer-tap"].waitForExistence(timeout: 5)
                      || app.buttons["New Chat"].waitForExistence(timeout: 2),
                      "Workspaces should expose New Chat composer entry")
        snapshot("02-workspaces-root", app: app)
    }

    func testProfile_SettingsTrustedMachinesOnOneStack() throws {
        let app = launchSkipOnboarding(destination: "profile")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 20)
                      || app.buttons["profile.row.settings"].waitForExistence(timeout: 5),
                      "Profile sheet should open")

        let settings = app.buttons["profile.row.settings"].exists
            ? app.buttons["profile.row.settings"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["cursor.settings"].waitForExistence(timeout: 5)
                      || app.buttons["cursor.settings.row.trusted-machines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.waitForExistence(timeout: 5),
                      "Policy & Governance must be an honest deferred state")
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists,
                       "Emergency Stop must not ship without atomic daemon wiring")
        snapshot("02b-profile-settings", app: app)

        let trusted = app.buttons["cursor.settings.row.trusted-machines"].exists
            ? app.buttons["cursor.settings.row.trusted-machines"]
            : app.staticTexts["Trusted machines"]
        XCTAssertTrue(trusted.waitForExistence(timeout: 5))
        trusted.tap()
        XCTAssertTrue(app.staticTexts["Trusted Machines"].waitForExistence(timeout: 10)
                      || app.staticTexts["Pair a machine"].waitForExistence(timeout: 5))
        snapshot("02c-trusted-machines", app: app)
    }

    // MARK: 3. Composer — real current controls

    func testComposer_OpensWithVendorModelAndSend() throws {
        let app = launchSkipOnboarding(destination: "composer")
        defer { app.terminate() }

        let agent = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Agent")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 15),
                      "Composer should expose Agent picker")
        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Model")).firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5),
                      "Claude Code vendor should expose Model picker (default Haiku)")
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5),
                      "Composer draft TextEditor should be a text view")
        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "Composer Send affordance (composer.send) must be present")
        snapshot("03-composer-controls", app: app)
    }

    // MARK: 4. Search overlay

    func testSearchOverlay_NoFakeSeededResults() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons["Search"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 10))

        let searchField = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzznomatch-uitest-xyz")
        snapshot("04-search-typed", app: app)

        XCTAssertTrue(
            app.staticTexts["No matching threads"].waitForExistence(timeout: 8)
                || app.staticTexts["No threads yet"].waitForExistence(timeout: 2),
            "Nonsense query must show honest empty copy, not invented seeded hits"
        )
        // Guard against fake seeded rows that used to appear in the mock shell.
        XCTAssertFalse(app.staticTexts["terraform apply"].exists)
    }

    // MARK: 5. In-thread approval destination (not fake review/inbox shell)

    func testApprovalDestination_InThreadCardChrome() throws {
        let app = launchSkipOnboarding(destination: "approval")
        defer { app.terminate() }

        let approve = app.buttons["cursor.approval.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 30),
                      "LANCER_DESTINATION=approval should open in-thread approval card")
        XCTAssertTrue(app.buttons["Deny"].waitForExistence(timeout: 5),
                      "In-thread card should expose Deny alongside Approve")
        XCTAssertFalse(app.buttons["cursor.review.approve"].exists,
                       "Removed Cursor Review IDs must not return")
        snapshot("05-in-thread-approval", app: app)
    }

    // MARK: 6. PR detail DEBUG destination (honest current surface)

    func testPRDetail_Destination() throws {
        let app = launchSkipOnboarding(destination: "prDetail")
        defer { app.terminate() }
        let visible = app.navigationBars["PR"].waitForExistence(timeout: 10)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ship history")).firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pull request")).firstMatch.waitForExistence(timeout: 5)
            || app.otherElements["pr-detail-screen"].waitForExistence(timeout: 5)
        XCTAssertTrue(visible, "PR detail destination should present current PR surface")
        snapshot("06-prdetail", app: app)
    }

    // MARK: 7. Settings destination honesty

    func testSettingsDestination_DeferredPolicyNoEmergencyStop() throws {
        let app = launchSkipOnboarding(destination: "settings")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["cursor.settings.row.trusted-machines"].waitForExistence(timeout: 5)
                      || app.staticTexts["Trusted machines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.exists)
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Halt every")).firstMatch.exists)
        snapshot("07-settings-honest", app: app)
    }
}
