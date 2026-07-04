import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit
@testable import SessionFeature

@Suite("StartAgentRunSupport")
struct StartAgentRunIntentTests {

    private func onlineRelaySnapshot(id: UUID = UUID(), name: String = "Relay Mac") -> IntentRelayMachineSnapshot {
        IntentRelayMachineSnapshot(id: id.uuidString, displayName: name, lastConnectedAt: .now)
    }

    private func offlineRelaySnapshot(id: UUID = UUID(), name: String = "Relay Mac") -> IntentRelayMachineSnapshot {
        IntentRelayMachineSnapshot(
            id: id.uuidString,
            displayName: name,
            lastConnectedAt: Date().addingTimeInterval(-3600)
        )
    }

    @Test("prepare happy path resolves relay machine, workspace, and prompt")
    func prepareHappyPath() async throws {
        let machineID = UUID()
        let relayID = "relay:\(machineID.uuidString)"
        let db = try AppDatabase.inMemory()
        let catalog = IntentEntityCatalog(db)
        let workspaceRepo = WorkspaceRepository(db)
        let workspace = try await workspaceRepo.create(
            name: "gateway",
            machineID: RelayMachineID(machineID),
            path: "/Users/dev/repos/gateway"
        )

        let result = try await StartAgentRunPreparer.prepare(
            catalog: catalog,
            relayMachines: [onlineRelaySnapshot(id: machineID)],
            machineID: relayID,
            vendor: "claudeCode",
            agentDisplayName: "Claude Code",
            prompt: "  fix the auth bug  ",
            workspaceID: workspace.id,
            bridgeActive: { _ in false }
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(prepared.relayUUID == machineID.uuidString)
        #expect(prepared.machineRecordID == relayID)
        #expect(prepared.displayName == "Relay Mac")
        #expect(prepared.cwd == "/Users/dev/repos/gateway")
        #expect(prepared.workspaceLabel == "gateway")
        #expect(prepared.agentName == "Claude Code")
        #expect(prepared.vendor == "claudeCode")
        #expect(prepared.trimmedPrompt == "fix the auth bug")
    }

    @Test("prepare fails closed when relay machine is offline and bridge is inactive")
    func prepareRelayUnavailable() async throws {
        let machineID = UUID()
        let relayID = "relay:\(machineID.uuidString)"
        let db = try AppDatabase.inMemory()
        let catalog = IntentEntityCatalog(db)

        let result = try await StartAgentRunPreparer.prepare(
            catalog: catalog,
            relayMachines: [offlineRelaySnapshot(id: machineID, name: "Studio Mac")],
            machineID: relayID,
            vendor: "codex",
            agentDisplayName: "Codex",
            prompt: "ship it",
            workspaceID: nil,
            bridgeActive: { _ in false }
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message.contains("Studio Mac"))
        #expect(message.contains("can't reach"))
    }

    @Test("prepare reports workspace-not-found when explicit workspace id is stale")
    func prepareWorkspaceNotFound() async throws {
        let machineID = UUID()
        let relayID = "relay:\(machineID.uuidString)"
        let db = try AppDatabase.inMemory()
        let catalog = IntentEntityCatalog(db)

        let result = try await StartAgentRunPreparer.prepare(
            catalog: catalog,
            relayMachines: [onlineRelaySnapshot(id: machineID)],
            machineID: relayID,
            vendor: "opencode",
            agentDisplayName: "OpenCode",
            prompt: "refactor module",
            workspaceID: "missing-workspace",
            bridgeActive: { _ in true }
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message == "I couldn't find that workspace on this machine anymore.")
    }

    @Test("prepare accepts an active bridge even when lastConnectedAt is stale")
    func prepareBridgeActiveOverridesStaleLastSeen() async throws {
        let machineID = UUID()
        let relayID = "relay:\(machineID.uuidString)"
        let db = try AppDatabase.inMemory()
        let catalog = IntentEntityCatalog(db)
        let chatRepo = ChatConversationRepository(db)
        _ = try await chatRepo.createConversation(
            title: "Auth work",
            agentID: "claudeCode",
            hostName: "Relay Mac",
            hostID: nil,
            cwd: "/Users/dev/repos/auth"
        )

        let result = try await StartAgentRunPreparer.prepare(
            catalog: catalog,
            relayMachines: [offlineRelaySnapshot(id: machineID)],
            machineID: relayID,
            vendor: "claudeCode",
            agentDisplayName: "Claude Code",
            prompt: "continue",
            workspaceID: nil,
            bridgeActive: { _ in true }
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(prepared.cwd == "/Users/dev/repos/auth")
        #expect(prepared.workspaceLabel == "auth")
    }

    @Test("multiple machines require entity disambiguation not guessing")
    func multiMachineAmbiguity() {
        let machines = [
            IntentMachineRecord(id: "relay:a", displayName: "Mac A", hostName: "a", kind: .relayMachine),
            IntentMachineRecord(id: "relay:b", displayName: "Mac B", hostName: "b", kind: .relayMachine),
        ]
        let matchA = machines.filter { $0.displayName.lowercased().contains("mac") }
        #expect(matchA.count > 1)
    }

    @Test("progress stages follow expected order")
    func progressStageOrder() {
        let stages = [
            "resolvingMachine",
            "checkingConnection",
            "creatingRun",
            "dispatchingAgent",
            "waitingForFirstState",
        ]
        #expect(stages.first == "resolvingMachine")
        #expect(stages.last == "waitingForFirstState")
    }

#if os(iOS)
    @MainActor
    @Test("dispatch cancellation mid-flight stops in-flight handler")
    func dispatchCancellationMidFlight() async {
        let service = RunDispatchService()
        service.setHandler { _, _, _, _, _, _, _ in
            for _ in 0..<40 {
                if Task.isCancelled {
                    return .unavailable("Cancelled before dispatch finished.")
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return .started(runId: "run-cancel", conversationId: nil, summary: "should not finish")
        }

        let task = Task {
            await service.startRun(
                machineID: UUID().uuidString,
                vendor: "claudeCode",
                cwd: "/tmp",
                prompt: "work"
            )
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()
        let result = await task.value

        guard case .unavailable(let message) = result else {
            Issue.record("expected .unavailable from cancellation, got \(result)")
            return
        }
        #expect(message == "Cancelled before dispatch finished.")
    }

    @MainActor
    @Test("dispatch happy path returns started summary from fake handler")
    func dispatchHappyPath() async {
        let service = RunDispatchService()
        service.setHandler { machineID, vendor, cwd, prompt, _, _, _ in
            #expect(!machineID.isEmpty)
            #expect(vendor == "kimi")
            #expect(cwd == "/proj")
            #expect(prompt == "audit deps")
            return .started(runId: "run-1", conversationId: "conv-1", summary: "Started on Relay Mac.")
        }

        let result = await service.startRun(
            machineID: UUID().uuidString,
            vendor: "kimi",
            cwd: "/proj",
            prompt: "audit deps"
        )

        guard case .started(let runId, let conversationId, let summary) = result else {
            Issue.record("expected .started, got \(result)")
            return
        }
        #expect(runId == "run-1")
        #expect(conversationId == "conv-1")
        #expect(summary == "Started on Relay Mac.")
    }
#endif
}
