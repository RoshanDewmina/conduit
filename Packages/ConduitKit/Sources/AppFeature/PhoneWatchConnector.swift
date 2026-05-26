#if os(iOS)
import WatchConnectivity
import Foundation
import ConduitCore
import PersistenceKit

/// nonisolated WCSession bridge for the iPhone side.
///
/// WCSession delivers callbacks on its own serial background queue. Putting this on @MainActor
/// would require every callback to hop actors synchronously, risking deadlocks. Instead we stay
/// nonisolated, yield to an AsyncStream (Continuation is Sendable), and let MainActor code
/// consume the stream asynchronously.
///
/// @unchecked Sendable: NSObject is not Sendable. All stored properties are let-constants or
/// Sendable types; WCSession's serial delegate queue provides the necessary exclusion.
private final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let messageStream: AsyncStream<WatchSyncMessage>
    private let continuation: AsyncStream<WatchSyncMessage>.Continuation

    override init() {
        let (stream, cont) = AsyncStream<WatchSyncMessage>.makeStream()
        messageStream = stream
        continuation = cont
        super.init()
    }

    var decisions: AsyncStream<WatchSyncMessage> { messageStream }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendApprovals(_ approvals: [Approval]) {
        let transfers = approvals.map(WatchApprovalTransfer.init)
        let msg = WatchSyncMessage.approvalSync(transfers).encode()
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(msg)
        }
    }

    // MARK: - Required iOS WCSessionDelegate methods

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

/// Coordinates syncing pending approvals to Apple Watch and routing Watch decisions
/// back through the active session's decision callback.
@MainActor
public final class PhoneWatchConnector {
    private let delegate = WatchSessionDelegate()
    private var syncTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?

    public init() {}

    /// Activate WatchConnectivity. Call once at app launch.
    public func activate() {
        delegate.activate()
    }

    /// Begin syncing the repository to Watch and routing decisions via `onDecision`.
    /// Replaces any previous sync — safe to call on each new session.
    public func startSyncing(
        repository: ApprovalRepository,
        onDecision: @escaping @Sendable (ApprovalID, Approval.Decision) async -> Void
    ) {
        stopSyncing()

        syncTask = Task { [delegate] in
            do {
                for try await approvals in await repository.observe() {
                    guard !Task.isCancelled else { break }
                    delegate.sendApprovals(approvals.filter { $0.isPending })
                }
            } catch {}
        }

        decisionTask = Task { [delegate] in
            for await message in delegate.decisions {
                guard !Task.isCancelled else { break }
                if case .decision(let idStr, let result) = message,
                   let uuid = UUID(uuidString: idStr) {
                    let approvalID = ApprovalID(uuid)
                    let decision: Approval.Decision = (result == "approved") ? .approved : .rejected
                    await onDecision(approvalID, decision)
                }
            }
        }
    }

    public func stopSyncing() {
        syncTask?.cancel()
        decisionTask?.cancel()
        syncTask = nil
        decisionTask = nil
    }
}
#endif
