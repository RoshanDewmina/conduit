@preconcurrency import XCTest

/// Claude Code app <-> Lancer chat-surface parity harness (owner directive 2026-07-16,
/// spec: docs/product/2026-07-16-claude-code-app-parity-spec.md, CC-1..CC-10).
///
/// No live daemon/relay is available in this offline harness, so these tests capture the
/// richest *reachable* DEBUG-seam state for each CC item rather than a fully-driven live
/// transcript. Where a surface (aggregated tool chips, per-turn summary, thinking rows) can
/// only exist after a real agent turn completes tool calls, the screenshot instead documents
/// the honest "no connected machine" fallback state — see docs/test-runs/2026-07-16-cc-parity/
/// VERDICTS.md for the per-item gap notes. Do not read a PASS out of these screenshots alone.
@MainActor
final class CCParityScreenshots: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - CC-1: thread list / transcript surface (auto-follow scroll)

    /// No persisted threads exist in a fresh sim (no seam seeds a conversation transcript),
    /// so this captures ThreadDetailView's empty state — the surface CC-1's follow-scroll
    /// behavior would apply to, honestly empty rather than fabricated.
    func testCC1_ThreadSurface() throws {
        let app = launch(destination: "threadDetail", extra: [:])
        defer { app.terminate() }

        XCTAssertTrue(
            app.staticTexts["No threads yet"].waitForExistence(timeout: 20)
                || app.otherElements["thread-detail-pending-followup"].waitForExistence(timeout: 5),
            "Thread detail surface must render (empty-state is expected without a seeded transcript)"
        )
        capture(app, name: "cc-1-follow")
    }

    // MARK: - CC-2 / CC-3 / CC-4 / CC-5: live-thread transcript surface

    /// Richest offline-reachable transcript surface: a real user prompt bubble + the
    /// "Couldn't get a reply" no-connected-machine card + a seeded pending-approval Command
    /// card + the follow-up composer with its permission-mode pill. No tool chips, per-turn
    /// summary row, or thinking rows are reachable here (they require a live agent turn) —
    /// documented as a gap, not fabricated.
    func testCC2_ToolChipsSurface() throws {
        let app = launchApprovalSurface()
        defer { app.terminate() }
        capture(app, name: "cc-2-chips")
    }

    func testCC3_SummarySurface() throws {
        let app = launchApprovalSurface()
        defer { app.terminate() }
        capture(app, name: "cc-3-summary")
    }

    func testCC4_ThinkingSurface() throws {
        let app = launchApprovalSurface()
        defer { app.terminate() }
        capture(app, name: "cc-4-thinking")
    }

    /// The one item with real signal in the offline harness: the assistant/user bubble
    /// typography (font, leading, chrome) is genuinely on-screen here, unlike CC-2/3/4.
    func testCC5_Typography() throws {
        let app = launchApprovalSurface()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Review the pending approval"].waitForExistence(timeout: 20))
        capture(app, name: "cc-5-typography")
    }

    // MARK: - CC-8: composer

    /// Follow-up composer as seeded by the approval surface: permission-mode pill +
    /// "Follow up..." placeholder are real; the mid-run "Queue for after this turn..."
    /// placeholder and the stop (■) button only render while a run is actually in flight,
    /// which is unreachable without a live connected machine — documented as a gap.
    func testCC8_Composer() throws {
        let app = launchApprovalSurface()
        defer { app.terminate() }
        capture(app, name: "cc-8-composer")
    }

    // MARK: - Helpers

    private func launch(destination: String, extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_SEED_DEMO"] = "1"
        app.launchEnvironment["LANCER_DESTINATION"] = destination
        for (key, value) in extra {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    /// approval destination: hydrates a deterministic pending approval + drives a live
    /// thread with a fixed prompt, all without a live relay connection. Established by
    /// probing WorkspacesView.onAppear (case "approval") + RelayApprovalIngest during
    /// harness construction; see docs/test-runs/2026-07-16-cc-parity/VERDICTS.md.
    private func launchApprovalSurface() -> XCUIApplication {
        let app = launch(destination: "approval", extra: [
            "LANCER_UITEST_RESEED": "1",
            "LANCER_LIVETHREAD_PROMPT": "Review the pending approval",
        ])
        XCTAssertTrue(
            app.staticTexts["Review the pending approval"].waitForExistence(timeout: 20),
            "Approval surface must render the seeded prompt bubble"
        )
        // Best-effort: wait briefly for the seeded pending-approval card to attach; the
        // screenshot is still useful without it, so this is not a hard assertion.
        _ = app.otherElements["awaiting-approval-card"].waitForExistence(timeout: 5)
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let data = app.screenshot().pngRepresentation
        let tmpOut = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lancer-\(name)-\(Int(Date().timeIntervalSince1970)).png")
        try? data.write(to: tmpOut)

        let docsOut = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/test-runs/2026-07-16-cc-parity/lancer/\(name).png")
        try? FileManager.default.createDirectory(at: docsOut.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: docsOut)

        let pathAttachment = XCTAttachment(contentsOfFile: tmpOut)
        pathAttachment.name = "\(name)-path:\(tmpOut.path)"
        pathAttachment.lifetime = .keepAlways
        add(pathAttachment)
        print("CC_PARITY_SCREENSHOT name=\(name) path=\(tmpOut.path) docsPath=\(docsOut.path)")
    }
}
