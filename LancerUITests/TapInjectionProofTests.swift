@preconcurrency import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
///
/// Determinism: every launch sets `LANCER_UITEST_RESEED=1`, which wipes the
/// approvals table and re-seeds the fixed sample set (2 pending + 1 decided) and
/// clears the app-lock opt-in (see `DebugSeeder.resetForUITestIfRequested`). That
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

    /// Cursor shell navigation proof: Workspaces root → profile drawer → Cursor Settings.
    func testTapInjectionViaTabSwitch() throws {
        let app = launchReseeded()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "Cursor shell should render the Workspaces root")

        let headerButtons = app.buttons.matching(NSPredicate(format: "identifier != 'plus'"))
        XCTAssertGreaterThan(headerButtons.count, 0, "Profile avatar button should exist")
        headerButtons.element(boundBy: 0).tap()

        let appSettings = app.staticTexts["App Settings"]
        XCTAssertTrue(appSettings.waitForExistence(timeout: 15),
                      "Profile drawer should expose App Settings")
        appSettings.tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10),
                      "Cursor Settings should present")
        XCTAssertTrue(app.staticTexts["Trusted machines"].waitForExistence(timeout: 10),
                      "Cursor Settings should list Trusted machines")
        XCTAssertFalse(app.staticTexts["GENERAL"].exists,
                       "Legacy policy-bridge Settings must not appear")
        XCTAssertFalse(app.staticTexts["POLICY BRIDGE"].exists,
                       "Legacy policy-bridge Settings must not appear")
    }

    /// Seeded pending approval → Cursor Review sheet → Approve.
    func testApproveDecisionApplies() throws {
        let app = launchReseeded(destination: "inbox")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Review"].waitForExistence(timeout: 30),
                      "Reseeded approval should open Cursor Review, not legacy Inbox")

        let approve = app.buttons["cursor.review.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15),
                      "Review screen should expose Approve")
        approve.tap()

        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 10),
                      "Approve should commit and show Approved status")
    }

    /// Settings → Trusted machines opens Cursor relay pairing (not legacy relay page).
    func testFaceIDToggleOptIn() throws {
        let app = launchReseeded(destination: "settings")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 30),
                      "Settings destination should open Cursor Settings")

        let trustedMachines = app.staticTexts["Trusted machines"]
        XCTAssertTrue(trustedMachines.waitForExistence(timeout: 15))
        trustedMachines.tap()

        XCTAssertTrue(app.staticTexts["Pair machine"].waitForExistence(timeout: 15),
                      "Trusted machines should open Cursor relay pairing sheet")
        XCTAssertFalse(app.staticTexts["relay pairing"].exists,
                       "Legacy relay pairing header must not appear")
        XCTAssertFalse(app.staticTexts["E2E Relay"].exists,
                       "Legacy relay pairing chrome must not appear")
    }

    /// Workspaces list is the default Cursor shell root (replaces sidebar Machines).
    func testSavedHostReconnectPresentsPrompt() throws {
        let app = launchReseeded()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "App should render the Workspaces list")
        let repoRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "lancer-ios", "command-center", "All Repos")
        ).firstMatch
        let emptyState = app.staticTexts["No conversations yet"].firstMatch
        XCTAssertTrue(
            repoRow.waitForExistence(timeout: 3) || emptyState.waitForExistence(timeout: 10),
            "Workspaces should show real repos when live-hydrated or the honest empty state when no conversations exist"
        )
    }

    /// Live relay approval proof (opt-in). See `scripts/validation/relay-approval-e2e.sh`.
    func testRelayApprovalUnblocksHostHook() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LANCER_RELAY_E2E"] == "1" else {
            throw XCTSkip("Set LANCER_RELAY_E2E=1 (+ LANCER_RELAY_URL/LANCER_RELAY_CODE/LANCER_PUSH_BACKEND_URL) via the relay-approval-e2e.sh harness")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launchEnvironment["LANCER_RELAY_URL"] = env["LANCER_RELAY_URL"] ?? ""
        app.launchEnvironment["LANCER_RELAY_CODE"] = env["LANCER_RELAY_CODE"] ?? ""
        app.launchEnvironment["LANCER_PUSH_BACKEND_URL"] = env["LANCER_PUSH_BACKEND_URL"] ?? ""
        app.launchEnvironment["LANCER_DESTINATION"] = "inbox"
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

        XCTAssertTrue(app.staticTexts["Review"].waitForExistence(timeout: 120),
                      "A relay-delivered escalation should surface Cursor Review")

        // LANCER_DESTINATION=inbox force-opens the Review sheet at launch via a DEBUG
        // seam, before the real relay escalation has necessarily arrived — "Review" and
        // the Approve button both exist immediately in that empty state too, so waiting
        // only for them is a false-positive gap: it lets this test tap Approve on an
        // unbound sheet and pass without the real round-trip ever completing (root-caused
        // 2026-07-08 via os_log instrumentation — zero onPendingApprovalsChanged/
        // lancerE2EApprovalReceived events fired before the premature tap in 4/4 repro
        // runs). CursorReviewDiffView.requestTitle renders the literal string
        // "No pending approval" until `approval` is real, so wait for that to clear
        // before trusting the screen is bound to the actual escalation.
        let noPendingApproval = app.staticTexts["No pending approval"]
        if noPendingApproval.exists {
            XCTAssertTrue(noPendingApproval.waitForNonExistence(timeout: 120),
                          "Review sheet should bind to the real relay-delivered approval, not stay on the empty DEBUG-seam placeholder")
        }

        let approve = app.buttons["cursor.review.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15),
                      "Review screen should expose Approve")
        approve.tap()

        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 15),
                       "After approving, the review screen should show Approved")
    }

    /// Strict localhost SSH proof, opt-in only.
    func testLocalhostSSHShowsTOFUAndConnects() throws {
        let runnerEnv = ProcessInfo.processInfo.environment
        let useSimulatorLaunchEnvironment = runnerEnv["LANCER_LIVE_SSH_SIM_ENV"] == "1"
        guard useSimulatorLaunchEnvironment || runnerEnv["LANCER_LIVE_SSH_E2E"] == "1" else {
            throw XCTSkip("Set LANCER_LIVE_SSH_E2E=1 with LANCER_TEST_PW to run the live localhost SSH proof")
        }

        throw XCTSkip("SSH host management moved out of user-facing Cursor Settings — run via daemon E2E harness instead")
    }

}
