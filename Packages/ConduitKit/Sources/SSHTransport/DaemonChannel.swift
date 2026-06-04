import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOCore
import ConduitCore

public actor DaemonChannel {
    private let session: SSHSession
    private let (eventStream, eventContinuation): (AsyncStream<DaemonEvent>, AsyncStream<DaemonEvent>.Continuation)
    private var readTask: Task<Void, Never>?
    private var stdinWriter: TTYStdinWriter?
    private var nextRPCID: Int = 10
    private var pendingRPC: [Int: CheckedContinuation<Data, Error>] = [:]

    public var events: AsyncStream<DaemonEvent> { eventStream }

    public init(session: SSHSession) {
        self.session = session
        (eventStream, eventContinuation) = AsyncStream<DaemonEvent>.makeStream()
    }

    public func start(daemonPath: String = "$HOME/.conduit/bin/conduitd") async throws {
        let (byteStream, byteCont) = AsyncStream<[UInt8]>.makeStream()
        let (writer, task) = try await session.requestExecChannel(
            command: "bash -c '\(daemonPath) serve'",
            dataContinuation: byteCont
        )
        stdinWriter = writer

        let continuation = eventContinuation
        readTask = Task { [byteStream] in
            var buffer = Data()
            for await bytes in byteStream {
                buffer.append(contentsOf: bytes)
                while let (msg, rest) = DaemonFraming.unframe(buffer) {
                    buffer = rest
                    await self.handleFrame(msg, eventContinuation: continuation)
                }
            }
            continuation.finish()
            await self.failPendingRPCs(DaemonChannelError.disconnected)
        }
        _ = task
    }

    private func handleFrame(_ msg: Data, eventContinuation: AsyncStream<DaemonEvent>.Continuation) {
        if let dict = (try? JSONSerialization.jsonObject(with: msg)) as? [String: Any],
           dict["method"] == nil,
           let idNum = dict["id"] as? Int,
           pendingRPC[idNum] != nil {
            let cont = pendingRPC.removeValue(forKey: idNum)!
            cont.resume(returning: msg)
            return
        }
        if let event = DaemonEvent.decode(from: msg) {
            eventContinuation.yield(event)
        }
    }

    private func failPendingRPCs(_ error: Error) {
        for (_, cont) in pendingRPC {
            cont.resume(throwing: error)
        }
        pendingRPC.removeAll()
    }

    private func sendRPC(method: String, params: [String: Any]) async throws -> Data {
        guard let writer = stdinWriter else { throw DaemonChannelError.notRunning }
        let id = nextRPCID
        nextRPCID += 1
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope) else {
            throw DaemonChannelError.encodeFailed
        }
        return try await withCheckedThrowingContinuation { cont in
            pendingRPC[id] = cont
            Task {
                do {
                    let frame = DaemonFraming.frame(json)
                    try await writer.write(ByteBuffer(bytes: frame))
                } catch {
                    pendingRPC.removeValue(forKey: id)
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func registerDevice(pushBackendURL: String, sessionID: String) async throws {
        guard let writer = stdinWriter else { return }
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "conduit.device.register",
            "params": [
                "pushBackendURL": pushBackendURL,
                "sessionID": sessionID,
            ],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        try await writer.write(ByteBuffer(bytes: DaemonFraming.frame(json)))
    }

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
        var params: [String: Any] = [
            "approvalId": approvalId,
            "decision": Self.decisionWireValue(for: decision),
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
        try await writer.write(ByteBuffer(bytes: DaemonFraming.frame(json)))
    }

    public func tailAudit(limit: Int = 50) async throws -> AuditTailResult {
        let data = try await sendRPC(method: "agent.audit.tail", params: ["limit": limit])
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .auditTail(let result): return result
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    public func fetchPolicy(cwd: String) async throws -> PolicyGetResult {
        let data = try await sendRPC(method: "agent.policy.get", params: ["cwd": cwd])
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .policyGet(let result): return result
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    public func reloadPolicy(cwd: String = "") async throws {
        let data = try await sendRPC(method: "agent.policy.reload", params: ["cwd": cwd])
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .ok, .pong: return
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    public func fetchAgentStatus(homeDir: String = "") async throws -> AgentStatusSnapshot {
        var params: [String: Any] = [:]
        if !homeDir.isEmpty { params["homeDir"] = homeDir }
        let data = try await sendRPC(method: "agent.status", params: params)
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .agentStatus(let snap): return snap
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    public func stop() {
        readTask?.cancel()
        readTask = nil
        stdinWriter = nil
        failPendingRPCs(DaemonChannelError.disconnected)
        eventContinuation.finish()
    }
}

public enum DaemonChannelError: Error, Sendable {
    case notRunning
    case encodeFailed
    case badResponse
    case disconnected
    case rpc(String)
}
