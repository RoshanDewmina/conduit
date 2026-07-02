#if os(iOS)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

/// "Deny the latest approval" — the one Siri-reachable approval decision, and
/// deliberately the ONLY one: approve stays a visual, in-app/Live-Activity-tap
/// action (`ApprovalActionIntent`), never Siri-triggered. Deny is safety-reducing
/// (it can only stop an agent action, never let one through), matching the
/// planning session's explicit risk framing for what's safe to expose to voice.
@available(iOS 17.0, *)
public struct DenyLatestApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Deny Latest Approval"
    public static let description = IntentDescription("Deny the most recent approval waiting for your review.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppDatabase.openShared(),
              let latest = try? await ApprovalRepository(db).pending().first
        else {
            return .result(dialog: "No approvals are waiting.")
        }
        let outcome = await CommandGateway.shared.execute(
            .respondApproval(id: latest.id.uuidString, decision: .rejected, editedInput: nil)
        )
        switch outcome {
        case .ok: return .result(dialog: "Denied the latest approval.")
        default: return .result(dialog: "Couldn't reach the database to deny that approval.")
        }
    }
}
#endif
