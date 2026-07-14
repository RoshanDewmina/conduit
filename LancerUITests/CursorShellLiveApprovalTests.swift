@preconcurrency import XCTest

/// Seeded UI coverage for pending-approval card chrome and local clearing.
/// Host forwarding and persistence are proved by the live relay harness.
@MainActor
final class SeededApprovalCardTests: XCTestCase {

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

    func testSeededPendingApprovalCardClearsAfterApprove() throws {
        let app = launchLiveShellReseeded(destination: "approval")
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
                      "Live shell should land on Workspaces before opening thread")

        let approve = app.buttons["cursor.approval.approve"].firstMatch
        let deny = app.buttons["Deny"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 30),
                      "In-thread approval card should expose Approve")
        XCTAssertTrue(deny.waitForExistence(timeout: 5),
                      "In-thread approval card should expose Deny")
        approve.tap()

        XCTAssertTrue(approve.waitForNonExistence(timeout: 8),
                      "Seeded approval card should clear locally after Approve")
        XCTAssertTrue(deny.waitForNonExistence(timeout: 3),
                      "Both controls should leave with the locally cleared card")
    }
}
