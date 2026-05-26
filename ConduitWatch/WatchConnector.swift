import WatchConnectivity
import Foundation
import ConduitCore

/// Watch-side WatchConnectivity bridge. Receives pending-approval syncs from the iPhone
/// and sends user decisions back. Uses AsyncStream so callers stay on MainActor cleanly.
///
/// Marked @unchecked Sendable because NSObject is not Sendable. The stored properties
/// (messageStream, continuation) are set once in init and never mutated. AsyncStream.Continuation
/// is itself Sendable, so calling .yield() from WCSession's serial background queue is safe.
final class WatchConnector: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let messageStream: AsyncStream<WatchSyncMessage>
    private let continuation: AsyncStream<WatchSyncMessage>.Continuation

    override init() {
        let (stream, cont) = AsyncStream<WatchSyncMessage>.makeStream()
        messageStream = stream
        continuation = cont
        super.init()
    }

    var messages: AsyncStream<WatchSyncMessage> { messageStream }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendDecision(approvalID: String, result: String) {
        let msg = WatchSyncMessage.decision(approvalID: approvalID, result: result).encode()
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        }
        // If unreachable (phone locked/away), silently drop — stale approvals expire on conduitd side.
    }

    // MARK: - WCSessionDelegate

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

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let msg = WatchSyncMessage.decode(applicationContext) { continuation.yield(msg) }
    }
}
