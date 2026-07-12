import Foundation
import Testing
@testable import AppFeature
import LancerCore

@Suite("WorkspaceRepoCatalog")
struct WorkspaceRepoCatalogTests {

    @Test("normalizeCwd expands tilde, strips trailing slash, resolves /tmp symlink")
    func normalizeCwd() {
        let home = NSHomeDirectory()
        #expect(WorkspaceRepoCatalog.normalizeCwd("~/Documents/my-app/") == "\(home)/Documents/my-app")
        #expect(WorkspaceRepoCatalog.normalizeCwd("~") == home)
        #expect(WorkspaceRepoCatalog.normalizeCwd("/Users/dev/repos/conduit/") == "/Users/dev/repos/conduit")
        #expect(WorkspaceRepoCatalog.normalizeCwd("/tmp/demo") == "/private/tmp/demo")
        #expect(WorkspaceRepoCatalog.normalizeCwd("  /tmp/demo/  ") == "/private/tmp/demo")
        #expect(WorkspaceRepoCatalog.normalizeCwd("") == "")
        #expect(WorkspaceRepoCatalog.normalizeCwd("   ") == "")
    }

    @Test("pathsMatch is case-preserving equality after normalize")
    func pathsMatch() {
        #expect(WorkspaceRepoCatalog.pathsMatch("/tmp/Demo/", "/private/tmp/Demo"))
        #expect(WorkspaceRepoCatalog.pathsMatch("/Users/Dev/Repo", "/Users/dev/repo"))
        #expect(!WorkspaceRepoCatalog.pathsMatch("/Users/dev/a", "/Users/dev/b"))
    }

