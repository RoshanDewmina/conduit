import WatchConnectivity
import Foundation
import ConduitCore

/// Watch-side WatchConnectivity bridge.
/// @unchecked Sendable: NSObject is not Sendable. Stored properties are let-constants;
/// AsyncStream.Continuation is Sendable — calling .yield() from WCSession's serial queue is safe.
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

    // MARK: - Sending (Watch → iPhone)

    func sendDecision(approvalID: String, result: String) {
        send(WatchSyncMessage.decision(approvalID: approvalID, result: result).encode())
    }

    func sendEmergencyStop() {
        send(WatchSyncMessage.emergencyStop.encode())
    }

    func sendRunSnippet(body: String) {
        send(WatchSyncMessage.runSnippet(body: body).encode())
    }

    private func send(_ dict: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        }
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
