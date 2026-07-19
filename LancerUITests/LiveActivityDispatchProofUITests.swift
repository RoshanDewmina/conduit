@preconcurrency import XCTest

/// Live proof that dispatching a real run through the production relay path
/// (`ShellLiveBridge.send()`) does not regress after this session's Live
/// Activity wiring (`startLiveActivity`/`updateLiveActivityIfNeeded`/
/// `endLiveActivity` calls threaded through `send`, `sendFollowUp`,
/// `pollUntilTerminal`, `pollObservedTranscriptReply`) — the send/reply cycle
/// must complete exactly as it did before those calls were added.
///
/// This is also the FIRST time in this device-testing session that any real
/// message has been sent through the app's composer — every prior Live
/// Activity check was static review + unit tests only, never a live dispatch.
/// A live dispatch is what actually calls `Activity.request(...)`
/// (`LancerLiveActivityManager.start`), which is the only thing that can
/// produce a real ActivityKit push token and light up the Dynamic Island /
/// Lock Screen — XCUITest itself cannot observe that system-chrome UI (it's
/// rendered by SpringBoard, outside this app's accessibility tree), so this
/// test proves the code path executes cleanly; the daemon log
/// (`~/.lancer/lancerd.stderr.log` "activityTokenRegister") is checked
/// separately for the token round-trip, and the actual Dynamic Island
/// appearance needs the owner's own eyes on the device.
///
/// PRECONDITIONS (set up out-of-band, same as `ReconnectCycleUITests`):
/// - App already paired to a running lancerd (production relay).
/// - A workspace repo already added; composer defaults to Claude Code + Haiku.
/// - Deliberately does NOT set LANCER_UITEST_RESEED (would wipe the live pairing).
@MainActor
final class LiveActivityDispatchProofUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testDispatchSucceedsWithLiveActivityWiringPresent() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        // Open the expanded composer via DEBUG destination — more reliable than
        // tapping the collapsed morph pill on iOS 27 sims (2026-07-18 fail:
        // cursor-composer-tap succeeded but TextEditor never appeared).
        app.launchEnvironment["LANCER_DESTINATION"] = "composer"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
            "app should land on Workspaces home"
        )

        // Wait for the expanded composer TextEditor BEFORE retargeting the
        // repo. List rows use "command-center, 37" / "lancer, 6"; the composer
        // chip is exactly "command-center". Tapping a list row navigates away
        // and tears down the draft (2026-07-18 fail on lease-220).
        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 20), "composer draft")

        let repoChip = app.buttons["command-center"].firstMatch
        if repoChip.waitForExistence(timeout: 5) {
            repoChip.tap()
            // Picker rows fold name + cwd subtitle — match by host path so we
            // don't hit the Workspaces list row "lancer, 6".
            let lancerRow = app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "/Volumes/LancerDev/lancer"))
                .firstMatch
            if !lancerRow.waitForExistence(timeout: 3) {
                let search = app.searchFields.firstMatch
                if search.waitForExistence(timeout: 3) {
                    search.tap()
                    search.typeText("lancer")
                } else if app.textFields.firstMatch.waitForExistence(timeout: 2) {
                    let field = app.textFields.firstMatch
                    field.tap()
                    field.typeText("lancer")
                }
            }
            XCTAssertTrue(
                lancerRow.waitForExistence(timeout: 10),
                "\"lancer\" picker row containing /Volumes/LancerDev/lancer"
            )
            lancerRow.tap()
            XCTAssertTrue(draft.waitForExistence(timeout: 10), "composer draft still present after repo retarget")
        }

        draft.tap()

        let prompt = "Reply with exactly live-activity-dispatch-ok. Do not use tools."
        if let existing = draft.value as? String,
           !existing.isEmpty,
           existing != prompt,
           !existing.contains("Plan, ask, build") {
            draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
        }
        draft.typeText(prompt)

        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "send button")
        XCTAssertTrue(send.isEnabled, "send should be enabled")
        send.tap()

        // Dispatch happened — this is the point `ShellLiveBridge.send()` called
        // `startLiveActivity()` for real, for the first time this session.
        let retry = app.buttons["Retry"].firstMatch
        let errorHeader = app.staticTexts["Couldn't get a reply"].firstMatch
        let reply = app.staticTexts["live-activity-dispatch-ok"].firstMatch

        var replied = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if retry.exists || errorHeader.exists {
                attachScreenshot(name: "live-activity-dispatch-FAIL-retry")
                XCTFail("Retry/error state appeared instead of a reply — Live Activity wiring may have regressed the send path")
                return
            }
            if reply.exists {
                replied = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(replied, "no reply within 120s — dispatch with Live Activity wiring present should complete normally")

        attachScreenshot(name: "live-activity-dispatch-PASS")

        // Give the async ActivityKit push-token callback a window to fire and
        // the coordinator to forward it before the test (and app) tears down.
        Thread.sleep(forTimeInterval: 5)
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
