import AppIntents
import Foundation
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Deny a specific pending approval resolved through `ApprovalEntity` /
/// system disambiguation. Approve stays visual-only — never Siri-triggered.
@available(iOS 17.0, *)
public struct DenyApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Deny Approval"
    public static let description = IntentDescription("Deny a pending approval waiting for your review.")

    @Parameter(title: "Approval")
    public var approval: ApprovalEntity

    public init() {}
    public init(approval: ApprovalEntity) { self.approval = approval }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: try await Self.deny(approvalID: approval.id))
    }

    /// Shared deny logic for a resolved approval ID. Extracted so
    /// `DenyLatestApprovalIntent` can reuse it without returning this
    /// function's opaque `perform()` result type directly (opaque types
    /// don't unify across distinct `perform()` declarations).
    static func deny(approvalID: String) async throws -> IntentDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        guard let record = try await catalog.approval(id: approvalID) else {
            return "Looks like that one's already been handled, or it's not on this device."
        }

        let outcome = await CommandGateway.shared.execute(
            .respondApproval(id: record.id, decision: .rejected, editedInput: nil)
        )
        switch outcome {
        case .ok:
            return SiriIntentDialogs.denySuccess(record)
        case .transportUnavailable:
            return SiriIntentDialogs.transportUnavailable(machine: record.hostName)
        default:
            return "I wasn't able to deny \(SiriIntentSupport.approvalDialogSubject(record))."
        }
    }
}

/// Back-compat phrase for "deny the latest approval" — delegates to the same
/// safety-reducing path but only when exactly one approval is pending.
@available(iOS 17.0, *)
public struct DenyLatestApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Deny Latest Approval"
    public static let description = IntentDescription("Deny the most recent approval waiting for your review.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        let pending = try await catalog.pendingApprovals()
        if pending.isEmpty {
            return .result(dialog: "You're all caught up — nothing's waiting for review.")
        }
        if pending.count > 1 {
            return .result(dialog: "You've got \(pending.count) approvals waiting — which one should I deny?")
        }
        guard let only = pending.first else {
            return .result(dialog: "You're all caught up — nothing's waiting for review.")
        }
        return .result(dialog: try await DenyApprovalIntent.deny(approvalID: only.id))
    }
}
