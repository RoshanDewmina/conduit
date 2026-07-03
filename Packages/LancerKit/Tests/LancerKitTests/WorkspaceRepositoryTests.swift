import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit

@Suite("WorkspaceRepository")
struct WorkspaceRepositoryTests {

    @Test("create round-trips all fields")
    func createRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineID = RelayMachineID()
        let workspace = try await repo.create(
            name: "gateway", machineID: machineID, path: "/Users/dev/repos/gateway",
            lastBranch: "main"
        )
        #expect(workspace.name == "gateway")
        #expect(workspace.machineID == machineID)
        #expect(workspace.path == "/Users/dev/repos/gateway")
        #expect(workspace.lastBranch == "main")

        let read = try await repo.workspace(id: workspace.id)
        #expect(read?.name == "gateway")
        #expect(read?.machineID == machineID)
        #expect(read?.path == "/Users/dev/repos/gateway")
        #expect(read?.lastBranch == "main")
    }

    @Test("workspace for unknown ID returns nil")
    func unknownIDNil() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        #expect(try await repo.workspace(id: "nonexistent") == nil)
    }

    @Test("list(machineID:) returns only that machine's workspaces")
    func listByMachineDoesNotLeak() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineA = RelayMachineID()
        let machineB = RelayMachineID()

        _ = try await repo.create(name: "repo-a1", machineID: machineA, path: "/a1")
        _ = try await repo.create(name: "repo-a2", machineID: machineA, path: "/a2")
        _ = try await repo.create(name: "repo-b1", machineID: machineB, path: "/b1")

        let machineAWorkspaces = try await repo.list(machineID: machineA)
        #expect(machineAWorkspaces.count == 2)
        #expect(machineAWorkspaces.allSatisfy { $0.machineID == machineA })
        #expect(Set(machineAWorkspaces.map(\.name)) == ["repo-a1", "repo-a2"])

        let machineBWorkspaces = try await repo.list(machineID: machineB)
        #expect(machineBWorkspaces.count == 1)
        #expect(machineBWorkspaces.first?.name == "repo-b1")
    }

    @Test("list(machineID:) for unknown machine returns empty")
    func listByMachineEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let workspaces = try await repo.list(machineID: RelayMachineID())
        #expect(workspaces.isEmpty)
    }

    @Test("rename changes name only")
    func rename() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineID = RelayMachineID()
        let workspace = try await repo.create(name: "old-name", machineID: machineID, path: "/repo")
        try await repo.rename(workspace.id, name: "new-name")

        let read = try await repo.workspace(id: workspace.id)
        #expect(read?.name == "new-name")
        #expect(read?.path == "/repo")
    }

    @Test("delete removes the record")
    func delete() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineID = RelayMachineID()
        let workspace = try await repo.create(name: "to-delete", machineID: machineID, path: "/repo")
        try await repo.delete(workspace.id)
        #expect(try await repo.workspace(id: workspace.id) == nil)
    }

    @Test("delete of one machine's workspace doesn't affect another machine's")
    func deleteScoped() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineA = RelayMachineID()
        let machineB = RelayMachineID()
        let wsA = try await repo.create(name: "a", machineID: machineA, path: "/a")
        let wsB = try await repo.create(name: "b", machineID: machineB, path: "/b")

        try await repo.delete(wsA.id)

        #expect(try await repo.workspace(id: wsA.id) == nil)
        #expect(try await repo.workspace(id: wsB.id) != nil)
        #expect(try await repo.list(machineID: machineB).count == 1)
    }

    @Test("touch updates lastUsedAt")
    func touch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineID = RelayMachineID()
        let workspace = try await repo.create(name: "gateway", machineID: machineID, path: "/repo")
        let originalLastUsed = workspace.lastUsedAt

        try await Task.sleep(for: .milliseconds(20))
        try await repo.touch(workspace.id)

        let read = try await repo.workspace(id: workspace.id)
        #expect(read != nil)
        if let read {
            #expect(read.lastUsedAt >= originalLastUsed)
        }
    }

    @Test("list orders by lastUsedAt descending")
    func listOrdering() async throws {
        let db = try AppDatabase.inMemory()
        let repo = WorkspaceRepository(db)
        let machineID = RelayMachineID()
        let older = try await repo.create(name: "older", machineID: machineID, path: "/older")
        try await Task.sleep(for: .milliseconds(20))
        let newer = try await repo.create(name: "newer", machineID: machineID, path: "/newer")

        let workspaces = try await repo.list(machineID: machineID)
        #expect(workspaces.first?.id == newer.id)
        #expect(workspaces.last?.id == older.id)
    }
}
