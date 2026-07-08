import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import SessionFeature

/// Ported from `cursor/siri-phase2-fixes-9257`'s `StartAgentRunIntentTests`
/// and adapted to the resurrected API: `IntentEntityCatalog` /
/// `IntentRelayMachineSnapshot` were superseded by direct repository
/// parameters + `RelayMachineRecord`, and the `"relay:"` prefix is stripped
/// by the caller before `prepare` sees the ID.
@Suite("StartAgentRunPreparer")
struct StartAgentRunPreparerTests {
    private func onlineMachine(name: String = "Relay Mac") -> RelayMachineRecord {
        RelayMachineRecord(displayName: name, lastConnectedAt: .now)
    }

    private func staleMachine(name: String = "Relay Mac") -> RelayMachineRecord {
        RelayMachineRecord(displayName: name, lastConnectedAt: Date().addingTimeInterval(-3600))
    }

    private func prepare(
        relayMachineID: String?,
        relayMachines: [RelayMachineRecord],
        db: AppDatabase,
        prompt: String = "fix the auth bug",
        workspaceID: String? = nil,
        bridgeActive: Bool = false,
        onProgress: ((StartAgentRunPreparer.Stage) -> Void)? = nil
    ) async throws -> StartAgentRunPreparer.PrepareResult {
        try await StartAgentRunPreparer.prepare(
            relayMachineID: relayMachineID,
            relayMachines: relayMachines,
            agentDisplayName: "Claude Code",
            vendor: "claudeCode",
            prompt: prompt,
            workspaceID: workspaceID,
            workspaceRepository: WorkspaceRepository(db),
            conversationRepository: ChatConversationRepository(db),
            bridgeActive: { _ in bridgeActive },
            onProgress: onProgress
        )
    }

    @Test("happy path resolves relay machine, workspace, and prompt")
    func prepareHappyPath() async throws {
        let machine = onlineMachine()
        let db = try AppDatabase.inMemory()
        let workspace = try await WorkspaceRepository(db).create(
            name: "gateway", machineID: machine.id, path: "/Users/dev/repos/gateway"
        )

        var stages: [StartAgentRunPreparer.Stage] = []
        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            prompt: "  fix the auth bug  ",
            workspaceID: workspace.id,
            onProgress: { stages.append($0) }
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(prepared.relayMachineID == machine.id)
        #expect(prepared.machineRecordID == "relay:\(machine.id.uuidString)")
        #expect(prepared.displayName == "Relay Mac")
        #expect(prepared.cwd == "/Users/dev/repos/gateway")
        #expect(prepared.workspaceLabel == "gateway")
        #expect(prepared.agentName == "Claude Code")
        #expect(prepared.vendor == "claudeCode")
        #expect(prepared.trimmedPrompt == "fix the auth bug")
        #expect(stages == [.resolvingMachine, .checkingConnection])
    }

    @Test("empty prompt asks for one instead of dispatching")
    func prepareEmptyPrompt() async throws {
        let machine = onlineMachine()
        let db = try AppDatabase.inMemory()

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            prompt: "   "
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message == "Sure — what should the agent work on?")
    }

    @Test("no paired machines fails closed with pairing guidance")
    func prepareNoMachines() async throws {
        let db = try AppDatabase.inMemory()

        let result = try await prepare(relayMachineID: nil, relayMachines: [], db: db)

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message.contains("don't have any machines paired"))
    }

    @Test("sshHost machine (nil relay ID) is rejected with relay guidance")
    func prepareRejectsSSHHost() async throws {
        let db = try AppDatabase.inMemory()

        let result = try await prepare(
            relayMachineID: nil,
            relayMachines: [onlineMachine()],
            db: db
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message.contains("relay-paired machine"))
    }

    @Test("fails closed when relay machine is stale and bridge is inactive")
    func prepareRelayUnavailable() async throws {
        let machine = staleMachine(name: "Studio Mac")
        let db = try AppDatabase.inMemory()

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            prompt: "ship it",
            bridgeActive: false
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message.contains("Studio Mac"))
        #expect(message.contains("can't reach"))
    }

    @Test("reports workspace-not-found when explicit workspace id is stale")
    func prepareWorkspaceNotFound() async throws {
        let machine = onlineMachine()
        let db = try AppDatabase.inMemory()

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            workspaceID: "missing-workspace",
            bridgeActive: true
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message == "I couldn't find that workspace on this machine anymore.")
    }

    @Test("rejects a workspace that belongs to a different machine")
    func prepareWorkspaceWrongMachine() async throws {
        let machine = onlineMachine()
        let otherMachine = RelayMachineID()
        let db = try AppDatabase.inMemory()
        let foreign = try await WorkspaceRepository(db).create(
            name: "foreign", machineID: otherMachine, path: "/other/foreign"
        )

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            workspaceID: foreign.id
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message == "I couldn't find that workspace on this machine anymore.")
    }

    @Test("no explicit workspace falls back to the machine's MRU workspace")
    func prepareMRUWorkspaceFallback() async throws {
        let machine = onlineMachine()
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        try await repo.create(name: "older", machineID: machine.id, path: "/repos/older")
        let newer = try await repo.create(name: "newer", machineID: machine.id, path: "/repos/newer")
        try await repo.touch(newer.id)

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(prepared.cwd == "/repos/newer")
        #expect(prepared.workspaceLabel == "newer")
    }

    @Test("active bridge overrides stale lastConnectedAt and falls back to recent conversation cwd")
    func prepareBridgeActiveOverridesStaleLastSeen() async throws {
        let machine = staleMachine()
        let db = try AppDatabase.inMemory()
        _ = try await ChatConversationRepository(db).createConversation(
            title: "Auth work",
            agentID: "claudeCode",
            hostName: "Relay Mac",
            hostID: nil,
            cwd: "/Users/dev/repos/auth"
        )

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db,
            prompt: "continue",
            bridgeActive: true
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(prepared.cwd == "/Users/dev/repos/auth")
        #expect(prepared.workspaceLabel == "auth")
    }

    @Test("no workspace and no conversation history asks to pick a folder")
    func prepareNoWorkspaceAnywhere() async throws {
        let machine = onlineMachine(name: "Fresh Mac")
        let db = try AppDatabase.inMemory()

        let result = try await prepare(
            relayMachineID: machine.id.uuidString,
            relayMachines: [machine],
            db: db
        )

        guard case .dialog(let message) = result else {
            Issue.record("expected .dialog, got \(result)")
            return
        }
        #expect(message.contains("no workspace set up on Fresh Mac"))
    }

    @Test("connectivity label: online within 10 minutes, stale after, offline when never seen")
    func connectivityLabels() {
        #expect(StartAgentRunPreparer.machineConnectivityLabel(onlineMachine()) == "online")
        #expect(StartAgentRunPreparer.machineConnectivityLabel(staleMachine()) == "stale")
        #expect(
            StartAgentRunPreparer.machineConnectivityLabel(
                RelayMachineRecord(displayName: "never", lastConnectedAt: nil)
            ) == "offline"
        )
    }
}
