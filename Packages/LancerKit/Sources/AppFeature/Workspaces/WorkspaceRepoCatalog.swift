import Foundation
import Observation
import LancerCore
import PersistenceKit

/// One workspace/repo row shown in Workspaces / composer / picker.
/// `cwd` is the real path used for live sends — never a guessed `~/name`.
public struct WorkspaceRepo: Identifiable, Hashable, Sendable {
    public var id: String { cwd }
    public let name: String
    public let cwd: String
    public let threadCount: Int
    public let isUserAdded: Bool

    public init(name: String, cwd: String, threadCount: Int, isUserAdded: Bool) {
        self.name = name
        self.cwd = cwd
        self.threadCount = threadCount
        self.isUserAdded = isUserAdded
    }
}

/// Honest thread-list / search row model derived from a real conversation.
public struct ThreadListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let statusKind: ThreadStatusKind
    public let statusLabel: String
    public let repoName: String?
    public let cwd: String
    public let lastActivityAt: Date

    public init(
        id: String,
        title: String,
        statusKind: ThreadStatusKind,
        statusLabel: String,
        repoName: String?,
        cwd: String,
        lastActivityAt: Date
    ) {
        self.id = id
        self.title = title
        self.statusKind = statusKind
        self.statusLabel = statusLabel
        self.repoName = repoName
        self.cwd = cwd
        self.lastActivityAt = lastActivityAt
    }
}

public enum ThreadStatusKind: Sendable, Equatable {
    case working
    case completed
    case failed
    case archived
    case idle
}

/// User-added repo persisted locally until a conversation also records the cwd.
public struct AddedRepo: Codable, Hashable, Sendable, Identifiable {
    public var id: String { cwd }
    public let name: String
    public let cwd: String
    public let addedAt: Date

    public init(name: String, cwd: String, addedAt: Date = .now) {
        self.name = name
        self.cwd = cwd
        self.addedAt = addedAt
    }
}

/// Pure derivation / mapping for workspace repos and thread rows.
/// Kept free of SwiftUI so unit tests can exercise it on macOS.
public enum WorkspaceRepoCatalog {
    public static func normalizeCwd(_ cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == "~" { return trimmed }
        if trimmed.hasSuffix("/") && trimmed.count > 1 {
            return String(trimmed.dropLast())
        }
        return trimmed
    }

    public static func displayName(forCwd cwd: String) -> String {
        let normalized = normalizeCwd(cwd)
        guard !normalized.isEmpty else { return "Untitled" }
        if normalized == "~" { return "Home" }
        let expanded = (normalized as NSString).expandingTildeInPath
        let base = (expanded as NSString).lastPathComponent
        return base.isEmpty ? normalized : base
    }

