@preconcurrency import XCTest

/// Live verification of the cross-device conversation sync feature's UI on a
/// real physical device (the simulator's tap injection is broken in this
/// Xcode-beta/iOS27 environment — see TapInjectionProofTests.swift's header
/// comment and docs/test-runs/2026-07-03-cross-device-sync-live-verification.md
/// — XCUITest on a real device is the reliable path). Screenshots are
/// attached to the xcresult bundle at each step as evidence.
@MainActor
final class PhysicalDeviceCrossDeviceSyncTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Home IA (rebuilt as part of this feature: commit 809cb6be) rendered on
    /// a real device, reseeded to a deterministic state.
    func testHomeIARendersOnDevice() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "sessions" // maps to .home
        app.launch()
        defer { app.terminate() }

        let goodMorning = app.staticTexts["Good morning"]
        XCTAssertTrue(goodMorning.waitForExistence(timeout: 30), "Home should render its greeting header")
        attach(app, name: "01-home")

        let machinesRow = app.buttons["Machines"]
        if machinesRow.waitForExistence(timeout: 5) {
            // Machines lives in the drawer only when the drawer is open on
            // compact width; if not directly visible, open it first.
        } else {
            app.buttons["Open navigation"].firstMatch.tap()
        }
        let hamburger = app.buttons["Open navigation"]
        if hamburger.waitForExistence(timeout: 3) { hamburger.tap() }
        let machines = app.buttons["Machines"]
        XCTAssertTrue(machines.waitForExistence(timeout: 10), "Drawer should list Machines")
        machines.tap()
        attach(app, name: "02-machines")
    }

    /// Real SSH connect from the physical device to this Mac's daemon over the
    /// actual LAN (not 127.0.0.1 — that's meaningless from a real device's own
    /// network namespace, unlike a simulator which shares the host Mac's).
    /// Proves the phone can reach lancerd for real, over real WiFi, the same
    /// network path a genuine second-device continuation would use.
    func testLANSSHConnectFromPhysicalDevice() throws {
        let runnerEnv = ProcessInfo.processInfo.environment
        guard let lanHost = runnerEnv["LANCER_LAN_HOST"], !lanHost.isEmpty,
              let pw = runnerEnv["LANCER_TEST_PW"], !pw.isEmpty else {
            throw XCTSkip("Set LANCER_LAN_HOST (this Mac's LAN IP) and LANCER_TEST_PW to run the real-device LAN SSH proof")
        }

        let app = XCUIApplication()
        app.launchEnvironment["LANCER_DAEMON_E2E"] = "1"
        app.launchEnvironment["LANCER_TEST_HOST"] = lanHost
        app.launchEnvironment["LANCER_TEST_PORT"] = runnerEnv["LANCER_TEST_PORT"] ?? "22"
        app.launchEnvironment["LANCER_TEST_USER"] = runnerEnv["LANCER_TEST_USER"] ?? NSUserName()
        app.launchEnvironment["LANCER_TEST_PW"] = pw
        app.launchEnvironment["LANCER_DESTINATION"] = "machines"
        app.launch()
        defer { app.terminate() }

        // On a real, already-signed-in account the initial destination can
        // land behind an open drawer (or account-restore can re-navigate
        // after LANCER_DESTINATION's synchronous init-time set) — explicitly
        // drive to Machines via the drawer rather than assuming the launch
        // seam alone lands there, matching the proven-working pattern from
        // testHomeIARendersOnDevice.
        let machinesRow = app.buttons["Machines"]
        if !machinesRow.waitForExistence(timeout: 5) {
            app.buttons["Open navigation"].firstMatch.tap()
        }
        attach(app, name: "00-post-launch")
        if app.buttons["Machines"].waitForExistence(timeout: 10) {
            app.buttons["Machines"].tap()
        }

        let localHost = app.staticTexts["This Mac (e2e)"]
        XCTAssertTrue(localHost.waitForExistence(timeout: 30), "Live E2E seed should add the LAN host entry")
        attach(app, name: "01-machines-with-lan-host")

        let hostCell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", "This Mac")).firstMatch
        if hostCell.exists { hostCell.tap() } else { localHost.tap() }

        let connectButton = app.buttons["Connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 20), "LAN host password prompt should appear")
        XCTAssertTrue(connectButton.isEnabled, "DEBUG-only E2E password prefill should enable Connect without typing")
        attach(app, name: "02-password-prompt")
        connectButton.tap()

        let tofuTitle = app.staticTexts["Unknown Host Key"]
        XCTAssertTrue(tofuTitle.waitForExistence(timeout: 30), "Real LAN connect should show the TOFU prompt (fresh trust from this device)")
        XCTAssertTrue(app.staticTexts["Fingerprint (SHA256)"].exists, "TOFU prompt should show the SSH fingerprint")
        attach(app, name: "03-tofu-prompt")
        XCTAssertTrue(app.buttons["Trust & Connect"].exists, "TOFU prompt should require explicit trust")

        app.buttons["Trust & Connect"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 45),
                      "After trusting the LAN host key, the SSH session should connect over real WiFi")
        attach(app, name: "04-connected")
    }
}
