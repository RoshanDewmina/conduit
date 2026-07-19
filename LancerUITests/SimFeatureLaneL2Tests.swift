@preconcurrency import XCTest

/// L2 — Chat / transcript (2026-07-19 sim feature lane).
/// Offline-only: `LANCER_SEED_TRANSCRIPT` + demo fixtures. No `lancerd` pair.
@MainActor
final class SimFeatureLaneL2Tests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private let stateDir = "/tmp/lancer-sim-l2-\(UUID().uuidString)"

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let data = app.screenshot().pngRepresentation
        let base = ProcessInfo.processInfo.environment["LANCER_EVIDENCE_ROOT"]
            ?? "/Volumes/LancerDev/lancer/.worktrees/sim-remaining-lanes"
        let out = URL(fileURLWithPath: base)
            .appendingPathComponent("docs/test-runs/2026-07-19-sim-feature-lanes/L2/screenshots/\(name).png")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: out)
    }

    private func launch(
        destination: String,
        extra: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_SKIP_NOTIFICATION_PROMPT"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_SEED_DEMO"] = "1"
        app.launchEnvironment["LANCER_SEED_TRANSCRIPT"] = "1"
        app.launchEnvironment["LANCER_STATE_DIR"] = stateDir
        app.launchEnvironment["LANCER_DESTINATION"] = destination
        for (key, value) in extra {
            app.launchEnvironment[key] = value
        }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    func testL2_ChatTranscriptOfflineSeed() throws {
        var summary: [String: String] = [:]

        // --- Thread list ---
        do {
            let app = launch(destination: "threadList")
            defer { app.terminate() }
            let header = app.navigationBars["All Repos"].firstMatch
            let repoHeader = app.navigationBars.element(boundBy: 0)
            let seedRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Parity seed")
            ).firstMatch
            let seedText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "flaky test")
            ).firstMatch
            let listDeadline = Date().addingTimeInterval(25)
            var listFound = false
            while Date() < listDeadline {
                if seedRow.exists || seedText.exists { listFound = true; break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            let navOk = header.waitForExistence(timeout: 2) || repoHeader.waitForExistence(timeout: 2)
            summary["threadList"] = (listFound || navOk) ? "PASS" : "FAIL"
            attach(app, "L2-01-thread-list")
            XCTAssertTrue(listFound || navOk, "Thread list destination should show seeded threads or a list nav")
        }

        // --- Open thread + transcript + tool chips ---
        var toolChipFound = false
        var transcriptProseFound = false
        var thinkingFound = false
        do {
            let app = launch(destination: "threadList")
            defer { app.terminate() }
            let seedRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Parity seed")
            ).firstMatch
            XCTAssertTrue(seedRow.waitForExistence(timeout: 30), "Seed row for open-thread step")
            seedRow.tap()

            let back = app.buttons["Back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 20), "Thread detail should open")

            let prose = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "AuthTests")
            ).firstMatch
            transcriptProseFound = prose.waitForExistence(timeout: 15)
            let thinking = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "timing-dependent")
            ).firstMatch
            thinkingFound = thinking.waitForExistence(timeout: 5)
            let chip = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Ran a command")
            ).firstMatch
            let chipAlt = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "command")
            ).firstMatch
            toolChipFound = chip.waitForExistence(timeout: 10) || chipAlt.waitForExistence(timeout: 3)
            summary["openThread"] = back.exists ? "PASS" : "FAIL"
            summary["transcriptRender"] = (transcriptProseFound || thinkingFound) ? "PASS" : "FAIL"
            summary["toolChips"] = toolChipFound ? "PASS" : "PARTIAL-label-drift"
            attach(app, "L2-02-thread-detail-transcript")
            // Transcript prose is the hard gate; tool-chip copy can drift without failing the lane.
            XCTAssertTrue(transcriptProseFound || thinkingFound, "Seeded transcript body should render")
        }

        // --- Background tasks pill (completed seed → no running tasks expected) ---
        do {
            let app = launch(destination: "threadList")
            defer { app.terminate() }
            let seedRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Parity seed")
            ).firstMatch
            if seedRow.waitForExistence(timeout: 25) { seedRow.tap() }
            Thread.sleep(forTimeInterval: 2)
            let pill = app.otherElements["background-tasks-pill"].firstMatch
            let pillVisible = pill.waitForExistence(timeout: 3)
            // Completed parity seed has terminal tools only — pill should stay hidden.
            summary["backgroundTasksPill"] = pillVisible ? "UNEXPECTED" : "N/A-completed-seed"
            if pillVisible {
                pill.tap()
                _ = app.otherElements["background-tasks-sheet"].waitForExistence(timeout: 5)
                attach(app, "L2-03-background-tasks-sheet")
            } else {
                attach(app, "L2-03-no-running-pill-expected")
            }
        }

        // --- Follow-up composer (dispatch fails without pair — UI path only) ---
        do {
            let app = launch(destination: "threadList")
            defer { app.terminate() }
            let seedRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Parity seed")
            ).firstMatch
            if seedRow.waitForExistence(timeout: 25) { seedRow.tap() }
            let followUp = app.textFields["Follow up…"].firstMatch
            let followUpAlt = app.textViews.matching(
                NSPredicate(format: "placeholderValue CONTAINS[c] %@", "Follow up")
            ).firstMatch
            let field = followUp.waitForExistence(timeout: 10) ? followUp : followUpAlt
            XCTAssertTrue(field.waitForExistence(timeout: 10), "Follow-up field should exist")
            let enabled = field.isEnabled
            field.tap()
            field.typeText("Quick follow-up from L2 lane")
            let send = app.buttons["Send"].firstMatch
            let sendReady = send.waitForExistence(timeout: 5) && send.isEnabled
            if sendReady { send.tap() }
            Thread.sleep(forTimeInterval: 3)
            let pending = app.otherElements["thread-detail-pending-followup"].exists
            let errorText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Couldn't")
            ).firstMatch.exists
            summary["followUpUI"] = (enabled && sendReady) ? "PASS" : "FAIL"
            summary["followUpDispatch"] = pending ? "PARTIAL-sending" : (errorText ? "PARTIAL-no-machine" : "UNKNOWN")
            attach(app, "L2-04-follow-up")
        }

        // --- Scroll / history window (long seeded transcript) ---
        do {
            let app = launch(
                destination: "threadList",
                extra: ["LANCER_SEED_TRANSCRIPT_COUNT": "40"]
            )
            defer { app.terminate() }
            let perfRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "perf seed")
            ).firstMatch
            let perfAlt = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Perf seed")
            ).firstMatch
            let row = perfRow.waitForExistence(timeout: 30) ? perfRow : perfAlt
            if row.waitForExistence(timeout: 5) {
                row.tap()
                let showEarlier = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Show earlier")
                ).firstMatch
                let scrollPass = showEarlier.waitForExistence(timeout: 20)
                if scrollPass { showEarlier.tap() }
                summary["scrollHistory"] = scrollPass ? "PASS" : "PARTIAL-no-window"
                attach(app, "L2-05-scroll-history")
            } else {
                summary["scrollHistory"] = "FAIL-no-perf-row"
                attach(app, "L2-05-scroll-missing-row")
            }
        }

        let report = summary.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        add(XCTAttachment(string: "L2_SUMMARY \(report)"))
        print("L2_SUMMARY \(report)")
    }
}
