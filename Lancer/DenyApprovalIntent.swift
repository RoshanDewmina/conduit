import AppIntents
import Foundation
import IntentsKit
import LancerCore
import PersistenceKit
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// "Deny an approval" — the one Siri-reachable approval decision, and
/// deliberately the ONLY one: approve stays a visual, in-app/Live-Activity-tap
/// action (`ApprovalActionIntent`), never Siri-triggered. Deny is safety-reducing
/// (it can only stop an agent action, never let one through), matching the
/// planning session's explicit risk framing for what's safe to expose to voice.
/// Renamed from `DenyLatestApprovalIntent` (D2): gains an `ApprovalEntity`
/// parameter so a phrase can name a specific approval via `ApprovalEntityQuery`
/// instead of blindly acting on `pending().first` (which also audited with an
/// empty hostID). The original "deny the latest approval" phrase still works —
/// leaving `approval` unspoken resolves to the most recent pending one.
@available(iOS 17.0, *)
public struct DenyApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Deny Approval"
    public static let description = IntentDescription("Deny an approval waiting for your review — the most recent one if you don't name another.")

    @Parameter(title: "Approval")
    public var approval: ApprovalEntity?

    public init() {}
    public init(approval: ApprovalEntity? = nil) {
        self.approval = approval
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let resolved: ApprovalEntity
        if let approval {
            resolved = approval
        } else {
            switch try await ApprovalEntityQuery().resolveMostRecentPending() {
            case .none:
                return .result(dialog: "No approvals are waiting.")
            case .mostRecent(let entity):
                resolved = entity
            }
        }
        // `resolved.title` already reads "'<action>' · <risk> · <host>" — machine
        // + title + risk in one line, so confirmation and result reuse it verbatim.
        try await requestConfirmation(dialog: "Deny \(resolved.title)?")
        guard let db = try? IntentsKitDependencies.database() else {
            return .result(dialog: "Couldn't reach the database to deny that approval.")
        }
        // Same route as ApprovalActionIntent (the Live Activity buttons): enqueue
        // persists first-decision-wins, audits, and forwards — passing the entity's
        // resolved hostID instead of CommandGateway's hardcoded "" so the audit row
        // carries the real host.
        await ApprovalRelay.shared.enqueue(
            approvalID: resolved.id,
            decision: .rejected,
            db: db,
            hostID: resolved.hostID ?? ""
        )
        return .result(dialog: "Denied \(resolved.title).")
    }
}
