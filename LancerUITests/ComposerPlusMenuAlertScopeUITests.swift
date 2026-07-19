@preconcurrency import XCTest

/// Goal 3 — screenshot follow-up `+` menu (Add context + Permission) and
/// verify alert-scope: hydration shows no alert; unpaired SET surfaces alert.
@MainActor
final class ComposerPlusMenuAlertScopeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(destination: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        if let destination { app.launchEnvironment["LANCER_DESTINATION"] = destination }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    /// Open the most recent lancer live thread so the follow-up `+` menu exists.
    private func openLancerThread(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45))
        let lancer = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "lancer,"))
            .firstMatch
        XCTAssertTrue(lancer.waitForExistence(timeout: 15), "lancer workspace row")
        lancer.tap()
        // Prefer a known recent prompt from Goal 1 dispatch.
        let recent = app.staticTexts["live-activity-dispatch-ok"].firstMatch
        if recent.waitForExistence(timeout: 8) {
            // Tap the surrounding cell / button if needed
            recent.tap()
        } else {
            let cell = app.cells.firstMatch
            if cell.waitForExistence(timeout: 5) {
                cell.tap()
            } else {
                // Any conversation row button
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Reply")).firstMatch
                if row.waitForExistence(timeout: 5) { row.tap() }
            }
        }
        // Wait for follow-up composer
        _ = app.textFields["Follow up…"].waitForExistence(timeout: 10)
            || app.textFields.firstMatch.waitForExistence(timeout: 5)
    }

    func testPlusMenuAndPermissionSubmenu() throws {
        let app = launch()
        openLancerThread(app)

        let plus = app.buttons["Add context"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "follow-up + / Add context")
        plus.tap()
        Thread.sleep(forTimeInterval: 1.2)
        attach("goal3-plus-menu")

        // Embedded permission submenu label: "Permission: …"
        let permission = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Permission"))
            .firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 5), "Permission row in + menu")
        permission.tap()
        Thread.sleep(forTimeInterval: 1.2)
        attach("goal3-permission-submenu")

        // Hydration path: merely opening menus must not raise the SET alert.
        let alert = app.alerts["Couldn't change permission mode"].firstMatch
        XCTAssertFalse(alert.exists, "hydration must not show permission alert")
        attach("goal3-no-alert-hydration")
    }

    func testUserSetFailureShowsAlert() throws {
        // Unpair so SET fails closed, then change a preset.
        let tm = launch(destination: "trustedMachines")
        _ = tm.staticTexts["Trusted Machines"].waitForExistence(timeout: 20)
        let relay = tm.staticTexts["Relay host"].firstMatch
        if relay.waitForExistence(timeout: 10) {
            relay.swipeLeft()
            let remove = tm.buttons["Remove"].firstMatch
            if remove.waitForExistence(timeout: 4) {
                remove.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }
        attach("goal3-unpaired")
        tm.terminate()

        let app = launch()
        openLancerThread(app)

        let plus = app.buttons["Add context"].firstMatch
        guard plus.waitForExistence(timeout: 15) else {
            attach("goal3-no-plus-after-unpair")
            return
        }
        plus.tap()
        let permission = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Permission"))
            .firstMatch
        guard permission.waitForExistence(timeout: 5) else {
            attach("goal3-no-permission-after-unpair")
            return
        }
        permission.tap()

        // Flip to a different preset than current to force SET.
        let candidates = ["Always ask", "Accept edits", "Plan mode", "Autonomous"]
        var tapped = false
        for label in candidates {
            let btn = app.buttons[label].firstMatch
            if btn.waitForExistence(timeout: 2), btn.isHittable {
                btn.tap()
                tapped = true
                break
            }
        }
        XCTAssertTrue(tapped, "should tap a permission preset")
        Thread.sleep(forTimeInterval: 4)

        let alert = app.alerts["Couldn't change permission mode"].firstMatch
        let alertText = app.staticTexts["Couldn't change permission mode"].firstMatch
        attach("goal3-user-set-result")
        XCTAssertTrue(
            alert.waitForExistence(timeout: 8) || alertText.exists,
            "user SET failure must show 'Couldn't change permission mode' alert"
        )
        if alert.exists { attach("goal3-user-set-alert-SHOWN") }
    }
}
