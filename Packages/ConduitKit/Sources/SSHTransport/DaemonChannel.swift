import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOCore
import ConduitCore

public actor DaemonChannel {
    private let session: SSHSession
    private let (eventStream, eventContinuation): (AsyncStream<DaemonEvent>, AsyncStream<DaemonEvent>.Continuation)
    private var readTask: Task<Void, Never>?
    private var stdinWriter: TTYStdinWriter?

    public var events: AsyncStream<DaemonEvent> { eventStream }

    public init(session: SSHSession) {
        self.session = session
        (eventStream, eventContinuation) = AsyncStream<DaemonEvent>.makeStream()
    }

    /// Start the conduitd daemon on the remote host. Uses a bidirectional exec
    /// channel (no PTY) so we can both read approval events and write decisions.
    /// daemonPath may contain $HOME-relative components; it is launched via bash -c
    /// so that $HOME is expanded correctly in non-interactive SSH exec channels.
    public func start(daemonPath: String = "$HOME/.conduit/bin/conduitd") async throws {
        let (byteStream, byteCont) = AsyncStream<[UInt8]>.makeStream()
        let (writer, task) = try await session.requestExecChannel(
            command: "bash -c '\(daemonPath) serve'",
            dataContinuation: byteCont
        )
        stdinWriter = writer
        _ = task  // task kept alive by the actor; cancelled in stop()
        readTask = task

        let continuation = eventContinuation
        readTask = Task { [byteStream] in
            var buffer = Data()
            for await bytes in byteStream {
                buffer.append(contentsOf: bytes)
                while let (msg, rest) = DaemonFraming.unframe(buffer) {
                    buffer = rest
                    if let event = DaemonEvent.decode(from: msg) {
                        continuation.yield(event)
                    }
                }
            }
            continuation.finish()
        }
    }

    /// Inform conduitd of the device's push registration so it can deliver APNs
    /// alerts when the SSH channel is down. Call after start() succeeds.
    /// - Parameters:
    ///   - pushBackendURL: The deployed push-backend HTTPS URL (from CONDUIT_PUSH_BACKEND_URL).
    ///   - sessionID: The iOS device's identifierForVendor UUID string (matches what was
    ///     registered with the push backend in AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken).
    public func registerDevice(pushBackendURL: String, sessionID: String) async throws {
        guard let writer = stdinWriter else { return }
        let params: [String: Any] = [
            "pushBackendURL": pushBackendURL,
            "sessionID": sessionID,
        ]
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "conduit.device.register",
            "params": params,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        let frame = DaemonFraming.frame(json)
        let buf = ByteBuffer(bytes: frame)
        try await writer.write(buf)
    }

    /// Send an approval decision back to conduitd via JSON-RPC over the daemon's stdin.
    public static func decisionWireValue(for decision: Approval.Decision) -> String {
        switch decision {
        case .approved: return "approve"
        case .approvedAlways: return "approveAlways"
        case .rejected, .expired: return "deny"
        }
    }

    public func respond(
        approvalId: String,
        decision: Approval.Decision,
        editedToolInput: String? = nil
    ) async throws {
        guard let writer = stdinWriter else { return }
        let decisionStr = Self.decisionWireValue(for: decision)
        var params: [String: Any] = [
            "approvalId": approvalId,
            "decision": decisionStr,
        ]
        if let editedToolInput, !editedToolInput.isEmpty {
            params["editedToolInput"] = editedToolInput
        }
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "agent.approval.response",
            "params": params,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        let frame = DaemonFraming.frame(json)
        let buf = ByteBuffer(bytes: frame)
        try await writer.write(buf)
    }

    public func stop() {
        readTask?.cancel()
        readTask = nil
        stdinWriter = nil
        eventContinuation.finish()
    }
}
