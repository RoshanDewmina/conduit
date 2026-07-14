@preconcurrency import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
///
/// Determinism: every launch sets `LANCER_UITEST_RESEED=1`, which wipes the
/// approvals table and re-seeds the fixed sample set (2 pending + 1 decided) and
/// clears residual app-lock prefs (see `DebugSeeder.resetForUITestIfRequested`). That
/// makes approval tests re-runnable — prior runs no longer leave approvals fully decided.
@MainActor
final class TapInjectionProofTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch the app in a deterministic, freshly-reseeded state, optionally
    /// landing directly on a supported DEBUG overlay (`LANCER_DESTINATION`).
    private func launchReseeded(destination: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        if let destination { app.launchEnvironment["LANCER_DESTINATION"] = destination }
        app.launch()
        return app
    }

    /// Workspaces root → profile → Settings (one NavigationStack).
    func testTapInjectionViaProfileSettings() throws {
        let app = launchReseeded()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "Workspaces-only shell should render the root")

        let headerButtons = app.buttons.matching(NSPredicate(format: "identifier != 'plus'"))
        XCTAssertGreaterThan(headerButtons.count, 0, "Profile avatar button should exist")
        headerButtons.element(boundBy: 0).tap()

        let settings = app.buttons["profile.row.settings"].exists
            ? app.buttons["profile.row.settings"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15),
                      "Profile sheet should expose Settings")
        settings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10),
                      "Settings should present on the Profile navigation stack")
        XCTAssertTrue(app.staticTexts["Trusted machines"].waitForExistence(timeout: 10)
                      || app.buttons["cursor.settings.row.trusted-machines"].waitForExistence(timeout: 5),
                      "Settings should list Trusted machines")
        XCTAssertTrue(app.otherElements["cursor.settings.policy-deferred"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Not available")).firstMatch.waitForExistence(timeout: 5),
                      "Policy & Governance must be deferred, not a fake editor")
        XCTAssertFalse(app.buttons["cursor.settings.emergency-stop"].exists)
        XCTAssertFalse(app.staticTexts["GENERAL"].exists,
                       "Legacy policy-bridge Settings must not appear")
        XCTAssertFalse(app.staticTexts["POLICY BRIDGE"].exists,
                       "Legacy policy-bridge Settings must not appear")
    }

    /// Seeded pending approval → in-thread Approve; durable local side-effect =
    /// both Approve and Deny leave the hierarchy (card unbound), not just button fade.
    func testApproveDecisionApplies() throws {
        let app = launchReseeded(destination: "approval")
        defer { app.terminate() }

        let approve = app.buttons["cursor.approval.approve"].firstMatch
        let deny = app.buttons["Deny"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 30),
                      "Reseeded approval should open in-thread approval card")
        XCTAssertTrue(deny.waitForExistence(timeout: 5),
                      "In-thread card should expose Deny")
        let commandSnippet = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "rm ", "curl ")
        ).firstMatch
        let hadCommandSnippet = commandSnippet.exists
        approve.tap()

        XCTAssertTrue(approve.waitForNonExistence(timeout: 8),
                      "Approve control should leave the hierarchy after decide")
        XCTAssertTrue(deny.waitForNonExistence(timeout: 3),
                      "Deny should leave with the card — disappearance of Approve alone is insufficient")
        if hadCommandSnippet {
            XCTAssertTrue(commandSnippet.waitForNonExistence(timeout: 3),
                          "Pending approval detail should clear after decide")
        }
    }

    /// Settings → Trusted machines opens relay pairing (Face ID permanently removed).
    func testSettingsTrustedMachinesOpensPairing() throws {
        let app = launchReseeded(destination: "settings")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 30),
                      "Settings destination should open Settings")

        let trustedMachines = app.descendants(matching: .any)["cursor.settings.row.trusted-machines"]
        XCTAssertTrue(trustedMachines.waitForExistence(timeout: 15),
                      "Trusted machines row should exist")
        if trustedMachines.isHittable {
            trustedMachines.tap()
        } else {
            trustedMachines.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        let pairingVisible = app.buttons["trusted-machines.pair"].waitForExistence(timeout: 10)
            || app.staticTexts["Pair a machine"].waitForExistence(timeout: 5)
            || app.staticTexts["No machines paired"].waitForExistence(timeout: 5)
            || app.navigationBars["Trusted Machines"].waitForExistence(timeout: 5)
        XCTAssertTrue(pairingVisible,
                      "Trusted machines should push the real pairing surface")
        XCTAssertFalse(app.staticTexts["relay pairing"].exists,
                       "Legacy relay pairing header must not appear")
        XCTAssertFalse(app.staticTexts["E2E Relay"].exists,
                       "Legacy relay pairing chrome must not appear")
        XCTAssertFalse(app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "Face ID")).firstMatch.exists,
                       "Face ID gating was permanently removed")
    }

    /// Workspaces list is the default shell root.
    func testWorkspacesRootShowsReposOrEmptyState() throws {
        let app = launchReseeded()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "App should render the Workspaces list")
        let repoRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "lancer-ios", "command-center", "All Repos")
        ).firstMatch
        let emptyState = app.staticTexts["No conversations yet"].firstMatch
        let addRepo = app.staticTexts["Add Repo"].firstMatch
        XCTAssertTrue(
            repoRow.waitForExistence(timeout: 3)
                || emptyState.waitForExistence(timeout: 5)
                || addRepo.waitForExistence(timeout: 10),
            "Workspaces should show real repos, All Repos, Add Repo, or an honest empty state"
        )
    }

    /// Live relay approval proof (opt-in). See `scripts/validation/relay-approval-e2e.sh`.
    /// Uses in-thread approval card — not removed inbox/review destinations.
    func testRelayApprovalUnblocksHostHook() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LANCER_RELAY_E2E"] == "1" else {
            throw XCTSkip("Owner-gated live relay: set LANCER_RELAY_E2E=1 (+ LANCER_RELAY_URL/LANCER_RELAY_CODE/LANCER_PUSH_BACKEND_URL) via relay-approval-e2e.sh; UI alone cannot prove host-hook unblock")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launchEnvironment["LANCER_RELAY_URL"] = env["LANCER_RELAY_URL"] ?? ""
        app.launchEnvironment["LANCER_RELAY_CODE"] = env["LANCER_RELAY_CODE"] ?? ""
        app.launchEnvironment["LANCER_PUSH_BACKEND_URL"] = env["LANCER_PUSH_BACKEND_URL"] ?? ""
        app.launchEnvironment["LANCER_DESTINATION"] = "approval"
        app.launchEnvironment["LANCER_SKIP_NOTIFICATION_PROMPT"] = "1"
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }

        app.launch()
        app.tap()
        defer { app.terminate() }

        let approve = app.buttons["cursor.approval.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 120),
                      "A relay-delivered escalation should surface the in-thread Approve card")
        let deny = app.buttons["Deny"].firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        approve.tap()

        XCTAssertTrue(approve.waitForNonExistence(timeout: 30),
                      "After decide, Approve must leave the hierarchy")
        XCTAssertTrue(deny.waitForNonExistence(timeout: 5),
                      "Deny must leave with the card (Approve disappearance alone is not success)")
        // Host-side hook unblock is asserted by relay-approval-e2e.sh against the daemon;
        // this UITest only proves the phone-side decide path for a live escalation.
    }

}
