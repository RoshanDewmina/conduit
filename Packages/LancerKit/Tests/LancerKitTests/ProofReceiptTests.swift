import Foundation
import Testing
@testable import LancerCore

/// Cross-language contract test: C1 `lancer.proof/v0` fixture from
/// `docs/product/artifacts/2026-07-07-layers-0-3-spec.html` (Receipt tab).
@Suite struct ProofReceiptTests {
  @Test("C1 fixture JSON round-trips through Codable")
  func c1FixtureRoundTrip() throws {
    let wireJSON = """
    {
      "schema": "lancer.proof/v0",
      "runId": "r-c1-fixture",
      "conversationId": "c-c1-fixture",
      "agent": "claude",
      "model": "sonnet",
      "startedAt": "2026-07-07T01:00:00Z",
      "endedAt": "2026-07-07T01:05:00Z",
      "status": "completed",
      "exitCode": 0,
      "contract": {
        "goal": "Add proof receipt decode plumbing",
        "doneCriteria": ["ProofReceipt decodes", "DaemonEvent routes receipt"],
        "validationCommands": ["cd Packages/LancerKit && swift test --filter ProofReceiptTests"]
      },
      "commands": [
        {
          "command": "go test ./...",
          "exitCode": 0,
          "kind": "test",
          "startedAt": "2026-07-07T01:04:00Z"
        }
      ],
      "filesTouched": [
        { "path": "Packages/LancerKit/Sources/LancerCore/ProofReceipt.swift", "additions": 12, "deletions": 3 }
      ],
      "tests": { "ran": true, "passed": 42, "failed": 0 },
      "criteria": [
        {
          "text": "ProofReceiptTests round-trip C1 fixture JSON",
          "status": "met",
          "evidence": "cd Packages/LancerKit && swift test --filter ProofReceiptTests"
        }
      ],
      "git": {
        "startRef": "abc123",
        "endRef": "def456",
        "dirtyAtStart": false,
        "worktreePath": "/Users/roshan/project/.lancer/worktrees/run-1"
      },
      "confidence": {
        "commands": "complete",
        "files": "complete",
        "tests": "bestEffort"
      },
      "resume": {
        "agent": "claude",
        "vendorSessionId": "sess-c1-fixture"
      },
      "answersReserved": null,
      "truncated": false
    }
    """
    let data = Data(wireJSON.utf8)
    let decoded = try JSONDecoder().decode(ProofReceipt.self, from: data)

    #expect(decoded.schema == "lancer.proof/v0")
    #expect(decoded.runId == "r-c1-fixture")
    #expect(decoded.conversationId == "c-c1-fixture")
    #expect(decoded.agent == "claude")
    #expect(decoded.model == "sonnet")
    #expect(decoded.status == "completed")
    #expect(decoded.exitCode == 0)
    #expect(decoded.contract?.goal == "Add proof receipt decode plumbing")
    #expect(decoded.contract?.doneCriteria.count == 2)
    #expect(decoded.contract?.validationCommands.first?.contains("ProofReceiptTests") == true)
    #expect(decoded.commands?.count == 1)
    #expect(decoded.commands?.first?.kind == "test")
    #expect(decoded.filesTouched?.first?.additions == 12)
    #expect(decoded.tests?.passed == 42)
    #expect(decoded.criteria?.first?.status == .met)
    #expect(decoded.confidence?.commands == "complete")
    #expect(decoded.resume?.vendorSessionId == "sess-c1-fixture")
    #expect(decoded.answersReserved == nil)
    #expect(decoded.truncated == false)

    let reencoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(ProofReceipt.self, from: reencoded)
    #expect(roundTripped == decoded)
  }

  @Test("agent.run.receipt decodes through DaemonEvent")
  func daemonEventDecodesReceipt() throws {
    let wireJSON = """
    {"jsonrpc":"2.0","method":"agent.run.receipt","params":{"schema":"lancer.proof/v0","runId":"r-1","conversationId":"c-1","agent":"claude","status":"completed","exitCode":0}}
    """
    let event = DaemonEvent.decode(from: Data(wireJSON.utf8))
  if case .runReceipt(let receipt) = event {
      #expect(receipt.runId == "r-1")
      #expect(receipt.schema == "lancer.proof/v0")
    } else {
      Issue.record("Expected .runReceipt")
    }
  }
}
