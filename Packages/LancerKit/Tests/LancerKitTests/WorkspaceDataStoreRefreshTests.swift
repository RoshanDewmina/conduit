import Foundation
import Testing
@testable import AppFeature
import LancerCore
import PersistenceKit

@Suite("WorkspaceDataStore.refresh cache-first")
struct WorkspaceDataStoreRefreshTests {

    @Test("returns ready after local rows without awaiting host sync")
    @MainActor
    func readyBeforeHostSync() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let seed = ChatConversation(
            id: "conv-cache-1",
            title: "Cached thread",
            agentID: "claudeCode",
            hostName: "mac",
            hostID: nil,
            cwd: "/Users/dev/command-center"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 1, syncState: .synced)

        let store = WorkspaceDataStore(chatRepo: repo)
        store.syncRunningStatuses = {
            // Deliberately slow — refresh() must not await this.
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        let started = ContinuousClock.now
        await store.refresh()
        let elapsed = started.duration(to: .now)

        #expect(elapsed < .milliseconds(400))
        #expect(store.fetchPhase == .ready)
        #expect(!store.showsInitialLoading)
        #expect(store.conversations.count == 1)
        #expect(store.conversations.first?.id == "conv-cache-1")
    }
}
