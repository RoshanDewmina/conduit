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
    // Per-session capability token minted by conduitd and returned in the
    // `conduit.device.register` reply. Sent as `Authorization: Bearer <token>`
    // on the backend decision relay. Treat as a secret — never log it.
    private var relayToken: String?

    public var events: AsyncStream<DaemonEvent> { eventStream }

    /// The per-session relay capability token, if the handshake delivered one.
    public var currentRelayToken: String? { relayToken }

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
                    self.handleFrame(msg, eventContinuation: continuation)
                }
            }
            continuation.finish()
            self.failPendingRPCs(DaemonChannelError.disconnected)
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

    /// Perform the session handshake with conduitd. Goes through `sendRPC` (not a
    /// fire-and-forget write) so the reply is read: conduitd returns a per-session
    /// `relayToken` which we store for the backend decision relay. Backward
    /// compatible — a legacy daemon that replies with the string `"ok"` simply
    /// leaves `relayToken` nil. Returns the token (if any) for the caller to wire
    /// into `ApprovalRelay`.
    @discardableResult
    public func registerDevice(pushBackendURL: String, sessionID: String) async throws -> String? {
        let data = try await sendRPC(
            method: "conduit.device.register",
            params: [
                "pushBackendURL": pushBackendURL,
                "sessionID": sessionID,
            ]
        )
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return relayToken
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "device.register failed")
        }
        if let result = dict["result"] as? [String: Any],
           let token = result["relayToken"] as? String, !token.isEmpty {
            relayToken = token
        }
        return relayToken
    }

    public static func decisionWireValue(for decision: Approval.Decision) -> String {
        switch decision {
        case .approved: return "approve"
        case .approvedAlways: return "approveAlways"
        case .rejected, .expired: return "deny"
        }
    }

    /// Build the `agent.approval.response` JSON-RPC envelope sent to conduitd.
    /// Pure + static so the wire contract is unit-testable (the live `respond`
    /// path needs an SSH channel). `approvalId` is carried verbatim — Swift's
    /// `UUID.uuidString` is UPPERCASE; the daemon matches it case-insensitively
    /// (a lowercase/uppercase mismatch here once dropped every decision).
    public static func responseEnvelope(
        approvalId: String,
        decision: Approval.Decision,
        editedToolInput: String? = nil
    ) -> [String: Any] {
        var params: [String: Any] = [
            "approvalId": approvalId,
            "decision": decisionWireValue(for: decision),
        ]
        if let editedToolInput, !editedToolInput.isEmpty {
            params["editedToolInput"] = editedToolInput
        }
        return [
            "jsonrpc": "2.0",
            "method": "agent.approval.response",
            "params": params,
        ]
    }

    public func respond(
        approvalId: String,
        decision: Approval.Decision,
        editedToolInput: String? = nil
    ) async throws {
        // Throw (don't silently return) when the channel is dead/stopped — a
        // reconnect nils `stdinWriter`. Callers treat the throw as "not delivered"
        // and fall back to the backend relay instead of dropping the decision.
        guard let writer = stdinWriter else { throw DaemonChannelError.notRunning }
        let envelope = Self.responseEnvelope(
            approvalId: approvalId,
            decision: decision,
            editedToolInput: editedToolInput
        )
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

    public func savePolicyYAML(cwd: String, yaml: String) async throws {
        let data = try await sendRPC(
            method: "agent.policy.set",
            params: ["cwd": cwd, "yaml": yaml]
        )
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .ok, .pong: return
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    /// Load policy YAML text for the editor (global or repo-local for `cwd`).
    public func fetchPolicyYAML(cwd: String) async throws -> String {
        let result = try await fetchPolicy(cwd: cwd)
        if let yaml = result.yaml, !yaml.isEmpty { return yaml }
        throw DaemonChannelError.badResponse
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

    // MARK: - Proactive dispatch & schedule (WS-B2)

    /// Start an agent run on the host, bounded by policy + budget on the daemon.
    public func dispatchAgent(agent: String, cwd: String, prompt: String, budgetUSD: Double = 0) async throws -> DispatchResult {
        var params: [String: Any] = ["agent": agent, "cwd": cwd, "prompt": prompt]
        if budgetUSD > 0 { params["budgetUSD"] = budgetUSD }
        let data = try await sendRPC(method: "agent.dispatch", params: params)
        return try Self.decodeResult(data, as: DispatchResult.self)
    }

    @discardableResult
    public func cancelRun(runId: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.cancel", params: ["runId": runId])
        return (try Self.decodeResultObject(data)["cancelled"] as? Bool) ?? false
    }

    /// Alias for `cancelRun` — the run-control surface uses "stop" terminology.
    @discardableResult
    public func stopRun(runId: String) async throws -> Bool { try await cancelRun(runId: runId) }

    @discardableResult
    public func pauseRun(runId: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.pause", params: ["runId": runId])
        return (try Self.decodeResultObject(data)["paused"] as? Bool) ?? false
    }

    @discardableResult
    public func resumeRun(runId: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.resume", params: ["runId": runId])
        return (try Self.decodeResultObject(data)["resumed"] as? Bool) ?? false
    }

    @discardableResult
    public func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool {
        let data = try await sendRPC(method: "agent.budget.set", params: ["runId": runId, "budgetUSD": budgetUSD])
        return (try Self.decodeResultObject(data)["ok"] as? Bool) ?? false
    }

    @discardableResult
    public func addSchedule(_ schedule: BridgeSchedule) async throws -> BridgeSchedule {
        let params: [String: Any] = [
            "agent": schedule.agent, "cwd": schedule.cwd, "prompt": schedule.prompt,
            "everySeconds": schedule.everySeconds, "budgetUSD": schedule.budgetUSD,
        ]
        let data = try await sendRPC(method: "agent.schedule.add", params: params)
        return try Self.decodeResult(data, as: BridgeSchedule.self)
    }

    public func listSchedules() async throws -> [BridgeSchedule] {
        let data = try await sendRPC(method: "agent.schedule.list", params: [:])
        struct Wrap: Decodable { let schedules: [BridgeSchedule]? }
        return try Self.decodeResult(data, as: Wrap.self).schedules ?? []
    }

    @discardableResult
    public func removeSchedule(id: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.schedule.remove", params: ["id": id])
        return (try Self.decodeResultObject(data)["removed"] as? Bool) ?? false
    }

    private static func decodeResultObject(_ data: Data) throws -> [String: Any] {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "rpc error")
        }
        return (dict["result"] as? [String: Any]) ?? [:]
    }

    private static func decodeResult<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let result = try decodeResultObject(data)
        let rdata = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: rdata)
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
