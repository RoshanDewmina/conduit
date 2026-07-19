@preconcurrency import XCTest

/// Lane C4 — 2026-07-16 untested-feature sweep, post-Wave-1 live re-test.
/// Tip must include `7707e4fa` (FX7 + FX5 + Lane P). Isolated daemon:
/// `LANCER_STATE_DIR=/tmp/sweep-C4`. Pass pair code via
/// `TEST_RUNNER_LANE_C4_PAIR_CODE` (xcodebuild only forwards `TEST_RUNNER_*`).
@MainActor
final class SweepLaneC4Tests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func tapAnyApprove(_ app: XCUIApplication) -> Bool {
        let byId = app.buttons["cursor.approval.approve"].firstMatch
        if byId.exists && byId.isHittable { byId.tap(); return true }
        let byLabel = app.buttons["Approve"].firstMatch
        if byLabel.exists && byLabel.isHittable { byLabel.tap(); return true }
        return false
    }

    private func launchSweepApp(destination: String, pairCode: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        // Suppresses the iOS notification permission sheet that blocked HID on
        // the 2026-07-19 L1 serial run (AppRoot honors this in DEBUG).
        app.launchEnvironment["LANCER_SKIP_NOTIFICATION_PROMPT"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = destination
        app.launchEnvironment["LANCER_STATE_DIR"] = "/tmp/sweep-C4"
        if let pairCode {
            app.launchEnvironment["LANCER_RELAY_PAIR_CODE"] = pairCode
        }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    private var pairCode: String? {
        ProcessInfo.processInfo.environment["LANE_C4_PAIR_CODE"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_LANE_C4_PAIR_CODE"]
    }

    func testLaneC4_PostWave1LiveSweep() throws {
        let code = pairCode
        XCTAssertNotNil(code, "TEST_RUNNER_LANE_C4_PAIR_CODE must be set by harness")

        // --- FX5: Connect visible above number pad ---
        do {
            let app = launchSweepApp(destination: "trustedMachines", pairCode: code)
            defer { app.terminate() }
            let pairButton = app.buttons["trusted-machines.pair"].firstMatch
            if pairButton.waitForExistence(timeout: 20) {
                pairButton.tap()
            }
            let codeField = app.textFields.firstMatch
            XCTAssertTrue(codeField.waitForExistence(timeout: 15), "Pairing code field should exist")
            codeField.tap()
            codeField.typeText("123456")
            attach(app, "LC4-01-pairing-keypad")
            let connect = app.buttons["Connect"].firstMatch
            XCTAssertTrue(connect.waitForExistence(timeout: 5), "Connect should be visible with keypad open (FX5)")
            XCTAssertTrue(connect.isHittable, "Connect should not be occluded by number pad (FX5)")
        }

        // --- #2 Policy + #3 Audit over relay (Lane P) ---
        var policyRelayPicker = false
        var auditLoaded = false
        var auditSSHError = false
        do {
            let app = launchSweepApp(destination: "settings", pairCode: code)
            defer { app.terminate() }
            Thread.sleep(forTimeInterval: 20)
            attach(app, "LC4-02-settings")

            let policyRow = app.descendants(matching: .any)["cursor.settings.row.policy"].firstMatch
            let policyByLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Policy")).firstMatch
            if policyRow.waitForExistence(timeout: 10) {
                policyRow.tap()
            } else if policyByLabel.waitForExistence(timeout: 5) {
                policyByLabel.tap()
            }
            Thread.sleep(forTimeInterval: 3)
            attach(app, "LC4-03-policy")
            let modePicker = app.descendants(matching: .any)["cursor.settings.policy.mode-picker"].firstMatch
            let sshPolicyError = app.descendants(matching: .any)["cursor.settings.policy.error"].firstMatch
            policyRelayPicker = modePicker.waitForExistence(timeout: 15)
            let sshOnlyFootnote = app.descendants(matching: .any)["cursor.settings.policy.relay-only-footnote"].firstMatch
            XCTAssertTrue(
                policyRelayPicker || sshOnlyFootnote.exists,
                "Policy should show relay coarse-mode picker, not SSH-only block"
            )
            XCTAssertFalse(
                sshPolicyError.exists && app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "SSH host session")
                ).firstMatch.exists,
                "Policy should not show SSH-required error on relay-only pairing post-Lane P"
            )

            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }

            let auditRow = app.descendants(matching: .any)["cursor.settings.row.audit"].firstMatch
            let auditByLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Audit")).firstMatch
            if auditRow.waitForExistence(timeout: 10) {
                auditRow.tap()
            } else if auditByLabel.waitForExistence(timeout: 5) {
                auditByLabel.tap()
            }
            Thread.sleep(forTimeInterval: 3)
            attach(app, "LC4-04-audit")
            let auditFeed = app.descendants(matching: .any)["cursor.settings.audit-feed"].firstMatch
            auditLoaded = auditFeed.waitForExistence(timeout: 10)
            auditSSHError = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "SSH host session")
            ).firstMatch.exists
            XCTAssertTrue(auditLoaded, "Audit feed view should load over relay")
            XCTAssertFalse(auditSSHError, "Audit should not require SSH post-Lane P")
        }

        // --- #7 chain + #19 repo honesty (FX7 awaiting-approval path) ---
        var approveTaps = 0
        var sawAwaitingCard = false
        var sawTerminalRetry = false
        var hasDiffPill = false
        var hasProof = false
        do {
            let app = launchSweepApp(destination: "addRepo", pairCode: code)
            defer { app.terminate() }

            let pathField = app.textFields.firstMatch
            XCTAssertTrue(pathField.waitForExistence(timeout: 20))
            pathField.tap()
            pathField.typeText("/tmp/sweep-C4/target-repo")
            let nameFields = app.textFields.allElementsBoundByIndex
            if nameFields.count > 1 {
                nameFields[1].tap()
                nameFields[1].typeText("sc4-repo")
            }
            attach(app, "LC4-05-add-repo")
            app.buttons["Add Repo"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Workspaces"].waitForExistence(timeout: 15))
            attach(app, "LC4-06-workspaces")

            Thread.sleep(forTimeInterval: 25)

            app.buttons["cursor-composer-tap"].firstMatch.tap()
            let draft = app.textViews.firstMatch
            XCTAssertTrue(draft.waitForExistence(timeout: 10))
            draft.tap()
            draft.typeText("Run `pwd` with Bash and print the output. Then edit greeting.txt and readme.md: append one line to each, then run git add -A && git commit -m 'sweep edit'.")
            attach(app, "LC4-07-composer")
            app.buttons["composer.send"].firstMatch.tap()

            let diffPill = app.otherElements["session-diff-pill"].firstMatch
            let diffPillButton = app.buttons["session-diff-pill"].firstMatch
            let awaitingCard = app.otherElements["awaiting-approval-card"].firstMatch
            let errorRetry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Retry")).firstMatch
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                if tapAnyApprove(app) { approveTaps += 1; Thread.sleep(forTimeInterval: 1); continue }
                if awaitingCard.exists { sawAwaitingCard = true }
                if errorRetry.exists && app.staticTexts["Couldn't get a reply"].firstMatch.exists {
                    sawTerminalRetry = true
                }
                if diffPill.exists || diffPillButton.exists { break }
                let proof = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Proof")).firstMatch
                if proof.exists { break }
                Thread.sleep(forTimeInterval: 3)
            }
            hasDiffPill = diffPill.exists || diffPillButton.exists
            let proofChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Proof")).firstMatch
            hasProof = proofChip.exists
            attach(app, "LC4-08-thread approves=\(approveTaps) awaiting=\(sawAwaitingCard) retry=\(sawTerminalRetry) diff=\(hasDiffPill) proof=\(hasProof)")

            if hasDiffPill {
                let pillToTap = diffPillButton.exists ? diffPillButton : diffPill
                pillToTap.tap()
                attach(app, "LC4-09-review-sheet")
                let openViewer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open ")).firstMatch
                if openViewer.waitForExistence(timeout: 10) {
                    openViewer.tap()
                    attach(app, "LC4-10-file-viewer")
                    if app.navigationBars.buttons.firstMatch.exists {
                        app.navigationBars.buttons.firstMatch.tap()
                    }
                }
                if app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Close")).firstMatch.exists {
                    app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Close")).firstMatch.tap()
                }
            }

            let moreButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "More")).firstMatch
            if moreButton.waitForExistence(timeout: 5) { moreButton.tap() }
            let flightRecorderItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Flight Recorder")).firstMatch
            if flightRecorderItem.waitForExistence(timeout: 8) {
                flightRecorderItem.tap()
                attach(app, "LC4-11-flight-recorder")
            }
        }

        // --- #10 / #14 recheck ---
        var pillAppeared = false
        var bashCount = 0
        do {
            let app = launchSweepApp(destination: "composer", pairCode: code)
            defer { app.terminate() }
            Thread.sleep(forTimeInterval: 15)
            let draft = app.textViews.firstMatch
            if draft.waitForExistence(timeout: 15) {
                draft.tap()
                draft.typeText("Run `sleep 35 && echo done` via Bash, then summarize.")
                let send = app.buttons["composer.send"].firstMatch
                if send.waitForExistence(timeout: 5), send.isEnabled { send.tap() }
            }
            let pill = app.otherElements["background-tasks-pill"].firstMatch
            let midDeadline = Date().addingTimeInterval(50)
            while Date() < midDeadline {
                if tapAnyApprove(app) { continue }
                if pill.exists { pillAppeared = true; break }
                Thread.sleep(forTimeInterval: 2)
            }
            let doneDeadline = Date().addingTimeInterval(90)
            while Date() < doneDeadline {
                if tapAnyApprove(app) { continue }
                if app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Proof")).firstMatch.exists { break }
                Thread.sleep(forTimeInterval: 2)
            }
            bashCount = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Bash'")).count
            attach(app, "LC4-12-pills pill=\(pillAppeared) bashCount=\(bashCount)")
        }

        // --- #1 Emergency Stop quick reachability ---
        var stopOutcome = "not-tried"
        do {
            let app = launchSweepApp(destination: "settings", pairCode: code)
            defer { app.terminate() }
            Thread.sleep(forTimeInterval: 20)
            let stop = app.buttons["cursor.settings.emergency-stop"].firstMatch
            if stop.waitForExistence(timeout: 15) {
                stop.tap()
                let confirm = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Stop")).firstMatch
                if confirm.waitForExistence(timeout: 8) {
                    confirm.tap()
                    Thread.sleep(forTimeInterval: 2)
                    stopOutcome = app.staticTexts.matching(
                        NSPredicate(format: "label CONTAINS[c] %@", "No connected host")
                    ).firstMatch.exists ? "no-host" : "tapped"
                } else {
                    stopOutcome = "no-confirm"
                }
            } else {
                stopOutcome = "missing"
            }
            attach(app, "LC4-13-emergency-stop outcome=\(stopOutcome)")
        }

        // Evidence summary attachment for report writer.
        let summary = """
        policyRelayPicker=\(policyRelayPicker) auditLoaded=\(auditLoaded) auditSSHError=\(auditSSHError)
        approveTaps=\(approveTaps) awaitingCard=\(sawAwaitingCard) terminalRetry=\(sawTerminalRetry)
        diffPill=\(hasDiffPill) proof=\(hasProof) bgPill=\(pillAppeared) bashCount=\(bashCount) stop=\(stopOutcome)
        """
        add(XCTAttachment(string: summary))
        XCTAssertTrue(true, "C4 evidence captured — see LC4-report.md")
    }
}
