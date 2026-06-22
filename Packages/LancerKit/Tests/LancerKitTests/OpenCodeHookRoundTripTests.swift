import Testing
import Foundation
@testable import LancerCore

@Suite("OpenCode hook inbox round-trip")
struct OpenCodeHookRoundTripTests {

    /// Wire JSON produced by lancerd `marshalPendingNotification` for an OpenCode
    /// PreToolUse fixture (see daemon/lancerd/testdata/opencode/pretooluse-bash.json).
    @Test("OpenCode pending notification decodes to inbox Approval fields")
    func opencodePendingNotificationDecodes() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "method": "agent.approval.pending",
          "params": {
            "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "agent": "opencode",
            "kind": "command",
            "command": "npm test",
            "cwd": "/Users/dev/my-app",
            "risk": 2,
            "toolName": "Bash",
            "toolUseID": "tu_opencode_01",
            "agentSessionID": "ses_opencode_fixture_01",
            "toolInput": "{\\"command\\":\\"npm test\\"}"
          }
        }
        """.data(using: .utf8)!

        let event = DaemonEvent.decode(from: json)
        guard case .approvalPending(let params) = event else {
            Issue.record("expected approvalPending")
            return
        }

        #expect(params.approvalAgent == .opencode)
        #expect(params.approvalKind == .command)
        #expect(params.command == "npm test")
        #expect(params.approvalToolName == "Bash")
        #expect(params.approvalAgentSessionID == "ses_opencode_fixture_01")

        let approval = Approval(
            id: ApprovalID(UUID(uuidString: params.id) ?? UUID()),
            sessionID: SessionID(),
            agent: params.approvalAgent,
            kind: params.approvalKind,
            command: params.command,
            cwd: params.cwd,
            risk: params.approvalRisk,
            toolName: params.approvalToolName,
            toolUseID: params.approvalToolUseID,
            agentSessionID: params.approvalAgentSessionID,
            toolInput: params.approvalToolInput
        )
        #expect(approval.agent == .opencode)
        #expect(approval.command == "npm test")
    }
}
