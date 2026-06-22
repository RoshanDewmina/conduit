@preconcurrency import XCTest

/// Proof that the Home shell's glass `DSCircleButton`s actually FIRE their actions
/// on a tap — the leaf the prior debugging never covered. `TapInjectionProofTests`
/// only ever tapped plain sidebar rows / Approve buttons, so dead glass buttons
/// passed CI while being dead on device. These tap the real Home hamburger and
/// New Chat (+) controls and assert the resulting state change.
///
/// Determinism: `LANCER_UITEST_RESEED=1` wipes + reseeds the sample set and clears
/// the app-lock opt-in (see `DebugSeeder.resetForUITestIfRequested`). No
/// `LANCER_DESTINATION` → lands on the default Home destination.
@MainActor
final class HomeButtonTapTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launch()
        return app
    }

    /// Tapping the Home hamburger ("Open navigation") must open the drawer. The
    /// reliable discriminator is geometric, not `isHittable`: the compact sidebar
    /// is always mounted behind the content (so its elements report hittable even
    /// while closed, per the harness's own note), but opening the drawer slides the
    /// whole content — including the hamburger itself — right by the drawer width.
    func testHomeHamburgerOpensDrawer() throws {
        let app = launchHome()
        defer { app.terminate() }

        let hamburger = app.buttons["Open navigation"]
        XCTAssertTrue(hamburger.waitForExistence(timeout: 30),
                      "Home should render the hamburger (Open navigation) button")

        let beforeX = hamburger.frame.minX
        hamburger.tap()

        // The content card translates right by the drawer width (~320pt on this
        // device); require a substantial shift so a no-op tap fails.
        let deadline = Date().addingTimeInterval(10)
        var shift = hamburger.frame.minX - beforeX
        while shift < 100 && Date() < deadline {
            usleep(200_000)
            shift = hamburger.frame.minX - beforeX
        }
        XCTAssertGreaterThan(shift, 100,
                             "Tapping the Home hamburger should slide the content right (drawer open); shift was \(shift)pt")
    }

    /// Tapping the Home New Chat (+) button ("Start a new chat") must navigate to
    /// the New Chat composer.
    func testHomeNewChatOpensComposer() throws {
        let app = launchHome()
        defer { app.terminate() }

        let newChat = app.buttons["Start a new chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 30),
                      "Home should render the New Chat (+) button")

        newChat.tap()

        // NewChatTabView's always-visible composer placeholder is a stable anchor.
        let composer = app.textFields["Message — / for commands, @ for files…"]
        let composerHeadline = app.staticTexts["Describe the work. Lancer routes it through policy before anything runs."]
        let deadline = Date().addingTimeInterval(10)
        while !(composer.exists || composerHeadline.exists) && Date() < deadline {
            usleep(200_000)
        }
        XCTAssertTrue(composer.exists || composerHeadline.exists,
                      "Tapping New Chat should open the composer (placeholder / headline should render)")
    }

    /// A paired relay host should appear in Home's "YOUR MACHINES" list (not just the
    /// "Connect a machine" empty state). Uses the LANCER_FAKE_RELAY_HOST seam to
    /// simulate a paired+live relay host without a live relay.
    func testRelayHostShowsOnHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_FAKE_RELAY_HOST"] = "hermes-box"
        app.launch()
        defer { app.terminate() }

        let hostName = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "hermes-box")).firstMatch
        XCTAssertTrue(hostName.waitForExistence(timeout: 30),
                      "A paired relay host should render in Home's machine list")
        XCTAssertFalse(app.staticTexts["Connect a machine"].exists,
                       "With a paired relay host, Home should not show the empty 'Connect a machine' state")
    }
}
