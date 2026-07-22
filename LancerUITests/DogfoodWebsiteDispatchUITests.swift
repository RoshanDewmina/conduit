@preconcurrency import XCTest

/// Physical-device dogfood — add dogfood repo, select it in composer, live-send.
/// Does NOT set LANCER_RELAY_PAIR_CODE (phone already paired; remint would orphan).
///
/// Pass bar: thread shows DOGFOOD-SITE-OK (host must have written index.html).
/// Fail-fast: "Couldn't get a reply", Retry, or wrong/missing cwd.
@MainActor
final class DogfoodWebsiteDispatchUITests: XCTestCase {
    private static let dogfoodRepoName = "lancer-dogfood-site"
    private static let dogfoodCwd = "/Volumes/LancerDev/lancer-dogfood-site"
    private static let okMarker = "DOGFOOD-SITE-OK"

    override func setUp() {
        continueAfterFailure = false
    }

    func testDispatchWebsiteBuildOnPairedPhone() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "addRepo"
        app.launchArguments += ["-onboardingSeen", "YES"]
        app.launch()

        let path = app.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 25), "Add Repo path field")
        path.tap()
        path.typeText(Self.dogfoodCwd)

        let addRepo = app.buttons["Add Repo"].firstMatch
        XCTAssertTrue(addRepo.waitForExistence(timeout: 5))
        let enabledDeadline = Date().addingTimeInterval(5)
        while Date() < enabledDeadline, !addRepo.isEnabled {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(addRepo.isEnabled, "Add Repo enabled after path")
        addRepo.tap()

        let openComposer = app.buttons["cursor-composer-tap"].firstMatch
        if openComposer.waitForExistence(timeout: 12) {
            openComposer.tap()
        } else {
            let newChat = app.buttons["New Chat"].firstMatch
            XCTAssertTrue(newChat.waitForExistence(timeout: 10), "New Chat fallback")
            newChat.tap()
        }

        // Composer defaults to repos.first (often a stale host path). Force dogfood cwd.
        try selectDogfoodRepo(in: app)

        let draft = app.textViews.firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 20), "composer draft TextEditor")
        draft.tap()
        let prompt =
            "Create index.html in this repo: brand Lancer, headline about governing AI coding agents from your phone, one short supporting sentence, one CTA, clean modern CSS (no purple). Reply with exactly: DOGFOOD-SITE-OK when written."
        draft.typeText(prompt)

        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "composer.send")
        XCTAssertTrue(send.isEnabled, "Send enabled with dogfood repo + draft")
        send.tap()

        // Thread must show the submitted prompt (proves dispatch left composer).
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Create index.html")
            ).firstMatch.waitForExistence(timeout: 30),
            "live send should open a thread with the prompt"
        )

        let deadline = Date().addingTimeInterval(240)
        var sawOK = false
        while Date() < deadline {
            let approve = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Approve")
            ).firstMatch
            if approve.exists, approve.isHittable {
                approve.tap()
                Thread.sleep(forTimeInterval: 0.8)
            }

            // Exact label only — CONTAINS matches the user prompt bubble, which
            // itself mentions the success token (false pass in uitest9).
            let okExact = app.staticTexts.matching(
                NSPredicate(format: "label == %@", Self.okMarker)
            ).firstMatch
            if okExact.exists {
                sawOK = true
                break
            }

            if app.staticTexts["Couldn't get a reply"].exists
                || app.buttons["Retry"].exists
                || app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "cwd does not exist")
                ).firstMatch.exists
                || app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "No connected machine")
                ).firstMatch.exists {
                attachShot(app, name: "dogfood-website-device-FAIL")
                XCTFail("dispatch failed (Couldn't get a reply / Retry / bad cwd / no machine)")
                return
            }

            Thread.sleep(forTimeInterval: 2)
        }

        attachShot(app, name: "dogfood-website-device")
        XCTAssertTrue(sawOK, "expected \(Self.okMarker) within 240s")
    }

    private func selectDogfoodRepo(in app: XCUIApplication) throws {
        // Already on dogfood? selector chip label is the repo display name.
        if app.buttons[Self.dogfoodRepoName].waitForExistence(timeout: 2) {
            return
        }

        // Open repo picker from whatever chip is showing (stale command-center, etc.).
        let chipCandidates = [
            "command-center",
            "Select a repo",
            "lancer",
            "Documents",
        ]
        var opened = false
        for label in chipCandidates {
            let chip = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", label)
            ).firstMatch
            if chip.waitForExistence(timeout: 1), chip.isHittable {
                chip.tap()
                opened = true
                break
            }
        }
        XCTAssertTrue(opened || app.staticTexts["Repo"].waitForExistence(timeout: 3),
                      "could not open composer repo picker")

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 2) {
            search.tap()
            search.typeText(Self.dogfoodRepoName)
        } else if app.textFields.firstMatch.waitForExistence(timeout: 3) {
            let field = app.textFields.firstMatch
            field.tap()
            field.typeText(Self.dogfoodRepoName)
        }

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", Self.dogfoodRepoName)
        ).firstMatch
        if row.waitForExistence(timeout: 8), row.isHittable {
            row.tap()
        } else {
            let textRow = app.staticTexts[Self.dogfoodRepoName]
            XCTAssertTrue(textRow.waitForExistence(timeout: 5), "dogfood repo row")
            textRow.tap()
        }

        XCTAssertTrue(
            app.buttons[Self.dogfoodRepoName].waitForExistence(timeout: 8)
                || app.staticTexts[Self.dogfoodRepoName].waitForExistence(timeout: 2),
            "composer should select \(Self.dogfoodRepoName)"
        )
    }

    private func attachShot(_ app: XCUIApplication, name: String) {
        _ = app
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
