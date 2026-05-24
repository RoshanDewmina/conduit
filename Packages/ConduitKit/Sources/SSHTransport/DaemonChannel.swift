import Foundation
import ConduitCore

public actor DaemonChannel {
    private let session: SSHSession
    private let (eventStream, eventContinuation): (AsyncStream<DaemonEvent>, AsyncStream<DaemonEvent>.Continuation)
    private var readTask: Task<Void, Never>?

    public var events: AsyncStream<DaemonEvent> { eventStream }

    public init(session: SSHSession) {
        self.session = session
        (eventStream, eventContinuation) = AsyncStream<DaemonEvent>.makeStream()
    }

    // Start reading events from conduitd serve --stdio
    public func start(daemonPath: String = "conduitd") async throws {
        let outputStream = try await session.execute("\(daemonPath) serve --stdio")
        let continuation = eventContinuation
        readTask = Task { [outputStream] in
            var buffer = Data()
            do {
                for try await (data, stream) in outputStream {
                    guard stream == .stdout else { continue }
                    buffer.append(data)
                    while let (msg, rest) = DaemonFraming.unframe(buffer) {
                        buffer = rest
                        if let event = DaemonEvent.decode(from: msg) {
                            continuation.yield(event)
                        }
                    }
                }
            } catch { /* channel closed */ }
            continuation.finish()
        }
    }

    // Send a decision back to conduitd (separate exec channel)
    public func respond(approvalId: String, decision: Approval.Decision) async throws {
        let d = decision == .approved || decision == .approvedAlways ? "approved" : "rejected"
        _ = try? await session.executeCollected("conduitd respond --id='\(approvalId)' --decision=\(d)")
    }

    public func stop() {
        readTask?.cancel()
        eventContinuation.finish()
    }
}
