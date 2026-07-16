import Foundation
import LancerCore

/// How the thread list groups rows after filtering.
public enum ThreadListGroupBy: String, CaseIterable, Sendable, Hashable {
    case recency
    case repo

    public var label: String {
        switch self {
        case .recency: return "Recency"
        case .repo: return "Repo"
        }
    }
}

/// Honest origins present in the unified thread list.
/// Phone = ledger (`ThreadListRowKind.ledger`); Desktop = observed sessions.
/// Automation is omitted — `SessionSource` does not expose a distinct automation origin.
public enum ThreadListFilterSource: String, CaseIterable, Sendable, Hashable {
    case phone
    case desktop

    public var label: String {
        switch self {
        case .phone: return "Phone"
        case .desktop: return "Desktop"
        }
    }
}

/// Status buckets on the Cursor-style Status filter sheet.
/// `unread` reuses the thread-list metadata flag; Draft is omitted (no ledger concept).
public enum ThreadListFilterStatus: String, CaseIterable, Sendable, Hashable {
    case working
    case completed
    case failed
    case archived
    case unread

    public var label: String {
        switch self {
        case .working: return "Working"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .archived: return "Archived"
        case .unread: return "Unread"
        }
    }
}

/// Persisted Customize / Status / Source preferences for the thread list.
public struct ThreadListFilterPrefs: Equatable, Sendable, Hashable {
    public var showAllStatuses: Bool
    public var showWorking: Bool
    public var showCompleted: Bool
    public var showFailed: Bool
    public var showArchived: Bool
    public var showUnread: Bool

    public var showAllSources: Bool
    public var showPhone: Bool
    public var showDesktop: Bool

    public var groupBy: ThreadListGroupBy
    public var showDiffStats: Bool
    public var showLastUpdated: Bool

    public static let `default` = ThreadListFilterPrefs(
        showAllStatuses: true,
        showWorking: true,
        showCompleted: true,
        showFailed: true,
        showArchived: true,
        showUnread: true,
        showAllSources: true,
        showPhone: true,
        showDesktop: true,
        groupBy: .recency,
        showDiffStats: true,
        showLastUpdated: true
    )

    public init(
        showAllStatuses: Bool = true,
        showWorking: Bool = true,
        showCompleted: Bool = true,
        showFailed: Bool = true,
        showArchived: Bool = true,
        showUnread: Bool = true,
        showAllSources: Bool = true,
        showPhone: Bool = true,
        showDesktop: Bool = true,
        groupBy: ThreadListGroupBy = .recency,
        showDiffStats: Bool = true,
        showLastUpdated: Bool = true
    ) {
        self.showAllStatuses = showAllStatuses
        self.showWorking = showWorking
        self.showCompleted = showCompleted
        self.showFailed = showFailed
        self.showArchived = showArchived
        self.showUnread = showUnread
        self.showAllSources = showAllSources
        self.showPhone = showPhone
        self.showDesktop = showDesktop
        self.groupBy = groupBy
        self.showDiffStats = showDiffStats
        self.showLastUpdated = showLastUpdated
    }

    public enum StorageKey {
        public static let showAllStatuses = "dev.lancer.threadList.filter.showAllStatuses"
        public static let showWorking = "dev.lancer.threadList.filter.showWorking"
        public static let showCompleted = "dev.lancer.threadList.filter.showCompleted"
        public static let showFailed = "dev.lancer.threadList.filter.showFailed"
        public static let showArchived = "dev.lancer.threadList.filter.showArchived"
        public static let showUnread = "dev.lancer.threadList.filter.showUnread"
        public static let showAllSources = "dev.lancer.threadList.filter.showAllSources"
        public static let showPhone = "dev.lancer.threadList.filter.showPhone"
        public static let showDesktop = "dev.lancer.threadList.filter.showDesktop"
        public static let groupBy = "dev.lancer.threadList.filter.groupBy"
        public static let showDiffStats = "dev.lancer.threadList.filter.showDiffStats"
        public static let showLastUpdated = "dev.lancer.threadList.filter.showLastUpdated"
    }
}

/// Pure status/source mapping + filter predicates (unit-tested on macOS).
public enum ThreadListFilters {
    /// Map a ledger row's `ThreadStatusKind` into a Status-sheet bucket.
    /// Idle ("No runs yet") folds into Completed — closest honest match; no Draft.
    public static func statusBucket(for kind: ThreadStatusKind) -> ThreadListFilterStatus {
        switch kind {
        case .working: return .working
        case .completed, .idle: return .completed
        case .failed: return .failed
        case .archived: return .archived
        }
    }

