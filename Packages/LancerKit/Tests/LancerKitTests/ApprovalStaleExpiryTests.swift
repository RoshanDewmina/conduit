import Testing
import Foundation
@testable import LancerCore
@testable import PersistenceKit

/// Covers `ApprovalRepository.expireStalePending` — the macOS-hostable half of
/// the Home Screen "N approvals waiting" corpse fix. The iOS-gated writer
/// path (`writeApprovalWidgetSnapshot` calling this sweep) lives in
/// `WidgetSnapshotWriterTests`.
@Suite("ApprovalRepository stale pending TTL")
struct ApprovalStaleExpiryTests {

    @Test("row older than TTL is marked expired; fresh row survives")
    func expireStalePendingRetiresOnlyOldRows() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
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

        let expiredCount = try await repo.expireStalePending(now: now)
        #expect(expiredCount == 1)

        let pending = try await repo.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == fresh.id)

        let staleRow = try await repo.find(id: stale.id)
        #expect(staleRow?.decision == .expired)
    }

    @Test("already-decided rows are not flipped by the TTL sweep")
    func expireStalePendingDoesNotOverrideExistingDecision() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let now = Date()

        let approved = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "echo approved",
            cwd: "/repo",
            risk: .low,
            createdAt: now.addingTimeInterval(-(WidgetSnapshot.pendingApprovalTTL + 120)),
            decidedAt: now.addingTimeInterval(-30),
            decision: .approved
        )
        try await repo.upsert(approved)

        let expiredCount = try await repo.expireStalePending(now: now)
        #expect(expiredCount == 0)
        let row = try await repo.find(id: approved.id)
        #expect(row?.decision == .approved)
    }
}
