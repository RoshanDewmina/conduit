import Testing
import Foundation
@testable import ConduitCore

@Suite("Approval tool-use fields")
struct ApprovalToolUseTests {

    // MARK: - ApprovalPendingParams decoding

    @Test("decodes new tool-use fields from conduitd JSON")
    func testApprovalPendingParamsDecoding() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "method": "agent.approval.pending",
          "params": {
            "id": "11111111-0000-0000-0000-000000000001",
            "sessionId": "22222222-0000-0000-0000-000000000002",
            "agent": "claudeCode",
            "kind": "command",
            "command": "ls -la",
            "cwd": "/home/user",
            "risk": 2,
            "toolName": "bash",
            "toolUseID": "toolu_abc123",
            "agentSessionID": "session-xyz",
            "toolInput": "{\\"command\\":\\"ls -la\\"}"
          }
        }
        """.data(using: .utf8)!

        let event = DaemonEvent.decode(from: json)
        guard case .approvalPending(let p) = event else {
            Issue.record("Expected .approvalPending, got \(String(describing: event))")
            return
        }

        #expect(p.id == "11111111-0000-0000-0000-000000000001")
        #expect(p.agent == "claudeCode")
        #expect(p.kind == "command")
        #expect(p.command == "ls -la")
        #expect(p.cwd == "/home/user")
        #expect(p.risk == 2)
        #expect(p.approvalRisk == .high)

        // New tool-use fields
        #expect(p.toolName == "bash")
        #expect(p.toolUseID == "toolu_abc123")
        #expect(p.agentSessionID == "session-xyz")
        #expect(p.toolInput == "{\"command\":\"ls -la\"}")

        // Computed helpers
        #expect(p.approvalToolName == "bash")
        #expect(p.approvalToolUseID == "toolu_abc123")
        #expect(p.approvalAgentSessionID == "session-xyz")
        #expect(p.approvalToolInput == "{\"command\":\"ls -la\"}")
    }

    @Test("legacy conduitd JSON (no tool-use fields) still decodes cleanly with nil values")
    func testApprovalPendingParamsDecodingLegacy() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "method": "agent.approval.pending",
          "params": {
            "id": "33333333-0000-0000-0000-000000000003",
            "agent": "codex",
            "kind": "command",
            "command": "npm install",
            "cwd": "/repo",
            "risk": 1
          }
        }
        """.data(using: .utf8)!

        let event = DaemonEvent.decode(from: json)
        guard case .approvalPending(let p) = event else {
            Issue.record("Expected .approvalPending, got \(String(describing: event))")
            return
        }

        #expect(p.id == "33333333-0000-0000-0000-000000000003")
        #expect(p.agent == "codex")
        #expect(p.risk == 1)
        #expect(p.approvalRisk == .medium)

        // New fields must be nil — not a decode failure
        #expect(p.toolName == nil)
        #expect(p.toolUseID == nil)
        #expect(p.agentSessionID == nil)
        #expect(p.toolInput == nil)
        #expect(p.approvalToolName == nil)
        #expect(p.approvalToolUseID == nil)
        #expect(p.approvalAgentSessionID == nil)
        #expect(p.approvalToolInput == nil)
    }

    // MARK: - Approval model

    @Test("Approval can be created with tool-use fields")
    func testApprovalWithToolUseFields() throws {
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "ls -la",
            cwd: "/home/user",
            risk: .high,
            toolName: "bash",
            toolUseID: "toolu_abc123",
            agentSessionID: "session-xyz",
            toolInput: "{\"command\":\"ls -la\"}"
        )

        #expect(approval.toolName == "bash")
        #expect(approval.toolUseID == "toolu_abc123")
        #expect(approval.agentSessionID == "session-xyz")
        #expect(approval.toolInput == "{\"command\":\"ls -la\"}")
    }

    @Test("Approval created without tool-use fields has nil values")
    func testApprovalWithoutToolUseFields() throws {
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "ls",
            cwd: "/tmp",
            risk: .low
        )

        #expect(approval.toolName == nil)
        #expect(approval.toolUseID == nil)
        #expect(approval.agentSessionID == nil)
        #expect(approval.toolInput == nil)
    }
}
