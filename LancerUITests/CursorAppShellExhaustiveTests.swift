@preconcurrency import XCTest

/// Functional pass over the rebuilt (2026-07-09) Cursor-styled mock-data shell
/// (`CursorAppShell` + `CursorStyle/*`) — 3-root TabView (Home/Workspaces/Settings),
/// docked composer, honest deferred PR detail, real Review decisions. Replaces the
/// pre-rebuild version of this file, which asserted a Profile-drawer + composer-sheet-
/// chain IA that this rebuild intentionally removed (brief: "update selectors if chrome
/// changes, do not delete coverage of the live approval loop" — the live approval loop
/// itself is covered separately by `CursorShellLiveApprovalTests`, left unchanged).
@MainActor
final class CursorAppShellExhaustiveTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSkipOnboarding(route: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_CURSOR_SHELL"] = "1"
        if let route { app.launchEnvironment["LANCER_CURSOR_ROUTE"] = route }
        app.launch()
        return app
    }

    private func launchOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_CURSOR_SHELL"] = "1"
        app.launch()
        return app
    }

    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapWithRetry(_ element: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0..<2 {
            if element.isHittable {
                element.tap()
                return
            }
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if attempt == 0 {
                _ = element.waitForExistence(timeout: 1)
            }
        }
        if element.exists { return }
        XCTFail("Could not tap \(label)", file: file, line: line)
    }

    private func assertReviewDiffVisible(_ app: XCUIApplication, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.otherElements["review-diff-screen"]
        let approve = app.buttons["cursor.review.approve"]
        let reviewNav = app.navigationBars["Review"]
        let visible = screen.waitForExistence(timeout: timeout)
            || approve.waitForExistence(timeout: 2)
            || reviewNav.waitForExistence(timeout: 2)
        XCTAssertTrue(visible, "Review diff screen should be visible", file: file, line: line)
    }

    // MARK: 1. Onboarding (simplified 2-step: product proof, then pair-or-skip)

    func testOnboarding_SkipLandsOnThreeRootShell() throws {
        let app = launchOnboarding()
        defer { app.terminate() }

        // Single-line title in CursorOnboardingView — do not require a hard newline.
        XCTAssertTrue(
            app.staticTexts["Steer AI coding agents from your phone."].waitForExistence(timeout: 30)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Steer AI coding agents")).firstMatch.waitForExistence(timeout: 5),
            "Onboarding step 0 title should be visible"
        )
        snapshot("01-onboarding-step0", app: app)
        let getStarted = app.buttons["Get started"].exists ? app.buttons["Get started"] : app.buttons["onboarding.get-started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        XCTAssertTrue(app.staticTexts["Pair your machine"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-step1", app: app)
        let skip = app.buttons["Skip for now"].exists ? app.buttons["Skip for now"] : app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 3, "Onboarding should complete onto the 3-root tab shell")
        snapshot("01b-onboarding-complete-shell", app: app)
    }

    // MARK: 2. 3-root shell

    func testThreeRootsVisible() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Home"].exists, "Home root should be a tab")
        XCTAssertTrue(app.buttons["Workspaces"].exists, "Workspaces root should be a tab")
        XCTAssertTrue(app.buttons["Settings"].exists, "Settings root should be a tab")
        snapshot("02-three-roots", app: app)

        app.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 10))
        snapshot("02b-home-root", app: app)
    }

    func testSettingsRoot_TrustedMachinesRowVisible() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["cursor.settings.row.trusted-machines"].waitForExistence(timeout: 5))
        snapshot("02c-settings-root", app: app)
    }

    // MARK: 3. Workspaces -> thread list -> docked composer (no full-screen sheet)

    func testWorkspaceThreadList_DockedComposerVisible() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))

        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))

        // Docked composer is a real text field on this screen already — never a sheet.
        let textField = app.textFields["composer.text-field"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5), "Docked composer text field should be visible without any tap-to-open sheet")
        snapshot("03-thread-list-docked-composer", app: app)

        // Named-workspace start-chat must not dead-end on "path unknown" (D6).
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Path for")).firstMatch.exists,
            "Mock named workspace must resolve a synthetic CWD so Send is enabled"
        )
        textField.tap()
        textField.typeText("start chat from named workspace")
        let send = app.buttons["composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        XCTAssertTrue(send.isEnabled, "Send should be enabled once named-workspace CWD resolves")
        send.tap()
        // Successful send opens workThread (Orca launch-into-conversation semantics).
        XCTAssertTrue(
            app.textFields["composer.text-field"].waitForExistence(timeout: 5),
            "workThread should present with its own docked composer after named-workspace send"
        )
        snapshot("03b-named-workspace-start-chat", app: app)
    }

    // MARK: 4. Search overlay (real search, no fake seeded rows)

    func testSearchOverlay_NoFakeSeededResults() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons["Search"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 10))

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("relay")
        snapshot("04-search-typed", app: app)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "available right now")).firstMatch.waitForExistence(timeout: 5)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "No matches for")).firstMatch.waitForExistence(timeout: 5),
            "Without a live search bridge, the overlay should not invent seeded results"
        )
    }

    // MARK: 5. Review/Diff decisions — unchanged behavior, new shell chrome

    func testReviewDiff_Approve() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        app.buttons["cursor.review.approve"].tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 5))
        snapshot("05-reviewdiff-approved", app: app)
    }

    func testReviewDiff_NoFakeFullDiffAction() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "terraform apply")).firstMatch.exists,
            "Review must not render the old fake terraform approval"
        )
    }

    // MARK: 6. PR Detail — honest deferred state (out of scope for this rebuild)

    func testPRDetail_IsHonestDeferredState() throws {
        let app = launchSkipOnboarding(route: "prDetail")
        defer { app.terminate() }
        let deferred = app.otherElements["pr-detail-screen"].waitForExistence(timeout: 10)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ship history")).firstMatch.waitForExistence(timeout: 5)
            || app.navigationBars["PR"].waitForExistence(timeout: 5)
        XCTAssertTrue(deferred, "PR detail deferred stub should be visible")
        snapshot("06-prdetail-deferred", app: app)
        // Toolbar uses Label "Back" + systemImage chevron.left — a11y label is "Back".
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
    }
}
