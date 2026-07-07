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

/// Risk tier carried from Live Activity `pendingApprovalRisk` (0…3, same scale as
/// `Approval.Risk`). Optional until the widget passes it; when absent the relay
/// reads the persisted row and fails closed on unknown risk.
@available(iOS 17.0, *)
public enum ApprovalIntentRisk: Int, AppEnum, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval Risk")
    public static let caseDisplayRepresentations: [ApprovalIntentRisk: DisplayRepresentation] = [
        .low: "Low",
        .medium: "Medium",
        .high: "High",
        .critical: "Critical",
    ]

    public var approvalRisk: Approval.Risk {
        Approval.Risk(rawValue: rawValue) ?? .high
    }
}

/// Resolves the App Intents authentication policy for lock-screen approval taps.
/// Approve (safety-increasing) requires authentication; reject is safety-reducing
/// and may stay unauthenticated — matching `LancerAppShortcuts` (Siri never
/// approves; deny-only is voice-safe). `authenticationPolicy` on `AppIntent` is
/// static, so approve/reject share one policy until T1 splits intent variants;
/// the T0 baseline applies `.requiresAuthentication` on approve paths (unknown
/// risk fails closed). `ApprovalRelay` remains the in-app backstop.
@available(iOS 17.0, *)
public enum ApprovalActionIntentPolicy {
    public static func requiresAuthentication(
        decision: ApprovalIntentDecision,
        risk: Approval.Risk?
    ) -> Bool {
        switch decision {
        case .reject:
            return false
        case .approve:
            guard let risk else { return true }
            return risk >= .high
        }
    }

    public static func authenticationPolicy(
        decision: ApprovalIntentDecision,
        risk: Approval.Risk?
    ) -> IntentAuthenticationPolicy {
        requiresAuthentication(decision: decision, risk: risk)
            ? .requiresAuthentication
            : .alwaysAllowed
    }
}

@available(iOS 17.0, *)
public struct ApprovalActionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Respond to Approval"
    public static let openAppWhenRun: Bool = true

    /// Lock-screen / Dynamic Island approve taps must not run without
    /// system-mediated authentication. Reject may stay on `.alwaysAllowed` once
    /// approve/reject split into separate intent types (T1); until then this
    /// baseline gates every Live Activity intent invocation — reject over-gates
    /// slightly but stays safety-reducing.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Approval ID")
    public var approvalID: String

    @Parameter(title: "Host ID")
    public var hostID: String

    @Parameter(title: "Decision")
    public var decision: ApprovalIntentDecision

    @Parameter(title: "Risk Level")
    public var riskLevel: ApprovalIntentRisk?

    public init() {}

    public init(
        approvalID: String,
        hostID: String,
        decision: ApprovalIntentDecision,
        riskLevel: ApprovalIntentRisk? = nil
    ) {
        self.approvalID = approvalID
        self.hostID = hostID
        self.decision = decision
        self.riskLevel = riskLevel
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
