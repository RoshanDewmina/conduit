@preconcurrency import XCTest

/// Exhaustive functional pass over the Cursor-styled mock-data prototype
/// (`CursorAppShell` + `CursorStyle/*`). Uses XCUITest (not idb/HID) to drive
/// taps: idb's synthesized taps do not reliably fire SwiftUI Button actions on
/// this headless Xcode-beta/iOS 27 simulator even when the code is correct
/// (verified independently), whereas XCUITest's accessibility-driven taps do.
/// Screenshots are attached with `.keepAlways` lifetime as evidence for every
/// significant state.
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

    private func avatarCoordinate(_ app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 38.0 / 402.0, dy: 92.0 / 874.0))
    }

    /// Mock shell uses `ManagedModel.claudeHaiku`; live shell may show other labels.
    private var composerModelPredicate: NSPredicate {
        NSPredicate(format: "label CONTAINS[c] 'Haiku' OR label CONTAINS[c] 'Composer' OR label CONTAINS[c] 'Sonnet' OR label CONTAINS[c] 'GPT'")
    }

    private func composerModelChip(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(composerModelPredicate).firstMatch
    }

    private func tappableRow(_ app: XCUIApplication, containing label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", label)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        return app.staticTexts.matching(predicate).firstMatch
    }

    /// Cloud run-target button is the most stable expanded-composer presence signal.
    private func isExpandedComposerVisible(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let cloud = app.buttons["cloud"]
        if cloud.waitForExistence(timeout: timeout) { return true }
        return composerModelChip(app).waitForExistence(timeout: 2)
    }

    @discardableResult
    private func waitForExpandedComposer(
        _ app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard isExpandedComposerVisible(app, timeout: timeout) else {
            XCTFail("Expanded composer did not appear (missing cloud button and model chip)", file: file, line: line)
            return false
        }
        return true
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    }

    private func dismissKeyboardIfPresent(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists {
            returnKey.tap()
            return
        }
        app.swipeDown(velocity: .slow)
    }

    /// Opens the expanded composer sheet from an inline bottom composer.
    private func tapComposerToOpenSheet(_ app: XCUIApplication, placeholder: String, file: StaticString = #filePath, line: UInt = #line) {
        let candidates: [XCUIElement] = [
            app.buttons["cursor-composer-tap"],
            app.buttons[placeholder],
            app.textFields[placeholder],
        ]
        for element in candidates {
            if element.waitForExistence(timeout: 3) {
                tapWithRetry(element, label: "composer \(placeholder)", file: file, line: line)
                if isExpandedComposerVisible(app, timeout: 8) { return }
            }
        }
        XCTFail("Composer sheet did not open for placeholder \(placeholder)", file: file, line: line)
    }

    /// Tap an element with one retry — mitigates iOS 27 simulator HID flakiness.
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
        XCTAssertTrue(
            screen.waitForExistence(timeout: timeout),
            "Review diff screen should be visible",
            file: file,
            line: line
        )
    }

    private func tapApprovalBanner(_ app: XCUIApplication, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        // Mock shell: tapping the status copy opens Review via `onOpenReview`.
        let statusCopy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "pending approval")
        ).firstMatch
        if statusCopy.waitForExistence(timeout: timeout) {
            tapWithRetry(statusCopy, label: "pending approval", file: file, line: line)
            return
        }
        // Live shell fallback: dedicated banner container or APPROVE.
        let banner = app.otherElements["approval-banner"].firstMatch
        if banner.waitForExistence(timeout: 2) {
            tapWithRetry(banner, label: "approval-banner", file: file, line: line)
        } else {
            tapButtonContaining(app, "APPROVE", timeout: timeout, file: file, line: line)
        }
    }

    private func tapButtonContaining(_ app: XCUIApplication, _ substring: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", substring)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing button containing \(substring)", file: file, line: line)
        tapWithRetry(button, label: substring, file: file, line: line)
    }

    // MARK: 1. Onboarding

    func testOnboarding_HappyPath() throws {
        let app = launchOnboarding()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Steer AI coding agents\nfrom your phone."].waitForExistence(timeout: 30))
        snapshot("01-onboarding-step0", app: app)
        app.buttons["Get started"].tap()

        XCTAssertTrue(app.staticTexts["Pair your machine"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-step1", app: app)
        app.buttons["Preview error state"].tap()
        XCTAssertTrue(app.staticTexts["That code didn't match — check it and try again."].waitForExistence(timeout: 5))
        snapshot("01-onboarding-step1-error", app: app)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Turn on notifications"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-step2", app: app)
        app.buttons["Enable notifications"].tap()

        XCTAssertTrue(app.staticTexts["Choose a policy"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-step3", app: app)
        app.buttons["Continue with recommended"].tap()

        XCTAssertTrue(app.staticTexts["Add a Lancer account?"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-step4", app: app)
        app.buttons["Add account"].tap()

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-complete-workspaces", app: app)
    }

    func testOnboarding_NotNow_AdvancesToPolicy() throws {
        let app = launchOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 30))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["Choose a policy"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-notnow-to-policy", app: app)
    }

    func testOnboarding_Customize_AdvancesToAccount() throws {
        let app = launchOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 30))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Customize"].waitForExistence(timeout: 10))
        app.buttons["Customize"].tap()
        XCTAssertTrue(app.staticTexts["Add a Lancer account?"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-customize-to-account", app: app)
    }

    func testOnboarding_SkipForNow_CompletesOnboarding() throws {
        let app = launchOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 30))
        app.buttons["Get started"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Customize"].waitForExistence(timeout: 10))
        app.buttons["Customize"].tap()
        XCTAssertTrue(app.buttons["Skip for now"].waitForExistence(timeout: 10))
        app.buttons["Skip for now"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
        snapshot("01-onboarding-skip-complete", app: app)
    }

    // MARK: 2/3/4. Workspaces root, Profile drawer, Search overlay

    func testWorkspacesRoot_HeaderAndRows() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        snapshot("02-workspaces-root", app: app)

        // + is a documented no-op; just confirm no crash.
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].exists, "+ should be a no-op, still on Workspaces")

        // Avatar -> Profile drawer
        avatarCoordinate(app).tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10), "Avatar tap should present Profile drawer")
        snapshot("03-profile-drawer", app: app)
        app.buttons["xmark"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10), "Closing drawer returns to Workspaces")

        // Search -> overlay
        app.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 10))
        snapshot("04-search-overlay", app: app)
        app.buttons["xmark"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))

        // Add Repo row is a static (non-Button) row -> no crash.
        XCTAssertTrue(app.staticTexts["Add Repo"].exists)
    }

    func testProfileDrawer_RowsAndSettingsSheet() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        avatarCoordinate(app).tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10))

        // No-op rows: confirm no crash after each tap.
        for label in ["Manage Plan", "Acknowledgements"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            if row.waitForExistence(timeout: 5) {
                row.tap()
                XCTAssertTrue(app.staticTexts["Profile"].exists, "\(label) should be a no-op, drawer stays open")
            }
        }
        let deleteAccount = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Delete Account")).firstMatch
        if deleteAccount.waitForExistence(timeout: 5) {
            deleteAccount.tap()
            XCTAssertTrue(app.staticTexts["Profile"].exists, "Delete Account should not crash")
        }
        snapshot("03b-profile-drawer-after-noops", app: app)

        // App Settings -> nested sheet
        let appSettings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "App Settings")).firstMatch
        XCTAssertTrue(appSettings.waitForExistence(timeout: 5))
        appSettings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10), "App Settings should present CursorSettingsView")
        snapshot("03c-app-settings-nested-sheet", app: app)

        // Swipe down to dismiss nested sheet -> back to Profile drawer.
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10), "Dismissing Settings should return to Profile drawer")
        snapshot("03d-back-to-profile-drawer", app: app)
    }

    func testProfileDrawer_SignOutReturnsToOnboarding() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        avatarCoordinate(app).tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10))
        let signOut = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign out")).firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(app.staticTexts["Steer AI coding agents\nfrom your phone."].waitForExistence(timeout: 10),
                      "Sign out should return the whole app to onboarding step 0")
        snapshot("03e-signout-to-onboarding", app: app)
    }

    func testSearchOverlay_TypeFilterAndSelect() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 10))

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("relay")
        snapshot("04b-search-typed", app: app)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "No matches for")).firstMatch.waitForExistence(timeout: 5),
            "Without a live search bridge, the overlay should not invent seeded results"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")).firstMatch.exists,
            "Search overlay must not show old hardcoded thread results when no real result exists"
        )
        snapshot("04c-search-no-fake-results", app: app)
    }

    // MARK: 5/6. Repo thread list, Repo picker

    func testRepoThreadList_HeaderAndRows() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5), "Thread list should show Today section")
        snapshot("05-repo-thread-list", app: app)

        // Search icon -> overlay
        app.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Search"].waitForExistence(timeout: 10))
        app.buttons["xmark"].tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))

        // Hamburger -> repo picker
        app.buttons["line.3.horizontal"].tap()
        XCTAssertTrue(app.staticTexts["Repo"].waitForExistence(timeout: 10))
        snapshot("06-repo-picker-sheet", app: app)
        app.buttons["xmark"].tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))

        // Back chevron -> Workspaces
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
    }

    func testRepoThreadList_RowPushesWorkThreadAndComposer() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].waitForExistence(timeout: 10))
        snapshot("05b-workthread-from-repo-list", app: app)
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10), "Back from Work Thread should return to repo thread list")

        // Composer tap. Note: the Composer sheet itself has no close/xmark
        // button (CursorComposerSheet passes no `leadingButton` to
        // CursorBottomSheetContainer) — swipe-down is its only dismiss path.
        // Use the model chip as the presence signal instead.
        tapComposerToOpenSheet(app, placeholder: "Plan, ask, build...")
        XCTAssertTrue(waitForExpandedComposer(app, timeout: 10), "Composer sheet should present")
        snapshot("10-composer-from-threadlist", app: app)
    }

    func testAllRepos_DistinctContent() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "All Repos")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["All Repos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Widget timeline refresh"].waitForExistence(timeout: 5),
                      "'All Repos' variant should show its own distinct seeded content")
        snapshot("05c-all-repos-thread-list", app: app)
    }

    // MARK: 5d. Workspace detail sheet (mock run targets)

    /// Verifies that `LANCER_CURSOR_MOCK_RUN_TARGETS=1` causes the mock shell
    /// to present `CursorWorkspaceDetailSheet` when the `lancer-ios` row is
    /// tapped, and that the sheet contains the expected run-target rows.
    /// Tapping a repo row must always open its thread list — matching the
    /// reference product exactly, a repo row is never an interstitial. The
    /// Workspace Detail / run-targets sheet is a secondary affordance reached
    /// by long-press, not the primary tap action (2026-07-07: an earlier
    /// version of this test asserted tap-opens-the-detail-sheet, which was
    /// itself the bug — this test enshrined the wrong behavior instead of
    /// catching it).
    func testWorkspaces_TapOpensThreadList_LongPressOpensDetailSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_CURSOR_SHELL"] = "1"
        app.launchEnvironment["LANCER_CURSOR_MOCK_RUN_TARGETS"] = "1"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        snapshot("05d-workspaces-before-tap", app: app)

        let lancerRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch
        XCTAssertTrue(lancerRow.waitForExistence(timeout: 10), "lancer-ios row should be visible")

        // Plain tap → thread list, even though this workspace has run targets.
        tapWithRetry(lancerRow, label: "lancer-ios workspace row")
        XCTAssertTrue(
            app.staticTexts["lancer-ios"].waitForExistence(timeout: 10),
            "Tapping a repo row should push the thread list with the workspace name as its title"
        )
        XCTAssertFalse(
            app.buttons["xmark"].waitForExistence(timeout: 2),
            "A plain tap must not present the Workspace Detail sheet (no xmark dismiss button)"
        )
        snapshot("05d-thread-list-after-tap", app: app)

        // Back to Workspaces, then long-press for the detail sheet.
        let backButton = app.buttons["chevron.left"]
        if backButton.waitForExistence(timeout: 5) { tapWithRetry(backButton, label: "back to Workspaces") }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))

        let lancerRowAgain = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch
        XCTAssertTrue(lancerRowAgain.waitForExistence(timeout: 10))
        lancerRowAgain.press(forDuration: 0.6)

        XCTAssertTrue(
            app.staticTexts["lancer-ios"].waitForExistence(timeout: 10),
            "Long-press should present the Workspace Detail sheet with the workspace name as title"
        )
        let targetRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "workspace-detail-target-row"))
            .firstMatch
        let hostLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Mac Mini Studio")
        ).firstMatch
        XCTAssertTrue(
            targetRow.waitForExistence(timeout: 5) || hostLabel.waitForExistence(timeout: 2),
            "Detail sheet must contain at least one workspace-detail-target-row"
        )
        snapshot("05d-workspace-detail-sheet-longpress", app: app)

        // Dismiss with xmark and confirm we're back on Workspaces.
        let xmark = app.buttons["xmark"].firstMatch
        XCTAssertTrue(xmark.waitForExistence(timeout: 5), "xmark dismiss button must exist on detail sheet")
        tapWithRetry(xmark, label: "xmark")
        XCTAssertTrue(
            app.staticTexts["Workspaces"].waitForExistence(timeout: 10),
            "Dismissing detail sheet should return to Workspaces"
        )
        snapshot("05d-back-to-workspaces-after-detail", app: app)
    }

    func testRepoPickerSheet_SearchAndSelect() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
        app.buttons["line.3.horizontal"].tap()
        XCTAssertTrue(app.staticTexts["Repo"].waitForExistence(timeout: 10))

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("hermes")
        snapshot("06b-repo-picker-typed", app: app)

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "hermes")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10), "Selecting a repo row should dismiss without crashing")
        }
    }

    // MARK: 7. Work Thread

    func testWorkThread_FullPass() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].waitForExistence(timeout: 10))

        // No tab bar anywhere.
        XCTAssertEqual(app.tabBars.count, 0, "There should be no system tab bar in this app")
        snapshot("07-workthread-top", app: app)

        // To-dos expand row
        let expandRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "3 more")).firstMatch
        if expandRow.waitForExistence(timeout: 5) {
            expandRow.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Confirm fix on a real device")).firstMatch.waitForExistence(timeout: 5),
                          "Expanding to-dos should reveal the 3 additional rows")
            snapshot("07b-workthread-todos-expanded", app: app)
        }

        // Scroll to bottom and screenshot for composer/content overlap check.
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        snapshot("07c-workthread-scrolled-bottom-overlap-check", app: app)

        // Action rail collapse toggle
        let collapse = app.buttons["chevron.down"]
        if collapse.waitForExistence(timeout: 5) {
            collapse.tap()
            snapshot("07d-workthread-actionrail-collapsed", app: app)
            let expand = app.buttons["chevron.up"]
            if expand.waitForExistence(timeout: 5) { expand.tap() }
        }

        // Mark Ready no-op
        let markReady = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Mark Ready")).firstMatch
        if markReady.waitForExistence(timeout: 5) {
            markReady.tap()
            XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].exists, "Mark Ready should be a no-op")
        }

        // PR detail is intentionally withheld from the default path until it is backed by real data.
        app.swipeUp()
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "View PR")).firstMatch.waitForExistence(timeout: 2),
            "Work Thread should not expose PR detail from the default path while the PR data source is deferred"
        )
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "chevron.left").count, 1, "Exactly one back chevron on Work Thread")

        // Approval banner -> Review Diff
        app.swipeUp()
        tapApprovalBanner(app, timeout: 10)
        assertReviewDiffVisible(app)
        snapshot("08-reviewdiff-from-workthread", app: app)
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].waitForExistence(timeout: 10), "Back from Review should return to Work Thread")

        // Back to repo list (both back-paths tested across this + testRepoThreadList_RowPushesWorkThreadAndComposer)
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
    }

    func testWorkThread_ComposerTap() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].waitForExistence(timeout: 10))

        tapComposerToOpenSheet(app, placeholder: "Follow up...")
        XCTAssertTrue(waitForExpandedComposer(app, timeout: 8), "Work Thread composer tap should present Composer sheet")
        snapshot("10b-composer-from-workthread", app: app)
    }

    // MARK: 8. Review/Diff decisions (each on a fresh launch)

    private func openReviewDiffFromWorkThread(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["lancer-ios"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fix onboarding pairing flow")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fix onboarding pairing flow"].waitForExistence(timeout: 10))
        app.swipeUp()
        tapApprovalBanner(app, timeout: 10)
        assertReviewDiffVisible(app)
    }

    func testReviewDiff_Approve() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        app.buttons["cursor.review.approve"].tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Decided by You")).firstMatch.waitForExistence(timeout: 5))
        snapshot("08b-reviewdiff-approved", app: app)
    }

    func testReviewDiff_Deny() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Deny")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 5))
        snapshot("08c-reviewdiff-denied", app: app)
    }

    func testReviewDiff_Reply() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        app.buttons["Reply"].tap()
        XCTAssertTrue(app.staticTexts["Reply sent"].waitForExistence(timeout: 5))
        snapshot("08d-reviewdiff-replied", app: app)
    }

    func testReviewDiff_NoFakeFullDiffAction() throws {
        let app = launchSkipOnboarding(route: "reviewDiff")
        defer { app.terminate() }
        assertReviewDiffVisible(app)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "View full diff")).firstMatch.exists,
            "Review should not expose the old fake full-diff action"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "terraform apply")).firstMatch.exists,
            "Review must not render the old fake terraform approval"
        )
    }

    // MARK: 9. PR Detail

    func testPRDetail_IsHonestDeferredState() throws {
        let app = launchSkipOnboarding(route: "prDetail")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Ship history not built yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "real PR, inline diff, or GitHub status data source")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Open"].exists, "PR detail must not render fake PR status")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "RelayReconnectManager.swift")).firstMatch.exists,
                       "PR detail must not render fake file rows")
        snapshot("09b-prdetail-deferred", app: app)

        // Back chevron, single instance
        XCTAssertEqual(app.buttons.matching(identifier: "chevron.left").count, 1)
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10))
    }

    // MARK: 10. Composer sheet chain

    func testComposerChain_RunOnAndModelNestedSheets() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        tapComposerToOpenSheet(app, placeholder: "Plan, ask, build...")
        XCTAssertTrue(waitForExpandedComposer(app, timeout: 10))
        snapshot("10c-composer-sheet-open", app: app)

        let textField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Plan, ask, build...")).firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            textField.typeText("Test prompt input")
            snapshot("10d-composer-text-typed", app: app)
            dismissKeyboardIfPresent(app)
        }

        // NOTE: the composer sheet has TWO separate pickers in its top row:
        // the repo/branch text button and a separate cloud-icon run-target
        // button. Repo picker behavior is covered by
        // testRepoPickerSheet_SearchAndSelect; this chain keeps focus on
        // Run-On and Model nested sheets.
        let repoPicker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "lancer-ios")).firstMatch
        XCTAssertTrue(repoPicker.waitForExistence(timeout: 5), "Composer should show its current repo selector")

        let runTargetPicker = app.buttons["cloud"]
        XCTAssertTrue(runTargetPicker.waitForExistence(timeout: 5), "Cloud run-target icon button should exist")
        tapWithRetry(runTargetPicker, label: "cloud run-target")
        let runOnTitle = app.staticTexts["Run on"]
        XCTAssertTrue(runOnTitle.waitForExistence(timeout: 10))
        snapshot("10e-runon-nested-sheet", app: app)
        let closeRunOn = app.buttons["xmark"].firstMatch
        XCTAssertTrue(closeRunOn.waitForExistence(timeout: 5))
        tapWithRetry(closeRunOn, label: "close Run on")
        waitForElementToDisappear(runOnTitle, timeout: 8)
        XCTAssertTrue(app.buttons["cloud"].waitForExistence(timeout: 10),
                      "Closing Run-on should return to composer sheet, not dismiss everything")

        // Model chip -> Model nested sheet
        let modelChip = composerModelChip(app)
        XCTAssertTrue(modelChip.waitForExistence(timeout: 8))
        tapWithRetry(modelChip, label: "model chip")
        let modelTitle = app.staticTexts["Model"]
        XCTAssertTrue(modelTitle.waitForExistence(timeout: 10))
        snapshot("10f-model-nested-sheet", app: app)

        let modelSearch = app.textFields["Search"]
        if modelSearch.waitForExistence(timeout: 5) {
            modelSearch.tap()
            modelSearch.typeText("GPT")
            snapshot("10g-model-search-typed", app: app)
            modelSearch.typeText(String(repeating: "\u{8}", count: 3))
            dismissKeyboardIfPresent(app)
        }

        let ellipsisOnRow = app.buttons["ellipsis"].firstMatch
        if ellipsisOnRow.waitForExistence(timeout: 5) {
            tapWithRetry(ellipsisOnRow, label: "model row ellipsis")
            XCTAssertTrue(modelTitle.exists, "Model row '...' should not crash")
        }

        let modelRow = tappableRow(app, containing: "Claude Opus 4")
        if modelRow.waitForExistence(timeout: 5) {
            tapWithRetry(modelRow, label: "Claude Opus 4")
            waitForElementToDisappear(modelTitle, timeout: 8)
            XCTAssertTrue(app.buttons["cloud"].waitForExistence(timeout: 10),
                          "Selecting a model should return to composer sheet")
        }

        // Swipe whole composer sheet down -> dismiss to Workspaces
        dismissKeyboardIfPresent(app)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 15), "Swiping composer down should dismiss back to Workspaces")
        snapshot("10h-composer-dismissed-to-workspaces", app: app)
    }

    func testReceiptCardMockShell() {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_CURSOR_SHELL"] = "1"
        app.launchEnvironment["LANCER_CURSOR_ROUTE"] = "receiptCard"
        app.launchEnvironment["LANCER_CURSOR_MOCK_RECEIPT"] = "1"
        app.launch()

        let receiptCard = app.otherElements["receipt-card"]
        XCTAssertTrue(receiptCard.waitForExistence(timeout: 10), "Receipt card should render in mock work thread")
        snapshot("receipt-card-visible", app: app)

        let acceptButton = app.buttons["receipt-accept"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 5))
        tapWithRetry(acceptButton, label: "Accept receipt")

        let anotherPass = app.buttons["receipt-another-pass"]
        XCTAssertTrue(anotherPass.waitForExistence(timeout: 5))
        tapWithRetry(anotherPass, label: "Request another pass")
        XCTAssertTrue(isExpandedComposerVisible(app, timeout: 10), "Another pass should open composer")
        snapshot("receipt-another-pass-composer", app: app)
    }

    func testSettings_SupportFeedbackRows() throws {
        let app = launchSkipOnboarding()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 30))
        avatarCoordinate(app).tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 10))

        let appSettings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "App Settings")).firstMatch
        XCTAssertTrue(appSettings.waitForExistence(timeout: 5))
        appSettings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))

        XCTAssertTrue(
            app.buttons["settings-suggest-feature"].waitForExistence(timeout: 5),
            "Suggest a Feature row should exist on Settings"
        )
        XCTAssertTrue(
            app.buttons["settings-report-issue"].waitForExistence(timeout: 5),
            "Report an Issue row should exist on Settings"
        )
    }
}
