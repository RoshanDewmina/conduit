#if os(iOS)
import Foundation
import AppIntents
import ConduitCore
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
        guard let id = UUID(uuidString: approvalID) else {
            return .result()
        }
        let db = try AppDatabase.openShared()
        let approvalRepo = ApprovalRepository(db)
        let auditRepo = AuditRepository(db)
        let selectedDecision: Approval.Decision = (decision == .approve) ? .approved : .rejected
        let hostUUID = UUID(uuidString: hostID) ?? UUID()

        try? await approvalRepo.decide(id: ApprovalID(id), decision: selectedDecision)
        try? await auditRepo.record(
            hostID: HostID(hostUUID),
            type: .approval,
            metadata: [
                "approvalId": approvalID,
                "hostId": hostID,
                "decision": selectedDecision.rawValue,
                "source": "liveActivityIntent",
            ]
        )
        return .result()
    }
}
#endif
