#if os(iOS)
import Foundation
import ConduitCore
import PersistenceKit
import SSHTransport

/// Thread-safe relay between `ApprovalActionIntent` (which runs in an
/// extension process with no live SSH connection) and the active
/// `DaemonChannel` in the main app process.
///
/// Flow:
///   1. `ApprovalActionIntent.perform()` calls `ApprovalRelay.shared.enqueue(...)`.
///   2. The relay writes the decision to the DB + audit log.
///   3. If a `DaemonChannel` is attached (`channel != nil`), it drains the queue
///      immediately via `channel.respond(...)`.
///   4. When the app becomes active, `AppRoot.startSession()` calls
///      `setChannel(_:)`, which triggers a drain of any pending decisions that
///      arrived while the channel was nil.
@MainActor
public final class ApprovalRelay {
    public static let shared = ApprovalRelay()

    // Decisions waiting to be forwarded to conduitd.
    private var queue: [(approvalID: String, decision: Approval.Decision)] = []

    /// The active daemon channel — set by AppRoot after SSH connect, cleared on disconnect.
    public weak var channel: DaemonChannel?

    private init() {}

    // MARK: - Public API

    /// Enqueue an approval decision and forward it to the daemon channel if
    /// one is currently attached.  Write to DB + audit in all cases.
    public func enqueue(
        approvalID: String,
        decision: Approval.Decision,
        db: AppDatabase,
        hostID: String
    ) async {
        // 1. Persist the decision immediately — this is always safe.
        let approvalRepo = ApprovalRepository(db)
        let auditRepo = AuditRepository(db)
        if let uuid = UUID(uuidString: approvalID) {
            try? await approvalRepo.decide(id: ApprovalID(uuid), decision: decision)
        }
        let hostUUID = UUID(uuidString: hostID) ?? UUID()
        try? await auditRepo.record(
            hostID: HostID(hostUUID),
            type: .approval,
            metadata: [
                "approvalId": approvalID,
                "hostId": hostID,
                "decision": decision.rawValue,
                "source": "liveActivityIntent",
            ]
        )

        // 2. Try to forward to conduitd right now.
        if let ch = channel {
            try? await ch.respond(approvalId: approvalID, decision: decision)
        } else {
            // Channel not yet available — queue for later drain.
            queue.append((approvalID: approvalID, decision: decision))
        }
    }

    /// Attach (or replace) the active `DaemonChannel` and drain any decisions
    /// that were queued while the channel was nil.
    public func setChannel(_ ch: DaemonChannel) async {
        channel = ch
        await drainQueue(through: ch)
    }

    /// Detach the channel (called on disconnect so stale references don't accumulate).
    public func clearChannel() {
        channel = nil
    }

    // MARK: - Private

    private func drainQueue(through ch: DaemonChannel) async {
        guard !queue.isEmpty else { return }
        let pending = queue
        queue.removeAll()
        for item in pending {
            try? await ch.respond(approvalId: item.approvalID, decision: item.decision)
        }
    }
}
#endif
