import Foundation
import Testing
@testable import AppFeature
import LancerCore

@Suite("WorkspaceRepoCatalog")
struct WorkspaceRepoCatalogTests {

    @Test("displayName uses last path component")
    func displayName() {
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "/Users/dev/repos/conduit") == "conduit")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~/Documents/my-app/") == "my-app")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~") == "Home")
    }

    @Test("deriveRepos merges conversation cwds with user-added repos")
    func deriveRepos() {
        let conversations = [
            ChatConversation(title: "A", agentID: "a", hostName: "mac", cwd: "/tmp/conduit"),
            ChatConversation(title: "B", agentID: "a", hostName: "mac", cwd: "/tmp/conduit"),
            ChatConversation(title: "C", agentID: "a", hostName: "mac", cwd: "/tmp/other"),
            ChatConversation(title: "D", agentID: "a", hostName: "mac", cwd: ""),
        ]
        let added = [
            AddedRepo(name: "manual", cwd: "/tmp/manual"),
            AddedRepo(name: "conduit-renamed", cwd: "/tmp/conduit"),
        ]

        let repos = WorkspaceRepoCatalog.deriveRepos(conversations: conversations, added: added)
        #expect(repos.map(\.cwd) == ["/tmp/conduit", "/tmp/other", "/tmp/manual"])
        #expect(repos[0].threadCount == 2)
        #expect(repos[0].name == "conduit-renamed")
        #expect(repos[0].isUserAdded)
        #expect(repos[1].threadCount == 1)
        #expect(repos[2].threadCount == 0)
        #expect(repos[2].name == "manual")
    }

    @Test("conversations for cwd filter and sort by recency")
    func conversationsForCwd() {
        let older = ChatConversation(
            title: "Older", agentID: "a", hostName: "mac", cwd: "/tmp/r",
            lastActivityAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatConversation(
            title: "Newer", agentID: "a", hostName: "mac", cwd: "/tmp/r",
            lastActivityAt: Date(timeIntervalSince1970: 200)
        )
        let other = ChatConversation(
            title: "Other", agentID: "a", hostName: "mac", cwd: "/tmp/x",
            lastActivityAt: Date(timeIntervalSince1970: 300)
        )

        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: "/tmp/r",
            allRepos: false,
            conversations: [older, other, newer]
        )
        #expect(filtered.map(\.title) == ["Newer", "Older"])

        let all = WorkspaceRepoCatalog.conversations(
            forCwd: nil,
            allRepos: true,
            conversations: [older, other, newer]
        )
        #expect(all.map(\.title) == ["Other", "Newer", "Older"])
    }

    @Test("thread status maps from last turn without inventing Checks Passed")
    func threadStatusMapping() {
        let conversation = ChatConversation(
            title: "Fix flow", agentID: "a", hostName: "mac", cwd: "/tmp/r",
            status: .completed
        )
        let running = ChatTurn(
            conversationID: conversation.id, ordinal: 0, prompt: "go",
            runID: "r1", status: .running
        )
        let failed = ChatTurn(
            conversationID: conversation.id, ordinal: 0, prompt: "go",
            runID: "r2", status: .failed
        )
        let completed = ChatTurn(
            conversationID: conversation.id, ordinal: 0, prompt: "go",
            runID: "r3", status: .completed
        )

        let working = WorkspaceRepoCatalog.threadItem(
            conversation: conversation, lastTurn: running, includeRepoName: false
        )
        #expect(working.statusKind == .working)
        #expect(working.statusLabel == "Working")

        let failedItem = WorkspaceRepoCatalog.threadItem(
            conversation: conversation, lastTurn: failed, includeRepoName: true
        )
        #expect(failedItem.statusKind == .failed)
        #expect(failedItem.statusLabel == "Failed")
        #expect(failedItem.repoName == "r")

        let done = WorkspaceRepoCatalog.threadItem(
            conversation: conversation, lastTurn: completed, includeRepoName: false
        )
        #expect(done.statusKind == .completed)
        #expect(done.statusLabel == "Completed")
        #expect(!done.statusLabel.contains("Checks"))
    }

    @Test("groupByRecency buckets without inventing rows")
    func groupByRecency() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .hour, value: -20, to: startOfToday)!
        let lastWeek = calendar.date(byAdding: .day, value: -3, to: startOfToday)!
        let earlier = calendar.date(byAdding: .day, value: -20, to: startOfToday)!

        let items = [
            ThreadListItem(
                id: "1", title: "Y", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: yesterday
            ),
            ThreadListItem(
                id: "2", title: "W", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: lastWeek
            ),
            ThreadListItem(
                id: "3", title: "E", statusKind: .idle, statusLabel: "No activity",
                repoName: nil, cwd: "/a", lastActivityAt: earlier
            ),
        ]

        let groups = WorkspaceRepoCatalog.groupByRecency(items, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Yesterday", "This Week", "Earlier"])
        #expect(groups.map { $0.items.count } == [1, 1, 1])
        #expect(WorkspaceRepoCatalog.groupByRecency([], now: now, calendar: calendar).isEmpty)
    }
}

@Suite("AddedRepoStore")
@MainActor
struct AddedRepoStoreTests {
    @Test("persists and reloads user-added repos")
    func persistRoundTrip() {
        let suite = "dev.lancer.tests.addedRepos.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let store = AddedRepoStore(userDefaults: defaults)
        store.add(name: "demo", cwd: "/tmp/demo/")
        #expect(store.repos.count == 1)
        #expect(store.repos[0].cwd == "/tmp/demo")
        #expect(store.repos[0].name == "demo")

        let reloaded = AddedRepoStore(userDefaults: defaults)
        #expect(reloaded.repos.map(\.cwd) == ["/tmp/demo"])
    }
}
