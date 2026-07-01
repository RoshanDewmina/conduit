#if os(iOS)
import Foundation
import LancerCore
import PersistenceKit
import SSHTransport
import NotificationsKit
import SecurityKit

/// Tracks pending decision delivery attempts for staleness detection.
public struct DecisionDeliveryTracker: Sendable {
    public struct PendingDelivery: Sendable {
        public let approvalID: String
        public let decision: Approval.Decision
        public let postedAt: Date
        public var attemptCount: Int
    }

    public var pendingDeliveries: [PendingDelivery] = []

    public init() {}

    public mutating func recordPost(approvalID: String, decision: Approval.Decision) {
        if let idx = pendingDeliveries.firstIndex(where: { $0.approvalID == approvalID }) {
            pendingDeliveries[idx].attemptCount += 1
        } else {
            pendingDeliveries.append(PendingDelivery(
                approvalID: approvalID,
                decision: decision,
                postedAt: Date(),
                attemptCount: 1
            ))
        }
    }

    public mutating func recordAcknowledgement(approvalID: String) {
        pendingDeliveries.removeAll { $0.approvalID == approvalID }
    }

    public func staleDeliveries(timeout: TimeInterval = 10) -> [PendingDelivery] {
        let now = Date()
        return pendingDeliveries.filter { now.timeIntervalSince($0.postedAt) > timeout }
    }
}

/// Relay between `ApprovalActionIntent` (which runs in the main app process,
/// triggered by a lock-screen or Dynamic Island button tap) and the active
/// `DaemonChannel`.
///
/// Flow:
///   1. `ApprovalActionIntent.perform()` calls `ApprovalRelay.shared.enqueue(...)`.
///   2. The relay writes the decision to the DB + audit log (always safe).
///   3. If a `DaemonChannel` is attached (`channel != nil`), it forwards
///      immediately via `channel.respond(...)`.
///   4. Otherwise the decision is queued. `setChannel(_:)` drains the queue
///      the next time a session connects.
///
/// Cold-launch gate (Phase 1 fix): `backendURL`/`sessionID`/`relayToken` are
/// persisted to the Keychain with `afterFirstUnlockThisDeviceOnly` so they
/// survive a process kill and can be hydrated at intent-perform time, enabling
/// a cold forward without a pre-warmed singleton. The DB write (step 2) and
/// lancerd's 120 s timeout remain the backstop for truly unrecoverable cases.
@MainActor
public final class ApprovalRelay {
    public static let shared = ApprovalRelay()

    // Decisions waiting to be forwarded to lancerd.
    private var queue: [(approvalID: String, decision: Approval.Decision, editedToolInput: String?)] = []

    /// The active daemon channel — set by AppRoot after SSH connect, cleared on disconnect.
    public weak var channel: DaemonChannel?

    /// Per-machine relay bridges, keyed by the machine that owns each bridge's
    /// WebSocket. Populated by a later lane (AppRoot) as machines pair/unpair.
    public var relayBridges: [RelayMachineID: E2ERelayBridge] = [:]

    /// Maps an in-flight approval to the machine it arrived from, so its decision
    /// routes back to exactly that machine's bridge — never a different one that
    /// happens to be connected. Populated when an approval is ingested (a later
    /// lane's AppRoot notification handler, using the machineID tag Lane A added
    /// to lancerE2EApprovalReceived's userInfo); cleared once forwarded.
    private var approvalMachineMap: [String: RelayMachineID] = [:]

    public func registerRelayOrigin(approvalID: String, machineID: RelayMachineID) {
        approvalMachineMap[approvalID] = machineID
    }

    private var backendURL: String = ""
    private var sessionID: String = ""
    // Per-session capability token (Tier-2 auth) required by the backend
    // `POST /approval/decision`. Sourced from the DaemonChannel handshake. Secret.
    private var relayToken: String = ""

    /// Keychain service used to persist relay credentials for cold-launch hydration.
    /// Tests may supply an in-memory instance.
    internal var credentialKeychain: Keychain = Keychain(
        service: "dev.lancer.relayCredentials",
        inMemory: false
    )

    // Keychain account keys.
    private static let kcBackendURL  = "backendURL"
    private static let kcSessionID   = "sessionID"
    private static let kcRelayToken  = "relayToken"

    /// Tracks pending decision deliveries for staleness detection.
    public private(set) var deliveryTracker = DecisionDeliveryTracker()

    /// Internal (not private) so tests can construct a fresh instance instead of
    /// mutating the shared singleton. Production code uses `shared`.
    init() {}

    // MARK: - Public API

