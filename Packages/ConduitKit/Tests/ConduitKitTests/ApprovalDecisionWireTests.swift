import Testing
@testable import SSHTransport
import ConduitCore

#if os(iOS)
@Suite("Approval decision wire format")
struct ApprovalDecisionWireTests {
    @Test("approvedAlways maps to approveAlways decision string")
    func approvedAlwaysDecision() {
        let mapped = DaemonChannel.decisionWireValue(for: .approvedAlways)
        #expect(mapped == "approveAlways")
    }

    @Test("approved maps to approve")
    func approvedDecision() {
        #expect(DaemonChannel.decisionWireValue(for: .approved) == "approve")
    }

    @Test("rejected maps to deny")
    func rejectedDecision() {
        #expect(DaemonChannel.decisionWireValue(for: .rejected) == "deny")
    }
}
#endif
