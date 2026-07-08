import Foundation

/// What's currently relevant to surface to Siri (Phase 2, resurrected in I1)
/// — the input to `SiriRelevanceSelection`'s pure selection logic. Kept as a
/// plain, `Equatable` value so the selection rules are unit-testable without
/// standing up `AppIntents`/`IntentDonationManager`.
public struct SiriRelevanceSnapshot: Sendable, Equatable {
    public var pendingApprovalIDs: [String]
    public var activeRunIDs: [String]
    public var recentConversationID: String?
    public var onlineMachineID: String?

    public init(
        pendingApprovalIDs: [String] = [],
        activeRunIDs: [String] = [],
        recentConversationID: String? = nil,
        onlineMachineID: String? = nil
    ) {
        self.pendingApprovalIDs = pendingApprovalIDs
        self.activeRunIDs = activeRunIDs
        self.recentConversationID = recentConversationID
        self.onlineMachineID = onlineMachineID
    }
}

/// Selects which donation "kinds" should be active for a given snapshot, and
/// diffs two snapshots to find which donations have gone stale and should be
/// deleted (`IntentDonationManager.deleteDonations`). Only donates for
/// intents that already exist in the current `Lancer` app target — no
/// `OpenApprovalIntent`/`ContinueConversationIntent` (those were Phase 2's own
/// app-target intents, superseded by `DenyApprovalIntent`/
/// `OpenConversationIntent` from D2/D3).
public enum SiriRelevanceSelection {
    /// Pure selection logic — no App Intents framework calls.
    public static func donations(for snapshot: SiriRelevanceSnapshot) -> [String] {
        var kinds: [String] = []
        if let first = snapshot.pendingApprovalIDs.first {
            kinds.append("denyApproval:\(first)")
        }
        if snapshot.activeRunIDs.count == 1, let runID = snapshot.activeRunIDs.first {
            kinds.append("pauseRun:\(runID)")
            kinds.append("stopRun:\(runID)")
        }
        if let conversationID = snapshot.recentConversationID {
            kinds.append("openConversation:\(conversationID)")
        }
        if snapshot.onlineMachineID != nil {
            kinds.append("startAgentRun")
        }
        return kinds
    }

    public static func staleDonationKinds(
        previous: SiriRelevanceSnapshot,
        current: SiriRelevanceSnapshot
    ) -> [String] {
        let previousKinds = Set(donations(for: previous))
        let currentKinds = Set(donations(for: current))
        return Array(previousKinds.subtracting(currentKinds))
    }
}
