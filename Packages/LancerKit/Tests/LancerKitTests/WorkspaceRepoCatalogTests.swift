import Foundation
import Testing
@testable import AppFeature
import LancerCore

@Suite("WorkspaceRepoCatalog")
struct WorkspaceRepoCatalogTests {

    @Test("normalizeCwd preserves tilde (host path), strips trailing slash, resolves /tmp symlink")
    func normalizeCwd() {
        // "~" is a HOST path: expanding it on iOS yields the app sandbox and
        // splits repos into duplicate buckets. It stays tilde-prefixed here;
        // only the daemon expands it, against the host home.
        #expect(WorkspaceRepoCatalog.normalizeCwd("~/Documents/my-app/") == "~/Documents/my-app")
        #expect(WorkspaceRepoCatalog.normalizeCwd("~") == "~")
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

    @Test("displayName uses last path component; home and empty are honest")
    func displayName() {
        let home = "/Users/u"
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "/Users/dev/repos/conduit") == "conduit")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~/Documents/my-app/") == "my-app")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "~") == "Home")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: home, homeDirectory: home) == "Home")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "") == "No folder")
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "command-center") == "command-center")
        // Host home is recognized by shape: on iOS NSHomeDirectory() is the app
        // sandbox, so an injected-home equality check can never match real
        // daemon cwds like /Users/roshansilva.
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "/Users/roshansilva", homeDirectory: "/sandbox") == "Home")
        // /home/… can't be asserted through displayName on a macOS test host —
        // normalizeCwd resolves the /home automount symlink. Assert the shape
        // check directly; on iOS /home never symlink-resolves.
        #expect(WorkspaceRepoCatalog.isHostHomePath("/home/deploy"))
        #expect(WorkspaceRepoCatalog.displayName(forCwd: "/Users/dev/repos", homeDirectory: "/sandbox") == "repos")
    }

    @Test("hasHiddenComponent detects worktree-style paths only")
    func hasHiddenComponent() {
        let root = "/Users/u/Documents/command-center"
        #expect(WorkspaceRepoCatalog.hasHiddenComponent(
            between: root,
            and: "\(root)/.claude/worktrees/x"
        ))
        #expect(WorkspaceRepoCatalog.hasHiddenComponent(
            between: root,
            and: "\(root)/.worktrees/p1"
        ))
        #expect(!WorkspaceRepoCatalog.hasHiddenComponent(
            between: "/tmp",
            and: "/tmp/lancer-chat-proof-fable"
        ))
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
        #expect(repos.reduce(0) { $0 + $1.threadCount } == 3)
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

    @Test("owner fixture: one command-center row, Home, sibling /tmp roots, empty excluded")
    func ownerFixtureBucketing() {
        let home = "/Users/u"
        let cc = "/Users/u/Documents/command-center"
        let conversations = Self.ownerFixtureConversations(home: home, cc: cc)
        let repos = WorkspaceRepoCatalog.deriveRepos(
            conversations: conversations,
            added: [],
            homeDirectory: home
        )
        Self.assertOwnerFixtureRepos(repos, home: home, cc: cc)
        Self.assertOwnerFixtureFilters(conversations, home: home, cc: cc)
    }

    @Test("owner phone repro: tilde-added repo folds into the discovered root, not a duplicate row")
    func tildeAddedRepoFolds() {
        let home = "/Users/u"
        let cc = "/Users/u/Documents/command-center"
        let conversations = Self.ownerFixtureConversations(home: home, cc: cc)
        // The phone's Add Repo entry was stored tilde-relative. Pre-fix this
        // sandbox-expanded on device into a bogus second absolute root: its
        // own 0-thread row PLUS the relative conversations un-merging into a
        // third row (owner screenshot 2026-07-12: command-center 16/1/0).
        let repos = WorkspaceRepoCatalog.deriveRepos(
            conversations: conversations,
            added: [AddedRepo(name: "command-center", cwd: "~/Documents/command-center")],
            homeDirectory: home
        )
        let ccRepos = repos.filter { $0.name == "command-center" }
        #expect(ccRepos.count == 1)
        #expect(ccRepos.first?.threadCount == 22)
        #expect(ccRepos.first?.cwd == cc)
        #expect(ccRepos.first?.isUserAdded == true)
    }

    @Test("tilde paths: no sandbox expansion, suffix bucketing, valid send target")
    func tildePathHandling() {
        #expect(WorkspaceRepoCatalog.normalizeCwd("~/Documents/x/") == "~/Documents/x")
        #expect(WorkspaceRepoCatalog.isAbsoluteSendTarget("~/Documents/x"))
        #expect(WorkspaceRepoCatalog.isAbsoluteSendTarget("~"))
        #expect(!WorkspaceRepoCatalog.isAbsoluteSendTarget("command-center"))
        let roots = ["/Users/u/Documents/command-center", "/Users/u", "/tmp/other"]
        #expect(WorkspaceRepoCatalog.bucketKey(forCwd: "~/Documents/Command-Center", among: roots)
            == "/Users/u/Documents/command-center")
        #expect(WorkspaceRepoCatalog.bucketKey(forCwd: "~", among: roots) == "/Users/u")
        // Ambiguous suffix stays its own bucket rather than guessing.
        let ambiguous = roots + ["/srv/Documents/command-center"]
        #expect(WorkspaceRepoCatalog.bucketKey(forCwd: "~/Documents/command-center", among: ambiguous)
            == "~/Documents/command-center")
    }

    private static func assertOwnerFixtureRepos(
        _ repos: [WorkspaceRepo],
        home: String,
        cc: String
    ) {
        let tmp = WorkspaceRepoCatalog.normalizeCwd("/tmp")
        let tmpProof = WorkspaceRepoCatalog.normalizeCwd("/tmp/lancer-chat-proof-fable")
        let ccRepo = repos.filter { $0.name == "command-center" }
        #expect(ccRepo.count == 1)
        #expect(ccRepo.first?.threadCount == 22)
        #expect(ccRepo.first?.cwd == cc)
        #expect(repos.first { $0.name == "Home" }?.threadCount == 39)
        #expect(repos.first { $0.name == "Home" }?.cwd == home)
        #expect(repos.first { WorkspaceRepoCatalog.pathsMatch($0.cwd, tmp) }?.threadCount == 8)
        #expect(repos.first { WorkspaceRepoCatalog.pathsMatch($0.cwd, tmpProof) }?.threadCount == 4)
        #expect(!repos.contains { $0.cwd.isEmpty })
        #expect(!repos.contains { $0.cwd.contains(".claude") })
        #expect(repos.reduce(0) { $0 + $1.threadCount } == 73)
    }

    private static func assertOwnerFixtureFilters(
        _ conversations: [ChatConversation],
        home: String,
        cc: String
    ) {
        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: cc,
            allRepos: false,
            conversations: conversations
        )
        #expect(filtered.count == 22)

        let homeFiltered = WorkspaceRepoCatalog.conversations(
            forCwd: home,
            allRepos: false,
            conversations: conversations
        )
        #expect(homeFiltered.count == 39)

        let all = WorkspaceRepoCatalog.conversations(
            forCwd: nil,
            allRepos: true,
            conversations: conversations
        )
        #expect(all.count == 74)

        guard let empty = conversations.last else {
            Issue.record("expected empty-cwd conversation")
            return
        }
        let item = WorkspaceRepoCatalog.threadItem(
            conversation: empty,
            lastTurn: nil,
            includeRepoName: true
        )
        #expect(item.repoName == "No folder")
    }

    /// Owner phone shape: 18 absolute + 3 relative + 1 worktree + 39 home + 8 /tmp
    /// + 4 nested /tmp proof + 1 empty.
    private static func ownerFixtureConversations(home: String, cc: String) -> [ChatConversation] {
        func make(_ title: String, cwd: String) -> ChatConversation {
            ChatConversation(title: title, agentID: "a", hostName: "mac", cwd: cwd)
        }
        var conversations: [ChatConversation] = []
        conversations.reserveCapacity(74)
        for i in 0..<18 { conversations.append(make("cc-\(i)", cwd: cc)) }
        for i in 0..<3 { conversations.append(make("rel-\(i)", cwd: "command-center")) }
        conversations.append(make("wt", cwd: "\(cc)/.claude/worktrees/x"))
        for i in 0..<39 { conversations.append(make("home-\(i)", cwd: home)) }
        for i in 0..<8 { conversations.append(make("tmp-\(i)", cwd: "/tmp")) }
        for i in 0..<4 {
            conversations.append(make("proof-\(i)", cwd: "/tmp/lancer-chat-proof-fable"))
        }
        conversations.append(make("empty", cwd: ""))
        return conversations
    }

    @Test("relative cwd stays its own bucket when last-component match is ambiguous")
    func relativeAmbiguousStaysSeparate() {
        let conversations = [
            ChatConversation(title: "A", agentID: "a", hostName: "mac", cwd: "/Users/u/a/demo"),
            ChatConversation(title: "B", agentID: "a", hostName: "mac", cwd: "/Users/u/b/demo"),
            ChatConversation(title: "R", agentID: "a", hostName: "mac", cwd: "demo"),
        ]
        let repos = WorkspaceRepoCatalog.deriveRepos(conversations: conversations, added: [])
        #expect(repos.contains { $0.cwd == "demo" && $0.threadCount == 1 })
        #expect(repos.filter { $0.name == "demo" }.count == 3)
    }

    @Test("conversations for cwd filter by bucketKey and sort by recency")
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

    @Test("thread status maps from last turn; idle copy is No runs yet")
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

        let idle = WorkspaceRepoCatalog.threadItem(
            conversation: ChatConversation(
                title: "Fresh", agentID: "a", hostName: "mac", cwd: "/Users/dev/r",
                status: .active
            ),
            lastTurn: nil,
            includeRepoName: false
        )
        #expect(idle.statusKind == .idle)
        #expect(idle.statusLabel == "No runs yet")
    }

    @Test("groupByRecency splits Today and Yesterday around midnight")
    func groupByRecency() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00:00 UTC
        let startOfToday = calendar.startOfDay(for: now)
        let todayMorning = calendar.date(byAdding: .hour, value: 1, to: startOfToday)!
        let justBeforeMidnight = calendar.date(byAdding: .second, value: -1, to: startOfToday)!
        let yesterdayNoon = calendar.date(byAdding: .hour, value: -12, to: startOfToday)!
        let lastWeek = calendar.date(byAdding: .day, value: -3, to: startOfToday)!
        let earlier = calendar.date(byAdding: .day, value: -20, to: startOfToday)!

        let items = [
            ThreadListItem(
                id: "t", title: "T", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: todayMorning
            ),
            ThreadListItem(
                id: "y1", title: "Y1", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: justBeforeMidnight
            ),
            ThreadListItem(
                id: "y2", title: "Y2", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: yesterdayNoon
            ),
            ThreadListItem(
                id: "w", title: "W", statusKind: .completed, statusLabel: "Completed",
                repoName: nil, cwd: "/a", lastActivityAt: lastWeek
            ),
            ThreadListItem(
                id: "e", title: "E", statusKind: .idle, statusLabel: "No runs yet",
                repoName: nil, cwd: "/a", lastActivityAt: earlier
            ),
        ]

        let groups = WorkspaceRepoCatalog.groupByRecency(items, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "This Week", "Earlier"])
        #expect(groups.map { $0.items.count } == [1, 2, 1, 1])
        #expect(groups[0].items.map(\.id) == ["t"])
        #expect(Set(groups[1].items.map(\.id)) == ["y1", "y2"])
        #expect(WorkspaceRepoCatalog.groupByRecency([], now: now, calendar: calendar).isEmpty)
    }

    @Test("groupByRepo preserves first-seen group order and item order")
    func groupByRepo() {
        struct Row: Hashable {
            let id: String
            let repo: String
        }
        let items = [
            Row(id: "1", repo: "alpha"),
            Row(id: "2", repo: "beta"),
            Row(id: "3", repo: "alpha"),
            Row(id: "4", repo: "gamma"),
            Row(id: "5", repo: "beta"),
        ]
        let groups = WorkspaceRepoCatalog.groupByRepo(items, title: \.repo)
        #expect(groups.map(\.title) == ["alpha", "beta", "gamma"])
        #expect(groups[0].items.map(\.id) == ["1", "3"])
        #expect(groups[1].items.map(\.id) == ["2", "5"])
        #expect(groups[2].items.map(\.id) == ["4"])
        #expect(WorkspaceRepoCatalog.groupByRepo([Row](), title: \.repo).isEmpty)
    }

    @Test("isAbsoluteSendTarget rejects relative and empty cwd")
    func isAbsoluteSendTarget() {
        #expect(WorkspaceRepoCatalog.isAbsoluteSendTarget("/Users/dev/r"))
        #expect(!WorkspaceRepoCatalog.isAbsoluteSendTarget("command-center"))
        #expect(!WorkspaceRepoCatalog.isAbsoluteSendTarget(""))
        #expect(!WorkspaceRepoCatalog.isAbsoluteSendTarget("   "))
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
