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

    // MARK: - Background pull (Task 8 / B9: CKDatabaseSubscription)

    @Test("handleRemoteNotification ignores a subscriptionID that isn't ours")
    func handleRemoteNotificationIgnoresForeignSubscription() async throws {
        let engine = try makeEngine()
        let handled = await engine.handleRemoteNotification(subscriptionID: "some-other-subscription")
        #expect(handled == false)
        // Not our subscription — must not have kicked off a sync cycle.
        let syncDate = await engine.lastSyncDate
        #expect(syncDate == nil)
    }

    @Test("handleRemoteNotification ignores a nil subscriptionID")
    func handleRemoteNotificationIgnoresNilSubscription() async throws {
        let engine = try makeEngine()
        let handled = await engine.handleRemoteNotification(subscriptionID: nil)
        #expect(handled == false)
    }

    @Test("handleRemoteNotification triggers a sync cycle when the subscriptionID matches")
    func handleRemoteNotificationTriggersSyncOnMatch() async throws {
        let engine = try makeEngine()
        let handled = await engine.handleRemoteNotification(subscriptionID: ConversationSyncEngine.backgroundSubscriptionID)
        #expect(handled == true)
        // Unlike `start()` (which checks account status first and bails
        // early on this CloudKit-less test host), handleRemoteNotification
        // calls performSync() unconditionally once the subscription ID
        // matches — it's a real push, so there's no "account unavailable"
        // check to skip. CloudSync's own methods no-op successfully rather
        // than throwing, so the cycle completes and isSyncing settles back
        // to false rather than getting stuck mid-sync.
        let stillSyncing = await engine.isSyncing
        #expect(stillSyncing == false)
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
