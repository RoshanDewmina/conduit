import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
///
/// Determinism: every launch sets `CONDUIT_UITEST_RESEED=1`, which wipes the
/// approvals table and re-seeds the fixed sample set (2 pending + 1 decided) and
/// clears the app-lock opt-in (see `DebugSeeder.resetForUITestIfRequested`). That
/// makes `testApproveDecisionApplies` re-runnable — prior runs no longer leave the
/// inbox fully decided.
final class TapInjectionProofTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch the app in a deterministic, freshly-reseeded state.
    private func launchReseeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CONDUIT_UITEST_RESEED"] = "1"
        app.launch()
        return app
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

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
