import Testing
import Foundation
@testable import ConduitCore

@Suite("WatchApprovalTransfer")
struct WatchApprovalTransferTests {

    // MARK: - Helpers

    private func makeApproval(
        risk: Approval.Risk = .low,
        kind: Approval.Kind = .command,
        agent: Approval.AgentSource = .claudeCode,
        command: String? = "ls -la"
    ) -> Approval {
        Approval(
            id: ApprovalID(UUID()),
            sessionID: SessionID(UUID()),
            agent: agent,
            kind: kind,
            command: command,
            cwd: "/home/user",
            risk: risk
        )
    }

    // MARK: - Codable round-trip

    @Test("round-trips all fields through JSON")
    func roundTrip() throws {
        let approval = makeApproval(risk: .high, kind: .patch, agent: .codex, command: nil)
        let transfer = WatchApprovalTransfer(approval: approval)

        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(WatchApprovalTransfer.self, from: data)

        #expect(decoded.id == transfer.id)
        #expect(decoded.sessionID == transfer.sessionID)
        #expect(decoded.agent == transfer.agent)
        #expect(decoded.kind == transfer.kind)
        #expect(decoded.command == transfer.command)
        #expect(decoded.cwd == transfer.cwd)
        #expect(decoded.risk == transfer.risk)
        #expect(decoded.createdAt == transfer.createdAt)
    }

    @Test("round-trips with optional command nil")
    func roundTripNilCommand() throws {
        let approval = makeApproval(command: nil)
        let transfer = WatchApprovalTransfer(approval: approval)
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(WatchApprovalTransfer.self, from: data)
        #expect(decoded.command == nil)
    }

    @Test("init(approval:) maps all fields correctly")
    func initFromApproval() {
        let approval = makeApproval(risk: .critical, kind: .fileDelete, agent: .opencode)
        let transfer = WatchApprovalTransfer(approval: approval)

        #expect(transfer.id == approval.id.uuidString)
        #expect(transfer.sessionID == approval.sessionID.uuidString)
        #expect(transfer.agent == approval.agent.rawValue)
        #expect(transfer.kind == approval.kind.rawValue)
        #expect(transfer.cwd == approval.cwd)
        #expect(transfer.risk == approval.risk.rawValue)
        #expect(transfer.createdAt == approval.createdAt.timeIntervalSinceReferenceDate)
    }

    // MARK: - riskLevel helper

    @Test("riskLevel returns correct enum for all raw values")
    func riskLevelAllCases() {
        for risk in [Approval.Risk.low, .medium, .high, .critical] {
            let approval = makeApproval(risk: risk)
            let transfer = WatchApprovalTransfer(approval: approval)
            #expect(transfer.riskLevel == risk)
        }
    }

    @Test("riskLevel falls back to .low for unknown raw value")
    func riskLevelFallback() {
        let transfer = WatchApprovalTransfer(
            id: UUID().uuidString,
            sessionID: UUID().uuidString,
            agent: Approval.AgentSource.unknown.rawValue,
            kind: Approval.Kind.command.rawValue,
            command: nil,
            cwd: "/",
            risk: 999,   // unknown raw value
            createdAt: Date.now.timeIntervalSinceReferenceDate
        )
        #expect(transfer.riskLevel == .low)
    }

    // MARK: - agentSource helper

    @Test("agentSource returns correct enum for known agents")
    func agentSourceKnown() {
        for agent in [Approval.AgentSource.claudeCode, .codex, .opencode, .cursor, .devin] {
            let approval = makeApproval(agent: agent)
            let transfer = WatchApprovalTransfer(approval: approval)
            #expect(transfer.agentSource == agent)
        }
    }

    @Test("agentSource falls back to .unknown for unrecognised string")
    func agentSourceFallback() {
        let transfer = WatchApprovalTransfer(
            id: UUID().uuidString,
            sessionID: UUID().uuidString,
            agent: "unrecognised-agent",
            kind: Approval.Kind.command.rawValue,
            command: nil,
            cwd: "/",
            risk: 0,
            createdAt: Date.now.timeIntervalSinceReferenceDate
        )
        #expect(transfer.agentSource == .unknown)
    }

    // MARK: - approvalKind helper

    @Test("approvalKind returns correct enum for all kinds")
    func approvalKindAllCases() {
        for kind in [Approval.Kind.command, .patch, .fileWrite, .fileDelete,
                     .network, .credential, .browser, .callMCP, .askQuestion] {
            let approval = makeApproval(kind: kind)
            let transfer = WatchApprovalTransfer(approval: approval)
            #expect(transfer.approvalKind == kind)
        }
    }

    // MARK: - createdDate helper

    @Test("createdDate reconstructs the original Date")
    func createdDateRoundTrip() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let transfer = WatchApprovalTransfer(
            id: UUID().uuidString,
            sessionID: UUID().uuidString,
            agent: Approval.AgentSource.claudeCode.rawValue,
            kind: Approval.Kind.command.rawValue,
            command: "echo hi",
            cwd: "/tmp",
            risk: Approval.Risk.low.rawValue,
            createdAt: now.timeIntervalSinceReferenceDate
        )
        #expect(transfer.createdDate == now)
    }

    // MARK: - WatchSyncMessage encode/decode round-trip (approval subset)

    @Test("WatchSyncMessage.approvalSync encodes and decodes correctly")
    func watchSyncMessageApprovalRoundTrip() {
        let approval = makeApproval(risk: .medium)
        let transfer = WatchApprovalTransfer(approval: approval)
        let message = WatchSyncMessage.approvalSync([transfer])

        let dict = message.encode()
        guard let decoded = WatchSyncMessage.decode(dict) else {
            Issue.record("WatchSyncMessage.decode returned nil")
            return
        }
        guard case .approvalSync(let items) = decoded else {
            Issue.record("Expected .approvalSync, got something else")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].id == transfer.id)
        #expect(items[0].risk == transfer.risk)
    }
}
