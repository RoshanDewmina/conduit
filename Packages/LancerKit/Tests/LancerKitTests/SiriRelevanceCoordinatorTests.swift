import Foundation
import Testing
@testable import NotificationsKit

@Suite("SiriRelevanceSelection")
struct SiriRelevanceCoordinatorTests {
    @Test("donations include approval and run intents for actionable state")
    func donationSelection() {
        let snapshot = SiriRelevanceSnapshot(
            pendingApprovalIDs: ["approval-1", "approval-2"],
            activeRunIDs: ["run-1"],
            recentConversationID: "conv-9",
            onlineMachineID: "relay:abc"
        )
        let kinds = SiriRelevanceSelection.donations(for: snapshot)
        #expect(kinds.contains("openApproval:approval-1"))
        #expect(kinds.contains("denyApproval:approval-1"))
        #expect(kinds.contains("pauseRun:run-1"))
        #expect(kinds.contains("stopRun:run-1"))
        #expect(kinds.contains("continueConversation:conv-9"))
        #expect(kinds.contains("startAgentRun"))
    }

    @Test("multiple active runs do not donate pause/stop without disambiguation")
    func multipleRunsNoPauseDonation() {
        let snapshot = SiriRelevanceSnapshot(
            activeRunIDs: ["run-1", "run-2"]
        )
        let kinds = SiriRelevanceSelection.donations(for: snapshot)
        #expect(!kinds.contains(where: { $0.hasPrefix("pauseRun:") }))
        #expect(!kinds.contains(where: { $0.hasPrefix("stopRun:") }))
    }

    @Test("stale donations removed when approvals resolve")
    func staleRemoval() {
        let previous = SiriRelevanceSnapshot(
            pendingApprovalIDs: ["approval-1"],
            activeRunIDs: ["run-1"]
        )
        let current = SiriRelevanceSnapshot(
            pendingApprovalIDs: [],
            activeRunIDs: []
        )
        let stale = SiriRelevanceSelection.staleDonationKinds(previous: previous, current: current)
        #expect(stale.contains("openApproval:approval-1"))
        #expect(stale.contains("pauseRun:run-1"))
    }
}
