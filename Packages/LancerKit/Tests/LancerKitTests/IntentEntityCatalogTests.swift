import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit

@Suite("IntentEntityCatalog")
struct IntentEntityCatalogTests {

    @Test("machines merges SSH hosts and relay snapshots")
    func machinesMerge() async throws {
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        try await hostRepo.upsert(
            Host(name: "Studio Mac", hostname: "studio.local", username: "dev")
        )
        let catalog = IntentEntityCatalog(db)
        let relay = [
            IntentRelayMachineSnapshot(id: UUID().uuidString, displayName: "Relay Mac", lastConnectedAt: .now),
        ]
        let machines = try await catalog.machines(relayMachines: relay)
        #expect(machines.count == 2)
        #expect(machines.contains { $0.displayName == "Studio Mac" && $0.kind == .sshHost })
        #expect(machines.contains { $0.displayName == "Relay Mac" && $0.kind == .relayMachine })
    }

    @Test("activeRuns enriches from conversation turns")
    func activeRunsEnriched() async throws {
        let db = try AppDatabase.inMemory()
        let chatRepo = ChatConversationRepository(db)
        let conv = try await chatRepo.createConversation(
            title: "Fix auth bug",
            agentID: "claude",
            hostName: "MacBook",
            hostID: nil,
            cwd: "/repo"
        )
        let turn = try await chatRepo.appendTurn(
            conversationID: conv.id,
            prompt: "investigate",
            runID: "run-abc"
        )
        #expect(turn.runID == "run-abc")

        let catalog = IntentEntityCatalog(db)
        let runs = try await catalog.activeRuns(activeRunIDs: ["run-abc"])
        #expect(runs.count == 1)
        #expect(runs[0].conversationTitle == "Fix auth bug")
        #expect(runs[0].hostName == "MacBook")
    }

    @Test("pendingApprovals maps risk and headline")
    func pendingApprovalsMapped() async throws {
        let db = try AppDatabase.inMemory()
        let approvalRepo = ApprovalRepository(db)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "git status",
            cwd: "/repo",
            risk: .high
        )
        try await approvalRepo.upsert(approval)

