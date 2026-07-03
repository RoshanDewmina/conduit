import Foundation

/// Selects which intents/entities to surface proactively. Injectable for unit tests.
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

public enum SiriRelevanceSelection {
    /// Pure selection logic — no App Intents framework calls.
    public static func donations(for snapshot: SiriRelevanceSnapshot) -> [String] {
        var kinds: [String] = []
        if let first = snapshot.pendingApprovalIDs.first {
            kinds.append("openApproval:\(first)")
            kinds.append("denyApproval:\(first)")
        }
        if snapshot.activeRunIDs.count == 1, let runID = snapshot.activeRunIDs.first {
            kinds.append("pauseRun:\(runID)")
            kinds.append("stopRun:\(runID)")
        }
        if let conversationID = snapshot.recentConversationID {
            kinds.append("continueConversation:\(conversationID)")
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
