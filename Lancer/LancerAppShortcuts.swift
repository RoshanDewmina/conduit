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
            intent: DenyLatestApprovalIntent(),
            phrases: [
                "Deny the latest approval in \(.applicationName)",
            ],
            shortTitle: "Deny Latest Approval",
            systemImageName: "xmark.shield"
        )
    }
}
