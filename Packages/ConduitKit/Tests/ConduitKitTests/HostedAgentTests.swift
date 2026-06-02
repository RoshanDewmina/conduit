import Foundation
import Testing
@testable import AgentKit

@Suite("HostedAgent domain types")
struct HostedAgentTests {
    @Test("AgentRun terminal statuses")
    func terminalStatuses() {
        #expect(RunStatus.succeeded.isTerminal)
        #expect(RunStatus.failed.isTerminal)
        #expect(RunStatus.cancelled.isTerminal)
        #expect(!RunStatus.running.isTerminal)
        #expect(!RunStatus.awaitingApproval.isTerminal)
    }

    @Test("UsageRecord totals tokens")
    func usageTotals() {
        let record = UsageRecord(inputTokens: 100, outputTokens: 50, costUSD: 0.05, model: "test/model")
        #expect(record.totalTokens == 150)
        #expect(record.costUSD == 0.05)
    }

    @Test("HostedAgent encodes and decodes")
    func codableRoundTrip() throws {
        let agent = HostedAgent(name: "claude", model: "anthropic/claude-sonnet-4", hostID: "host-1", command: "claude")
        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(HostedAgent.self, from: data)
        #expect(decoded.name == agent.name)
        #expect(decoded.hostID == "host-1")
    }

    @Test("Backend agent DTO maps to HostedAgent")
    func backendAgentMapping() {
        let backend = HostedAgentAPIClient.BackendAgent(
            id: "agent_abc",
            name: "Deploy Bot",
            runtime: "ssh-host",
            config: .init(model: "anthropic/claude-sonnet-4", hostID: "host-1", command: "claude"),
            createdAt: "2025-06-02T12:00:00Z",
            updatedAt: "2025-06-02T12:00:00Z"
        )
        let mapped = HostedAgentAPIClient.mapAgent(backend)
        #expect(mapped.id == "agent_abc")
        #expect(mapped.name == "Deploy Bot")
        #expect(mapped.runtimeKind == .sshHost)
        #expect(mapped.hostID == "host-1")
        #expect(mapped.command == "claude")
    }

    @Test("Backend run DTO maps to AgentRun")
    func backendRunMapping() {
        let backend = HostedAgentAPIClient.BackendRun(
            id: "run_xyz",
            agentId: "agent_abc",
            status: "running",
            command: "echo hello",
            startedAt: "2025-06-02T12:01:00Z",
            completedAt: nil,
            createdAt: "2025-06-02T12:01:00Z"
        )
        let mapped = HostedAgentAPIClient.mapRun(backend)
        #expect(mapped.id == "run_xyz")
        #expect(mapped.agentID == "agent_abc")
        #expect(mapped.status == .running)
        #expect(mapped.prompt == "echo hello")
    }

    @Test("Fly runtime maps correctly")
    func flyRuntimeMapping() {
        #expect(HostedAgentAPIClient.mapRuntimeKind("fly") == .fly)
        #expect(HostedAgentAPIClient.mapRuntime(.fly) == "fly")
    }
}
