import Foundation
import Testing
@testable import ConduitCore
@testable import PersistenceKit
@testable import AppFeature

@Suite("FleetThreadMapper")
struct FleetThreadMapperTests {

    @Test("findConversation returns matching conversation")
    func findMatch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Debug session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        let match = await FleetThreadMapper.findConversation(
            hostName: "prod-1", agentID: "claude", cwd: "/home/user",
            chatRepo: repo
        )
        #expect(match != nil)
        #expect(match?.title == "Debug session")
    }

    @Test("findConversation returns nil when no match")
    func noMatch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Debug session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        let result = await FleetThreadMapper.findConversation(
            hostName: "other-host", agentID: "claude", cwd: "/home/user",
            chatRepo: repo
        )
        #expect(result == nil)
    }

    @Test("findConversation prefers most recent when multiple match")
    func mostRecentMatch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Old session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        _ = try await repo.createConversation(
            title: "New session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        let match = await FleetThreadMapper.findConversation(
            hostName: "prod-1", agentID: "claude", cwd: "/home/user",
            chatRepo: repo
        )
        #expect(match?.title == "New session")
    }

    @Test("findConversation filters out completed conversations")
    func filtersCompleted() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Old session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        _ = try await repo.createConversation(
            title: "Active session", agentID: "claude",
            hostName: "prod-1", hostID: "h1", cwd: "/home/user"
        )
        try await repo.updateConversationStatus(conv.id, status: .completed)
        let match = await FleetThreadMapper.findConversation(
            hostName: "prod-1", agentID: "claude", cwd: "/home/user",
            chatRepo: repo
        )
        #expect(match?.title == "Active session")
    }
}
