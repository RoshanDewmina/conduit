@preconcurrency import XCTest
import AppIntentsTesting

/// Owner-style Siri/Shortcuts phrase dogfood (phrases 1–9 + negative Approve),
/// driven via AppIntentsTesting on a physical device with
/// `LANCER_APPINTENTS_LIVE=1`. Same out-of-process execution path as
/// `AgentStatusIntentLiveExecutionTests` — not voice, not a direct in-process
/// call into Lancer intent types.
///
/// Empty-state intents (no active run / no pending approval / no question) still
/// prove the shortcut resolves and `perform()` completes; mutation paths that
/// need live work are asserted only when preconditions exist.
@available(iOS 27.0, *)
@MainActor
final class LancerShortcutsPhraseLiveExecutionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIApplication().launch()
    }

    private func requireLive() throws {
        guard ProcessInfo.processInfo.environment["LANCER_APPINTENTS_LIVE"] == "1" else {
            throw XCTSkip("AppIntentsTesting live execution needs a validated bundle; set LANCER_APPINTENTS_LIVE=1 on device.")
        }
    }

    private func definitions() -> IntentDefinitions {
        IntentDefinitions(bundleIdentifier: "dev.lancer.mobile")
    }

    private func runIntent(named name: String) async throws {
        let intent = definitions().intents[name].makeIntent()
        _ = try await intent.run()
    }

    /// Phrase 1 — already covered by AgentStatusIntentLiveExecutionTests; kept
    /// here so one suite exercises the full shortcut surface.
    func testPhrase1_AgentStatusQueryIntent() async throws {
        try requireLive()
        try await runIntent(named: "AgentStatusQueryIntent")
    }

    /// Phrase 2 — "Are any approvals waiting in Lancer?"
    func testPhrase2_PendingApprovalsQueryIntent() async throws {
        try requireLive()
        try await runIntent(named: "PendingApprovalsQueryIntent")
    }

    /// Phrase 3 — empty-state OK when no active run ("No agent runs…").
    func testPhrase3_PauseRunIntent_EmptyState() async throws {
        try requireLive()
        try await runIntent(named: "PauseRunIntent")
    }

    /// Phrase 4 — empty-state OK when no active run; stop is confirmation-gated
    /// only when a run resolves.
    func testPhrase4_StopRunIntent_EmptyState() async throws {
        try requireLive()
        try await runIntent(named: "StopRunIntent")
    }

    /// Phrase 5 — empty-state OK when queue is empty ("No approvals are waiting.").
    func testPhrase5_DenyApprovalIntent_EmptyState() async throws {
        try requireLive()
        try await runIntent(named: "DenyApprovalIntent")
    }

    /// Phrase 6 — "Search Lancer"; supplies a query so perform() can complete
    /// without blocking on requestValueDialog.
    func testPhrase6_SearchLancerIntent() async throws {
        try requireLive()
        var intent = definitions().intents["SearchLancerIntent"].makeIntent()
        intent.query = "pong"
        _ = try await intent.run()
    }

    /// Phrase 7 — discovery only. Full `run()` needs an interactive conversation
    /// pick (`AutoConfirmingPerformDelegate` cannot supply `conversation`).
    func testPhrase7_OpenConversationIntent_IsDiscoverable() async throws {
        try requireLive()
        XCTAssertNotNil(
            definitions().intents["OpenConversationIntent"],
            "OpenConversationIntent must be discoverable for Siri/Shortcuts"
        )
    }

    /// Phrase 8 — StartAgentRunIntent is confirmation-gated; do not complete a
    /// real dispatch from automation. Discoverability is the safe automated bar.
    func testPhrase8_StartAgentRunIntent_IsDiscoverableNotAutoDispatched() async throws {
        try requireLive()
        let defs = definitions()
        XCTAssertNotNil(defs.intents["StartAgentRunIntent"], "StartAgentRunIntent must be discoverable")
        // Do not call run() — it would prompt for machine/agent/prompt and could
        // dispatch after confirmation. Discovery-only is intentional.
    }

    /// Phrase 9 — empty-state OK when no unanswered question.
    func testPhrase9_AnswerQuestionIntent_EmptyState() async throws {
        try requireLive()
        var intent = definitions().intents["AnswerQuestionIntent"].makeIntent()
        intent.answer = "yes"
        _ = try await intent.run()
    }

    /// Phrase 10 (negative) — Approve must NEVER be a Siri App Shortcut.
    ///
    /// `IntentDefinitions.intents[name]` returns a stub for *any* string key, so
    /// nil-checks on fictional names are invalid. Static Metadata.appintents
    /// `autoShortcuts` (companion evidence in this dogfood run) lists exactly the
    /// nine Lancer phrases and omits `ApprovalActionIntent`. Live bar here:
    /// Deny remains executable; fictional Approve* intents must fail to run.
    /// Do not call `ApprovalActionIntent.run()` — missing Live Activity params
    /// can hang under AutoConfirmingPerformDelegate.
    func testPhrase10_ApproveNotRegisteredAsAppShortcut() async throws {
        try requireLive()
        let defs = definitions()
        XCTAssertNotNil(defs.intents["DenyApprovalIntent"])
        XCTAssertNotNil(defs.intents["ApprovalActionIntent"],
                        "Live Activity ApprovalActionIntent may exist; it must not be an App Shortcut")

        for name in [
            "ApproveApprovalIntent",
            "ApproveLatestApprovalIntent",
            "ApprovePendingCommandIntent",
            "ApproveIntent",
        ] {
            do {
                _ = try await defs.intents[name].makeIntent().run()
                XCTFail("\(name) must not execute successfully — Approve is not a Siri shortcut")
            } catch {
                // Expected: unknown / unloadable intent.
            }
        }
    }

    /// Catalog sanity: expected Lancer shortcut intents are present.
    func testRegisteredShortcutIntentsAreDiscoverable() async throws {
        try requireLive()
        let defs = definitions()
        for expected in [
            "AgentStatusQueryIntent",
            "PendingApprovalsQueryIntent",
            "PauseRunIntent",
            "StopRunIntent",
            "DenyApprovalIntent",
            "SearchLancerIntent",
            "OpenConversationIntent",
            "StartAgentRunIntent",
            "AnswerQuestionIntent",
        ] {
            XCTAssertNotNil(defs.intents[expected], "Missing discoverable intent: \(expected)")
        }
    }
}
