#if os(iOS)
import Testing
import Foundation
import LancerCore
@testable import InboxFeature

/// Regression tests for the local-auth gate on approval decisions: a
/// high/critical-risk approve/reject whose unlock fails (locked device,
/// cancelled prompt) must leave the gate pending and never reach the wire.
@MainActor
@Suite("Inbox decision local-auth gate")
struct InboxDecisionGateTests {

    private func makeApproval(risk: Approval.Risk) -> Approval {
        Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "sudo rm -rf /var/data",
            cwd: "/tmp",
            risk: risk
        )
    }

    private func drainMainQueue() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("high-risk decision with failed unlock stays pending and never hits the sink")
    func highRiskFailedUnlockBlocks() async {
        let approval = makeApproval(risk: .high)
        let vm = InboxViewModel(approvals: [approval])
        vm.decisionAuthorizer = { _ in false }
        var sinkFired = false
        vm.decisionSink = { _, _, _, _ in sinkFired = true }

        vm.decide(approval.id, decision: .approved)
        await drainMainQueue()

        #expect(vm.approvals[0].isPending)
        #expect(!sinkFired)
    }

    @Test("high-risk decision with successful unlock commits")
    func highRiskUnlockedCommits() async {
        let approval = makeApproval(risk: .high)
        let vm = InboxViewModel(approvals: [approval])
        var prompted = false
        vm.decisionAuthorizer = { _ in
            prompted = true
            return true
        }
        var sinkFired = false
        vm.decisionSink = { _, _, _, _ in sinkFired = true }

        vm.decide(approval.id, decision: .approved)
        await drainMainQueue()

        #expect(prompted)
        #expect(!vm.approvals[0].isPending)
        #expect(sinkFired)
    }

    @Test("low-risk decision commits synchronously without consulting the authorizer")
    func lowRiskSkipsGate() async {
        let approval = makeApproval(risk: .low)
        let vm = InboxViewModel(approvals: [approval])
        vm.decisionAuthorizer = { _ in
            Issue.record("authorizer must not run for a low-risk decision")
            return false
        }

        vm.decide(approval.id, decision: .rejected)

        #expect(!vm.approvals[0].isPending)
    }
}
#endif
