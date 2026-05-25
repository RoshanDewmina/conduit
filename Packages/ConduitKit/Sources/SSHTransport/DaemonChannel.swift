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
    public func start(daemonPath: String = "conduitd") async throws {
        let (byteStream, byteCont) = AsyncStream<[UInt8]>.makeStream()
        let (writer, task) = try await session.requestExecChannel(
            command: "\(daemonPath) serve",
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

    /// Send an approval decision back to conduitd via JSON-RPC over the daemon's stdin.
    public func respond(approvalId: String, decision: Approval.Decision) async throws {
        guard let writer = stdinWriter else { return }
        let decisionStr = (decision == .approved || decision == .approvedAlways) ? "approved" : "rejected"
        let params: [String: Any] = ["approvalId": approvalId, "decision": decisionStr]
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
