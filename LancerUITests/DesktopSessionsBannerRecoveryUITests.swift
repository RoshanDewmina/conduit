@preconcurrency import XCTest

/// Regression proof for the 2026-07-18 owner-reported bug: `ThreadListView`'s
/// "Couldn't load desktop sessions" banner (`observedSessionsError`) used to
/// stick forever once a fetch landed mid-reconnect, because
/// `loadObservedSessions()` only ran on the view's initial `.task` or a manual
/// Retry tap — nothing re-triggered it when the relay actually recovered.
/// Root-caused live: several rapid force-quit/relaunch cycles (from a
/// same-session device-testing pass) left the banner stuck on the owner's
/// phone well after the daemon log showed a successful re-pair.
///
/// Fix under test: `ThreadListView` now has `.onChange(of:
/// relayFleetStore.firstConnectedMachine != nil)` that re-fires
/// `loadObservedSessions()` the moment a machine (re)connects while an error
/// is currently showing — no manual Retry needed.
///
/// PRECONDITIONS (set up out-of-band, same as `ReconnectCycleUITests` /
/// `DesktopSessionDecryptUITests`):
/// - App already paired to a running lancerd (production relay).
/// - Deliberately does NOT set LANCER_UITEST_RESEED (would wipe the live pairing).
///
/// This reproduces the owner's actual repro (rapid kill/relaunch cycles), not
/// a synthetic RPC-timeout injection — the daemon here is real production
/// infrastructure, not a fault-injectable test double, so the most faithful
/// regression proof is the same disruptive pattern that caused the bug live.
@MainActor
final class DesktopSessionsBannerRecoveryUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testDesktopSessionsBannerSelfHealsAfterRapidReconnectCycles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]

        // Rapid force-quit/relaunch, same disruptive pattern that produced the
        // stuck banner live — each relaunch races the relay reconnect.
        for cycle in 1...3 {
            app.terminate()
            app.launch()
            XCTAssertTrue(
                app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
                "cycle \(cycle): app should land on Workspaces home"
            )
            // Deliberately brief — don't wait for a full connect settle,
            // that's exactly the race that used to strand the banner.
            Thread.sleep(forTimeInterval: 2)
        }

        // Final relaunch, then navigate straight to All Repos (the desktop
        // sessions list) while the relay may still be reconnecting.
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
            "final launch: app should land on Workspaces home"
        )

        let allRepos = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "All Repos"))
            .firstMatch
        XCTAssertTrue(allRepos.waitForExistence(timeout: 15), "All Repos row should be on Workspaces home")
        allRepos.tap()

        XCTAssertTrue(
            app.staticTexts["All Repos"].waitForExistence(timeout: 15),
            "should land on the All Repos thread list"
        )

        // The banner combines into one accessibility element
        // (`.accessibilityElement(children: .combine)` in InlineRetryBanner),
        // so locate it by its summary label rather than a nested Retry button.
        let banner = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Couldn\u{2019}t load desktop sessions"))
            .firstMatch

        // Give the relay generous time to finish reconnecting and the fix's
        // onChange-triggered retry to fire — this is the self-heal window.
        let deadline = Date().addingTimeInterval(60)
        var sawBannerAtLeastOnce = false
        while Date() < deadline {
            if banner.exists {
                sawBannerAtLeastOnce = true
            } else if sawBannerAtLeastOnce {
                // It appeared, then cleared on its own — exactly the fix.
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }

        if banner.exists {
            attachScreenshot(name: "desktop-sessions-banner-STUCK")
        }
        XCTAssertFalse(
            banner.exists,
            "desktop sessions banner must not still be showing \(Int(Date().timeIntervalSince(deadline.addingTimeInterval(-60))))s after landing on All Repos — it should self-heal once the relay reconnects, not require a manual Retry tap"
        )

        attachScreenshot(name: "desktop-sessions-banner-PASS")
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
