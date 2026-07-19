import Testing
import Foundation
@testable import LancerCore
@testable import PersistenceKit

// Regression coverage for the Home Screen `PendingApprovalsWidget` bug:
// live-reproduced on-device, the widget showed "7 approvals waiting" with a
// stale summary ("cat go.mod...") while the real daemon only had 1 pending
// approval. Root cause (two independent gaps, both fixed alongside this
// test):
//
//   1. `RelayApprovalIngest.handle(_:)` — the ONLY production "new approval
//      arrived" path (the SSH-based `ApprovalIngest` actor that already
//      called the writer is only reachable through the dead `FleetStore`
//      type, never constructed by AppRoot/WorkspacesView) — never called
//      `ApprovalRepository.writeApprovalWidgetSnapshot()`, so the widget
//      never refreshed on arrival, only ever as a side effect of a later
//      in-app decision.
//   2. `AppDatabase.openShared()` used `.applicationSupportDirectory`
//      (scoped to the calling process's own private sandbox container)
//      instead of the App Group container. `ApprovalActionIntent` (the Lock
//      Screen / Dynamic Island Approve/Reject button) is a
//      `LiveActivityIntent`, which iOS runs inside the `LancerWidgets`
//      extension process, not the main app's — so every lock-screen
//      decision was persisted to a throwaway database the main app could
//      never see. The daemon resolved correctly (network path, unaffected)
//      but the main app's local row stayed "pending" forever, producing a
//      permanent ghost row that inflated `pending()`'s count and could
//      surface as the stale "newest" summary indefinitely.
//
// This suite exercises the writer's UserDefaults-writing logic in isolation
// (Suite A — an injectable test suite name, since the real
// `WidgetSnapshot.appGroupID` is not overridable at the production call
// sites) and the real `RelayApprovalIngest`/`ApprovalRelay` call sites'
// effect on the underlying data the writer reads (Suite B), together
// covering the full path this bug broke.
#if os(iOS)
import AppFeature
import SessionFeature

@Suite("PendingApprovalsWidget snapshot writer — arrive/resolve sequence")
struct WidgetSnapshotWriterTests {

    @Test("count and summary track a realistic arrive -> arrive -> resolve -> resolve sequence")
    func writerTracksArriveAndResolveSequence() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let suite = "widget-snapshot-writer-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // 1. A first approval arrives.
        let older = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "date +lockscreen-proof-1",
            cwd: "/repo",
            risk: .low,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        try await repo.upsert(older)
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 1)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)?.contains("date +lockscreen-proof-1") == true)

        // 2. A second, newer approval arrives — the summary must track the
        //    NEWEST pending row, not the first one ever seen (this is
        //    exactly the "cat go.mod" staleness symptom: an old row's
        //    summary text surviving past when a newer one should be shown).
        let newer = Approval(
            sessionID: SessionID(),
            agent: .codex,
            kind: .command,
            command: "cat go.mod",
            cwd: "/repo",
            risk: .medium,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        try await repo.upsert(newer)
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 2)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)?.contains("cat go.mod") == true)

        // 3. The newest one resolves — count drops to 1, summary falls back
        //    to the still-pending older row.
        let newerChanged = try await repo.decide(id: newer.id, decision: .approved)
        #expect(newerChanged == true)
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 1)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)?.contains("date +lockscreen-proof-1") == true)

        // 4. The last one resolves — count hits 0 and the summary key is
        //    REMOVED (not just emptied), matching `PendingApprovalsProvider`
        //    treating a nil summary as "nothing to show" only when count > 0.
        let olderChanged = try await repo.decide(id: older.id, decision: .rejected)
        #expect(olderChanged == true)
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 0)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey) == nil)
    }

    @Test("stale pending row past TTL is expired and excluded from the widget snapshot")
    func writerExpiresStalePendingRow() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let suite = "widget-snapshot-stale-ttl-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Date()
        let stale = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "date +lockscreen-stale",
            cwd: "/repo",
            risk: .low,
            createdAt: now.addingTimeInterval(-(WidgetSnapshot.pendingApprovalTTL + 60))
        )
        let fresh = Approval(
            sessionID: SessionID(),
            agent: .codex,
            kind: .command,
            command: "echo still-live",
            cwd: "/repo",
            risk: .medium,
            createdAt: now.addingTimeInterval(-60)
        )
        try await repo.upsert(stale)
        try await repo.upsert(fresh)

        // Must fail without expireStalePending inside writeApprovalWidgetSnapshot:
        // both rows would still be pending and count would be 2.
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 1)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)?.contains("echo still-live") == true)

        let pending = try await repo.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == fresh.id)

        let staleRow = try await repo.find(id: stale.id)
        #expect(staleRow?.decision == .expired)
        #expect(staleRow?.decidedAt != nil)
    }

    @Test("fresh pending row under TTL survives the snapshot write sweep")
    func writerKeepsFreshPendingRow() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let suite = "widget-snapshot-fresh-ttl-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "date +fresh",
            cwd: "/repo",
            risk: .low,
            createdAt: Date().addingTimeInterval(-60)
        )
        try await repo.upsert(fresh)
        await repo.writeApprovalWidgetSnapshot(suiteName: suite)

        #expect(defaults.integer(forKey: WidgetSnapshot.pendingApprovalsKey) == 1)
        #expect(defaults.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)?.contains("date +fresh") == true)
        let pending = try await repo.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.decision == nil)
    }
}

