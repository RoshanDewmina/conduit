import Foundation
import Testing
import LancerCore

@Suite("ChatTurn.Status.fromHostStatus")
struct ChatTurnHostStatusTests {
    @Test("maps daemon process-lifecycle statuses onto phone turn vocabulary")
    func mapsHostStatuses() {
        #expect(ChatTurn.Status.fromHostStatus("running") == .running)
        #expect(ChatTurn.Status.fromHostStatus("started") == .running)
        #expect(ChatTurn.Status.fromHostStatus("needsApproval") == .running)

        #expect(ChatTurn.Status.fromHostStatus("completed") == .completed)
        #expect(ChatTurn.Status.fromHostStatus("exited") == .completed)

        #expect(ChatTurn.Status.fromHostStatus("failed") == .failed)
        #expect(ChatTurn.Status.fromHostStatus("error") == .failed)
        #expect(ChatTurn.Status.fromHostStatus("cancelled") == .failed)
        #expect(ChatTurn.Status.fromHostStatus("denied") == .failed)
        #expect(ChatTurn.Status.fromHostStatus("budgetExceeded") == .failed)

        // Unknown labels stay fail-closed as running so we keep polling rather
        // than falsely clearing Working… on a status we don't understand.
        #expect(ChatTurn.Status.fromHostStatus("mystery") == .running)
    }
}
