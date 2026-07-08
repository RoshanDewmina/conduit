#if os(iOS)
import WatchConnectivity
import Foundation
import LancerCore
import PersistenceKit
import SessionFeature

/// nonisolated WCSession bridge for the iPhone side.
/// @unchecked Sendable: NSObject is not Sendable. All let-properties are set once in init.
/// WCSession's serial delegate queue provides the necessary exclusion.
private final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let messageStream: AsyncStream<WatchSyncMessage>
    private let continuation: AsyncStream<WatchSyncMessage>.Continuation

    override init() {
        let (stream, cont) = AsyncStream<WatchSyncMessage>.makeStream()
        messageStream = stream
        continuation = cont
        super.init()
    }

    var incoming: AsyncStream<WatchSyncMessage> { messageStream }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func deliver(_ dict: [String: Any]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(dict)
        }
    }

    func sendApprovals(_ approvals: [Approval]) {
        let transfers = approvals.map(WatchApprovalTransfer.init)
        deliver(WatchSyncMessage.approvalSync(transfers).encode())
    }

    func sendSessionStatus(_ status: WatchSessionStatus) {
        deliver(WatchSyncMessage.sessionSync(status).encode())
    }

    func sendActivity(_ blocks: [WatchActivityBlock]) {
        deliver(WatchSyncMessage.activitySync(blocks).encode())
    }

    func sendSnippets(_ snippets: [WatchSnippet]) {
        deliver(WatchSyncMessage.snippetSync(snippets).encode())
    }

    // MARK: - Required iOS WCSessionDelegate

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let msg = WatchSyncMessage.decode(message) { continuation.yield(msg) }
    }
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let msg = WatchSyncMessage.decode(message) { continuation.yield(msg) }
        replyHandler([:])
    }
}

/// Coordinates all Watch ↔ iPhone data sync.
/// Call `activate()` at app launch, `startSyncing(...)` each time a session starts.
@MainActor
public final class PhoneWatchConnector {
    private let delegate = WatchSessionDelegate()
    private var tasks: [Task<Void, Never>] = []

    // Live pending-approval count, updated by the approval-observer task and read by the
    // session-status task so both consumers share the same value without a second query.
    private var livePendingCount: Int = 0
    // Timestamp captured once when the session connects; used for true uptime.
    private var connectedSince: TimeInterval? = nil

    // Callbacks set by AppRoot per-session
    public var onEmergencyStop: (@Sendable () async -> Void)?
    public var onRunSnippet: (@Sendable (String) async -> Void)?
    public var onDecision: (@Sendable (ApprovalID, Approval.Decision) async -> Void)?

    public init() {}

    public func activate() { delegate.activate() }

    public func stopSyncing() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        livePendingCount = 0
        connectedSince = nil
        onEmergencyStop = nil
        onRunSnippet = nil
        onDecision = nil
    }
}
#endif
