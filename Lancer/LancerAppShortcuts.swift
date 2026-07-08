import AppIntents
import SessionFeature

/// Registers Siri/Shortcuts/Spotlight phrases for the read-only and
/// safety-reducing intents only. `ApprovalActionIntent` (approve/reject) is
/// deliberately NEVER registered here — approving an agent's action must stay a
/// visual, in-app or Live-Activity-tap action, not a voice command. This is an
/// explicit product/security decision from the planning session, not an
/// oversight — do not add a Siri-triggerable approve/allow-always phrase.
///
/// Lives in the `Lancer` app target, NOT a linked SPM library (SessionFeature) —
/// `AppShortcutsProvider` is only discovered by Xcode's app-intents metadata
/// merge step when it's reachable from the app's own compiled module. The
/// individual `AppIntent` conformances below (`PauseRunIntent` etc.) merge fine
/// from SessionFeature; only the shortcuts/phrases registration itself needs to
/// live here — confirmed via the build log (`appintentsnltrainingprocessor:
/// "No AppShortcuts found - Skipping"`) when this type lived in SessionFeature.
@available(iOS 17.0, *)
public struct LancerAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AgentStatusQueryIntent(),
            phrases: [
                "How many agents are running on \(.applicationName)",
                "Check agent status in \(.applicationName)",
            ],
            shortTitle: "Agent Status",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
        AppShortcut(
            intent: PendingApprovalsQueryIntent(),
            phrases: [
                "Are any approvals waiting in \(.applicationName)",
                "Check pending approvals in \(.applicationName)",
            ],
            shortTitle: "Pending Approvals",
            systemImageName: "checkmark.shield"
        )
        AppShortcut(
            intent: PauseRunIntent(),
            phrases: [
                "Pause the agent in \(.applicationName)",
                "Pause my \(.applicationName) session",
            ],
            shortTitle: "Pause Run",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: StopRunIntent(),
            phrases: [
                "Stop the agent in \(.applicationName)",
                "Stop my \(.applicationName) session",
            ],
            shortTitle: "Stop Run",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: DenyApprovalIntent(),
            phrases: [
                // Pre-D2 phrase kept verbatim: with no approval named, the intent
                // resolves to the most recent pending one, so the old habit still works.
                "Deny the latest approval in \(.applicationName)",
                "Deny an approval in \(.applicationName)",
            ],
            shortTitle: "Deny Approval",
            systemImageName: "xmark.shield"
        )
        AppShortcut(
            intent: SearchLancerIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search my \(.applicationName) conversations",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: [
                "Open a conversation in \(.applicationName)",
            ],
            shortTitle: "Open Conversation",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        // Siri Phase 2 (resurrected in I1): the one shortcut that dispatches a
        // NEW run rather than controlling/querying an existing one. Always
        // confirms machine/agent/workspace/prompt before anything runs
        // (`StartAgentRunIntent.perform()`), and only targets relay-paired
        // machines — never an approval, never auto-run.
        AppShortcut(
            intent: StartAgentRunIntent(),
            phrases: [
                "Start an agent run in \(.applicationName)",
                "Start Claude Code in \(.applicationName)",
            ],
            shortTitle: "Start Agent Run",
            systemImageName: "play.circle"
        )
        // AnswerQuestionIntent requires iOS 18 (see its own doc comment for
        // why) — "if statements in an AppShortcutsBuilder can only be used
        // with #available clauses" per the AppIntents SDK, which is exactly
        // this case.
        if #available(iOS 18.0, *) {
            AppShortcut(
                intent: AnswerQuestionIntent(),
                phrases: [
                    "Answer the question in \(.applicationName)",
                    "Answer the agent's question in \(.applicationName)",
                ],
                shortTitle: "Answer Question",
                systemImageName: "questionmark.bubble"
            )
        }
    }
}
