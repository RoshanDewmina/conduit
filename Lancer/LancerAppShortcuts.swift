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
            intent: SearchLancerIntent(),
            phrases: [
                "Search \(.applicationName)",
            ],
            shortTitle: "Search Lancer",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: [
                "Open \(\.$conversation) in \(.applicationName)",
                "Show conversation \(\.$conversation) in \(.applicationName)",
            ],
            shortTitle: "Open Conversation",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: ContinueConversationIntent(),
            phrases: [
                "Continue \(\.$conversation) in \(.applicationName)",
                "Keep working on \(\.$conversation) in \(.applicationName)",
            ],
            shortTitle: "Continue Conversation",
            systemImageName: "arrow.turn.up.right"
        )
        AppShortcut(
            intent: OpenMachineIntent(),
            phrases: [
                "Open \(\.$machine) in \(.applicationName)",
                "Show machine \(\.$machine) in \(.applicationName)",
            ],
            shortTitle: "Open Machine",
            systemImageName: "desktopcomputer"
        )
        AppShortcut(
            intent: OpenApprovalIntent(),
            phrases: [
                "Open approval \(\.$approval) in \(.applicationName)",
                "Review \(\.$approval) in \(.applicationName)",
            ],
            shortTitle: "Open Approval",
            systemImageName: "checkmark.shield"
        )
        AppShortcut(
            intent: PauseRunIntent(),
            phrases: [
                "Pause \(\.$run) in \(.applicationName)",
                "Pause the agent in \(.applicationName)",
                "Pause my \(.applicationName) session",
            ],
            shortTitle: "Pause Run",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: StopRunIntent(),
            phrases: [
                "Stop \(\.$run) in \(.applicationName)",
                "Stop the agent in \(.applicationName)",
                "Stop my \(.applicationName) session",
            ],
            shortTitle: "Stop Run",
            systemImageName: "stop.circle"
        )
        // `DenyApprovalIntent(approval:)` covers both the entity-disambiguated
        // and single-pending-approval cases (it resolves via `ApprovalEntity`
        // just like every other entity-parameterized shortcut here); a
        // separate `DenyLatestApprovalIntent` shortcut would push this list
        // to 11, over Apple's 10-per-app App Shortcuts cap. The intent itself
        // still exists for direct invocation — it's just not a Siri phrase.
        AppShortcut(
            intent: DenyApprovalIntent(),
            phrases: [
                "Deny \(\.$approval) in \(.applicationName)",
                "Deny the latest approval in \(.applicationName)",
            ],
            shortTitle: "Deny Approval",
            systemImageName: "xmark.shield"
        )
    }
}
