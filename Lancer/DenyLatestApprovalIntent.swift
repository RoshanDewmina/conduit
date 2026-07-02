import AppIntents
import Foundation
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
///
/// `approval` is an optional `ApprovalEntity` (per the SDK's own
/// `@Parameter`-with-`default` pattern for entity parameters,
/// `AppIntents.swiftinterface:336`): when Siri/Shortcuts resolves a specific
/// approval (via `ApprovalEntityQuery`, e.g. the user names which one, or picks
/// from a disambiguation list), it arrives non-nil and that exact approval is
/// denied — fixing the always-newest/empty-`hostID` ambiguity bug. With no
/// entity resolved (a bare "deny the latest approval" phrase, or an older
/// Shortcut with no parameter bound), it falls back to "the most recent
/// pending approval" exactly as before.
@available(iOS 17.0, *)
public struct DenyLatestApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Deny Latest Approval"
    public static let description = IntentDescription("Deny the most recent approval waiting for your review.")

    @Parameter(title: "Approval")
    public var approval: ApprovalEntity?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let targetID: String
        if let approval {
            targetID = approval.id
        } else {
            guard let db = try? AppDatabase.openShared(),
                  let latest = try? await ApprovalRepository(db).pending().first
            else {
                return .result(dialog: "No approvals are waiting.")
            }
            targetID = latest.id.uuidString
        }
        let outcome = await CommandGateway.shared.execute(
            .respondApproval(id: targetID, decision: .rejected, editedInput: nil)
        )
        switch outcome {
        case .ok: return .result(dialog: "Denied the approval.")
        default: return .result(dialog: "Couldn't reach the database to deny that approval.")
        }
    }
}
