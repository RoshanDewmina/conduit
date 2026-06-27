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

        let inboxRow = app.buttons["Inbox"]
        XCTAssertTrue(inboxRow.waitForExistence(timeout: 10), "Re-opened drawer should list the Inbox destination")
        inboxRow.tap()
        XCTAssertTrue(inboxTitle.waitForExistence(timeout: 10),
                      "Tapping Inbox in the re-opened drawer should return to the Inbox destination")
    }

    /// The real verification goal: tap APPROVE on a seeded pending card and confirm
    /// the decision applies (the card leaves PENDING → APPROVE-button count drops).
    func testApproveDecisionApplies() throws {
        let app = launchReseeded(destination: "inbox")
        defer { app.terminate() }

        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Approve"))
        XCTAssertTrue(app.buttons["Approve"].firstMatch.waitForExistence(timeout: 30),
                      "Reseeded inbox should show at least one pending APPROVE button")
        let before = approveButtons.count
        XCTAssertGreaterThan(before, 0, "Expected pending approval cards in the reseeded inbox")

        app.buttons["Approve"].firstMatch.tap()

        let deadline = Date().addingTimeInterval(10)
        var after = approveButtons.count
        while after >= before && Date() < deadline {
            usleep(300_000)
            after = approveButtons.count
        }
        XCTAssertLessThan(after, before,
                          "After tapping APPROVE the pending APPROVE-button count should drop (decision applied)")
    }

    /// Phase-5 app-lock opt-in: Settings → Security → "Require Face ID on launch"
    /// starts OFF (reseed clears `appLockEnabled`) and the toggle flips it ON.
    func testFaceIDToggleOptIn() throws {
        let app = launchReseeded(destination: "settings")
        defer { app.terminate() }

        let securityCard = app.buttons["Security"].firstMatch
        if securityCard.waitForExistence(timeout: 10) {
            securityCard.tap()
        } else {
            app.staticTexts["Security"].firstMatch.tap()
        }
        let toggle = app.switches["Require Face ID on launch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30),
                      "Settings → Security should expose the Face ID app-lock toggle")
        scrollIntoView(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0",
                       "App lock should start OFF — reseed clears the appLockEnabled default")

        // With the toggle scrolled fully into view, a row tap flips the control
        // (a SwiftUI `Toggle { Text }` toggles from anywhere on its row).
        toggle.tap()

        let deadline = Date().addingTimeInterval(5)
        while (toggle.value as? String) != "1" && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(toggle.value as? String, "1",
                       "Tapping the toggle should enable app lock (opt-in persisted)")

        toggle.tap()
        let resetDeadline = Date().addingTimeInterval(5)
        while (toggle.value as? String) != "0" && Date() < resetDeadline { usleep(200_000) }
        XCTAssertEqual(toggle.value as? String, "0",
                       "Test cleanup should disable app lock before the next launch")
    }

    /// Fleet → "Saved hosts": tapping a seeded host fires onReconnect → openSession,
    /// which (for a password host) presents the connect prompt. Proves the reconnect
    /// wiring without needing a live SSH endpoint.
    func testSavedHostReconnectPresentsPrompt() throws {
        let app = launchReseeded(destination: "machines")
        defer { app.terminate() }

        // The design system renders section labels in uppercase; match the
        // semantic label case-insensitively rather than asserting its casing.
        let savedHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Saved hosts")
        ).firstMatch
        XCTAssertTrue(savedHeader.waitForExistence(timeout: 30),
                      "Fleet should list the seeded saved hosts under a 'Saved hosts' section")

        // The redesigned saved-host row composes the name into a non-discrete
        // label, so match any descendant containing it rather than an exact staticText.
        let devVPS = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Dev VPS")).firstMatch
        XCTAssertTrue(devVPS.waitForExistence(timeout: 10),
                      "Seeded 'Dev VPS' host row should exist")
        let reconnect = app.buttons["Reconnect to Dev VPS"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 10),
                      "Seeded host should expose a labelled reconnect control")
        reconnect.tap()

        // The seeded hosts use password auth → openSession presents PasswordPromptView.
        // Accept any of its stable elements as proof the prompt presented.
        let passwordField = app.secureTextFields["Password"]
        let connectButton = app.buttons["Connect"]
        let passwordLabel = app.staticTexts["PASSWORD"]
        let deadline = Date().addingTimeInterval(15)
        while !(passwordField.exists || connectButton.exists || passwordLabel.exists) && Date() < deadline {
            usleep(300_000)
        }
        XCTAssertTrue(passwordField.exists || connectButton.exists || passwordLabel.exists,
                      "Tapping a saved host should fire onReconnect → present the connect prompt")
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

        // Cold-start quirk: a just-installed app does NOT pair on its very first
        // launch (the relay client / store finish initializing only after the
        // first run — the daemon sees the socket drop, then a clean reconnect).
        // Launch once to initialize, then relaunch to actually pair. Verified
        // manually: 1st launch no pair, 2nd launch pairs in ~4s.
        app.launch()
        sleep(8)
        app.terminate()
        app.launch()
        defer { app.terminate() }

        // The host fires the escalation a few seconds after the app pairs; wait
        // generously for the relay-delivered APPROVE control to surface.
        let approve = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 120),
                      "A relay-delivered escalation should surface an Approve button in the Inbox")
        approve.tap()

        // The decision rides the relay back to the daemon; the card should leave
        // PENDING (its Approve control disappears). The host script independently
        // asserts the hook unblocked (exit 0) and audit recorded `approve`.
        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Approve"))
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
