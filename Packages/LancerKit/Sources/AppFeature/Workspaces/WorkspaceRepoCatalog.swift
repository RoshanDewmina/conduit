import Darwin
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
    /// Canonical path form used everywhere paths meet: expand `~`, resolve
    /// symlinks when cheap (e.g. `/tmp` → `/private/tmp`), strip trailing slash.
    /// Comparison helpers are case-insensitive while this form preserves case.
    public static func normalizeCwd(_ cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var path = (trimmed as NSString).expandingTildeInPath
        path = resolveSymlinksWherePossible(path)
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        return path
    }

    /// Resolve the deepest existing path prefix via `realpath`, then reattach
    /// any missing suffix. No-ops when nothing on the local FS matches (remote
    /// Mac paths on the phone stay unchanged).
    private static func resolveSymlinksWherePossible(_ path: String) -> String {
        var suffix: [String] = []
        var probe = path
        while true {
            if let resolved = posixRealpath(probe) {
                var result = resolved
                for part in suffix.reversed() {
                    result = (result as NSString).appendingPathComponent(part)
                }
                return result
            }
            if probe == "/" || probe.isEmpty { return path }
            let parent = (probe as NSString).deletingLastPathComponent
            let leaf = (probe as NSString).lastPathComponent
            if parent == probe { return path }
            suffix.append(leaf)
            probe = parent
        }
    }

    private static func posixRealpath(_ path: String) -> String? {
        path.withCString { cPath in
            guard let resolved = realpath(cPath, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// Case-insensitive equality of normalized paths (case-preserving storage).
    public static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeCwd(lhs)
        let b = normalizeCwd(rhs)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// True when `cwd` is the repo path or a descendant (worktree / subdir).
    public static func isEqualOrUnder(cwd: String, repoPath: String) -> Bool {
        let child = normalizeCwd(cwd)
        let root = normalizeCwd(repoPath)
        guard !child.isEmpty, !root.isEmpty else { return false }
        if pathsMatch(child, root) { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return child.lowercased().hasPrefix(prefix.lowercased())
    }

    /// Stable dictionary key for path-keyed maps (case-folded normalized form).
    public static func pathKey(_ cwd: String) -> String {
        normalizeCwd(cwd).lowercased()
    }

    public static func displayName(forCwd cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return "Home" }
        let normalized = normalizeCwd(cwd)
        guard !normalized.isEmpty else { return "Untitled" }
        if pathsMatch(normalized, NSHomeDirectory()) { return "Home" }
        let base = (normalized as NSString).lastPathComponent
        return base.isEmpty ? normalized : base
    }

    /// Longest matching repo cwd that equals or contains `cwd`, if any.
    public static func matchingRepoCwd(for cwd: String, among repoCwds: [String]) -> String? {
        let needle = normalizeCwd(cwd)
        guard !needle.isEmpty else { return nil }
        return repoCwds
            .map(normalizeCwd)
            .filter { !$0.isEmpty && isEqualOrUnder(cwd: needle, repoPath: $0) }
            .max(by: { $0.count < $1.count })
    }

    /// Merge distinct conversation cwds with user-added repos. Sorted by
    /// thread count (desc), then name. Empty / home-only placeholder cwds
    /// from conversations are omitted unless the user explicitly added them.
    /// Subpath conversations count under the longest matching added (or
    /// derived) repo rather than spawning a sibling row.
    public static func deriveRepos(
        conversations: [ChatConversation],
        added: [AddedRepo]
    ) -> [WorkspaceRepo] {
        let addedNormalized: [(key: String, cwd: String, name: String)] = added.compactMap { repo in
            let cwd = normalizeCwd(repo.cwd)
            guard !cwd.isEmpty else { return nil }
            return (pathKey(cwd), cwd, repo.name)
        }

        // Prefer first-seen casing for each added key (deduped).
        var addedByKey: [String: (cwd: String, name: String)] = [:]
        for entry in addedNormalized {
            if addedByKey[entry.key] == nil {
                addedByKey[entry.key] = (entry.cwd, entry.name)
            }
        }
        let addedCwds = Array(addedByKey.values.map(\.cwd))

        var counts: [String: Int] = [:]
        var displayCwdByKey: [String: String] = [:]

        for conversation in conversations {
            let cwd = normalizeCwd(conversation.cwd)
            guard !cwd.isEmpty else { continue }
            let bucket = matchingRepoCwd(for: cwd, among: addedCwds) ?? cwd
            let key = pathKey(bucket)
            counts[key, default: 0] += 1
            if displayCwdByKey[key] == nil {
                displayCwdByKey[key] = normalizeCwd(bucket)
            }
        }

        var byKey: [String: WorkspaceRepo] = [:]

        for (key, count) in counts {
            let cwd = displayCwdByKey[key] ?? key
            byKey[key] = WorkspaceRepo(
                name: displayName(forCwd: cwd),
                cwd: cwd,
                threadCount: count,
                isUserAdded: false
            )
        }

        for (key, addedRepo) in addedByKey {
            if let existing = byKey[key] {
                byKey[key] = WorkspaceRepo(
                    name: addedRepo.name.isEmpty ? existing.name : addedRepo.name,
                    cwd: addedRepo.cwd,
                    threadCount: existing.threadCount,
                    isUserAdded: true
                )
            } else {
                byKey[key] = WorkspaceRepo(
                    name: addedRepo.name.isEmpty ? displayName(forCwd: addedRepo.cwd) : addedRepo.name,
                    cwd: addedRepo.cwd,
                    threadCount: 0,
                    isUserAdded: true
                )
            }
        }

        return byKey.values.sorted {
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
        guard !needle.isEmpty else { return [] }
        return sorted.filter { isEqualOrUnder(cwd: $0.cwd, repoPath: needle) }
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

    /// Adds a repo, or returns the existing one when the normalized path already
    /// exists (no-op — does not replace name / bump position).
    @discardableResult
    public func add(name: String, cwd: String) -> AddedRepo? {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard !normalized.isEmpty else { return nil }
        if let existing = repos.first(where: {
            WorkspaceRepoCatalog.pathsMatch($0.cwd, normalized)
        }) {
            return existing
        }
        let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = AddedRepo(
            name: display.isEmpty ? WorkspaceRepoCatalog.displayName(forCwd: normalized) : display,
            cwd: normalized
        )
        repos.insert(repo, at: 0)
        persist()
        return repo
    }

    public func remove(cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        repos.removeAll { WorkspaceRepoCatalog.pathsMatch($0.cwd, normalized) }
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
        return deduplicate(decoded)
    }

    /// Keep first occurrence of each normalized path; drop later duplicates.
    static func deduplicate(_ repos: [AddedRepo]) -> [AddedRepo] {
        var seen: Set<String> = []
        var result: [AddedRepo] = []
        for repo in repos {
            let normalized = WorkspaceRepoCatalog.normalizeCwd(repo.cwd)
            guard !normalized.isEmpty else { continue }
            let key = WorkspaceRepoCatalog.pathKey(normalized)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(AddedRepo(name: repo.name, cwd: normalized, addedAt: repo.addedAt))
        }
        return result
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

    @discardableResult
    public func addRepo(name: String, cwd: String) -> AddedRepo? {
        addedRepos.add(name: name, cwd: cwd)
    }

    /// Resolves a run's `lancer.proof/v0` receipt for the live thread card.
    /// Prefers the materialized `chat_artifacts` row; falls back to a mirrored
    /// `chat_events` row (`kind == "receipt"`) when the artifact isn't present yet.
    public func receipt(runID: String, conversationID: String) async -> ProofReceipt? {
        if let artifacts = try? await chatRepo.artifacts(runID: runID) {
            for artifact in artifacts where artifact.kind == .receipt {
                if let receipt = ProofReelModel.decodeReceipt(from: artifact) {
                    return receipt
                }
            }
        }
        let events = (try? await chatRepo.events(conversationID: conversationID, sinceSeq: 0, limit: 5000)) ?? []
        for event in events.reversed() where event.kind == "receipt" && event.runID == runID {
            if let receipt = ProofReelModel.decodeReceipt(from: event) {
                return receipt
            }
        }
        return nil
    }
}
