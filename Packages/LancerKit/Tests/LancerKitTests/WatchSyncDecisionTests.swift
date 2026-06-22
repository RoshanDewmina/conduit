import Testing
import Foundation
@testable import LancerCore

@Suite("WatchSyncMessage — decision and count paths")
struct WatchSyncDecisionTests {

    // MARK: - Decision encode/decode round-trip

    @Test("decision approved encodes and decodes correctly")
    func decisionApprovedRoundTrip() {
        let id = UUID().uuidString
        let msg = WatchSyncMessage.decision(approvalID: id, result: "approved")
        let dict = msg.encode()

        guard let decoded = WatchSyncMessage.decode(dict) else {
            Issue.record("WatchSyncMessage.decode returned nil for decision"); return
        }
        guard case .decision(let decodedID, let decodedResult) = decoded else {
            Issue.record("Expected .decision, got something else"); return
        }
        #expect(decodedID == id)
        #expect(decodedResult == "approved")
    }

    @Test("decision rejected encodes and decodes correctly")
    func decisionRejectedRoundTrip() {
        let id = UUID().uuidString
        let msg = WatchSyncMessage.decision(approvalID: id, result: "rejected")
        let dict = msg.encode()

        guard let decoded = WatchSyncMessage.decode(dict) else {
            Issue.record("WatchSyncMessage.decode returned nil for rejected decision"); return
        }
        guard case .decision(let decodedID, let decodedResult) = decoded else {
            Issue.record("Expected .decision, got something else"); return
        }
        #expect(decodedID == id)
        #expect(decodedResult == "rejected")
    }

    @Test("decision decode requires both id and result fields")
    func decisionDecodeRejectsIncompletePayload() {
        // Missing "decision" key
        let missingResult: [String: Any] = ["type": "decision", "id": UUID().uuidString]
        #expect(WatchSyncMessage.decode(missingResult) == nil)

        // Missing "id" key
        let missingID: [String: Any] = ["type": "decision", "decision": "approved"]
        #expect(WatchSyncMessage.decode(missingID) == nil)
    }

    @Test("decision id survives a UUID round-trip")
    func decisionIDPreservesUUID() {
        let uuid = UUID()
        let msg = WatchSyncMessage.decision(approvalID: uuid.uuidString, result: "approved")
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .decision(let decodedID, _) = decoded else {
            Issue.record("Decode failed"); return
        }
        #expect(UUID(uuidString: decodedID) == uuid)
    }

    // MARK: - emergencyStop encode/decode

    @Test("emergencyStop encodes and decodes correctly")
    func emergencyStopRoundTrip() {
        let msg = WatchSyncMessage.emergencyStop
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict) else {
            Issue.record("Decode returned nil"); return
        }
        guard case .emergencyStop = decoded else {
            Issue.record("Expected .emergencyStop"); return
        }
    }

    // MARK: - runSnippet encode/decode

    @Test("runSnippet encodes and decodes body correctly")
    func runSnippetRoundTrip() {
        let body = "git status && git log --oneline -5"
        let msg = WatchSyncMessage.runSnippet(body: body)
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .runSnippet(let decodedBody) = decoded else {
            Issue.record("Decode failed"); return
        }
        #expect(decodedBody == body)
    }

    // MARK: - approvalSync count update path

    @Test("approvalSync count reflects pending-only items")
    func approvalSyncPendingCountFiltering() throws {
        let makeTransfer = { (risk: Int) in
            WatchApprovalTransfer(
                id: UUID().uuidString,
                sessionID: UUID().uuidString,
                agent: Approval.AgentSource.claudeCode.rawValue,
                kind: Approval.Kind.command.rawValue,
                command: "ls",
                cwd: "/tmp",
                risk: risk,
                createdAt: Date.now.timeIntervalSinceReferenceDate
            )
        }
        let items = [makeTransfer(0), makeTransfer(1), makeTransfer(2)]
        let msg = WatchSyncMessage.approvalSync(items)
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .approvalSync(let decodedItems) = decoded else {
            Issue.record("approvalSync decode failed"); return
        }
        #expect(decodedItems.count == 3)
        #expect(decodedItems.map(\.risk).sorted() == [0, 1, 2])
    }

    @Test("approvalSync with empty list encodes and decodes")
    func approvalSyncEmptyList() {
        let msg = WatchSyncMessage.approvalSync([])
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .approvalSync(let items) = decoded else {
            Issue.record("Empty approvalSync decode failed"); return
        }
        #expect(items.isEmpty)
    }

    // MARK: - sessionSync pendingCount and agentActive path

    @Test("sessionSync carries live pendingCount and agentActive")
    func sessionSyncLiveFields() throws {
        let status = WatchSessionStatus(
            hostName: "prod-server",
            hostname: "10.0.0.1",
            isConnected: true,
            agentActive: true,
            pendingCount: 3,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSinceReferenceDate
        )
        let msg = WatchSyncMessage.sessionSync(status)
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .sessionSync(let decodedStatus) = decoded else {
            Issue.record("sessionSync decode failed"); return
        }
        #expect(decodedStatus.pendingCount == 3)
        #expect(decodedStatus.agentActive == true)
        #expect(decodedStatus.isConnected == true)
        #expect(decodedStatus.hostName == "prod-server")
    }

    @Test("sessionSync with zero pendingCount and agentActive false")
    func sessionSyncIdleState() throws {
        let status = WatchSessionStatus(
            hostName: "dev",
            hostname: "localhost",
            isConnected: true,
            agentActive: false,
            pendingCount: 0,
            connectedAt: nil
        )
        let msg = WatchSyncMessage.sessionSync(status)
        let dict = msg.encode()
        guard let decoded = WatchSyncMessage.decode(dict),
              case .sessionSync(let s) = decoded else {
            Issue.record("sessionSync decode failed"); return
        }
        #expect(s.pendingCount == 0)
        #expect(s.agentActive == false)
        #expect(s.connectedAt == nil)
    }

    // MARK: - Unknown type returns nil

    @Test("unknown type key returns nil")
    func unknownTypeReturnsNil() {
        let dict: [String: Any] = ["type": "some.future.unknown.message.type"]
        #expect(WatchSyncMessage.decode(dict) == nil)
    }

    @Test("missing type key returns nil")
    func missingTypeKeyReturnsNil() {
        let dict: [String: Any] = ["payload": "something"]
        #expect(WatchSyncMessage.decode(dict) == nil)
    }
}
