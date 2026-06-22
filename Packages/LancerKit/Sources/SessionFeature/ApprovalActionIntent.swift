#if os(iOS)
import Foundation
import AppIntents
import LancerCore
import PersistenceKit

@available(iOS 17.0, *)
public enum ApprovalIntentDecision: String, AppEnum, Sendable {
    case approve
    case reject

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval Decision")
    public static let caseDisplayRepresentations: [ApprovalIntentDecision: DisplayRepresentation] = [
        .approve: "Approve",
        .reject: "Reject",
    ]
}

@available(iOS 17.0, *)
public struct ApprovalActionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Respond to Approval"
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Approval ID")
    public var approvalID: String

    @Parameter(title: "Host ID")
    public var hostID: String

    @Parameter(title: "Decision")
    public var decision: ApprovalIntentDecision

    public init() {}

    public init(approvalID: String, hostID: String, decision: ApprovalIntentDecision) {
        self.approvalID = approvalID
        self.hostID = hostID
        self.decision = decision
    }

    public func perform() async throws -> some IntentResult {
        guard UUID(uuidString: approvalID) != nil else {
            return .result()
        }
        let db = try AppDatabase.openShared()
        let selectedDecision: Approval.Decision = (decision == .approve) ? .approved : .rejected

        // Route through ApprovalRelay so the decision is forwarded to lancerd
        // (via the active DaemonChannel) in addition to being persisted locally.
        // If the channel is not yet attached the relay queues the decision for
        // drain when the app becomes active.
        await ApprovalRelay.shared.enqueue(
            approvalID: approvalID,
            decision: selectedDecision,
            db: db,
            hostID: hostID
        )
        return .result()
    }
}
#endif
