import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("ThreadListFilters")
struct ThreadListFiltersTests {
    private func ledger(
        status: ThreadStatusKind,
        unread: Bool = false,
        id: String = "t1"
    ) -> ThreadListItem {
        ThreadListItem(
            id: id,
            title: "Thread",
            statusKind: status,
            statusLabel: WorkspaceRepoCatalog.statusLabel(status),
            repoName: "repo",
            cwd: "/Users/dev/repo",
            lastActivityAt: Date(timeIntervalSince1970: 100),
            unread: unread
        )
    }

    private func desktop(
        state: ObservedSessionState,
        id: String = "s1"
    ) -> ObservedSession {
        ObservedSession(
            sessionId: id,
            provider: "claudeCode",
            title: "Session",
            cwd: "/Users/dev/repo",
            state: state,
            source: .transcriptObserved,
            lastActivity: Date(timeIntervalSince1970: 100),
            messageCount: 2
        )
    }

    @Test("statusBucket maps ledger kinds; idle folds into completed")
    func ledgerStatusBuckets() {
        #expect(ThreadListFilters.statusBucket(for: ThreadStatusKind.working) == .working)
        #expect(ThreadListFilters.statusBucket(for: ThreadStatusKind.completed) == .completed)
        #expect(ThreadListFilters.statusBucket(for: ThreadStatusKind.idle) == .completed)
        #expect(ThreadListFilters.statusBucket(for: ThreadStatusKind.failed) == .failed)
        #expect(ThreadListFilters.statusBucket(for: ThreadStatusKind.archived) == .archived)
    }

