@preconcurrency import XCTest

/// Focused UI coverage for remaining 2026-07-19 sim lanes L3 / L7 / L8.
/// Offline DEBUG destinations only — no production `lancerd pair`.
@MainActor
final class SimRemainingLanesUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func evidenceDir(_ lane: String) -> URL {
        // Prefer absolute repo-rooted path so XCTest attachments land in the worktree
        // even when xcodebuild's process CWD is DerivedData.
        let candidates = [
            ProcessInfo.processInfo.environment["LANCER_EVIDENCE_ROOT"],
            "/Volumes/LancerDev/lancer/.worktrees/sim-remaining-lanes",
            FileManager.default.currentDirectoryPath,
        ].compactMap { $0 }
        let base = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            ?? candidates.first
            ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: base)
            .appendingPathComponent("docs/test-runs/2026-07-19-sim-feature-lanes/\(lane)/screenshots")
    }

    private func attach(_ app: XCUIApplication, lane: String, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let dir = evidenceDir(lane)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func launch(destination: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_SKIP_NOTIFICATION_PROMPT"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_SEED_DEMO"] = "1"
        app.launchEnvironment["LANCER_STATE_DIR"] = "/tmp/lancer-sim-remaining-\(UUID().uuidString)"
        app.launchEnvironment["LANCER_DESTINATION"] = destination
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()
        return app
    }

    // MARK: L8 — Accounts & Usage

    func testL8_AccountsUsageDestination() throws {
        let app = launch(destination: "accounts")
        defer { app.terminate() }

        let root = app.otherElements["accounts.usage"].firstMatch
        let title = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Accounts")
        ).firstMatch
        XCTAssertTrue(
            root.waitForExistence(timeout: 25) || title.waitForExistence(timeout: 10),
            "LANCER_DESTINATION=accounts should open Accounts & Usage"
        )

        let addClaude = app.buttons["accounts.add.claude"].firstMatch
        let addCodex = app.buttons["accounts.add.codex"].firstMatch
        let vendorRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Claude")
        ).firstMatch
        XCTAssertTrue(
            addClaude.waitForExistence(timeout: 8)
                || addCodex.waitForExistence(timeout: 3)
                || vendorRow.waitForExistence(timeout: 3),
            "Vendor list / add affordance should be visible"
        )
        attach(app, lane: "L8", name: "L8-01-accounts-usage")
    }

    // MARK: L3 — Workspaces chrome deep-links

    func testL3_WorkspacesChromeDeepLinks() throws {
        let destinations: [(String?, String, NSPredicate)] = [
            (nil, "L3-01-workspaces-root", NSPredicate(format: "label == %@", "Workspaces")),
            ("composer", "L3-02-composer", NSPredicate(format: "label CONTAINS[c] %@", "Agent")),
            ("profile", "L3-03-profile", NSPredicate(format: "label CONTAINS[c] %@", "Profile")),
            ("settings", "L3-04-settings", NSPredicate(format: "label == %@", "Settings")),
            ("search", "L3-05-search", NSPredicate(format: "label == %@", "Search")),
            ("addRepo", "L3-06-add-repo", NSPredicate(format: "label CONTAINS[c] %@", "Add")),
            ("repoPickerDirect", "L3-07-repo-picker", NSPredicate(format: "label CONTAINS[c] %@", "Repo")),
        ]

        var summary: [String: String] = [:]
        for (dest, shot, predicate) in destinations {
            let app = XCUIApplication()
            app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
            app.launchEnvironment["LANCER_SKIP_NOTIFICATION_PROMPT"] = "1"
            app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
            app.launchEnvironment["LANCER_SEED_DEMO"] = "1"
            app.launchEnvironment["LANCER_STATE_DIR"] = "/tmp/lancer-sim-l3-\(UUID().uuidString)"
            if let dest {
                app.launchEnvironment["LANCER_DESTINATION"] = dest
            }
            app.launchArguments += ["-onboardingSeen", "YES"]
            app.launch()
            defer { app.terminate() }

            let match = app.descendants(matching: .any).matching(predicate).firstMatch
            let composerTap = app.buttons["cursor-composer-tap"].firstMatch
            let ok: Bool
            if dest == nil {
                ok = app.staticTexts["Workspaces"].waitForExistence(timeout: 30)
                    && (composerTap.waitForExistence(timeout: 5) || app.buttons["New Chat"].waitForExistence(timeout: 2))
                    && app.tabBars.count == 0
            } else if dest == "composer" {
                ok = match.waitForExistence(timeout: 20)
                    || app.buttons["composer.send"].waitForExistence(timeout: 5)
            } else {
                ok = match.waitForExistence(timeout: 20)
            }
            summary[dest ?? "root"] = ok ? "PASS" : "FAIL"
            attach(app, lane: "L3", name: shot)
            XCTAssertTrue(ok, "L3 destination \(dest ?? "root") should present")
        }
        print("L3_SUMMARY \(summary.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
    }

    // MARK: L7 — Review sheet (fixture destination)

    func testL7_ReviewSheetFixtureDestination() throws {
        let app = launch(destination: "review")
        defer { app.terminate() }

        let modified = app.buttons["Modified"].firstMatch
        let allFiles = app.buttons["All Files"].firstMatch
        let hint = app.otherElements["review-pr-hint-card"].firstMatch
        let filesChanged = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "files changed")
        ).firstMatch
        let prHint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "PR not opened")
        ).firstMatch

        let sheetVisible =
            modified.waitForExistence(timeout: 25)
            || allFiles.waitForExistence(timeout: 5)
            || hint.waitForExistence(timeout: 5)
            || filesChanged.waitForExistence(timeout: 5)
            || prHint.waitForExistence(timeout: 5)

        XCTAssertTrue(sheetVisible, "LANCER_DESTINATION=review should present ReviewSheetView fixtures")
        attach(app, lane: "L7", name: "L7-01-review-sheet-modified")

        if allFiles.exists || allFiles.waitForExistence(timeout: 3) {
            allFiles.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, lane: "L7", name: "L7-02-review-sheet-all-files")
        }

        // Edit-tool red/green inline sheet is a known missing regression (CursorStyle deletion);
        // this lane asserts the Codex-style ReviewSheetView fixture path, not the Edit tool card.
        add(XCTAttachment(string: "L7_EDIT_TOOL_SHEET=MISSING (known; DiffKit present, CursorReviewDiffView deleted with 6b97da65)"))
    }
}
