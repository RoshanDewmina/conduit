#if os(iOS)
import Testing
import Foundation
import LancerCore
@testable import InboxFeature

/// Regression tests for `InboxViewModel.decide()`: a decision commits
/// synchronously regardless of risk tier (no local-auth gate — Face ID/biometric
/// approval gating was removed from this app entirely).
@MainActor
@Suite("Inbox decision commit")
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

    @Test("high-risk decision commits synchronously and hits the sink")
    func highRiskCommitsSynchronously() async {
        let approval = makeApproval(risk: .high)
        let vm = InboxViewModel(approvals: [approval])
        var sinkFired = false
        vm.decisionSink = { _, _, _, _ in sinkFired = true }

        vm.decide(approval.id, decision: .approved)

        #expect(!vm.approvals[0].isPending)
        #expect(sinkFired)
    }

    @Test("low-risk decision commits synchronously and hits the sink")
    func lowRiskCommitsSynchronously() async {
        let approval = makeApproval(risk: .low)
        let vm = InboxViewModel(approvals: [approval])
        var sinkFired = false
        vm.decisionSink = { _, _, _, _ in sinkFired = true }

        vm.decide(approval.id, decision: .rejected)

        #expect(!vm.approvals[0].isPending)
        #expect(sinkFired)
    }

    @Test("decision for an unknown id is a no-op")
    func unknownIDIsNoOp() async {
        let approval = makeApproval(risk: .high)
        let vm = InboxViewModel(approvals: [approval])
        var sinkFired = false
        vm.decisionSink = { _, _, _, _ in sinkFired = true }

        vm.decide(ApprovalID(), decision: .approved)

        #expect(vm.approvals[0].isPending)
        #expect(!sinkFired)
    }
}
#endif