    /// Map an observed desktop session's live state into a Status-sheet bucket.
    public static func statusBucket(for state: ObservedSessionState) -> ThreadListFilterStatus {
        switch state {
        case .working, .waitingForInput, .recentlyActive:
            return .working
        case .completed, .idle, .unknown:
            return .completed
        case .historical:
            return .archived
        }
    }

    public static func allows(
        _ prefs: ThreadListFilterPrefs,
        source: ThreadListFilterSource
    ) -> Bool {
        if prefs.showAllSources { return true }
        switch source {
        case .phone: return prefs.showPhone
        case .desktop: return prefs.showDesktop
        }
    }

    /// Status filter: Show All passes; otherwise the row matches if its status
    /// bucket is enabled, or Unread is enabled and the row is unread.
    public static func allows(
        _ prefs: ThreadListFilterPrefs,
        status: ThreadListFilterStatus,
        unread: Bool
    ) -> Bool {
        if prefs.showAllStatuses { return true }
        if unread && prefs.showUnread { return true }
        switch status {
        case .working: return prefs.showWorking
        case .completed: return prefs.showCompleted
        case .failed: return prefs.showFailed
        case .archived: return prefs.showArchived
        case .unread: return prefs.showUnread
        }
    }

    public static func allows(
        _ prefs: ThreadListFilterPrefs,
        source: ThreadListFilterSource,
        status: ThreadListFilterStatus,
        unread: Bool
    ) -> Bool {
        allows(prefs, source: source)
            && allows(prefs, status: status, unread: unread)
    }

    public static func allowsLedger(_ prefs: ThreadListFilterPrefs, thread: ThreadListItem) -> Bool {
        allows(
            prefs,
            source: .phone,
            status: statusBucket(for: thread.statusKind),
            unread: thread.unread
        )
    }

    public static func allowsDesktop(_ prefs: ThreadListFilterPrefs, session: ObservedSession) -> Bool {
        allows(
            prefs,
            source: .desktop,
            status: statusBucket(for: session.state),
            unread: false
        )
    }

    /// Active status labels for the Customize "Filter rows" summary (empty ⇒ Show All).
    public static func activeStatusLabels(_ prefs: ThreadListFilterPrefs) -> [String] {
        if prefs.showAllStatuses { return [] }
        var labels: [String] = []
        if prefs.showWorking { labels.append(ThreadListFilterStatus.working.label) }
        if prefs.showCompleted { labels.append(ThreadListFilterStatus.completed.label) }
        if prefs.showFailed { labels.append(ThreadListFilterStatus.failed.label) }
        if prefs.showArchived { labels.append(ThreadListFilterStatus.archived.label) }
        if prefs.showUnread { labels.append(ThreadListFilterStatus.unread.label) }
        return labels
    }

    /// Active source labels for the Customize summary (empty ⇒ Show All).
    public static func activeSourceLabels(_ prefs: ThreadListFilterPrefs) -> [String] {
        if prefs.showAllSources { return [] }
        var labels: [String] = []
        if prefs.showPhone { labels.append(ThreadListFilterSource.phone.label) }
        if prefs.showDesktop { labels.append(ThreadListFilterSource.desktop.label) }
        return labels
    }

    public static func statusSummary(_ prefs: ThreadListFilterPrefs) -> String {
        let labels = activeStatusLabels(prefs)
        return labels.isEmpty ? "Show All" : labels.joined(separator: ", ")
    }

    public static func sourceSummary(_ prefs: ThreadListFilterPrefs) -> String {
        let labels = activeSourceLabels(prefs)
        return labels.isEmpty ? "Show All" : labels.joined(separator: ", ")
    }

    /// Turning Show All on enables every status toggle; turning a status off clears Show All.
    public static func applyingShowAllStatuses(_ prefs: ThreadListFilterPrefs, enabled: Bool) -> ThreadListFilterPrefs {
        var next = prefs
        next.showAllStatuses = enabled
        if enabled {
            next.showWorking = true
            next.showCompleted = true
            next.showFailed = true
            next.showArchived = true
            next.showUnread = true
        }
        return next
    }

    public static func applyingStatus(
        _ prefs: ThreadListFilterPrefs,
        _ status: ThreadListFilterStatus,
        enabled: Bool
    ) -> ThreadListFilterPrefs {
        var next = prefs
        switch status {
        case .working: next.showWorking = enabled
        case .completed: next.showCompleted = enabled
        case .failed: next.showFailed = enabled
        case .archived: next.showArchived = enabled
        case .unread: next.showUnread = enabled
        }
        next.showAllStatuses =
            next.showWorking && next.showCompleted && next.showFailed
            && next.showArchived && next.showUnread
        return next
    }

    public static func applyingShowAllSources(_ prefs: ThreadListFilterPrefs, enabled: Bool) -> ThreadListFilterPrefs {
        var next = prefs
        next.showAllSources = enabled
        if enabled {
            next.showPhone = true
            next.showDesktop = true
        }
        return next
    }

