import Testing
import Foundation
@testable import SyncKit
@testable import PersistenceKit
@testable import ConduitCore

@Suite("SyncEngine")
struct SyncEngineTests {
    @Test func syncEngineInitializes() async throws {
        // Verifies SyncEngine can be constructed without crashing on macOS
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        let snippetRepo = SnippetRepository(db: db)
        let cloudSync = CloudSync()
        let engine = SyncEngine(cloudSync: cloudSync, hostRepo: hostRepo, snippetRepo: snippetRepo)

        // On macOS, accountStatus is .unavailable, so start() should be a no-op
        await engine.start()
        let syncDate = await engine.lastSyncDate
        // On macOS, no sync happens, so lastSyncDate stays nil
        _ = syncDate  // just verify it compiled and ran
    }

    @Test func cloudSyncStatusUnavailableOnMacOS() async throws {
        let cloudSync = CloudSync()
        let status = try await cloudSync.accountStatus()
        #if os(macOS)
        #expect(status == .unavailable)
        #else
        // On iOS simulator, may be .available or .noAccount
        _ = status
        #endif
    }

    @Test func syncEngineErrorIsNilInitially() async throws {
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        let snippetRepo = SnippetRepository(db: db)
        let cloudSync = CloudSync()
        let engine = SyncEngine(cloudSync: cloudSync, hostRepo: hostRepo, snippetRepo: snippetRepo)

        let error = await engine.syncError
        #expect(error == nil)
    }

    @Test func syncEngineConflictCountStartsAtZero() async throws {
        let db = try AppDatabase.inMemory()
        let hostRepo = HostRepository(db)
        let snippetRepo = SnippetRepository(db: db)
        let cloudSync = CloudSync()
        let engine = SyncEngine(cloudSync: cloudSync, hostRepo: hostRepo, snippetRepo: snippetRepo)

        let count = await engine.conflictCount
        #expect(count == 0)
    }
}
