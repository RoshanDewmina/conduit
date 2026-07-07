@preconcurrency import XCTest

/// Tier-0 integration: Cursor live shell + seeded pending approval → banner → Review → Approve.
/// Avoids flaking on real relay by using `LANCER_UITEST_RESEED` + biometric bypass in AppRoot.
@MainActor
final class CursorShellLiveApprovalTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchLiveShellReseeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    func testLiveShell_PendingApprovalBannerApprove() throws {
        let app = launchLiveShellReseeded()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
                      "Live Cursor shell should land on Workspaces")

        let workspace = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "command-center", "lancer-ios", "All Repos")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 15), "Expected a workspace row")
        workspace.tap()

        let thread = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")
        ).firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 15), "Expected a thread row in the workspace list")
        thread.tap()

        let banner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "pending approval")
        ).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30),
                      "Live shell should surface approval banner when pending approvals exist")
        banner.tap()

        let approve = app.buttons["cursor.review.approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15),
                      "Review screen should expose Approve")
        approve.tap()

        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 10),
                      "Approve should commit and show Approved status")
    }
}