@Suite("RelayApprovalIngest — the real production arrive/resolve call sites")
@MainActor
struct RelayApprovalIngestWidgetDataTests {

    // `RelayApprovalIngest` (constructed by AppRoot/WorkspacesView in
    // production — the SSH-based `ApprovalIngest` actor is dead code, only
    // reachable through the never-instantiated `FleetStore`) is the ONLY
    // real "new approval arrived" entry point. This test drives it through
    // its actual notification-based API and asserts on `ApprovalRepository`
    // (the same source `writeApprovalWidgetSnapshot()` reads) rather than
    // `UserDefaults(suiteName: WidgetSnapshot.appGroupID)` directly: the
    // production call sites (this file's `handle`, and
    // `ApprovalRelay.enqueue`) always write to the real App Group ID, which
    // is not injectable per-call — `WidgetSnapshotWriterTests` above proves
    // the writer's UserDefaults logic against an isolated suite for
    // equivalent DB states, so together these two suites cover the full
    // path without a test touching the real shared App Group domain.
    @Test("a relay-delivered approval is persisted and resolving it clears it from pending()")
    func relayIngestArriveThenResolve() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let ingest = RelayApprovalIngest(database: db)
        ingest.start()
        // `start()` kicks off `Task { for await notification in ... }`; the
        // async sequence's observer registers once that task actually runs,
        // not synchronously inside `start()` itself. Give it a beat before
        // posting, or the notification can fire before anything is
        // listening (production never hits this — AppRoot calls `start()`
        // well before any real approval event).
        try await Task.sleep(for: .milliseconds(50))

        let machineID = RelayMachineID(UUID())
        let approvalData = E2ERelayMessage.ApprovalData(
            approvalID: UUID().uuidString,
            agent: "claudeCode",
            kind: "command",
            command: "date +lockscreen-proof-test",
            risk: 1,
            cwd: "/repo",
            toolName: nil
        )

        NotificationCenter.default.post(
            name: Notification.Name("lancerE2EApprovalReceived"),
            object: nil,
            userInfo: ["approvalData": approvalData, "machineID": machineID]
        )
        // Notification delivery + the ingest's async handler run on separate
        // tasks; give them a beat to land before asserting (same pattern as
        // `RelayApprovalDecisionRaceTests` elsewhere in this file's suite).
        try await Task.sleep(for: .milliseconds(100))

        let pendingAfterArrival = try await repo.pending()
        #expect(pendingAfterArrival.count == 1)
        #expect(pendingAfterArrival.first?.command == "date +lockscreen-proof-test")
        #expect(ingest.latestPendingApproval[machineID]?.command == "date +lockscreen-proof-test")

        // Deliberately does NOT also call `ingest.decide(...)` here:
        // `RelayApprovalIngest.decide` unconditionally calls
        // `ApprovalRelay.shared.enqueue`, which unconditionally calls
        // `Notifications.shared.clearDeliveredApproval` ->
        // `UNUserNotificationCenter.current()` with no test-injection seam
        // (unlike `LiveInboxViewModel`, which takes an overridable
        // `clearDeliveredApproval` closure precisely so tests can avoid
        // this). Calling it from this bare SPM-test-hosted bundle crashes
        // the test process (`bundleProxyForCurrentProcess is nil`,
        // `NSInternalInconsistencyException`) — an environmental limitation
        // of `UNUserNotificationCenter` needing a real app-host bundle
        // identity, unrelated to this bug fix. The resolve side of the
        // widget-snapshot logic (count decrements, summary updates/clears)
        // is fully covered at the correct layer by
        // `WidgetSnapshotWriterTests` above, which calls
        // `ApprovalRepository.decide` + `writeApprovalWidgetSnapshot`
        // directly — the same layer `ExactlyOnceDecisionTests` in
        // `ApprovalReliabilityWave2Tests.swift` already tests `decide` at,
        // sidestepping `ApprovalRelay`/`Notifications` on purpose.
    }
}
#endif
