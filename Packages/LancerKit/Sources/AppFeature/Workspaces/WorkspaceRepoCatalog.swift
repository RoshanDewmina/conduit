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

    public static func displayName(
        forCwd cwd: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return "Home" }
        let normalized = normalizeCwd(cwd)
        guard !normalized.isEmpty else { return "No folder" }
        if pathsMatch(normalized, homeDirectory) { return "Home" }
        if isHostHomePath(normalized) { return "Home" }
        if !isAbsoluteCwd(normalized) { return normalized }
        let base = (normalized as NSString).lastPathComponent
        return base.isEmpty ? normalized : base
    }

    /// True for a host machine's home directory (`/Users/<name>`, `/home/<name>`).
    /// On iOS `NSHomeDirectory()` is the app sandbox, so host cwds coming from the
    /// daemon ledger can only be recognized by shape.
    public static func isHostHomePath(_ path: String) -> Bool {
        var components = (path as NSString).pathComponents
        if components.last == "/" { components.removeLast() }
        guard components.count == 3, components[0] == "/" else { return false }
        return components[1] == "Users" || components[1] == "home"
    }

    /// True when `cwd` is a non-empty absolute path after normalize — the only
    /// kind of target live sends may use.
    public static func isAbsoluteSendTarget(_ cwd: String) -> Bool {
        let normalized = normalizeCwd(cwd)
        return !normalized.isEmpty && isAbsoluteCwd(normalized)
    }

    public static func isAbsoluteCwd(_ cwd: String) -> Bool {
        (cwd as NSString).isAbsolutePath
    }

    /// True when the relative path from `ancestor` to `descendant` crosses a
    /// hidden path component (`.worktrees`, `.claude`, …).
    public static func hasHiddenComponent(between ancestor: String, and descendant: String) -> Bool {
        let root = normalizeCwd(ancestor)
        let child = normalizeCwd(descendant)
        guard !root.isEmpty, !child.isEmpty else { return false }
        guard isEqualOrUnder(cwd: child, repoPath: root), !pathsMatch(child, root) else { return false }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard child.lowercased().hasPrefix(prefix.lowercased()) else { return false }
        let remainder = String(child.dropFirst(prefix.count))
        return remainder.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Discovered + added repo roots used by `bucketKey`.
    /// Nested conversation cwds stay independent roots unless the path between
    /// them crosses a hidden directory (worktree-style). Relative cwds are
    /// kept as provisional roots and may merge later via last-component match.
    public static func computeRoots(
        conversationCwds: [String],
        addedCwds: [String]
    ) -> [String] {
        var absolute: [String] = []
        var relative: [String] = []
        var seenAbsolute: Set<String> = []
        var seenRelative: Set<String> = []

        for raw in conversationCwds + addedCwds {
            let cwd = normalizeCwd(raw)
            guard !cwd.isEmpty else { continue }
            if isAbsoluteCwd(cwd) {
                let key = pathKey(cwd)
                if seenAbsolute.insert(key).inserted {
                    absolute.append(cwd)
                }
            } else {
                let key = pathKey(cwd)
                if seenRelative.insert(key).inserted {
                    relative.append(cwd)
                }
            }
        }

        let absoluteRoots = absolute.filter { candidate in
            !absolute.contains { ancestor in
                pathKey(ancestor) != pathKey(candidate)
                    && isEqualOrUnder(cwd: candidate, repoPath: ancestor)
                    && !pathsMatch(candidate, ancestor)
                    && hasHiddenComponent(between: ancestor, and: candidate)
            }
        }
        return absoluteRoots + relative
    }

    /// Single bucketing rule for rows, counts, tap-filters, and search chips.
    /// Returns the normalized bucket cwd, or `nil` for empty cwd.
    public static func bucketKey(
        forCwd cwd: String,
        among roots: [String]
    ) -> String? {
        let normalized = normalizeCwd(cwd)
        guard !normalized.isEmpty else { return nil }

        let normalizedRoots = roots.map(normalizeCwd).filter { !$0.isEmpty }

        if !isAbsoluteCwd(normalized) {
            let matches = normalizedRoots.filter { root in
                isAbsoluteCwd(root)
                    && (root as NSString).lastPathComponent
                    .caseInsensitiveCompare(normalized) == .orderedSame
            }
            if matches.count == 1 {
                return matches[0]
            }
            return normalized
        }

        // Longest matching root: home is last resort because it is shortest.
        let matching = normalizedRoots.filter { isEqualOrUnder(cwd: normalized, repoPath: $0) }
        if let best = matching.max(by: { $0.count < $1.count }) {
            return best
        }
        return normalized
    }

    /// Merge distinct conversation cwds with user-added repos. Sorted by
    /// thread count (desc), then name. Empty cwds are omitted from rows.
    /// One `bucketKey` rule absorbs worktrees / relative aliases into the
    /// longest matching root among added ∪ discovered roots.
    public static func deriveRepos(
        conversations: [ChatConversation],
        added: [AddedRepo],
        homeDirectory: String = NSHomeDirectory()
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
        let roots = computeRoots(
            conversationCwds: conversations.map(\.cwd),
            addedCwds: addedCwds
        )

        var counts: [String: Int] = [:]
        var displayCwdByKey: [String: String] = [:]

        for conversation in conversations {
            guard let bucket = bucketKey(
                forCwd: conversation.cwd,
                among: roots
            ) else { continue }
            let key = pathKey(bucket)
            counts[key, default: 0] += 1
            if displayCwdByKey[key] == nil {
                displayCwdByKey[key] = bucket
            }
        }

        var byKey: [String: WorkspaceRepo] = [:]

        for (key, count) in counts {
            let cwd = displayCwdByKey[key] ?? key
            byKey[key] = WorkspaceRepo(
                name: displayName(forCwd: cwd, homeDirectory: homeDirectory),
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
                    name: addedRepo.name.isEmpty
                        ? displayName(forCwd: addedRepo.cwd, homeDirectory: homeDirectory)
                        : addedRepo.name,
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
        conversations: [ChatConversation],
        added: [AddedRepo] = []
    ) -> [ChatConversation] {
        let sorted = conversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
        guard !allRepos else { return sorted }
        guard let cwd else { return [] }
        let roots = computeRoots(
            conversationCwds: conversations.map(\.cwd),
            addedCwds: added.map(\.cwd)
        )
        guard let needle = bucketKey(forCwd: cwd, among: roots) else {
            return []
        }
        let needleKey = pathKey(needle)
        return sorted.filter { conversation in
            guard let bucket = bucketKey(
                forCwd: conversation.cwd,
                among: roots
            ) else { return false }
            return pathKey(bucket) == needleKey
        }
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
    /// Today = `[startOfToday, ∞)`, Yesterday = `[startOfYesterday, startOfToday)`.
    public static func groupByRecency(
        _ items: [ThreadListItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(title: String, items: [ThreadListItem])] {
        guard !items.isEmpty else { return [] }

        var today: [ThreadListItem] = []
        var yesterday: [ThreadListItem] = []
        var thisWeek: [ThreadListItem] = []
        var earlier: [ThreadListItem] = []

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        for item in items {
            if item.lastActivityAt >= startOfToday {
                today.append(item)
            } else if item.lastActivityAt >= startOfYesterday {
                yesterday.append(item)
            } else if item.lastActivityAt >= startOfWeek {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [(title: String, items: [ThreadListItem])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
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
        case .idle: return "No runs yet"
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
            name: display.isEmpty
                ? WorkspaceRepoCatalog.displayName(forCwd: normalized)
                : display,
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
    /// Optional host list sync — when any mirrored last-turn is still
    /// `.running`, `refresh()` awaits this before re-reading local rows so
    /// stale "Working" badges clear after daemon orphan reconciliation.
    /// Set from `AppRoot`; nil / failure → list still renders local data.
    public var syncRunningStatuses: (() async -> Void)?

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
        // Local rows render immediately; the host sync (which may wait for the
        // relay to reconnect) runs after, then local rows are re-read so a
        // cleared "Working" badge lands without blocking the first paint.
        await loadLocalRows()
        if await hasLocalRunningLastTurn(), let syncRunningStatuses {
            await syncRunningStatuses()
            await loadLocalRows()
        }
    }

    private func loadLocalRows() async {
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

    private func hasLocalRunningLastTurn() async -> Bool {
        let recent = (try? await chatRepo.recent(limit: 200)) ?? []
        for conversation in recent {
            if let last = try? await chatRepo.turns(conversationID: conversation.id).last,
               last.status == .running {
                return true
            }
        }
        return false
    }

    public func search(_ query: String) async -> [ThreadListItem] {
        let results = (try? await chatRepo.search(query, limit: 50)) ?? []
        var items: [ThreadListItem] = []
        items.reserveCapacity(results.count)
        for result in results {
            let lastTurn = (try? await chatRepo.turns(conversationID: result.conversation.id))?.last
            items.append(
                WorkspaceRepoCatalog.threadItem(
                    conversation: result.conversation,
                    lastTurn: lastTurn,
                    includeRepoName: true
                )
            )
        }
        return items
    }

    public func threads(forCwd cwd: String?, allRepos: Bool) -> [ThreadListItem] {
        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: cwd,
            allRepos: allRepos,
            conversations: conversations,
            added: addedRepos.repos
        )
        return WorkspaceRepoCatalog.threadItems(
            conversations: filtered,
            lastTurnByConversationID: lastTurnByConversationID,
            includeRepoName: allRepos
        )
    }

    /// All Repos badge — must equal the row count the All Repos tap shows
    /// (`threads(forCwd: nil, allRepos: true)`), which includes empty-cwd
    /// "No folder" conversations even though they are excluded from repo rows.
    public var allReposThreadCount: Int {
        conversations.count
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
