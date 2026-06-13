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

        let inboxBreadcrumb = app.staticTexts["agent approvals"]
        XCTAssertTrue(inboxBreadcrumb.waitForExistence(timeout: 30),
                      "Inbox should be the default tab with the 'agent approvals' breadcrumb")

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

        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "APPROVE"))
        XCTAssertTrue(app.buttons["APPROVE"].firstMatch.waitForExistence(timeout: 30),
                      "Reseeded inbox should show at least one pending APPROVE button")
        let before = approveButtons.count
        XCTAssertGreaterThan(before, 0, "Expected pending approval cards in the reseeded inbox")

        app.buttons["APPROVE"].firstMatch.tap()

        let deadline = Date().addingTimeInterval(10)
        var after = approveButtons.count
        while after >= before && Date() < deadline {
            usleep(300_000)
            after = approveButtons.count
        }
        XCTAssertLessThan(after, before,
                          "After tapping APPROVE the pending APPROVE-button count should drop (decision applied)")
    }

    /// Visual before/after of a live approval decision, saved as attachments so the
    /// audit has a reproducible screenshot pair (the SimulatorKit AX-read bridge is
    /// unreliable on this machine for live MCP taps; XCUITest is the reliable path).
    func testApproveDecisionVisualEvidence() {
        let app = launchReseeded()

        XCTAssertTrue(app.buttons["APPROVE"].firstMatch.waitForExistence(timeout: 30),
                      "Reseeded inbox should show a pending APPROVE button")
        attach(app, name: "approve-01-before-pending")

        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "APPROVE"))
        let before = approveButtons.count
        app.buttons["APPROVE"].firstMatch.tap()

        let deadline = Date().addingTimeInterval(10)
        while approveButtons.count >= before && Date() < deadline { usleep(300_000) }
        attach(app, name: "approve-02-after-decided")
    }

    /// Phase-5 app-lock opt-in: Settings → Security → "Require Face ID on launch"
    /// starts OFF (reseed clears `appLockEnabled`) and the toggle flips it ON.
    func testFaceIDToggleOptIn() {
        let app = launchReseeded(tab: "settings")

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
    }

    /// Fleet → "Saved hosts": tapping a seeded host fires onReconnect → openSession,
    /// which (for a password host) presents the connect prompt. Proves the reconnect
    /// wiring without needing a live SSH endpoint.
    func testSavedHostReconnectPresentsPrompt() {
        let app = launchReseeded(tab: "fleet")

        let savedHeader = app.staticTexts["Saved hosts"]
        XCTAssertTrue(savedHeader.waitForExistence(timeout: 30),
                      "Fleet should list the seeded saved hosts under a 'Saved hosts' section")

        XCTAssertTrue(app.staticTexts["Dev VPS"].waitForExistence(timeout: 10),
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

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
