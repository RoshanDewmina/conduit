@preconcurrency import XCTest

/// 10 consecutive force-quit → relaunch → wait-Connected → first-send cycles
/// against a live paired daemon (isolated LANCER_STATE_DIR test daemon, real
/// production relay). Proves the fix/relay-append-correlated-resume behavior:
/// no Retry, no duplicate turn, exactly one reply per cycle.
///
/// PRECONDITIONS (set up out-of-band, see docs/test-runs/2026-07-15-reconnect-10x-sim):
/// - Sim app already paired to a running lancerd whose state dir is isolated.
/// - A workspace repo already added; composer defaults to Claude Code + Haiku.
/// - Deliberately does NOT set LANCER_UITEST_RESEED (would wipe the live pairing).
@MainActor
final class ReconnectCycleUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private static let prompt = "Reply with exactly reconnect-ok. Do not use tools."
    private static let replyText = "reconnect-ok"

    func testTenConsecutiveReconnectFirstSendCycles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchArguments += ["-onboardingSeen", "YES"]

        for cycle in 1...10 {
            try runCycle(cycle, app: app)
        }
    }

    private func runCycle(_ cycle: Int, app: XCUIApplication) throws {
        app.terminate()
        let launchedAt = Date()
        app.launch()

        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 45),
                      "cycle \(cycle): app should land on Workspaces home")

        // --- Wait Connected: Profile -> Trusted Machines -> "connected" ---
        let profile = app.buttons["Profile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "cycle \(cycle): Profile button")
        profile.tap()

        let trusted = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Trusted Machines"))
            .firstMatch
        XCTAssertTrue(trusted.waitForExistence(timeout: 10),
                      "cycle \(cycle): Trusted Machines row")
        trusted.tap()

        let connected = app.staticTexts["connected"].firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 60),
                      "cycle \(cycle): paired machine should show 'connected'")
        let connectedAt = Date()

        // Close Trusted Machines sheet, then Profile sheet.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "cycle \(cycle): close trusted sheet")
        close.tap()
        let profileClose = app.buttons["Close"].firstMatch
        if profileClose.waitForExistence(timeout: 5) {
            profileClose.tap()
        }
        XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 10),
                      "cycle \(cycle): back on Workspaces home")

        // --- Post-rekey hard case: wait 16s after Connected before first send ---
        Thread.sleep(forTimeInterval: 16)

        // --- First send ---
        let openComposer = app.buttons["cursor-composer-tap"].firstMatch
        XCTAssertTrue(openComposer.waitForExistence(timeout: 10),
                      "cycle \(cycle): home composer button")
        openComposer.tap()

        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 10), "cycle \(cycle): composer draft")
        draft.tap()

        // Clear any persisted draft from a previous session before typing.
        if let existing = draft.value as? String,
           !existing.isEmpty,
           existing != Self.prompt,
           !existing.contains("Plan, ask, build") {
            draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: existing.count + 4))
        }
        draft.typeText(Self.prompt)

        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "cycle \(cycle): send button")
        XCTAssertTrue(send.isEnabled, "cycle \(cycle): send should be enabled")
        let sentAt = Date()
        send.tap()

        // --- Await reply; fail fast on Retry / error state ---
        let retry = app.buttons["Retry"].firstMatch
        let errorHeader = app.staticTexts["Couldn't get a reply"].firstMatch
        let reply = app.staticTexts[Self.replyText].firstMatch

        var replied = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if retry.exists || errorHeader.exists {
                attachScreenshot(name: "cycle-\(pad(cycle))-FAIL-retry")
                XCTFail("cycle \(cycle): Retry/error state appeared instead of a reply")
                return
            }
            if reply.exists {
                replied = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        let firstTokenAt = Date()
        if !replied {
            attachScreenshot(name: "cycle-\(pad(cycle))-FAIL-timeout")
            XCTFail("cycle \(cycle): no reply within 120s (no Retry either — stuck Working)")
            return
        }

        // --- No duplicate turn: the prompt bubble and the reply appear exactly once ---
        let promptMatches = app.staticTexts
            .matching(NSPredicate(format: "label == %@", Self.prompt)).count
        let replyMatches = app.staticTexts
            .matching(NSPredicate(format: "label == %@", Self.replyText)).count
        XCTAssertEqual(promptMatches, 1, "cycle \(cycle): duplicate user turn detected")
        XCTAssertEqual(replyMatches, 1, "cycle \(cycle): duplicate reply detected")

        // Final Retry sweep after the reply landed.
        XCTAssertFalse(retry.exists, "cycle \(cycle): Retry appeared after reply")

        attachScreenshot(name: "cycle-\(pad(cycle))")
        let connectSecs = connectedAt.timeIntervalSince(launchedAt)
        let tokenSecs = firstTokenAt.timeIntervalSince(sentAt)
        print("RECONNECT_CYCLE \(cycle) PASS timeToConnected=\(String(format: "%.1f", connectSecs))s timeToFirstToken=\(String(format: "%.1f", tokenSecs))s")
    }

    private func pad(_ n: Int) -> String { String(format: "%02d", n) }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
