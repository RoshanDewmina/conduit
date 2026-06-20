@preconcurrency import XCTest

/// Drives the onboarding REDESIGN prototype (DebugGalleryView route
/// `CONDUIT_GALLERY=onboarding-redesign` → `OnboardingRedesignGalleryView`) and
/// asserts the step machine actually advances/retreats on real taps.
///
/// Why this exists: `idb` / ios-simulator-mcp HID taps land but never fire the
/// SwiftUI `Button` action in the stripped Xcode-beta / iOS 27 headless simulator,
/// so the flow could previously only be "verified" by hard-coding `@State step`.
/// XCUITest event injection DOES work here (see `TapInjectionProofTests`), so this
/// exercises `advance()` / the back button / preset selection for real.
///
/// `AppRoot` presents this redesign on first run. The gallery route keeps this
/// state-machine test deterministic without relying on pairing infrastructure.
/// The editorial redesign replaced the "N / 3" counter with step dots + Skip, so
/// step identity is asserted via each step's title instead, and the per-step CTA is
/// tapped by its stable `onboardingPrimary` identifier (its label changes per step).
@MainActor
final class OnboardingRedesignNavTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launchRedesign() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CONDUIT_GALLERY"] = "onboarding-redesign"
        app.launch()
        return app
    }

    /// Forward: the primary CTA walks Why → Pair → Policy, and the back button flips
    /// from disabled (step 1) to enabled (step 2+).
    func testForwardNavigationAdvancesCounter() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["in your pocket."].waitForExistence(timeout: 30),
                      "Redesign should open on step 1 (Why Conduit)")
        XCTAssertFalse(app.buttons["onboardingBack"].isEnabled,
                       "Back should be disabled on step 1")

        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["Pair the bridge."].waitForExistence(timeout: 10),
                      "Tapping the primary CTA should advance to the pairing step")
        XCTAssertTrue(app.buttons["onboardingBack"].isEnabled,
                      "Back should become enabled on step 2")

        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["How much rope?"].waitForExistence(timeout: 10),
                      "Tapping the primary CTA again should advance to the policy step")
    }

    /// Back button retreats Policy → Pair → Why and is disabled again at step 1.
    func testBackNavigationRetreatsCounter() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["in your pocket."].waitForExistence(timeout: 30))
        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["Pair the bridge."].waitForExistence(timeout: 10))
        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["How much rope?"].waitForExistence(timeout: 10))

        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.staticTexts["Pair the bridge."].waitForExistence(timeout: 10),
                      "Back from step 3 should return to the pairing step")

        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.staticTexts["in your pocket."].waitForExistence(timeout: 10),
                      "Back from step 2 should return to step 1")
        XCTAssertFalse(app.buttons["onboardingBack"].isEnabled,
                       "Back should be disabled again on step 1")
    }

    /// Policy step: "Balanced" is selected by default; tapping "Cautious" moves the
    /// selection (asserted via the preset row's accessibility value).
    func testPolicyPresetSelection() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["in your pocket."].waitForExistence(timeout: 30))
        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["Pair the bridge."].waitForExistence(timeout: 10))
        app.buttons["onboardingPrimary"].tap()
        XCTAssertTrue(app.staticTexts["How much rope?"].waitForExistence(timeout: 10))

        let balanced = app.buttons["policyPreset_balanced"]
        let cautious = app.buttons["policyPreset_cautious"]
        XCTAssertTrue(balanced.waitForExistence(timeout: 10), "Balanced preset row should exist")
        XCTAssertTrue(cautious.exists, "Cautious preset row should exist")
        XCTAssertEqual(balanced.value as? String, "selected",
                       "Balanced should be the default selected preset")
        XCTAssertEqual(cautious.value as? String, "unselected", "Cautious should start unselected")

        cautious.tap()
        let deadline = Date().addingTimeInterval(5)
        while (cautious.value as? String) != "selected" && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(cautious.value as? String, "selected", "Tapping Cautious should select it")
        XCTAssertEqual(balanced.value as? String, "unselected",
                       "Selecting Cautious should deselect Balanced")
    }
}
