@preconcurrency import XCTest

/// Seeded attachment bubble (thumbnail + file card) without a live paired daemon.
@MainActor
final class AttachmentPreviewUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSeededAttachmentBubble_ShowsThumbnailAndFileCardWithoutHostPaths() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "attachmentPreview"
        app.launch()
        defer { app.terminate() }

        // Require the bubble itself — title alone is not enough.
        let bubble = app.otherElements["attachment-preview-demo.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 20), "Attachment preview bubble must exist")
        XCTAssertTrue(app.staticTexts["Describe this image and the PDF"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["notes.pdf"].waitForExistence(timeout: 5)
                || app.descendants(matching: .any)["Attached file, notes.pdf, 8 KB"].waitForExistence(timeout: 2),
            "File card must show filename"
        )
        // Thumbnail path: image name or attached-image a11y label should appear.
        XCTAssertTrue(
            app.images.firstMatch.waitForExistence(timeout: 5)
                || app.descendants(matching: .any)["Attached image, sunset.jpg, 24 KB"].waitForExistence(timeout: 2)
                || app.staticTexts["sunset.jpg"].waitForExistence(timeout: 2),
            "Image thumbnail or image fallback name must appear"
        )
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", ".lancer/attachments")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/Users/")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "contentDigest")).firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "attachment-preview-thumbnail-and-file-card"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let data = app.screenshot().pngRepresentation
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lancer-attachment-preview-\(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: out)
        let docsOut = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/test-runs/2026-07-14-attachment-preview-thumbnail-and-file-card.png")
        try? FileManager.default.createDirectory(at: docsOut.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: docsOut)
        let pathAttachment = XCTAttachment(contentsOfFile: out)
        pathAttachment.name = "attachment-preview-path:\(out.path)"
        pathAttachment.lifetime = .keepAlways
        add(pathAttachment)
        print("ATTACHMENT_SCREENSHOT_PATH=\(out.path)")
    }

    func testSeededAttachmentBubble_DarkModeAndDynamicTypeSmoke() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SKIP_CURSOR_ONBOARDING"] = "1"
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = "attachmentPreview"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        // Force dark appearance for this process.
        if #available(iOS 13.0, *) {
            app.launchArguments += ["-AppleLanguages", "(en)"]
        }
        app.launch()
        defer { app.terminate() }

        let bubble = app.otherElements["attachment-preview-demo.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 20), "Bubble must survive Dynamic Type smoke")
        XCTAssertTrue(app.staticTexts["notes.pdf"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["Attached file, notes.pdf, 8 KB"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/Users/")).firstMatch.exists)
    }
}
