import Testing
import Foundation
import GRDB
@testable import PersistenceKit
import LancerCore

@Suite("SnippetRepository")
struct SnippetRepositoryTests {

    private func makeRepo() async throws -> SnippetRepository {
        let db = try AppDatabase.inMemory()
        return SnippetRepository(db: db)
    }

    @Test("upsert and retrieve all")
    func upsertAndRetrieve() async throws {
        let repo = try await makeRepo()
        let s = Snippet(name: "list files", body: "ls -la")
        try await repo.upsert(s)
        let all = try await repo.all()
        #expect(all.count == 1)
        #expect(all[0].name == "list files")
        #expect(all[0].body == "ls -la")
    }

    @Test("upsert updates existing snippet")
    func upsertUpdates() async throws {
        let repo = try await makeRepo()
        var s = Snippet(name: "original", body: "echo original")
        try await repo.upsert(s)
        s.name = "updated"
        s.body = "echo updated"
        try await repo.upsert(s)
        let all = try await repo.all()
        #expect(all.count == 1)
        #expect(all[0].name == "updated")
        #expect(all[0].body == "echo updated")
    }

    @Test("search by name matches")
    func searchByName() async throws {
        let repo = try await makeRepo()
        try await repo.upsert(Snippet(name: "tail logs", body: "journalctl -f"))
        try await repo.upsert(Snippet(name: "disk usage", body: "df -h"))
        let results = try await repo.search("tail")
        #expect(results.count == 1)
        #expect(results[0].name == "tail logs")
    }

    @Test("search by body matches")
    func searchByBody() async throws {
        let repo = try await makeRepo()
        try await repo.upsert(Snippet(name: "show processes", body: "ps aux | grep nginx"))
        try await repo.upsert(Snippet(name: "uptime", body: "uptime"))
        let results = try await repo.search("nginx")
        #expect(results.count == 1)
        #expect(results[0].name == "show processes")
    }

    @Test("search empty query returns all")
    func searchEmptyReturnsAll() async throws {
        let repo = try await makeRepo()
        try await repo.upsert(Snippet(name: "a", body: "cmd a"))
        try await repo.upsert(Snippet(name: "b", body: "cmd b"))
        let results = try await repo.search("")
        #expect(results.count == 2)
    }

    @Test("delete removes snippet")
    func deleteRemoves() async throws {
        let repo = try await makeRepo()
        let s1 = Snippet(name: "keep", body: "keep")
        let s2 = Snippet(name: "delete me", body: "rm -rf /")
        try await repo.upsert(s1)
        try await repo.upsert(s2)
        try await repo.delete(id: s2.id)
        let all = try await repo.all()
        #expect(all.count == 1)
        #expect(all[0].id == s1.id)
    }

    @Test("delete non-existent id is a no-op")
    func deleteNonExistent() async throws {
        let repo = try await makeRepo()
        try await repo.upsert(Snippet(name: "keep", body: "keep"))
        // Should not throw
        try await repo.delete(id: SnippetID())
        let all = try await repo.all()
        #expect(all.count == 1)
    }

    @Test("markUsed updates lastUsedAt")
    func markUsedIncrements() async throws {
        let repo = try await makeRepo()
        let s = Snippet(name: "hello", body: "echo hello")
        try await repo.upsert(s)

        let before = try await repo.all()
        #expect(before[0].lastUsedAt == nil)

        let t = Date(timeIntervalSinceReferenceDate: 1_000_000)
        try await repo.markUsed(id: s.id, at: t)
        let after = try await repo.all()
        #expect(after[0].lastUsedAt != nil)
    }

    @Test("arguments round-trip through JSON")
    func argumentsRoundTrip() async throws {
        let repo = try await makeRepo()
        let args: [SnippetArgument] = [
            SnippetArgument(name: "branch", description: "Git branch", source: .dynamicShellCommand("git branch --format='%(refname:short)'")),
            SnippetArgument(name: "env", source: .enumValues(["dev", "staging", "prod"])),
            SnippetArgument(name: "msg", defaultValue: "hello", source: .literal),
        ]
        let s = Snippet(name: "deploy", body: "deploy {{env}} {{branch}}", arguments: args)
        try await repo.upsert(s)
        let loaded = try await repo.all()
        #expect(loaded.count == 1)
        #expect(loaded[0].arguments.count == 3)
        #expect(loaded[0].arguments[0].name == "branch")
        if case .dynamicShellCommand(let cmd) = loaded[0].arguments[0].source {
            #expect(cmd.contains("git branch"))
        } else {
            Issue.record("Expected dynamicShellCommand source")
        }
        if case .enumValues(let vals) = loaded[0].arguments[1].source {
            #expect(vals == ["dev", "staging", "prod"])
        } else {
            Issue.record("Expected enumValues source")
        }
        #expect(loaded[0].arguments[2].defaultValue == "hello")
    }

    @Test("rankedForPalette orders by score descending")
    func rankedByScore() async throws {
        let repo = try await makeRepo()
        let oldTime = Date(timeIntervalSinceReferenceDate: 0)
        let recentTime = Date(timeIntervalSinceReferenceDate: 1_000_000_000)

        var frequent = Snippet(name: "frequent", body: "cmd a", useCount: 20, createdAt: oldTime)
        frequent = Snippet(id: frequent.id, name: frequent.name, body: frequent.body, useCount: 20, createdAt: oldTime, lastUsedAt: recentTime)
        let unused = Snippet(name: "unused", body: "cmd b", useCount: 0, createdAt: oldTime)

        try await repo.upsert(frequent)
        try await repo.upsert(unused)

        let ranked = try await repo.rankedForPalette()
        #expect(ranked.first?.name == "frequent")
    }
}
