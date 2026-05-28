import Foundation
import Testing
@testable import ConduitCore
@testable import PersistenceKit

@Suite("SessionSnapshotRepository")
struct SessionSnapshotRepositoryTests {

    @Test("snapshot for unknown host returns nil")
    func nilForUnknownHost() async throws {
        let db = try AppDatabase.inMemory()
        let repo = SessionSnapshotRepository(db)
        let hostID = HostID()
        #expect(try await repo.snapshot(for: hostID) == nil)
    }

    @Test("upsert + read round-trips all fields")
    func upsertAndRead() async throws {
        let db = try AppDatabase.inMemory()
        // Insert a host first because session_snapshots has a foreign key.
        let host = ConduitCore.Host(name: "test", hostname: "x", username: "u")
        try await HostRepository(db).upsert(host)

        let snapshot = SessionSnapshot(
            hostID: host.id,
            lastUsedTime: Date(timeIntervalSince1970: 1_700_000_000),
            agentID: "claude",
            agentSessionID: "abc123",
            agentWorkingDirectory: "/home/me/proj",
            tmuxSessionName: "work"
        )
        let repo = SessionSnapshotRepository(db)
        try await repo.upsert(snapshot)

        let read = try await repo.snapshot(for: host.id)
        #expect(read?.agentID == "claude")
        #expect(read?.agentSessionID == "abc123")
        #expect(read?.agentWorkingDirectory == "/home/me/proj")
        #expect(read?.tmuxSessionName == "work")
        #expect(read?.lastUsedTime == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("isResumable returns true only when both agentID + sessionID set")
    func isResumableLogic() {
        let hostID = HostID()
        var snap = SessionSnapshot(hostID: hostID)
        #expect(snap.isResumable == false)

        snap.agentID = "claude"
        #expect(snap.isResumable == false)

        snap.agentSessionID = "abc"
        #expect(snap.isResumable == true)

        snap.agentID = ""
        #expect(snap.isResumable == false)
    }

    @Test("touch updates lastUsedTime in place")
    func touchUpdatesTime() async throws {
        let db = try AppDatabase.inMemory()
        let host = ConduitCore.Host(name: "t", hostname: "x", username: "u")
        try await HostRepository(db).upsert(host)
        let repo = SessionSnapshotRepository(db)

        let oldTime = Date(timeIntervalSince1970: 1_000_000_000)
        try await repo.upsert(
            SessionSnapshot(hostID: host.id, lastUsedTime: oldTime, agentID: "claude", agentSessionID: "a")
        )
        try await repo.touch(hostID: host.id, at: .now)
        let updated = try await repo.snapshot(for: host.id)
        #expect((updated?.lastUsedTime ?? .distantPast) > oldTime)
        // touch must not erase agent fields
        #expect(updated?.agentID == "claude")
        #expect(updated?.agentSessionID == "a")
    }

    @Test("allRecent sorts by lastUsedTime DESC")
    func allRecentSorted() async throws {
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        let h1 = ConduitCore.Host(name: "old", hostname: "x", username: "u")
        let h2 = ConduitCore.Host(name: "new", hostname: "x", username: "u")
        try await hostRepo.upsert(h1)
        try await hostRepo.upsert(h2)

        let repo = SessionSnapshotRepository(db)
        try await repo.upsert(SessionSnapshot(hostID: h1.id, lastUsedTime: Date(timeIntervalSince1970: 100)))
        try await repo.upsert(SessionSnapshot(hostID: h2.id, lastUsedTime: Date(timeIntervalSince1970: 200)))

        let all = try await repo.allRecent()
        #expect(all.first?.hostID == h2.id)
        #expect(all.last?.hostID == h1.id)
    }

    @Test("delete removes the snapshot")
    func deleteRemoves() async throws {
        let db = try AppDatabase.inMemory()
        let host = ConduitCore.Host(name: "t", hostname: "x", username: "u")
        try await HostRepository(db).upsert(host)
        let repo = SessionSnapshotRepository(db)
        try await repo.upsert(SessionSnapshot(hostID: host.id, agentID: "claude", agentSessionID: "a"))
        try await repo.delete(hostID: host.id)
        #expect(try await repo.snapshot(for: host.id) == nil)
    }
}
