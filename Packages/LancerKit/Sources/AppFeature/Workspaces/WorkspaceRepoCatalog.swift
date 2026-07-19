import Darwin
import Foundation
import Observation
import LancerCore
import PersistenceKit
import OSLog

/// Perf measurement seam (WP1, 2026-07-17) — thread-list return-visit cost.
/// Grep for "workspaceCatalog.loadLocalRows" in the device/simulator log.
private let workspaceCatalogPerfLog = Logger(subsystem: "dev.lancer.mobile", category: "WorkspaceCatalogPerf")

/// Not `#if os(iOS)`-gated (unlike `ThreadDetailPerf`'s home file) so it's
/// visible to both the cross-platform `swift build`/`swift test` gate and
/// the iOS app target — several perf log call sites across both need it.
extension Duration {
    /// Millisecond value for perf log lines — `Duration` has no direct
    /// Double conversion, only `.components` (seconds, attoseconds).
    var asMilliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}

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
    /// Session-total +/− from local tool/diff artifacts (same source SessionDiffPill uses).
    public let addedLines: Int?
    public let removedLines: Int?
    public let previewSnippet: String?
    public let unread: Bool

    public init(
        id: String,
        title: String,
        statusKind: ThreadStatusKind,
        statusLabel: String,
        repoName: String?,
        cwd: String,
        lastActivityAt: Date,
        addedLines: Int? = nil,
        removedLines: Int? = nil,
        previewSnippet: String? = nil,
        unread: Bool = false
    ) {
        self.id = id
        self.title = title
        self.statusKind = statusKind
        self.statusLabel = statusLabel
        self.repoName = repoName
        self.cwd = cwd
        self.lastActivityAt = lastActivityAt
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.previewSnippet = previewSnippet
        self.unread = unread
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

        // Never expand "~": these are HOST paths, and on iOS
        // NSHomeDirectory() is the app sandbox — expansion mints a bogus
        // absolute path that splits into its own repo bucket (owner-phone
        // triple-row bug, 2026-07-12). Tilde paths keep their prefix and are
        // suffix-matched in bucketKey; the daemon expands host-side.
        var path = trimmed
        if !isTildeCwd(path) {
            path = resolveSymlinksWherePossible(path)
        }
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        return path
    }

    /// True for "~" or "~/…" — a host-home-relative path.
    public static func isTildeCwd(_ path: String) -> Bool {
        path == "~" || path.hasPrefix("~/")
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
        if !isAbsoluteCwd(normalized) && !isTildeCwd(normalized) { return normalized }
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
        // Tilde paths are valid targets: the daemon expands "~" against the
        // HOST home and then fail-closed validates (resolveDispatchCWD).
        return !normalized.isEmpty && (isAbsoluteCwd(normalized) || isTildeCwd(normalized))
    }

    public static func isAbsoluteCwd(_ cwd: String) -> Bool {
        // NSString.isAbsolutePath counts "~/…" as absolute; for bucketing a
        // tilde path is host-relative until the daemon expands it.
        !isTildeCwd(cwd) && (cwd as NSString).isAbsolutePath
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

        if isTildeCwd(normalized) {
            // "~/Documents/x" is a host path: fold into the unique absolute
            // root ending in the same component suffix ("/documents/x").
            let suffixKey = pathKey(String(normalized.dropFirst()))
            let matches = normalizedRoots.filter { root in
                isAbsoluteCwd(root)
                    && (suffixKey.isEmpty
                        ? isHostHomePath(root)
                        : pathKey(root).hasSuffix(suffixKey))
            }
            if matches.count == 1 {
                return matches[0]
            }
            return normalized
        }

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

        for (_, addedRepo) in addedByKey {
            // Bucket added cwds with the same rule as conversations, so a
            // "~/…" or aliased added repo folds into the discovered root
            // instead of minting a duplicate row.
            let bucket = bucketKey(forCwd: addedRepo.cwd, among: roots) ?? addedRepo.cwd
            let key = pathKey(bucket)
            if let existing = byKey[key] {
                byKey[key] = WorkspaceRepo(
                    name: addedRepo.name.isEmpty ? existing.name : addedRepo.name,
                    cwd: existing.cwd,
                    threadCount: existing.threadCount,
                    isUserAdded: true
                )
            } else {
                byKey[key] = WorkspaceRepo(
                    name: addedRepo.name.isEmpty
                        ? displayName(forCwd: bucket, homeDirectory: homeDirectory)
                        : addedRepo.name,
                    cwd: bucket,
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

    /// Default composer / thread-list send target: most-recently-active absolute
    /// cwd that is not in `failedCwdKeys`, mapped to a `WorkspaceRepo` row;
    /// falls back to the first absolute repo row not marked failed.
    public static func preferredDefaultRepo(
        repos: [WorkspaceRepo],
        conversations: [ChatConversation],
        added: [AddedRepo] = [],
        failedCwdKeys: Set<String> = []
    ) -> WorkspaceRepo? {
        func isFailed(_ cwd: String) -> Bool {
            let key = pathKey(cwd)
            return !key.isEmpty && failedCwdKeys.contains(key)
        }

        let roots = computeRoots(
            conversationCwds: conversations.map(\.cwd),
            addedCwds: added.map(\.cwd)
        )

        func repo(matchingConversationCwd cwd: String) -> WorkspaceRepo? {
            guard let bucket = bucketKey(forCwd: cwd, among: roots) else { return nil }
            let key = pathKey(bucket)
            return repos.first { pathKey($0.cwd) == key }
        }

        let sorted = conversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
        for conversation in sorted {
            let cwd = normalizeCwd(conversation.cwd)
            guard isAbsoluteSendTarget(cwd), !isFailed(cwd) else { continue }
            if let match = repo(matchingConversationCwd: cwd) {
                return match
            }
        }

        return repos.first { isAbsoluteSendTarget($0.cwd) && !isFailed($0.cwd) }
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
        includeRepoName: Bool,
        addedLines: Int? = nil,
        removedLines: Int? = nil,
        lastOpenedAt: Date? = nil
    ) -> ThreadListItem {
        let kind = statusKind(conversation: conversation, lastTurn: lastTurn)
        return ThreadListItem(
            id: conversation.id,
            title: conversation.title.isEmpty ? "Untitled thread" : conversation.title,
            statusKind: kind,
            statusLabel: statusLabel(kind),
            repoName: includeRepoName ? displayName(forCwd: conversation.cwd) : nil,
            cwd: normalizeCwd(conversation.cwd),
            lastActivityAt: conversation.lastActivityAt,
            addedLines: addedLines,
            removedLines: removedLines,
            previewSnippet: ThreadListMetadata.previewSnippet(lastTurn: lastTurn),
            unread: ThreadListMetadata.isUnread(
                lastActivityAt: conversation.lastActivityAt,
                lastOpenedAt: lastOpenedAt
            )
        )
    }

    public static func threadItems(
        conversations: [ChatConversation],
        lastTurnByConversationID: [String: ChatTurn],
        includeRepoName: Bool,
        diffByConversationID: [String: (added: Int, removed: Int)] = [:],
        lastOpenedAtByConversationID: [String: Date] = [:]
    ) -> [ThreadListItem] {
        conversations.map {
            let diff = diffByConversationID[$0.id]
            return threadItem(
                conversation: $0,
                lastTurn: lastTurnByConversationID[$0.id],
                includeRepoName: includeRepoName,
                addedLines: diff?.added,
                removedLines: diff?.removed,
                lastOpenedAt: lastOpenedAtByConversationID[$0.id]
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
        groupByRecency(items, date: \.lastActivityAt, now: now, calendar: calendar)
    }

    /// Same recency buckets as the ledger overload, keyed by an arbitrary date.
    public static func groupByRecency<T>(
        _ items: [T],
        date: KeyPath<T, Date>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(title: String, items: [T])] {
        guard !items.isEmpty else { return [] }

        var today: [T] = []
        var yesterday: [T] = []
        var thisWeek: [T] = []
        var earlier: [T] = []

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        for item in items {
            let activity = item[keyPath: date]
            if activity >= startOfToday {
                today.append(item)
            } else if activity >= startOfYesterday {
                yesterday.append(item)
            } else if activity >= startOfWeek {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [(title: String, items: [T])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !earlier.isEmpty { groups.append(("Earlier", earlier)) }
        return groups
    }

    /// Group by repo display title. Callers should pass newest-first items so
    /// first-seen order yields newest-activity groups; items keep input order.
    public static func groupByRepo<T>(
        _ items: [T],
        title: KeyPath<T, String>
    ) -> [(title: String, items: [T])] {
        guard !items.isEmpty else { return [] }

        var buckets: [String: [T]] = [:]
        var order: [String] = []
        for item in items {
            let key = item[keyPath: title]
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = [item]
            } else {
                buckets[key]!.append(item)
            }
        }
        return order.map { (title: $0, items: buckets[$0]!) }
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

/// Host cwds rejected by `resolveDispatchCWD` (`cwd does not exist`) — excluded
/// from default composer selection until the user picks another folder.
@MainActor
@Observable
public final class FailedCwdStore {
    private static let defaultsKey = "dev.lancer.failedCwds"

    public private(set) var pathKeys: Set<String>

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.pathKeys = Self.load(from: userDefaults)
    }

    private let userDefaults: UserDefaults

    public func contains(cwd: String) -> Bool {
        let key = WorkspaceRepoCatalog.pathKey(cwd)
        guard !key.isEmpty else { return false }
        return pathKeys.contains(key)
    }

    public func markFailed(_ cwd: String) {
        let key = WorkspaceRepoCatalog.pathKey(cwd)
        guard !key.isEmpty else { return }
        guard pathKeys.insert(key).inserted else { return }
        persist()
    }

    private func persist() {
        let sorted = Array(pathKeys).sorted()
        userDefaults.set(sorted, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> Set<String> {
        guard let stored = defaults.array(forKey: defaultsKey) as? [String] else {
            return []
        }
        return Set(stored)
    }
}

/// Catalog list/search fetch honesty — first paint vs failed refresh vs ready.
public enum WorkspaceCatalogFetchPhase: Equatable, Sendable {
    /// No successful load yet; not currently fetching.
    case pending
    /// In-flight refresh (first paint or retry).
    case loading
    /// At least one successful local row load.
    case ready
    /// Last refresh failed. `message` is user-facing; prior rows may still be present.
    case failed(message: String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Result of `WorkspaceDataStore.search` — never collapses transport failure into "no matches".
public enum WorkspaceSearchResult: Equatable, Sendable {
    case success([ThreadListItem])
    case failure(String)
}

/// Observable shell-facing mirror of conversations + derived repos.
@MainActor
@Observable
public final class WorkspaceDataStore {
    public private(set) var conversations: [ChatConversation] = []
    public private(set) var lastTurnByConversationID: [String: ChatTurn] = [:]
    public private(set) var diffByConversationID: [String: (added: Int, removed: Int)] = [:]
    /// First-paint / refresh honesty for Workspaces, ThreadList, and Search.
    public private(set) var fetchPhase: WorkspaceCatalogFetchPhase = .pending
    public let addedRepos: AddedRepoStore
    public let failedCwds: FailedCwdStore
    public let readReceipts: ConversationReadReceiptStore

    private let chatRepo: ChatConversationRepository
    private var refreshGeneration: UInt64 = 0
    private var hasLoadedSuccessfully = false
    /// Optional host list sync — when any mirrored last-turn is still
    /// `.running`, `refresh()` awaits this before re-reading local rows so
    /// stale "Working" badges clear after daemon orphan reconciliation.
    /// Set from `AppRoot`; nil / failure → list still renders local data.
    public var syncRunningStatuses: (() async -> Void)?

    /// Pulls one conversation's turns/events from the host into the local
    /// mirror (fetch-on-open). Backfilled threads otherwise open empty —
    /// the list backfill copies summaries only. Set from `AppRoot`.
    /// Throws on transport/hydration failure so ThreadDetail can surface
    /// a retryable state instead of silently keeping empty assistant bodies.
    public var refreshThreadFromHost: ((_ conversationID: String) async throws -> Void)?

    public init(
        chatRepo: ChatConversationRepository,
        addedRepos: AddedRepoStore = AddedRepoStore(),
        failedCwds: FailedCwdStore = FailedCwdStore(),
        readReceipts: ConversationReadReceiptStore = ConversationReadReceiptStore()
    ) {
        self.chatRepo = chatRepo
        self.addedRepos = addedRepos
        self.failedCwds = failedCwds
        self.readReceipts = readReceipts
    }

    public var repos: [WorkspaceRepo] {
        WorkspaceRepoCatalog.deriveRepos(
            conversations: conversations,
            added: addedRepos.repos
        )
    }

    /// Composer / thread-list default — recency-first absolute send target,
    /// skipping host paths previously rejected with `cwd does not exist`.
    public var defaultRepo: WorkspaceRepo? {
        WorkspaceRepoCatalog.preferredDefaultRepo(
            repos: repos,
            conversations: conversations,
            added: addedRepos.repos,
            failedCwdKeys: failedCwds.pathKeys
        )
    }

    /// True on first paint before any successful catalog load (show ProgressView, not empty).
    public var showsInitialLoading: Bool {
        !hasLoadedSuccessfully && fetchPhase.isLoading
    }

    public func refresh() async {
        // Local rows render immediately; the host sync (which may wait for the
        // relay to reconnect) runs in the background, then local rows are
        // re-read so a cleared "Working" badge lands without blocking first
        // paint. The sync must run UNCONDITIONALLY: gating it on a local
        // running turn meant a fresh install (empty mirror) never backfilled
        // the host's conversation history at all (owner phone, 2026-07-12).
        //
        // Mark `.ready` after the first successful local read and return —
        // never keep callers (All Repos / Workspaces) awaiting an 8s relay
        // round-trip when SwiftData already has rows (2026-07-16).
        refreshGeneration += 1
        let token = refreshGeneration
        if !hasLoadedSuccessfully {
            fetchPhase = .loading
        }
        do {
            try await loadLocalRows()
            guard token == refreshGeneration else { return }
            hasLoadedSuccessfully = true
            fetchPhase = .ready
            guard let syncRunningStatuses else { return }
            let sync = syncRunningStatuses
            Task { @MainActor in
                await sync()
                guard token == self.refreshGeneration else { return }
                do {
                    try await self.loadLocalRows()
                    guard token == self.refreshGeneration else { return }
                    self.fetchPhase = .ready
                } catch {
                    guard token == self.refreshGeneration else { return }
                    self.fetchPhase = .failed(message: error.localizedDescription)
                }
            }
        } catch {
            guard token == refreshGeneration else { return }
            fetchPhase = .failed(message: error.localizedDescription)
        }
    }

    /// Was an N+1 loop (up to 200 sequential `turns(conversationID:)` full
    /// scans + `artifacts(turnID:)` calls, one pair per conversation) that
    /// re-ran on every thread-list appear/return-visit. Now two batched
    /// round trips regardless of conversation count — see
    /// `ChatConversationRepository.latestTurns(conversationIDs:)` and
    /// `artifacts(turnIDs:)`. Measured 2026-07-17 —
    /// docs/test-runs/2026-07-17-perf/README.md.
    private func loadLocalRows() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let recent = try await chatRepo.recent(limit: 200)
        let conversationIDs = recent.map(\.id)
        let turns = try await chatRepo.latestTurns(conversationIDs: conversationIDs)
        let turnIDs = turns.values.map(\.id)
        let artifactsByTurnID = try await chatRepo.artifacts(turnIDs: turnIDs)

        var diffs: [String: (added: Int, removed: Int)] = [:]
        for (conversationID, turn) in turns {
            // Latest turn's artifacts — same +/− chips SessionDiffPill's
            // local path derives from (no per-row sessionDiff RPC).
            if let artifacts = artifactsByTurnID[turn.id],
               let totals = ThreadListMetadata.diffTotals(fromArtifacts: artifacts) {
                diffs[conversationID] = totals
            }
        }
        conversations = recent
        lastTurnByConversationID = turns
        diffByConversationID = diffs
        let elapsed = start.duration(to: clock.now)
        workspaceCatalogPerfLog.notice("workspaceCatalog.loadLocalRows conversations=\(recent.count) elapsedMs=\(elapsed.asMilliseconds, privacy: .public)")
    }

    public func search(_ query: String) async -> WorkspaceSearchResult {
        let results: [ChatConversationSearchResult]
        do {
            results = try await chatRepo.search(query, limit: 50)
        } catch {
            return .failure(error.localizedDescription)
        }
        var items: [ThreadListItem] = []
        items.reserveCapacity(results.count)
        for result in results {
            let lastTurn = (try? await chatRepo.turns(conversationID: result.conversation.id))?.last
            var added: Int?
            var removed: Int?
            if let lastTurn,
               let artifacts = try? await chatRepo.artifacts(turnID: lastTurn.id),
               let totals = ThreadListMetadata.diffTotals(fromArtifacts: artifacts) {
                added = totals.added
                removed = totals.removed
            }
            items.append(
                WorkspaceRepoCatalog.threadItem(
                    conversation: result.conversation,
                    lastTurn: lastTurn,
                    includeRepoName: true,
                    addedLines: added,
                    removedLines: removed,
                    lastOpenedAt: readReceipts.lastOpenedAt(conversationID: result.conversation.id)
                )
            )
        }
        return .success(items)
    }

    public func threads(forCwd cwd: String?, allRepos: Bool) -> [ThreadListItem] {
        let filtered = WorkspaceRepoCatalog.conversations(
            forCwd: cwd,
            allRepos: allRepos,
            conversations: conversations,
            added: addedRepos.repos
        )
        var opened: [String: Date] = [:]
        for conversation in filtered {
            if let at = readReceipts.lastOpenedAt(conversationID: conversation.id) {
                opened[conversation.id] = at
            }
        }
        return WorkspaceRepoCatalog.threadItems(
            conversations: filtered,
            lastTurnByConversationID: lastTurnByConversationID,
            includeRepoName: allRepos,
            diffByConversationID: diffByConversationID,
            lastOpenedAtByConversationID: opened
        )
    }

    public func markThreadOpened(_ conversationID: String) {
        readReceipts.markOpened(conversationID)
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