    public static func applyingSource(
        _ prefs: ThreadListFilterPrefs,
        _ source: ThreadListFilterSource,
        enabled: Bool
    ) -> ThreadListFilterPrefs {
        var next = prefs
        switch source {
        case .phone: next.showPhone = enabled
        case .desktop: next.showDesktop = enabled
        }
        next.showAllSources = next.showPhone && next.showDesktop
        return next
    }

    public static func load(from defaults: UserDefaults = .standard) -> ThreadListFilterPrefs {
        func bool(_ key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }
        let groupRaw = defaults.string(forKey: ThreadListFilterPrefs.StorageKey.groupBy) ?? ThreadListGroupBy.recency.rawValue
        let groupBy = ThreadListGroupBy(rawValue: groupRaw) ?? .recency
        var prefs = ThreadListFilterPrefs(
            showAllStatuses: bool(ThreadListFilterPrefs.StorageKey.showAllStatuses, default: true),
            showWorking: bool(ThreadListFilterPrefs.StorageKey.showWorking, default: true),
            showCompleted: bool(ThreadListFilterPrefs.StorageKey.showCompleted, default: true),
            showFailed: bool(ThreadListFilterPrefs.StorageKey.showFailed, default: true),
            showArchived: bool(ThreadListFilterPrefs.StorageKey.showArchived, default: true),
            showUnread: bool(ThreadListFilterPrefs.StorageKey.showUnread, default: true),
            showAllSources: bool(ThreadListFilterPrefs.StorageKey.showAllSources, default: true),
            showPhone: bool(ThreadListFilterPrefs.StorageKey.showPhone, default: true),
            showDesktop: bool(ThreadListFilterPrefs.StorageKey.showDesktop, default: true),
            groupBy: groupBy,
            showDiffStats: bool(ThreadListFilterPrefs.StorageKey.showDiffStats, default: true),
            showLastUpdated: bool(ThreadListFilterPrefs.StorageKey.showLastUpdated, default: true)
        )
        // Normalize master toggles against individuals (stale defaults edge).
        prefs.showAllStatuses =
            prefs.showWorking && prefs.showCompleted && prefs.showFailed
            && prefs.showArchived && prefs.showUnread
        prefs.showAllSources = prefs.showPhone && prefs.showDesktop
        return prefs
    }

    public static func save(_ prefs: ThreadListFilterPrefs, to defaults: UserDefaults = .standard) {
        defaults.set(prefs.showAllStatuses, forKey: ThreadListFilterPrefs.StorageKey.showAllStatuses)
        defaults.set(prefs.showWorking, forKey: ThreadListFilterPrefs.StorageKey.showWorking)
        defaults.set(prefs.showCompleted, forKey: ThreadListFilterPrefs.StorageKey.showCompleted)
        defaults.set(prefs.showFailed, forKey: ThreadListFilterPrefs.StorageKey.showFailed)
        defaults.set(prefs.showArchived, forKey: ThreadListFilterPrefs.StorageKey.showArchived)
        defaults.set(prefs.showUnread, forKey: ThreadListFilterPrefs.StorageKey.showUnread)
        defaults.set(prefs.showAllSources, forKey: ThreadListFilterPrefs.StorageKey.showAllSources)
        defaults.set(prefs.showPhone, forKey: ThreadListFilterPrefs.StorageKey.showPhone)
        defaults.set(prefs.showDesktop, forKey: ThreadListFilterPrefs.StorageKey.showDesktop)
        defaults.set(prefs.groupBy.rawValue, forKey: ThreadListFilterPrefs.StorageKey.groupBy)
        defaults.set(prefs.showDiffStats, forKey: ThreadListFilterPrefs.StorageKey.showDiffStats)
        defaults.set(prefs.showLastUpdated, forKey: ThreadListFilterPrefs.StorageKey.showLastUpdated)
    }
}

/// Blank-spinner policy for All Repos / thread list first paint.
/// Kept free of SwiftUI so macOS unit tests can lock the cache-first rule.
public enum ThreadListLoadingPolicy {
    /// Show a full-screen ProgressView only when there are no rows to paint
    /// yet and the catalog has not finished its first successful local load.
    public static func showsBlankInitialLoading(
        hasAnyThreads: Bool,
        hasCompletedInitialBootstrap: Bool,
        catalogShowsInitialLoading: Bool,
        catalogFailureMessage: String?
    ) -> Bool {
        if hasAnyThreads { return false }
        if catalogShowsInitialLoading { return true }
        if hasCompletedInitialBootstrap { return false }
        // Still bootstrapping with an empty cache and no failure — spinner.
        return catalogFailureMessage == nil
    }
}
