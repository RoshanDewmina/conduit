import Testing
import Foundation
@testable import SSHTransport
import LancerCore

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

    // MARK: - Response envelope contract (regression: the app↔daemon decision wire)

    @Test("response envelope uses the agent.approval.response method")
    func envelopeMethod() {
        let env = DaemonChannel.responseEnvelope(approvalId: "abc", decision: .approved)
        #expect(env["method"] as? String == "agent.approval.response")
        #expect(env["jsonrpc"] as? String == "2.0")
    }

    // Regression for the UUID-case bug: Swift's UUID.uuidString is UPPERCASE and
    // is carried VERBATIM in the response. The daemon must match it
    // case-insensitively (it once did a case-sensitive lookup → every decision
    // missed → agent hung to timeout → auto-deny). This pins the Swift side of
    // that contract: we send the id exactly as given, uppercase and all.
    @Test("response envelope carries the approval id verbatim (uppercase UUID)")
    func envelopeCarriesUppercaseIdVerbatim() {
        let id = UUID().uuidString                  // canonical Swift casing: UPPERCASE
        #expect(id == id.uppercased(), "precondition: UUID.uuidString is uppercase")
        let env = DaemonChannel.responseEnvelope(approvalId: id, decision: .approved)
        let params = env["params"] as? [String: Any]
        #expect(params?["approvalId"] as? String == id, "id must be sent unchanged, not lowercased")
        #expect(params?["decision"] as? String == "approve")
    }

    @Test("response envelope omits editedToolInput when nil or empty, includes it otherwise")
    func envelopeEditedToolInput() {
        let none = DaemonChannel.responseEnvelope(approvalId: "x", decision: .approved)
        #expect((none["params"] as? [String: Any])?["editedToolInput"] == nil)

        let empty = DaemonChannel.responseEnvelope(approvalId: "x", decision: .approved, editedToolInput: "")
        #expect((empty["params"] as? [String: Any])?["editedToolInput"] == nil)

        let edited = DaemonChannel.responseEnvelope(approvalId: "x", decision: .approved, editedToolInput: "ls -la")
        #expect((edited["params"] as? [String: Any])?["editedToolInput"] as? String == "ls -la")
    }

    // The envelope must survive JSON serialization (it's handed to
    // JSONSerialization before framing) — a non-serializable value would be
    // silently dropped at runtime.
    @Test("response envelope is JSON-serializable")
    func envelopeSerializes() throws {
        let env = DaemonChannel.responseEnvelope(
            approvalId: UUID().uuidString, decision: .approvedAlways, editedToolInput: "echo hi"
        )
        let data = try JSONSerialization.data(withJSONObject: env)
        #expect(!data.isEmpty)
    }
}
#endif

// NOTE — documented test gap (SessionViewModel.trustHostKey → onReconnected):
// The companion fix to the UUID-case bug arms the lancerd channel after a
// first-connect TOFU trust. That success path is NOT covered by a unit test:
// it requires SessionViewModel.connect() to reach .connected, which drives a
// real Citadel SSH connect (SSHSession is a concrete actor with no fake seam),
// and pendingHostKeyFingerprint is private(set), only set by a live
// hostKeyUnknown throw. It is covered end-to-end in
// docs/test-runs/2026-06-12-live-loop-pass1.md. Unit coverage would require
// protocolizing SSHSession — deferred to avoid touching the live-session path.
