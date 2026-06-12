import XCTest

/// Proof that XCUITest event injection works on this machine (stripped Xcode-beta,
/// macOS 27, no Simulator.app GUI, idb broken). If these pass, the tap-gated audit
/// verification can be done entirely through XCUITest — no idb, no Simulator.app.
final class TapInjectionProofTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Cleanest proof of HID/event injection: switching tabs. Independent of any
    /// approval-decision wiring — if the tap lands, the Inbox-only breadcrumb leaves.
    func testTapInjectionViaTabSwitch() {
        let app = XCUIApplication()
        app.launch()

        let inboxBreadcrumb = app.staticTexts["agent approvals"]
        XCTAssertTrue(inboxBreadcrumb.waitForExistence(timeout: 30),
                      "Inbox should be the default tab with the 'agent approvals' breadcrumb")

        let settingsTab = app.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab button should exist")
        settingsTab.tap()

        XCTAssertTrue(inboxBreadcrumb.waitForNonExistence(timeout: 10),
                      "After tapping Settings the Inbox breadcrumb should disappear — proves event injection")

        // And back, to prove repeated injection.
        app.buttons["Inbox"].tap()
        XCTAssertTrue(inboxBreadcrumb.waitForExistence(timeout: 10),
                      "Tapping Inbox should return to the approvals breadcrumb")
    }

    /// The real verification goal: tap APPROVE on a seeded pending card and confirm
    /// the decision applies (the card leaves PENDING → APPROVE-button count drops).
    func testApproveDecisionApplies() {
        let app = XCUIApplication()
        app.launch()

        let approveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "APPROVE"))
        XCTAssertTrue(app.buttons["APPROVE"].firstMatch.waitForExistence(timeout: 30),
                      "Seeded inbox should show at least one APPROVE button")
        let before = approveButtons.count
        XCTAssertGreaterThan(before, 0, "Expected pending approval cards in the seeded inbox")

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
}