    /// Enqueue an approval decision and forward it to the daemon channel if
    /// one is currently attached.  Write to DB + audit in all cases.
    public func enqueue(
        approvalID: String,
        decision: Approval.Decision,
        db: AppDatabase,
        hostID: String
    ) async {
        // 1. Persist the decision immediately — first-decision-wins. The DB
        //    UPDATE is guarded on `decision IS NULL`, so a stale Live Activity /
        //    banner tap on an already-resolved gate is a no-op here.
        let approvalRepo = ApprovalRepository(db)
        let auditRepo = AuditRepository(db)
        if let uuid = UUID(uuidString: approvalID) {
            let id = ApprovalID(uuid)
            let changed = (try? await approvalRepo.decide(id: id, decision: decision)) ?? false
            if !changed {
                // Not changed: either the gate is already resolved (a local row
                // exists) — in which case we must NOT re-forward and risk flipping
                // a decided gate — or there is no local row yet (cold-launch,
                // push-only) and we should forward so lancerd can resolve it.
                let alreadyResolved = (try? await approvalRepo.exists(id: id)) ?? false
                if alreadyResolved {
                    Notifications.shared.clearDeliveredApproval(id: approvalID)
                    return
                }
            } else {
                Notifications.shared.clearDeliveredApproval(id: approvalID)
            }
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

        // 2. Hydrate credentials from Keychain in case this is a cold launch
        //    (no prior foreground connect in this process lifetime).
        await hydrateCredentialsIfNeeded()

        // 3. Forward to lancerd (live SSH channel → backend relay → SSH-drain queue).
        await forwardDecisionOnly(approvalID: approvalID, decision: decision, editedToolInput: nil)
    }

    /// Forward a decision the caller has ALREADY persisted + audited. Tries the
    /// current live channel first (which may have been re-armed on reconnect),
    /// falls back to the backend relay, and only queues for the next SSH attach
    /// if both fail. Does not touch the DB/audit. This is the single forwarding
    /// chokepoint so the inbox-card, watch, banner and Live Activity paths all
    /// get the same dead-channel fallback (MAJOR-5) and near-exactly-once
    /// behaviour (MAJOR-9).
    public func forwardDecisionOnly(
        approvalID: String,
        decision: Approval.Decision,
        editedToolInput: String?
    ) async {
        deliveryTracker.recordPost(approvalID: approvalID, decision: decision)

        // 0. Multi-machine relay routing: if this approval was tagged with the
        //    machine it arrived from AND that machine still has a live bridge,
        //    route the decision there specifically. Fail-closed: if either lookup
        //    misses (never a relay approval, or the machine was unpaired since),
        //    fall through — do NOT retry against some other relay bridge.
        if let originMachineID = approvalMachineMap[approvalID],
           let bridge = relayBridges[originMachineID],
           await bridge.sendDecision(
               approvalID: approvalID,
               decision: DaemonChannel.decisionWireValue(for: decision),
               editedToolInput: editedToolInput
           ) {
            approvalMachineMap.removeValue(forKey: approvalID)
            deliveryTracker.recordAcknowledgement(approvalID: approvalID)
            return
        }

        // 2. Fall back to live SSH channel
        if let ch = channel {
            do {
                try await ch.respond(approvalId: approvalID, decision: decision, editedToolInput: editedToolInput)
                deliveryTracker.recordAcknowledgement(approvalID: approvalID)
                return
            } catch {
                // Attached-but-dead channel (stopped / mid-reconnect) — fall through
                // to the backend relay rather than silently dropping the decision.
            }
        }

        // 3. Try backend relay (hydrate credentials if still empty from cold launch)
        await hydrateCredentialsIfNeeded()
        let delivered = await postDecisionToBackend(approvalID: approvalID, decision: decision, editedToolInput: editedToolInput)
        if delivered {
            deliveryTracker.recordAcknowledgement(approvalID: approvalID)
        } else {
            // 4. Queue for next SSH attach
            queue.append((approvalID: approvalID, decision: decision, editedToolInput: editedToolInput))
        }
    }

    /// Attach (or replace) the active `DaemonChannel` and drain any decisions
    /// that were queued while the channel was nil. Also refreshes the per-session
    /// relay token from the channel's handshake so cold-launch / backend-relayed
    /// decisions can authenticate even after a reconnect re-mint.
    public func setChannel(_ ch: DaemonChannel) async {
        channel = ch
        if let token = await ch.currentRelayToken, !token.isEmpty {
            relayToken = token
        }
        await drainQueue(through: ch)
    }

    /// Detach the channel (called on disconnect so stale references don't accumulate).
    public func clearChannel() {
        channel = nil
    }

    public func configureBackend(url: String, sessionID: String) {
        self.backendURL = url
        self.sessionID = sessionID
        persistCredentials()
    }

    /// Store the per-session relay capability token (from the DaemonChannel
    /// handshake). Required for the backend `POST /approval/decision` Bearer auth.
    public func setRelayToken(_ token: String) {
        guard !token.isEmpty else { return }
        self.relayToken = token
        persistCredentials()
    }

    public static func backendDecisionBody(
        approvalID: String,
        decision: Approval.Decision,
        sessionID: String,
        editedToolInput: String?
    ) -> Data {
        var obj: [String: Any] = [
            "approvalId": approvalID,
            "decision": DaemonChannel.decisionWireValue(for: decision),
            "sessionId": sessionID,
        ]
        if let edited = editedToolInput, !edited.isEmpty { obj["editedToolInput"] = edited }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    // MARK: - Private

    /// Persist relay credentials to the Keychain so cold-launch processes can
    /// hydrate them without waiting for a foreground connect.
    private func persistCredentials() {
        let kc = credentialKeychain
        let url = backendURL
        let sid = sessionID
        let tok = relayToken
        Task {
            if let d = url.data(using: .utf8), !url.isEmpty {
                try? await kc.write(d, account: Self.kcBackendURL, accessibility: .afterFirstUnlockThisDeviceOnly)
            }
            if let d = sid.data(using: .utf8), !sid.isEmpty {
                try? await kc.write(d, account: Self.kcSessionID, accessibility: .afterFirstUnlockThisDeviceOnly)
            }
            if let d = tok.data(using: .utf8), !tok.isEmpty {
                try? await kc.write(d, account: Self.kcRelayToken, accessibility: .afterFirstUnlockThisDeviceOnly)
            }
        }
    }

    /// Load relay credentials from Keychain when the in-memory vars are empty
    /// (i.e. this is a cold-launch process that was never connected to a daemon).
    /// `await` this before any path that reads the credentials: the Keychain read
    /// is async, and `postDecisionToBackend`'s `guard !relayToken.isEmpty` runs
    /// *before* its URLSession suspension — so a fire-and-forget hydration would
    /// not have populated the token in time and the cold-launch forward would be
    /// queued instead of relayed.
    private func hydrateCredentialsIfNeeded() async {
        guard backendURL.isEmpty || sessionID.isEmpty || relayToken.isEmpty else { return }
        let kc = credentialKeychain
        if backendURL.isEmpty,
           let d = try? await kc.read(account: Self.kcBackendURL),
           let s = String(data: d, encoding: .utf8), !s.isEmpty {
            backendURL = s
        }
        if sessionID.isEmpty,
           let d = try? await kc.read(account: Self.kcSessionID),
           let s = String(data: d, encoding: .utf8), !s.isEmpty {
            sessionID = s
        }
        if relayToken.isEmpty,
           let d = try? await kc.read(account: Self.kcRelayToken),
           let s = String(data: d, encoding: .utf8), !s.isEmpty {
            relayToken = s
        }
    }

    /// POST a decision to the backend relay. Returns `true` only on a 2xx
    /// response so the caller can decide whether to keep the decision queued for
    /// SSH re-delivery. Fail-safe: a missing token or any non-2xx / transport
    /// error returns `false` (never assume the gate was resolved).
    @discardableResult
    private func postDecisionToBackend(approvalID: String, decision: Approval.Decision, editedToolInput: String?) async -> Bool {
        guard !backendURL.isEmpty, !sessionID.isEmpty,
              let url = URL(string: backendURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/approval/decision")
        else { return false }
        // Tier-2 capability: the backend requires `Authorization: Bearer <relayToken>`.
        // Without it the POST would 401 with no side effects, so don't bother —
        // rely on the SSH drain when a channel re-attaches + lancerd's timeout
        // auto-deny backstop.
        guard !relayToken.isEmpty else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = Self.backendDecisionBody(
            approvalID: approvalID, decision: decision, sessionID: sessionID, editedToolInput: editedToolInput
        )
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return false }
        return true
    }

    private func drainQueue(through ch: DaemonChannel) async {
        guard !queue.isEmpty else { return }
        let pending = queue
        queue.removeAll()
        // Re-queue anything the (possibly still-stale) channel couldn't deliver,
        // so we don't lose a decision by clearing it before it's confirmed sent.
        var stillPending: [(approvalID: String, decision: Approval.Decision, editedToolInput: String?)] = []
        for item in pending {
            do {
                try await ch.respond(approvalId: item.approvalID, decision: item.decision, editedToolInput: item.editedToolInput)
                deliveryTracker.recordAcknowledgement(approvalID: item.approvalID)
            } catch {
                stillPending.append(item)
            }
        }
        queue.append(contentsOf: stillPending)
    }
}
#endif
