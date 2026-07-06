@preconcurrency import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
///
/// Determinism: every launch sets `LANCER_UITEST_RESEED=1`, which wipes the
/// approvals table and re-seeds the fixed sample set (2 pending + 1 decided) and
/// clears the app-lock opt-in (see `DebugSeeder.resetForUITestIfRequested`). That
/// makes `testApproveDecisionApplies` re-runnable — prior runs no longer leave the
/// inbox fully decided.
@MainActor
final class TapInjectionProofTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch the app in a deterministic, freshly-reseeded state, optionally
    /// landing directly on a supported sidebar destination.  Destinations are a
    /// DEBUG-only test seam in AppRoot; production navigation remains the
    /// sidebar/New Chat shell.
    private func launchReseeded(destination: String? = nil, drawerOpen: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        if let destination { app.launchEnvironment["LANCER_DESTINATION"] = destination }
        if drawerOpen { app.launchEnvironment["LANCER_DRAWER_OPEN"] = "1" }
        app.launch()
        return app
    }

    /// Scroll `element` into the comfortably-visible viewport. `isHittable` is
    /// unreliable here: an element below the scroll fold still reports hittable
    /// because its frame sits within the window bounds (just behind the tab bar),
    /// so a tap would land off-screen. Scroll on the actual scroll view until the
    /// element's frame is clear of the top chrome and the bottom tab bar.
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        let scrollView = app.scrollViews.firstMatch
        let window = app.windows.firstMatch
        var swipes = 0
        while swipes < maxSwipes {
            guard element.exists else { break }
            let safeBottom = window.frame.height - 140
            let f = element.frame
            if f.minY > 90 && f.maxY < safeBottom { return }
            if f.maxY >= safeBottom {
                if scrollView.exists { scrollView.swipeUp() } else { app.swipeUp() }
            } else {
                return
            }
            swipes += 1
        }
    }

    /// Cleanest proof of HID/event injection: switching sidebar destinations.
    /// Independent of approval-decision wiring — it proves a tap lands, closes
    /// the compact drawer, and renders the selected destination.
    func testTapInjectionViaTabSwitch() throws {
        let app = launchReseeded(destination: "inbox", drawerOpen: true)
        defer { app.terminate() }

        let inboxTitle = app.staticTexts["Inbox"]
        XCTAssertTrue(inboxTitle.waitForExistence(timeout: 30),
                      "Reseeded sidebar Inbox should render its title")

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "Settings sidebar row should exist")
        settings.tap()

        XCTAssertTrue(app.staticTexts["GENERAL"].waitForExistence(timeout: 10),
                      "After tapping Settings, its General section should render")

        // Settings is a top-level destination in the sidebar shell: it returns via
        // the hamburger (re-open the drawer) → tap another destination, not a Back
        // control. (The old in-content Back affordance was removed with the shell.)
        let hamburger = app.buttons["Open navigation"]
        XCTAssertTrue(hamburger.waitForExistence(timeout: 10),
                      "Settings should expose the shell hamburger to re-open the drawer")
        hamburger.tap()

        // Home IA rebuild (2026-07-02, commit 809cb6be) folded the standalone
        // "Inbox" sidebar row into "Home" — the drawer's primary rows are now
        // just Home and Machines. "Inbox" (`.needsAttention`) is still reachable
        // via the LANCER_DESTINATION=inbox launch seam used above, and inline
        // from Home's "Needs attention" section, but no longer has its own
        // sidebar row to tap back to. Assert against the row that actually
        // exists post-redesign rather than the pre-redesign label.
        let homeRow = app.buttons["Home"]
        XCTAssertTrue(homeRow.waitForExistence(timeout: 10), "Re-opened drawer should list the Home destination")
        homeRow.tap()
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10),
                      "Tapping Home in the re-opened drawer should return to the Home destination")
    }

    /// The real verification goal: tap through a seeded pending card and confirm
    /// the decision applies (pending primary-button count drops). Medium+ risk
    /// cards surface "Review" on the board; low risk shows "Approve" inline.
    func testApproveDecisionApplies() throws {
        let app = launchReseeded(destination: "inbox")
        defer { app.terminate() }

        let reviewButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Review"))
        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Approve"))
        let boardPrimary = app.buttons["board.primary"].firstMatch
        XCTAssertTrue(boardPrimary.waitForExistence(timeout: 30),
                      "Reseeded inbox should show at least one pending board card")
        let before = reviewButtons.count + approveButtons.count
        XCTAssertGreaterThan(before, 0, "Expected pending approval cards in the reseeded inbox")

        boardPrimary.tap()
        let sheetApprove = app.buttons["approval.approve"].firstMatch
        XCTAssertTrue(sheetApprove.waitForExistence(timeout: 10),
                      "Opening a medium+ board card should surface the sheet approve control")
        sheetApprove.tap()

        let deadline = Date().addingTimeInterval(10)
        var after = reviewButtons.count + approveButtons.count
        while after >= before && Date() < deadline {
            usleep(300_000)
            after = reviewButtons.count + approveButtons.count
        }
        XCTAssertLessThan(after, before,
                          "After approving, the pending Review/Approve control count should drop")
    }

    /// Settings → Security & Trust opens the relay/pairing trust surface (the
    /// legacy Face-ID app-lock toggle was removed in the 2026-07 shell rebuild).
    func testFaceIDToggleOptIn() throws {
        let app = launchReseeded(destination: "settings")
        defer { app.terminate() }

        let securityRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Security")
        ).firstMatch
        XCTAssertTrue(securityRow.waitForExistence(timeout: 30),
                      "Settings should expose Security & Trust")
        securityRow.tap()

        let relayRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Relay")
        ).firstMatch
        XCTAssertTrue(relayRow.waitForExistence(timeout: 15),
                      "Security & Trust should surface relay pairing trust controls")
    }

    /// Machines → Workspaces: the sidebar Machines destination now renders the
    /// Cursor-style workspace list (SSH saved-host reconnect moved to Settings).
    func testSavedHostReconnectPresentsPrompt() throws {
        let app = launchReseeded(destination: "machines")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30),
                      "Machines destination should render the Workspaces list")
        let repoRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "lancer-ios", "command-center", "All Repos")
        ).firstMatch
        XCTAssertTrue(repoRow.waitForExistence(timeout: 10),
                      "Workspaces should list a repo row (seed or live-hydrated)")
    }

    /// Live relay approval proof (opt-in). Closes the one leaf the host-side relay
    /// round-trip couldn't reach via idb: tapping APPROVE on a card delivered over
    /// the production E2E relay. The host harness (see
    /// scripts/validation/relay-approval-e2e.sh) stands up a resident daemon paired
    /// to the same relay code, fires a `fileWrite` escalation ~after pairing, and
    /// asserts the blocked hook unblocks (exit 0) + audit shows `approve` once this
    /// test taps APPROVE. Runner env is supplied via `TEST_RUNNER_*` by that script.
    func testRelayApprovalUnblocksHostHook() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LANCER_RELAY_E2E"] == "1" else {
            throw XCTSkip("Set LANCER_RELAY_E2E=1 (+ LANCER_RELAY_URL/LANCER_RELAY_CODE/LANCER_PUSH_BACKEND_URL) via the relay-approval-e2e.sh harness")
        }
        let app = XCUIApplication()
        // Bypass first-launch onboarding (a fresh install otherwise shows the
        // onboarding view, where the relay auto-pair never runs). Setting the
        // @AppStorage("onboardingSeen") default via the argument domain reaches the
        // post-onboarding shell WITHOUT seeding demo approvals, so the only Inbox
        // card is the relay-delivered one.
        app.launchArguments += ["-onboardingSeen", "YES"]
        // Pair to the live relay headlessly (DEBUG seam) and land on the Inbox so
        // the relay-delivered card is on screen the moment it arrives.
        app.launchEnvironment["LANCER_RELAY_URL"] = env["LANCER_RELAY_URL"] ?? ""
        app.launchEnvironment["LANCER_RELAY_CODE"] = env["LANCER_RELAY_CODE"] ?? ""
        app.launchEnvironment["LANCER_PUSH_BACKEND_URL"] = env["LANCER_PUSH_BACKEND_URL"] ?? ""
        app.launchEnvironment["LANCER_DESTINATION"] = "inbox"
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }

        // Launch once for this pairing code. Relaunching after a successful pair
        // rotates the phone key while the daemon remains connected under the same
        // code, which the relay correctly rejects as a key-mismatch hijack.
        app.launch()
        app.tap()
        defer { app.terminate() }

        // The host fires a medium-risk fileWrite escalation, which the Inbox
        // board card renders as "Review" (not "Approve") — medium+ risk always
        // routes through the detail sheet (see InboxView.pendingCard's
        // requiresFullReview). Wait for that board card, open the sheet, then
        // wait for the sheet's actual approve control.
        let boardPrimary = app.buttons["board.primary"].firstMatch
        XCTAssertTrue(boardPrimary.waitForExistence(timeout: 120),
                      "A relay-delivered escalation should surface a board card in the Inbox")
        boardPrimary.tap()

        let approve = app.buttons["approval.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15),
                      "Opening the medium-risk board card should surface the sheet's approve button")
        approve.tap()

        // The decision rides the relay back to the daemon; the card should leave
        // PENDING (its Approve control disappears). The host script independently
        // asserts the hook unblocked (exit 0) and audit recorded `approve`.
        let approveButtons = app.buttons.matching(identifier: "approval.approve")
        let deadline = Date().addingTimeInterval(15)
        while approveButtons.count > 0 && Date() < deadline { usleep(300_000) }
        XCTAssertEqual(approveButtons.count, 0,
                       "After approving the relay card, no pending Approve control should remain")
    }

    /// Strict localhost SSH proof, opt-in only because it needs macOS Remote Login
    /// plus a Keychain-backed password. In simulator-env mode, the password is set
    /// in the Device Hub app-launch environment; the test runner receives only a
    /// non-secret flag.
    func testLocalhostSSHShowsTOFUAndConnects() throws {
        let runnerEnv = ProcessInfo.processInfo.environment
        let useSimulatorLaunchEnvironment = runnerEnv["LANCER_LIVE_SSH_SIM_ENV"] == "1"
        guard useSimulatorLaunchEnvironment || runnerEnv["LANCER_LIVE_SSH_E2E"] == "1" else {
            throw XCTSkip("Set LANCER_LIVE_SSH_E2E=1 with LANCER_TEST_PW to run the live localhost SSH proof")
        }

        let app: XCUIApplication
        if useSimulatorLaunchEnvironment {
            app = XCUIApplication()
            app.launch()
        } else {
            let testPassword = runnerEnv["LANCER_TEST_PW"] ?? ""
            XCTAssertFalse(testPassword.isEmpty, "LANCER_TEST_PW must be supplied by the test runner environment")
            app = XCUIApplication()
            app.launchEnvironment["LANCER_DAEMON_E2E"] = "1"
            app.launchEnvironment["LANCER_TEST_HOST"] = runnerEnv["LANCER_TEST_HOST"] ?? "127.0.0.1"
            app.launchEnvironment["LANCER_TEST_PORT"] = runnerEnv["LANCER_TEST_PORT"] ?? "22"
            app.launchEnvironment["LANCER_TEST_USER"] = runnerEnv["LANCER_TEST_USER"] ?? NSUserName()
            app.launchEnvironment["LANCER_TEST_PW"] = testPassword
            app.launchEnvironment["LANCER_DESTINATION"] = "machines"
            app.launch()
        }
        defer { app.terminate() }

        let localHost = app.staticTexts["This Mac (e2e)"]
        XCTAssertTrue(localHost.waitForExistence(timeout: 30), "Live E2E seed should add the localhost host")
        let hostCell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", "This Mac")).firstMatch
        if hostCell.exists { hostCell.tap() } else { localHost.tap() }

        let connectButton = app.buttons["Connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 20), "Localhost password prompt should appear")
        XCTAssertTrue(connectButton.isEnabled, "DEBUG-only E2E password prefill should enable Connect without typing")
        connectButton.tap()

        let tofuTitle = app.staticTexts["Unknown Host Key"]
        XCTAssertTrue(tofuTitle.waitForExistence(timeout: 30), "Production localhost connect should show the TOFU prompt")
        XCTAssertTrue(app.staticTexts["Fingerprint (SHA256)"].exists, "TOFU prompt should show the SSH fingerprint label")
        XCTAssertTrue(app.buttons["Trust & Connect"].exists, "TOFU prompt should require explicit trust")

        app.buttons["Trust & Connect"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 45),
                      "After trusting the localhost key, the SSH session should connect")
    }

}