    @Test("isEqualOrUnder matches exact path and descendants")
    func isEqualOrUnder() {
        let repo = "/Users/dev/command-center"
        #expect(WorkspaceRepoCatalog.isEqualOrUnder(cwd: repo, repoPath: repo))
        #expect(WorkspaceRepoCatalog.isEqualOrUnder(
            cwd: "\(repo)/.worktrees/fix-x",
            repoPath: repo
        ))
        #expect(WorkspaceRepoCatalog.isEqualOrUnder(
            cwd: "\(repo)/Packages/LancerKit",
            repoPath: "\(repo)/"
        ))
        #expect(!WorkspaceRepoCatalog.isEqualOrUnder(
            cwd: "/Users/dev/command-center-other",
            repoPath: repo
        ))
        #expect(!WorkspaceRepoCatalog.isEqualOrUnder(
            cwd: "/Users/dev",
            repoPath: repo
        ))
    }

    @Test("displayName uses last path component")
    func displayName() {
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "/Users/dev/repos/conduit") == "conduit")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~/Documents/my-app/") == "my-app")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~") == "Home")
    }

    @Test("deriveRepos merges conversation cwds with user-added repos")
    func deriveRepos() {
        let conversations = [
            ChatConversation(title: "A", agentID: "a", hostName: "mac", cwd: "/Users/dev/conduit"),
            ChatConversation(title: "B", agentID: "a", hostName: "mac", cwd: "/Users/dev/conduit"),
            ChatConversation(title: "C", agentID: "a", hostName: "mac", cwd: "/Users/dev/other"),
            ChatConversation(title: "D", agentID: "a", hostName: "mac", cwd: ""),
        ]
        let added = [
            AddedRepo(name: "manual", cwd: "/Users/dev/manual"),
            AddedRepo(name: "conduit-renamed", cwd: "/Users/dev/conduit"),
        ]

        let repos = WorkspaceRepoCatalog.deriveRepos(conversations: conversations, added: added)
        #expect(repos.map(\.cwd) == ["/Users/dev/conduit", "/Users/dev/other", "/Users/dev/manual"])
        #expect(repos[0].threadCount == 2)
        #expect(repos[0].name == "conduit-renamed")
        #expect(repos[0].isUserAdded)
        #expect(repos[1].threadCount == 1)
        #expect(repos[2].threadCount == 0)
        #expect(repos[2].name == "manual")
    }

    @Test("deriveRepos counts worktree/subdir threads under matching repo")
    func deriveReposSubpathGrouping() {
        let conversations = [
            ChatConversation(
                title: "Root", agentID: "a", hostName: "mac",
                cwd: "/Users/dev/command-center"
            ),
            ChatConversation(
                title: "Worktree", agentID: "a", hostName: "mac",
                cwd: "/Users/dev/command-center/.worktrees/p1"
            ),
            ChatConversation(
                title: "Sibling", agentID: "a", hostName: "mac",
                cwd: "/Users/dev/other"
            ),
        ]
        let added = [
            AddedRepo(name: "command-center", cwd: "/Users/dev/command-center/")
        ]

        let repos = WorkspaceRepoCatalog.deriveRepos(
            conversations: conversations,
            added: added
        )
        let cc = repos.first { $0.name == "command-center" }
        #expect(cc?.threadCount == 2)
        #expect(cc?.cwd == "/Users/dev/command-center")
        #expect(repos.contains { $0.cwd == "/Users/dev/other" && $0.threadCount == 1 })
        #expect(!repos.contains { $0.cwd.contains(".worktrees") })
    }

    @Test("conversations for cwd filter exact + subpath and sort by recency")
    func conversationsForCwd() {
        let older = ChatConversation(
            title: "Older", agentID: "a", hostName: "mac", cwd: "/Users/dev/r",
            lastActivityAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatConversation(
            title: "Newer", agentID: "a", hostName: "mac", cwd: "/Users/dev/r",
            lastActivityAt: Date(timeIntervalSince1970: 200)
        )
        let worktree = ChatConversation(
            title: "Worktree", agentID: "a", hostName: "mac",
            cwd: "/Users/dev/r/.worktrees/x",
            lastActivityAt: Date(timeIntervalSince1970: 250)
        )
        let other = ChatConversation(
            title: "Other", agentID: "a", hostName: "mac", cwd: "/Users/dev/x",
            lastActivityAt: Date(timeIntervalSince1970: 300)
        )

        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: "/Users/dev/r/",
            allRepos: false,
            conversations: [older, other, newer, worktree]
        )
        #expect(filtered.map(\.title) == ["Worktree", "Newer", "Older"])

        let all = WorkspaceRepoCatalog.conversations(
            forCwd: nil,
            allRepos: true,
            conversations: [older, other, newer, worktree]
        )
        #expect(all.map(\.title) == ["Other", "Worktree", "Newer", "Older"])
    }

    @Test("thread status maps from last turn without inventing Checks Passed")
    func threadStatusMapping() {
        let conversation = ChatConversation(
            title: "Fix flow", agentID: "a", hostName: "mac", cwd: "/Users/dev/r",
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
        store.add(name: "demo", cwd: "/Users/dev/demo/")
        #expect(store.repos.count == 1)
        #expect(store.repos[0].cwd == "/Users/dev/demo")
        #expect(store.repos[0].name == "demo")

        let reloaded = AddedRepoStore(userDefaults: defaults)
        #expect(reloaded.repos.map(\.cwd) == ["/Users/dev/demo"])
    }

    @Test("add of existing normalized path is a no-op keeping first")
    func dedupOnAdd() {
        let suite = "dev.lancer.tests.addedRepos.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AddedRepoStore(userDefaults: defaults)
        let first = store.add(name: "command-center", cwd: "/Users/dev/command-center")
        let second = store.add(name: "duplicate", cwd: "/Users/dev/command-center/")
        let viaTmpStyle = store.add(name: "again", cwd: "/Users/dev/command-center")

        #expect(store.repos.count == 1)
        #expect(first?.cwd == "/Users/dev/command-center")
        #expect(second?.id == first?.id)
        #expect(second?.name == "command-center")
        #expect(viaTmpStyle?.name == "command-center")
        #expect(store.repos[0].name == "command-center")
    }

    @Test("load dedups persisted duplicates keeping first")
    func dedupOnLoad() throws {
        let suite = "dev.lancer.tests.addedRepos.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let duplicates = [
            AddedRepo(name: "first", cwd: "/Users/dev/command-center"),
            AddedRepo(name: "second", cwd: "/Users/dev/command-center/"),
            AddedRepo(name: "other", cwd: "/Users/dev/other"),
        ]
        let data = try JSONEncoder().encode(duplicates)
        defaults.set(data, forKey: "dev.lancer.addedRepos")

        let store = AddedRepoStore(userDefaults: defaults)
        #expect(store.repos.count == 2)
        #expect(store.repos.map(\.name) == ["first", "other"])
        #expect(store.repos.map(\.cwd) == ["/Users/dev/command-center", "/Users/dev/other"])
    }
}