    @Test("statusBucket maps observed session states")
    func desktopStatusBuckets() {
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.working) == .working)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.waitingForInput) == .working)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.recentlyActive) == .working)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.completed) == .completed)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.idle) == .completed)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.unknown) == .completed)
        #expect(ThreadListFilters.statusBucket(for: ObservedSessionState.historical) == .archived)
    }

    @Test("Show All statuses passes every row")
    func showAllStatuses() {
        let prefs = ThreadListFilterPrefs.default
        #expect(ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .working)))
        #expect(ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .failed)))
        #expect(ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .historical)))
    }

    @Test("status filter keeps only enabled buckets")
    func statusFilterBuckets() {
        let prefs = ThreadListFilterPrefs(
            showAllStatuses: false,
            showWorking: true,
            showCompleted: false,
            showFailed: false,
            showArchived: false,
            showUnread: false
        )

        #expect(ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .working)))
        #expect(!ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .completed)))
        #expect(!ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .idle)))
        #expect(!ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .failed)))
        #expect(ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .waitingForInput)))
        #expect(!ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .completed)))
    }

    @Test("unread toggle includes unread rows even when status bucket is off")
    func unreadOrStatus() {
        var prefs = ThreadListFilterPrefs.default
        prefs = ThreadListFilters.applyingShowAllStatuses(prefs, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .working, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .completed, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .failed, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .archived, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .unread, enabled: true)

        #expect(ThreadListFilters.allowsLedger(
            prefs, thread: ledger(status: .completed, unread: true)
        ))
        #expect(!ThreadListFilters.allowsLedger(
            prefs, thread: ledger(status: .completed, unread: false)
        ))
        #expect(!ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .completed)))
    }

    @Test("source filter separates phone ledger from desktop sessions")
    func sourceFilter() {
        var phoneOnly = ThreadListFilterPrefs.default
        phoneOnly = ThreadListFilters.applyingShowAllSources(phoneOnly, enabled: false)
        phoneOnly = ThreadListFilters.applyingSource(phoneOnly, .phone, enabled: true)
        phoneOnly = ThreadListFilters.applyingSource(phoneOnly, .desktop, enabled: false)

        #expect(ThreadListFilters.allowsLedger(phoneOnly, thread: ledger(status: .working)))
        #expect(!ThreadListFilters.allowsDesktop(phoneOnly, session: desktop(state: .working)))

        var desktopOnly = ThreadListFilterPrefs.default
        desktopOnly = ThreadListFilters.applyingSource(desktopOnly, .phone, enabled: false)
        desktopOnly = ThreadListFilters.applyingSource(desktopOnly, .desktop, enabled: true)

        #expect(!ThreadListFilters.allowsLedger(desktopOnly, thread: ledger(status: .working)))
        #expect(ThreadListFilters.allowsDesktop(desktopOnly, session: desktop(state: .working)))
        #expect(!desktopOnly.showAllSources)
    }

    @Test("combined source and status predicates both apply")
    func combinedPredicates() {
        var prefs = ThreadListFilterPrefs.default
        prefs = ThreadListFilters.applyingSource(prefs, .phone, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .completed, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .failed, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .archived, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .unread, enabled: false)

        #expect(!ThreadListFilters.allowsLedger(prefs, thread: ledger(status: .working)))
        #expect(ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .working)))
        #expect(!ThreadListFilters.allowsDesktop(prefs, session: desktop(state: .completed)))
    }

    @Test("applying Show All statuses enables every toggle")
    func applyingShowAllStatuses() {
        var prefs = ThreadListFilterPrefs(
            showAllStatuses: false,
            showWorking: false,
            showCompleted: true,
            showFailed: false,
            showArchived: false,
            showUnread: false
        )
        prefs = ThreadListFilters.applyingShowAllStatuses(prefs, enabled: true)
        #expect(prefs.showAllStatuses)
        #expect(prefs.showWorking && prefs.showCompleted && prefs.showFailed)
        #expect(prefs.showArchived && prefs.showUnread)
    }

    @Test("turning a status off clears Show All; all-on restores it")
    func statusMasterToggleSync() {
        var prefs = ThreadListFilterPrefs.default
        prefs = ThreadListFilters.applyingStatus(prefs, .failed, enabled: false)
        #expect(!prefs.showAllStatuses)
        #expect(!prefs.showFailed)

        prefs = ThreadListFilters.applyingStatus(prefs, .failed, enabled: true)
        #expect(prefs.showAllStatuses)
    }

    @Test("summaries report Show All or active labels")
    func summaries() {
        #expect(ThreadListFilters.statusSummary(.default) == "Show All")
        #expect(ThreadListFilters.sourceSummary(.default) == "Show All")

        var prefs = ThreadListFilterPrefs.default
        prefs = ThreadListFilters.applyingStatus(prefs, .archived, enabled: false)
        prefs = ThreadListFilters.applyingStatus(prefs, .unread, enabled: false)
        prefs = ThreadListFilters.applyingSource(prefs, .desktop, enabled: false)

        #expect(ThreadListFilters.statusSummary(prefs) == "Working, Completed, Failed")
        #expect(ThreadListFilters.sourceSummary(prefs) == "Phone")
    }

    @Test("load/save round-trips through UserDefaults")
    func persistenceRoundTrip() {
        let suiteName = "dev.lancer.tests.threadListFilters.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var prefs = ThreadListFilterPrefs.default
        prefs = ThreadListFilters.applyingStatus(prefs, .failed, enabled: false)
        prefs = ThreadListFilters.applyingSource(prefs, .phone, enabled: false)
        prefs.groupBy = .repo
        prefs.showDiffStats = false
        prefs.showLastUpdated = false
        ThreadListFilters.save(prefs, to: defaults)

        let loaded = ThreadListFilters.load(from: defaults)
        #expect(loaded == prefs)
        #expect(loaded.groupBy == .repo)
        #expect(!loaded.showDiffStats)
        #expect(!loaded.showLastUpdated)
        #expect(!loaded.showPhone)
        #expect(loaded.showDesktop)
        #expect(!loaded.showFailed)
    }
}

@Suite("ThreadListLoadingPolicy")
struct ThreadListLoadingPolicyTests {
    @Test("cached rows never blank-spinner even before bootstrap completes")
    func cachedRowsSkipBlankSpinner() {
        #expect(!ThreadListLoadingPolicy.showsBlankInitialLoading(
            hasAnyThreads: true,
            hasCompletedInitialBootstrap: false,
            catalogShowsInitialLoading: true,
            catalogFailureMessage: nil
        ))
    }

    @Test("empty cache shows spinner until bootstrap finishes")
    func emptyCacheShowsSpinner() {
        #expect(ThreadListLoadingPolicy.showsBlankInitialLoading(
            hasAnyThreads: false,
            hasCompletedInitialBootstrap: false,
            catalogShowsInitialLoading: false,
            catalogFailureMessage: nil
        ))
        #expect(!ThreadListLoadingPolicy.showsBlankInitialLoading(
            hasAnyThreads: false,
            hasCompletedInitialBootstrap: true,
            catalogShowsInitialLoading: false,
            catalogFailureMessage: nil
        ))
    }

    @Test("catalog failure does not keep a blank spinner")
    func failureClearsBlankSpinner() {
        #expect(!ThreadListLoadingPolicy.showsBlankInitialLoading(
            hasAnyThreads: false,
            hasCompletedInitialBootstrap: false,
            catalogShowsInitialLoading: false,
            catalogFailureMessage: "relay timeout"
        ))
    }
}
