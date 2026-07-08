@preconcurrency import XCTest

/// Tier-0 integration: live `AppRoot` + seeded pending approval → Review → Approve.
/// Uses `LANCER_UITEST_RESEED` and the `LANCER_DESTINATION=review` DEBUG seam
/// (same live `CursorReviewDiffView` + bridge `onDecide` path as production).
/// Work-thread banner visibility is covered by `CursorAppShellExhaustiveTests` (mock shell)
/// and `scripts/relay-approval-e2e.sh` (live shell, synthetic tap).
@MainActor
final class CursorShellLiveApprovalTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchLiveShellReseeded(destination: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        if let destination {
            app.launchEnvironment["LANCER_DESTINATION"] = destination
        }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    func testLiveShell_PendingApprovalBannerApprove() throws {
        let app = launchLiveShellReseeded(destination: "review")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
                      "Live Cursor shell should land on Workspaces")

        let reviewApprove = app.buttons["cursor.review.approve"].firstMatch
        XCTAssertTrue(reviewApprove.waitForExistence(timeout: 30),
                      "Review screen should expose Approve via live bridge")
        reviewApprove.tap()

        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 10),
                      "Approve should commit and show Approved status")
    }
}