    /// Merge distinct conversation cwds with user-added repos. Sorted by
    /// thread count (desc), then name. Empty / home-only placeholder cwds
    /// from conversations are omitted unless the user explicitly added them.
    public static func deriveRepos(
        conversations: [ChatConversation],
        added: [AddedRepo]
    ) -> [WorkspaceRepo] {
        var counts: [String: Int] = [:]
        for conversation in conversations {
            let cwd = normalizeCwd(conversation.cwd)
            guard !cwd.isEmpty else { continue }
            counts[cwd, default: 0] += 1
        }

        var byCwd: [String: WorkspaceRepo] = [:]

        for (cwd, count) in counts {
            byCwd[cwd] = WorkspaceRepo(
                name: displayName(forCwd: cwd),
                cwd: cwd,
                threadCount: count,
                isUserAdded: false
            )
        }

        for repo in added {
            let cwd = normalizeCwd(repo.cwd)
            guard !cwd.isEmpty else { continue }
            if let existing = byCwd[cwd] {
                byCwd[cwd] = WorkspaceRepo(
                    name: repo.name.isEmpty ? existing.name : repo.name,
                    cwd: cwd,
                    threadCount: existing.threadCount,
                    isUserAdded: true
                )
            } else {
                byCwd[cwd] = WorkspaceRepo(
                    name: repo.name.isEmpty ? displayName(forCwd: cwd) : repo.name,
                    cwd: cwd,
                    threadCount: 0,
                    isUserAdded: true
                )
            }
        }

        return byCwd.values.sorted {
            if $0.threadCount != $1.threadCount { return $0.threadCount > $1.threadCount }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func conversations(
        forCwd cwd: String?,
        allRepos: Bool,
        conversations: [ChatConversation]
    ) -> [ChatConversation] {
        let sorted = conversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
        guard !allRepos else { return sorted }
        guard let cwd else { return [] }
        let needle = normalizeCwd(cwd)
        return sorted.filter { normalizeCwd($0.cwd) == needle }
    }

    public static func threadItem(
        conversation: ChatConversation,
        lastTurn: ChatTurn?,
        includeRepoName: Bool
    ) -> ThreadListItem {
        let kind = statusKind(conversation: conversation, lastTurn: lastTurn)
        return ThreadListItem(
            id: conversation.id,
            title: conversation.title.isEmpty ? "Untitled thread" : conversation.title,
            statusKind: kind,
            statusLabel: statusLabel(kind),
            repoName: includeRepoName ? displayName(forCwd: conversation.cwd) : nil,
            cwd: normalizeCwd(conversation.cwd),
            lastActivityAt: conversation.lastActivityAt
        )
    }

    public static func threadItems(
        conversations: [ChatConversation],
        lastTurnByConversationID: [String: ChatTurn],
        includeRepoName: Bool
    ) -> [ThreadListItem] {
        conversations.map {
            threadItem(
                conversation: $0,
                lastTurn: lastTurnByConversationID[$0.id],
                includeRepoName: includeRepoName
            )
        }
    }

    /// Date-bucket labels for a sorted (newest-first) thread list. Returns
    /// contiguous groups; never invents sample rows.
    public static func groupByRecency(
        _ items: [ThreadListItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(title: String, items: [ThreadListItem])] {
        guard !items.isEmpty else { return [] }

        var yesterday: [ThreadListItem] = []
        var thisWeek: [ThreadListItem] = []
        var earlier: [ThreadListItem] = []

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        for item in items {
            if item.lastActivityAt >= startOfYesterday {
                yesterday.append(item)
            } else if item.lastActivityAt >= startOfWeek {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [(title: String, items: [ThreadListItem])] = []
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !earlier.isEmpty { groups.append(("Earlier", earlier)) }
        return groups
    }

    public static func statusKind(conversation: ChatConversation, lastTurn: ChatTurn?) -> ThreadStatusKind {
        if let lastTurn {
            switch lastTurn.status {
            case .running:
                return .working
            case .failed:
                return .failed
            case .completed:
                switch conversation.status {
                case .archived: return .archived
                case .failed: return .failed
                default: return .completed
                }
            }
        }
        switch conversation.status {
        case .active:
            return .idle
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .archived:
            return .archived
        }
    }

    public static func statusLabel(_ kind: ThreadStatusKind) -> String {
        switch kind {
        case .working: return "Working"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .archived: return "Archived"
        case .idle: return "No activity"
        }
    }
}

// MARK: - Persistence + live mirror

@MainActor
@Observable
public final class AddedRepoStore {
    private static let defaultsKey = "dev.lancer.addedRepos"

    public private(set) var repos: [AddedRepo]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.repos = Self.load(from: userDefaults)
    }

    private let userDefaults: UserDefaults

    public func add(name: String, cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard !normalized.isEmpty else { return }
        let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = AddedRepo(
            name: display.isEmpty ? WorkspaceRepoCatalog.displayName(forCwd: normalized) : display,
            cwd: normalized
        )
        repos.removeAll { WorkspaceRepoCatalog.normalizeCwd($0.cwd) == normalized }
        repos.insert(repo, at: 0)
        persist()
    }

    public func remove(cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        repos.removeAll { WorkspaceRepoCatalog.normalizeCwd($0.cwd) == normalized }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [AddedRepo] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([AddedRepo].self, from: data)
        else { return [] }
        return decoded
    }
}

/// Observable shell-facing mirror of conversations + derived repos.
@MainActor
@Observable
public final class WorkspaceDataStore {
    public private(set) var conversations: [ChatConversation] = []
    public private(set) var lastTurnByConversationID: [String: ChatTurn] = [:]
    public let addedRepos: AddedRepoStore

    private let chatRepo: ChatConversationRepository

    public init(chatRepo: ChatConversationRepository, addedRepos: AddedRepoStore = AddedRepoStore()) {
        self.chatRepo = chatRepo
        self.addedRepos = addedRepos
    }

    public var repos: [WorkspaceRepo] {
        WorkspaceRepoCatalog.deriveRepos(
            conversations: conversations,
            added: addedRepos.repos
        )
    }

    public func refresh() async {
        let recent = (try? await chatRepo.recent(limit: 200)) ?? []
        var turns: [String: ChatTurn] = [:]
        for conversation in recent {
            if let last = try? await chatRepo.turns(conversationID: conversation.id).last {
                turns[conversation.id] = last
            }
        }
        conversations = recent
        lastTurnByConversationID = turns
    }

    public func search(_ query: String) async -> [ThreadListItem] {
        let results = (try? await chatRepo.search(query, limit: 50)) ?? []
        return results.map {
            WorkspaceRepoCatalog.threadItem(
                conversation: $0.conversation,
                lastTurn: lastTurnByConversationID[$0.conversation.id],
                includeRepoName: true
            )
        }
    }

    public func threads(forCwd cwd: String?, allRepos: Bool) -> [ThreadListItem] {
        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: cwd,
            allRepos: allRepos,
            conversations: conversations
        )
        return WorkspaceRepoCatalog.threadItems(
            conversations: filtered,
            lastTurnByConversationID: lastTurnByConversationID,
            includeRepoName: allRepos
        )
    }

    public func addRepo(name: String, cwd: String) {
        addedRepos.add(name: name, cwd: cwd)
    }
}
