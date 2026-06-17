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
/// NOTE: on this branch the redesign is gallery-only — `AppRoot`'s first-run path
/// still presents the legacy `OnboardingView`. This test guards the prototype's
/// step machine; it does not assert the redesign ships to first-run users.
@MainActor
final class OnboardingRedesignNavTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launchRedesign() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CONDUIT_GALLERY"] = "onboarding-redesign"
        app.launch()
        return app
    }

    /// Forward: "Get started" → "Continue" walks 1/3 → 2/3 → 3/3, and the back
    /// button flips from disabled (step 1) to enabled (step 2+).
    func testForwardNavigationAdvancesCounter() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 30),
                      "Redesign should open on step 1 of 3")
        XCTAssertTrue(app.staticTexts["Agents ask. You approve. Work resumes."].exists,
                      "Step 1 title")
        XCTAssertFalse(app.buttons["onboardingBack"].isEnabled,
                       "Back should be disabled on step 1")

        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10),
                      "Tapping 'Get started' should advance to step 2")
        XCTAssertTrue(app.staticTexts["Connect the machine where agents run."].exists,
                      "Step 2 title")
        XCTAssertTrue(app.buttons["onboardingBack"].isEnabled,
                      "Back should become enabled on step 2")

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 10),
                      "Tapping 'Continue' should advance to step 3")
        XCTAssertTrue(app.staticTexts["Choose how cautious Conduit should be."].exists,
                      "Step 3 title")
    }

    /// Back button retreats 3/3 → 2/3 → 1/3 and is disabled again at step 1.
    func testBackNavigationRetreatsCounter() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 30))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 10))

        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10),
                      "Back from step 3 should return to step 2")

        app.buttons["onboardingBack"].tap()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 10),
                      "Back from step 2 should return to step 1")
        XCTAssertFalse(app.buttons["onboardingBack"].isEnabled,
                       "Back should be disabled again on step 1")
    }

    /// Policy step: "Balanced" is selected by default; tapping "Cautious" moves the
    /// selection (asserted via the preset row's accessibility value).
    func testPolicyPresetSelection() {
        let app = launchRedesign()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 30))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Choose how cautious Conduit should be."].waitForExistence(timeout: 10))

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
