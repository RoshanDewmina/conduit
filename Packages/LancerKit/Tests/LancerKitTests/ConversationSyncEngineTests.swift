import Foundation
import Testing
@testable import SyncKit
@testable import PersistenceKit
@testable import LancerCore

@Suite("ConversationSyncEngine")
struct ConversationSyncEngineTests {

    @Test("start() is a no-op when CloudKit is unavailable (macOS test target)")
    func startNoOpWithoutCloudKit() async throws {
        let engine = try makeEngine()
        await engine.start()
        let syncDate = await engine.lastSyncDate
        #if os(macOS)
        #expect(syncDate == nil)
        #else
        _ = syncDate
        #endif
    }

    @Test("syncError is nil initially")
    func errorNilInitially() async throws {
        let engine = try makeEngine()
        let error = await engine.syncError
        #expect(error == nil)
    }

    @Test("isSyncing is false initially")
    func notSyncingInitially() async throws {
        let engine = try makeEngine()
        let isSyncing = await engine.isSyncing
        #expect(isSyncing == false)
    }

    @Test("syncNow() completes without throwing when CloudKit is unavailable")
    func syncNowDoesNotThrowWithoutCloudKit() async throws {
        let engine = try makeEngine()
        try await engine.syncNow()
    }

    // MARK: - Helpers

    private func makeEngine() throws -> ConversationSyncEngine {
        let db = try AppDatabase.inMemory()
        let chatRepo = ChatConversationRepository(db)
        let cloudSync = CloudSync()
        let defaults = UserDefaults(suiteName: "ConversationSyncEngineTests-\(UUID().uuidString)")!
        return ConversationSyncEngine(cloudSync: cloudSync, chatRepo: chatRepo, defaults: defaults)
    }
}
