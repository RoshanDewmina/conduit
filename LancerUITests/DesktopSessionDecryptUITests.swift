@preconcurrency import XCTest

/// Live-proof: opening a Desktop Claude Code session must hydrate the transcript
/// without surfacing "Decryption failed" (SessionMessage.Role `"thinking"` decode).
///
/// PRECONDITIONS (set up out-of-band):
/// - Sim app already paired to a running lancerd (production relay).
/// - Daemon session list includes ≥1 desktop Claude Code session whose transcript
///   contains thinking blocks.
/// - Deliberately does NOT set LANCER_UITEST_RESEED (would wipe the live pairing).
///
/// Navigation: `LANCER_DESTINATION=threadList` opens the first-repo ThreadListView
/// (cwd-filtered), which can hide Desktop rows — tap Workspaces → All Repos instead
/// so every claudeCode observed session is listed.
@MainActor
final class DesktopSessionDecryptUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testDesktopSessionOpensWithoutDecryptionFailed() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
            "app should land on Workspaces home"
        )

        // WorkspaceRowView folds the thread count into the AX label
        // ("All Repos, 55") — exact-match lookup never fires.
        let allRepos = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "All Repos"))
            .firstMatch
        XCTAssertTrue(
            allRepos.waitForExistence(timeout: 15),
            "All Repos row should be on Workspaces home"
        )
        allRepos.tap()

        // Session list arrives over the relay — allow time for Desktop-badged rows.
        // DesktopSessionListRow badge Text("Desktop") lands in the Button's AX label.
        let desktopRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Desktop"))
            .firstMatch
        let listDeadline = Date().addingTimeInterval(60)
        var foundDesktop = false
        while Date() < listDeadline {
            if desktopRow.exists {
                foundDesktop = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(foundDesktop, "expected ≥1 Desktop-badged session row within 60s")
        desktopRow.tap()

        // Desktop row opens LiveThreadView (sheet) via armObservedContinue + adopt.
        XCTAssertTrue(
            app.navigationBars["Chat"].waitForExistence(timeout: 30),
            "LiveThreadView should present (navigationTitle Chat)"
        )

        let decryptExact = app.staticTexts["Decryption failed"].firstMatch
        let decryptContains = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Decryption failed"))
            .firstMatch
        let failDeadline = Date().addingTimeInterval(20)
        while Date() < failDeadline {
            if decryptExact.exists || decryptContains.exists {
                attachScreenshot(name: "desktop-decrypt-FAIL")
                XCTFail("Decryption failed appeared after opening a Desktop session")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Positive: hydrated transcript rendered in LiveThreadView (priorTurns →
        // ChatUserBubble / ChatMarkdownBody), not error or empty-adopt placeholders.
        XCTAssertTrue(
            app.buttons["Add context"].waitForExistence(timeout: 5),
            "ChatFollowUpComposerBar Add context should be present"
        )
        XCTAssertFalse(
            app.buttons["Retry"].exists,
            "Retry / Couldn't get a reply error chrome must not appear"
        )
        XCTAssertFalse(
            app.staticTexts["Couldn't get a reply"].exists,
            "error header must not appear after successful transcript hydrate"
        )
        XCTAssertFalse(
            app.otherElements["adopted-no-history-placeholder"].exists,
            "expected host transcript content, not empty adopt placeholder"
        )
        // Transcript prose renders as Text views whose AX exposure varies
        // (staticTexts under the scroll view proved empty on a hydrated
        // thread) — accept any element carrying a sentence-length label.
        let prose = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "(?s).{40,}"))
            .firstMatch
        XCTAssertTrue(
            prose.waitForExistence(timeout: 10),
            "expected transcript message text in LiveThreadView"
        )

        attachScreenshot(name: "desktop-decrypt-PASS")
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