        let catalog = IntentEntityCatalog(db)
        let pending = try await catalog.pendingApprovals()
        #expect(pending.count == 1)
        #expect(pending[0].riskLabel == "high risk")
        #expect(pending[0].headline.contains("git"))
    }

    @Test("searchConversations uses FTS path")
    func searchConversations() async throws {
        let db = try AppDatabase.inMemory()
        let chatRepo = ChatConversationRepository(db)
        _ = try await chatRepo.createConversation(
            title: "Deploy pipeline",
            agentID: "codex",
            hostName: "ci-host",
            hostID: nil,
            cwd: "/srv"
        )
        _ = try await chatRepo.createConversation(
            title: "Lunch plans",
            agentID: "claude",
            hostName: "ci-host",
            hostID: nil,
            cwd: "/home"
        )

        let catalog = IntentEntityCatalog(db)
        let results = try await catalog.searchConversations("deploy")
        #expect(results.count == 1)
        #expect(results[0].title == "Deploy pipeline")
    }

    @Test("matcher prefers exact id resolution")
    func matcherExactID() {
        struct Item: Identifiable { let id: String; let title: String }
        let items = [Item(id: "a", title: "Alpha"), Item(id: "b", title: "Beta")]
        let resolved = IntentEntityMatcher.resolveByID(items, identifiers: ["b"])
        #expect(resolved.count == 1)
        #expect(resolved[0].title == "Beta")
    }

    @Test("matcher string search is case-insensitive substring")
    func matcherSubstring() {
        struct Item: Identifiable { let id: String; let title: String; let when: Date }
        let now = Date()
        let items = [
            Item(id: "1", title: "Auth refactor", when: now),
            Item(id: "2", title: "Billing UI", when: now.addingTimeInterval(-60)),
        ]
        let matches = IntentEntityMatcher.matchString(
            items,
            query: "auth",
            title: { $0.title },
            recency: { $0.when }
        )
        #expect(matches.count == 1)
        #expect(matches[0].title == "Auth refactor")
    }

    @Test("deny-latest ambiguity: multiple pending approvals")
    func multiplePendingApprovals() async throws {
        let db = try AppDatabase.inMemory()
        let approvalRepo = ApprovalRepository(db)
        try await approvalRepo.upsert(Approval(sessionID: SessionID(), agent: .codex, kind: .command, command: "ls", cwd: "/a", risk: .low))
        try await approvalRepo.upsert(Approval(sessionID: SessionID(), agent: .codex, kind: .command, command: "pwd", cwd: "/b", risk: .low))
        let catalog = IntentEntityCatalog(db)
        let pending = try await catalog.pendingApprovals()
        #expect(pending.count == 2)
    }

    @Test("no machines when catalog and relay are empty")
    func noMachines() async throws {
        let db = try AppDatabase.inMemory()
        let catalog = IntentEntityCatalog(db)
        let machines = try await catalog.machines(relayMachines: [])
        #expect(machines.isEmpty)
    }

    @Test("offline machine has stale lastConnectedAt label path")
    func offlineMachine() async throws {
        let stale = Date().addingTimeInterval(-3600)
        let relay = [
            IntentRelayMachineSnapshot(id: UUID().uuidString, displayName: "Offline Mac", lastConnectedAt: stale),
        ]
        let catalog = IntentEntityCatalog(try AppDatabase.inMemory())
        let machines = try await catalog.machines(relayMachines: relay)
        #expect(machines.count == 1)
        #expect(machines[0].lastConnectedAt == stale)
    }

    @Test("two active runs resolve independently")
    func twoActiveRuns() async throws {
        let db = try AppDatabase.inMemory()
        let chatRepo = ChatConversationRepository(db)
        let convA = try await chatRepo.createConversation(title: "Run A", agentID: "claude", hostName: "mac", hostID: nil, cwd: "/a")
        let convB = try await chatRepo.createConversation(title: "Run B", agentID: "codex", hostName: "mac", hostID: nil, cwd: "/b")
        _ = try await chatRepo.appendTurn(conversationID: convA.id, prompt: "a", runID: "run-a")
        _ = try await chatRepo.appendTurn(conversationID: convB.id, prompt: "b", runID: "run-b")
        let catalog = IntentEntityCatalog(db)
        let runs = try await catalog.activeRuns(activeRunIDs: ["run-a", "run-b"])
        #expect(runs.count == 2)
        #expect(Set(runs.map(\.id)) == ["run-a", "run-b"])
    }

    @Test("deleted conversation lookup returns nil")
    func deletedConversation() async throws {
        let db = try AppDatabase.inMemory()
        let chatRepo = ChatConversationRepository(db)
        let conv = try await chatRepo.createConversation(title: "Gone", agentID: "claude", hostName: "mac", hostID: nil, cwd: "/x")
        try await chatRepo.deleteConversation(conv.id)
        let catalog = IntentEntityCatalog(db)
        let found = try await catalog.conversation(id: conv.id)
        #expect(found == nil)
    }

    @Test("resolved approval is not in pending list after decision")
    func deletedApproval() async throws {
        let db = try AppDatabase.inMemory()
        let approvalRepo = ApprovalRepository(db)
        let approval = Approval(sessionID: SessionID(), agent: .codex, kind: .command, command: "rm -rf", cwd: "/tmp", risk: .high)
        try await approvalRepo.upsert(approval)
        try await approvalRepo.decide(id: approval.id, decision: .rejected)
        let catalog = IntentEntityCatalog(db)
        let pending = try await catalog.pendingApprovals()
        #expect(pending.contains { $0.id == approval.id.uuidString } == false)
    }

    @Test("matcher handles duplicate display names via recency")
    func duplicateNames() {
        struct Item: Identifiable { let id: String; let title: String; let when: Date }
        let now = Date()
        let items = [
            Item(id: "1", title: "Mac Studio", when: now.addingTimeInterval(-120)),
            Item(id: "2", title: "Mac Studio", when: now),
        ]
        let matches = IntentEntityMatcher.matchString(
            items,
            query: "studio",
            title: { $0.title },
            recency: { $0.when }
        )
        #expect(matches.count == 2)
        #expect(matches[0].id == "2")
    }
}
