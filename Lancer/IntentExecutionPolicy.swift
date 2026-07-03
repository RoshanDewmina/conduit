import AppIntents
import SessionFeature

// Pins App Intent execution to the main app binary for DB/Keychain/relay paths,
// and to the widget extension for Live Activity approval taps (iOS 27+).

@available(iOS 27.0, *)
protocol LancerMainAppExecutionIntent: AppIntent {}

@available(iOS 27.0, *)
extension LancerMainAppExecutionIntent {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension SearchLancerIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension OpenConversationIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension OpenMachineIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension OpenApprovalIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension ContinueConversationIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension StartAgentRunIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension PauseRunIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension StopRunIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension DenyApprovalIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension DenyLatestApprovalIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension AgentStatusQueryIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension PendingApprovalsQueryIntent: LancerMainAppExecutionIntent {}

@available(iOS 27.0, *)
extension MachineEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension RunEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension ApprovalEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension ConversationEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension WorkspaceEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
}

@available(iOS 27.0, *)
extension ApprovalActionIntent {
    public static var allowedExecutionTargets: IntentExecutionTargets { .widgetKitExtension }
}
