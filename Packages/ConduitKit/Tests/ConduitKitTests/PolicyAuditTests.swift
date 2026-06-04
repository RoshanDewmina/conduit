import Testing
import Foundation
@testable import ConduitCore

@Suite("Policy + audit protocol (WS-B)")
struct PolicyAuditTests {

    @Test("decodes blast-radius on approval pending")
    func blastRadiusDecode() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "method": "agent.approval.pending",
          "params": {
            "id": "a1",
            "agent": "claudeCode",
            "kind": "patch",
            "command": "apply",
            "cwd": "/repo",
            "risk": 2,
            "files": ["src/a.go", "src/b.go"],
            "touchesGit": true,
            "touchesNetwork": false,
            "matchedRule": "ask-patch"
          }
        }
        """.data(using: .utf8)!

        guard case .approvalPending(let p) = DaemonEvent.decode(from: json) else {
            Issue.record("expected approvalPending")
            return
        }
        #expect(p.files?.count == 2)
        #expect(p.touchesGit == true)
        #expect(p.matchedRule == "ask-patch")
        #expect(p.blastRadius.files?.first == "src/a.go")
    }

    @Test("audit tail result decodes")
    func auditTailDecode() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": 1,
          "result": {
            "entries": [{
              "timestamp": "2026-06-04T12:00:00Z",
              "action": "auto-allow",
              "agent": "codex",
              "rule": "allow-low-shell",
              "command": "ls"
            }]
          }
        }
        """.data(using: .utf8)!
        guard let response = DaemonRPCResponse.decode(from: json) else {
            Issue.record("decode failed")
            return
        }
        guard case .auditTail(let tail) = response else {
            Issue.record("expected auditTail")
            return
        }
        #expect(tail.entries.first?.action == "auto-allow")
    }

    @Test("policy get result decodes")
    func policyGetDecode() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": 2,
          "result": {
            "default": "ask",
            "documents": [{ "default": "ask", "rules": [{ "id": "x", "effect": "deny", "kind": "network" }] }]
          }
        }
        """.data(using: .utf8)!
        guard case .policyGet(let pol)? = DaemonRPCResponse.decode(from: json) else {
            Issue.record("expected policyGet")
            return
        }
        #expect(pol.default == "ask")
        #expect(pol.documents?.first?.rules?.first?.effect == "deny")
    }

    @Test("Approval stores blast radius")
    func approvalBlastRadius() {
        let br = ApprovalBlastRadius(files: ["x.swift"], touchesGit: true, matchedRule: "ask-patch")
        let a = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .patch,
            cwd: "/r",
            risk: .high,
            blastRadius: br
        )
        #expect(a.blastRadius?.files?.first == "x.swift")
    }
}
