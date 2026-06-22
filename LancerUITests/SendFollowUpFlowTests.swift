@preconcurrency import XCTest

/// End-to-end proof of the compose → send → chat-transition → follow-up loop, the
/// flow that regressed (dead send / no transition / dead follow-up / double-tap).
/// Uses the `newchat-live` gallery harness: a real NewChatTabView wired to a mock
/// dispatch that echoes "Mock reply to: <prompt>", so the whole UI loop is
/// deterministic without a live daemon/relay.
@MainActor
final class SendFollowUpFlowTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_GALLERY"] = "newchat-live"
        app.launch()
        return app
    }

    /// The core proof: typing a prompt and tapping Send must transition into the
    /// chat and render the reply; a follow-up must append a second answered turn.
    func testSendThenFollowUp() throws {
        let app = launch()

        // Compose + send the first message.
        let composer = app.textFields["Message — / for commands, @ for files…"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "composer should render")
        composer.tap()
        composer.typeText("First message")

        let send = app.buttons["Send chat"]
        XCTAssertTrue(send.exists, "Send button should exist")
        send.tap()

        // Transition into the chat + the reply renders.
        XCTAssertTrue(app.staticTexts["Mock reply to: First message"].waitForExistence(timeout: 10),
                      "After Send, the chat should open and show the reply")

        // Follow-up appends a second answered turn.
        let followUp = app.textFields["follow-up"]
        XCTAssertTrue(followUp.waitForExistence(timeout: 10), "follow-up field should render in the chat")
        followUp.tap()
        followUp.typeText("Second message")
        // The follow-up bar's send control (arrow.up). Fall back to pressing return.
        if app.buttons["arrow.up"].exists {
            app.buttons["arrow.up"].tap()
        } else {
            app.typeText("\n")
        }

        XCTAssertTrue(app.staticTexts["Mock reply to: Second message"].waitForExistence(timeout: 10),
                      "The follow-up should send and append a second answered turn")
        // The first turn's reply must still be present (turns accumulate).
        XCTAssertTrue(app.staticTexts["Mock reply to: First message"].exists,
                      "Earlier turns must remain after a follow-up")
    }

    /// Guard against the double-dispatch that produced the "superseded" alert: while
    /// a send is in-flight the Send button is disabled, so a second tap can't fire a
    /// duplicate. We assert no "Couldn't send" alert ever appears across the flow.
    func testNoSupersededAlertOnRapidSend() throws {
        let app = launch()
        let composer = app.textFields["Message — / for commands, @ for files…"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("Rapid")

        let send = app.buttons["Send chat"]
        send.tap()
        // A second immediate tap (button is disabled mid-send) must not produce a run
        // nor an alert. Tapping a disabled button is a no-op.
        if send.exists && send.isHittable { send.tap() }

        XCTAssertTrue(app.staticTexts["Mock reply to: Rapid"].waitForExistence(timeout: 10),
                      "Send should still complete cleanly")
        XCTAssertFalse(app.staticTexts["Couldn't send"].exists,
                       "No 'Couldn't send' / superseded alert should appear")
    }

    /// A tool-using turn must render as a terminal block card (command + output),
    /// not plain text — the relay tool-event path that was previously dropped.
    func testToolCommandRendersTerminalCard() throws {
        let app = launch()
        let composer = app.textFields["Message — / for commands, @ for files…"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("bash list files")

        app.buttons["Send chat"].tap()

        // The terminal card shows the command (rendered as "→ ls -la") and its output.
        let command = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "ls -la")).firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 10),
                      "A tool turn should render the command in a terminal card")
        let output = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "README.md")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5),
                      "The terminal card should show the command's output")
    }
}
