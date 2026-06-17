@preconcurrency import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
///
/// Determinism: every launch sets `CONDUIT_UITEST_RESEED=1`, which wipes the
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
    /// landing directly on a tab (CONDUIT_TAB: inbox/fleet/activity/settings).
    private func launchReseeded(tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CONDUIT_UITEST_RESEED"] = "1"
        if let tab { app.launchEnvironment["CONDUIT_TAB"] = tab }
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

    /// Cleanest proof of HID/event injection: switching tabs. Independent of any
    /// approval-decision wiring — if the tap lands, the Inbox-only breadcrumb leaves.
    func testTapInjectionViaTabSwitch() {
        let app = launchReseeded()
        defer { app.terminate() }

        // The redesign replaced the "agent approvals" breadcrumb with a lowercase
        // "inbox" header (InboxView). Assert on that as the inbox-tab marker.
        let inboxBreadcrumb = app.staticTexts["inbox"]
        XCTAssertTrue(inboxBreadcrumb.waitForExistence(timeout: 30),
                      "Inbox should be the default tab with the 'inbox' header")

        let settingsTab = app.buttons["Settings"]
        // 20s, not 5s: a cold relaunch on a contended sim (right after a build or the
        // prior test's teardown) can take >5s to lay out the tab bar — that timeout
        // was the only thing flaking here; the injection itself is reliable.
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "Settings tab button should exist")
        settingsTab.tap()

        XCTAssertTrue(inboxBreadcrumb.waitForNonExistence(timeout: 10),
                      "After tapping Settings the Inbox breadcrumb should disappear — proves event injection")

        // And back, to prove repeated injection.
        let inboxTab = app.buttons["Inbox"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 20), "Inbox tab button should exist")
        inboxTab.tap()
        XCTAssertTrue(inboxBreadcrumb.waitForExistence(timeout: 10),
                      "Tapping Inbox should return to the approvals breadcrumb")
    }

    /// The real verification goal: tap APPROVE on a seeded pending card and confirm
    /// the decision applies (the card leaves PENDING → APPROVE-button count drops).
    func testApproveDecisionApplies() {
        let app = launchReseeded()
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
    func testFaceIDToggleOptIn() {
        let app = launchReseeded(tab: "settings")
        defer { app.terminate() }

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
    func testSavedHostReconnectPresentsPrompt() {
        let app = launchReseeded(tab: "fleet")
        defer { app.terminate() }

        let savedHeader = app.staticTexts["Saved hosts"]
        XCTAssertTrue(savedHeader.waitForExistence(timeout: 30),
                      "Fleet should list the seeded saved hosts under a 'Saved hosts' section")

        // The redesigned saved-host row composes the name into a non-discrete
        // label, so match any descendant containing it rather than an exact staticText.
        let devVPS = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Dev VPS")).firstMatch
        XCTAssertTrue(devVPS.waitForExistence(timeout: 10),
                      "Seeded 'Dev VPS' host row should exist")
        // Tap the row cell, not the inner Text: tapping the static label inside a
        // SwiftUI List-row Button doesn't reliably activate the button.
        let hostCell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", "Dev VPS")).firstMatch
        if hostCell.exists { hostCell.tap() } else { app.staticTexts["Dev VPS"].tap() }

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

    /// Strict localhost SSH proof, opt-in only because it needs macOS Remote Login
    /// plus a Keychain-backed password. In simulator-env mode, the password is set
    /// in the Device Hub app-launch environment; the test runner receives only a
    /// non-secret flag.
    func testLocalhostSSHShowsTOFUAndConnects() throws {
        let runnerEnv = ProcessInfo.processInfo.environment
        let useSimulatorLaunchEnvironment = runnerEnv["CONDUIT_LIVE_SSH_SIM_ENV"] == "1"
        guard useSimulatorLaunchEnvironment || runnerEnv["CONDUIT_LIVE_SSH_E2E"] == "1" else {
            throw XCTSkip("Set CONDUIT_LIVE_SSH_E2E=1 with CONDUIT_TEST_PW to run the live localhost SSH proof")
        }

        let app: XCUIApplication
        if useSimulatorLaunchEnvironment {
            app = XCUIApplication()
            app.launch()
        } else {
            let testPassword = runnerEnv["CONDUIT_TEST_PW"] ?? ""
            XCTAssertFalse(testPassword.isEmpty, "CONDUIT_TEST_PW must be supplied by the test runner environment")
            app = XCUIApplication()
            app.launchEnvironment["CONDUIT_DAEMON_E2E"] = "1"
            app.launchEnvironment["CONDUIT_TEST_HOST"] = runnerEnv["CONDUIT_TEST_HOST"] ?? "127.0.0.1"
            app.launchEnvironment["CONDUIT_TEST_PORT"] = runnerEnv["CONDUIT_TEST_PORT"] ?? "22"
            app.launchEnvironment["CONDUIT_TEST_USER"] = runnerEnv["CONDUIT_TEST_USER"] ?? NSUserName()
            app.launchEnvironment["CONDUIT_TEST_PW"] = testPassword
            app.launchEnvironment["CONDUIT_TAB"] = "fleet"
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
