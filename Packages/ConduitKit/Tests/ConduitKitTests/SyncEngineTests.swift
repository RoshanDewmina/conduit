import Testing
import Foundation
@testable import SyncKit
@testable import PersistenceKit
@testable import ConduitCore
import SecurityKit

@Suite("SyncEngine")
struct SyncEngineTests {

    // MARK: - Init / basic state

    @Test func syncEngineInitializes() async throws {
        let (engine, _, _, _) = try makeEngine()
        await engine.start()
        let syncDate = await engine.lastSyncDate
        _ = syncDate  // on macOS, no sync happens — just verify construction
    }

    @Test func cloudSyncStatusUnavailableOnMacOS() async throws {
        let cloudSync = CloudSync()
        let status = try await cloudSync.accountStatus()
        #if os(macOS)
        #expect(status == .unavailable)
        #else
        _ = status
        #endif
    }

    @Test func syncEngineErrorIsNilInitially() async throws {
        let (engine, _, _, _) = try makeEngine()
        let error = await engine.syncError
        #expect(error == nil)
    }

    @Test func syncEngineConflictCountStartsAtZero() async throws {
        let (engine, _, _, _) = try makeEngine()
        let count = await engine.conflictCount
        #expect(count == 0)
    }

    @Test func isNotSyncingInitially() async throws {
        let (engine, _, _, _) = try makeEngine()
        let syncing = await engine.isSyncing
        #expect(syncing == false)
    }

    // MARK: - Host model

    @Test func hostCarriesModifiedAt() {
        let host = ConduitCore.Host(name: "Box", hostname: "h", username: "u")
        #expect(host.modifiedAt <= Date())
    }

    @Test func hostSyncedKeyHintDefaultsToNil() {
        let host = ConduitCore.Host(name: "Box", hostname: "h", username: "u")
        #expect(host.syncedKeyHint == nil)
    }

    @Test func hostWithKeyHint() {
        let hint = "SHA256:abc123"
        let host = ConduitCore.Host(name: "Box", hostname: "h", username: "u", syncedKeyHint: hint)
        #expect(host.syncedKeyHint == hint)
    }

    // MARK: - HostRepository: modifiedAt round-trip

    @Test func hostRepositoryUpsertSetsModifiedAt() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        let now = Date()
        var host = ConduitCore.Host(name: "Box", hostname: "h.example.com", username: "user")
        host.modifiedAt = now - 100   // stale timestamp should be overwritten
        try await repo.upsert(host)
        let loaded = try await repo.all().first!
        // upsert() bumps modifiedAt to ~now. Assert with slack rather than a strict
        // `>= now`: GRDB's Date round-trip can truncate sub-second precision below a
        // full-precision `now` captured in the same clock tick, which flaked under
        // parallel test load. A 5s window still proves the stale value was overwritten.
        #expect(loaded.modifiedAt > now - 5)
    }

    @Test func hostRepositoryUpsertSyncPreservesModifiedAt() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        let sentinel = Date(timeIntervalSince1970: 1_000_000)
        var host = ConduitCore.Host(name: "Box", hostname: "h.example.com", username: "user")
        host.modifiedAt = sentinel
        try await repo.upsertSync(host)
        let loaded = try await repo.all().first!
        #expect(loaded.modifiedAt == sentinel)
    }

    @Test func hostRepositoryPreservesSyncedKeyHint() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        var host = ConduitCore.Host(name: "Box", hostname: "h.example.com", username: "user")
        host.syncedKeyHint = "SHA256:test"
        try await repo.upsert(host)
        let loaded = try await repo.all().first!
        #expect(loaded.syncedKeyHint == "SHA256:test")
    }

    // MARK: - Snippet model

    @Test func snippetCarriesModifiedAt() {
        let s = Snippet(name: "ls", body: "ls -la")
        #expect(s.modifiedAt <= Date())
    }

    @Test func snippetRepositoryUpsertSyncPreservesModifiedAt() async throws {
        let db = try AppDatabase.inMemory()
        let repo = SnippetRepository(db: db)
        let sentinel = Date(timeIntervalSince1970: 2_000_000)
        var snippet = Snippet(name: "ls", body: "ls -la")
        snippet.modifiedAt = sentinel
        try await repo.upsertSync(snippet)
        let loaded = try await repo.all().first!
        #expect(loaded.modifiedAt == sentinel)
    }

    // MARK: - Tombstones

    @Test func hostDeleteCreatesTombstone() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        let tombstoneRepo = SyncTombstoneRepository(db)
        let host = ConduitCore.Host(name: "ToDelete", hostname: "x.local", username: "u")
        try await repo.upsert(host)
        try await repo.delete(id: host.id)
        let pending = try await tombstoneRepo.pending(recordType: "Host")
        #expect(pending.contains(host.id.uuidString))
    }

    @Test func hostDeleteFromSyncLeavesNoTombstone() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        let tombstoneRepo = SyncTombstoneRepository(db)
        let host = ConduitCore.Host(name: "ToDelete", hostname: "x.local", username: "u")
        try await repo.upsert(host)
        try await repo.deleteFromSync(id: host.id)
        let pending = try await tombstoneRepo.pending(recordType: "Host")
        #expect(!pending.contains(host.id.uuidString))
    }

    @Test func snippetDeleteCreatesTombstone() async throws {
        let db = try AppDatabase.inMemory()
        let repo = SnippetRepository(db: db)
        let tombstoneRepo = SyncTombstoneRepository(db)
        let snippet = Snippet(name: "x", body: "y")
        try await repo.upsert(snippet)
        try await repo.delete(id: snippet.id)
        let pending = try await tombstoneRepo.pending(recordType: "Snippet")
        #expect(pending.contains(snippet.id.uuidString))
    }

    @Test func upsertSyncClearsTombstone() async throws {
        let db = try AppDatabase.inMemory()
        let repo = HostRepository(db)
        let tombstoneRepo = SyncTombstoneRepository(db)
        let host = ConduitCore.Host(name: "Deleted", hostname: "x.local", username: "u")
        try await repo.upsert(host)
        try await repo.delete(id: host.id)  // creates tombstone
        try await repo.upsertSync(host)     // remote brought it back — tombstone should clear
        let pending = try await tombstoneRepo.pending(recordType: "Host")
        #expect(!pending.contains(host.id.uuidString))
    }

    // MARK: - Tombstone repository

    @Test func tombstoneRepositoryRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = SyncTombstoneRepository(db)
        try await repo.insert(id: "abc", recordType: "Host")
        try await repo.insert(id: "def", recordType: "Host")
        let pending = try await repo.pending(recordType: "Host")
        #expect(pending.contains("abc"))
        #expect(pending.contains("def"))
        try await repo.remove(ids: ["abc"], recordType: "Host")
        let remaining = try await repo.pending(recordType: "Host")
        #expect(!remaining.contains("abc"))
        #expect(remaining.contains("def"))
    }

    // MARK: - Helpers

    private func makeEngine() throws -> (SyncEngine, HostRepository, SnippetRepository, SyncTombstoneRepository) {
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        let snippetRepo = SnippetRepository(db: db)
        let tombstoneRepo = SyncTombstoneRepository(db)
        let cloudSync = CloudSync()
        let engine = SyncEngine(
            cloudSync: cloudSync,
            hostRepo: hostRepo,
            snippetRepo: snippetRepo,
            tombstoneRepo: tombstoneRepo
        )
        return (engine, hostRepo, snippetRepo, tombstoneRepo)
    }
}
