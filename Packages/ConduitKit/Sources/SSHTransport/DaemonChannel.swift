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

    /// Run health checks on the remote daemon
    public func runDoctor() async throws -> DoctorReport {
        let data = try await sendRPC(method: "agent.doctor", params: [String: String]())
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .doctorReport(let report): return report
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
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

    public func verifyAudit() async throws -> AuditVerification {
        let data = try await sendRPC(method: "agent.audit.verify", params: [String: String]())
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .auditVerification(let result): return result
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    public func exportAudit() async throws -> Data {
        let data = try await sendRPC(method: "agent.audit.export", params: [String: String]())
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .auditExport(let jsonl):
            guard let jsonData = jsonl.data(using: .utf8) else {
                throw DaemonChannelError.badResponse
            }
            return jsonData
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

    public func simulatePolicy(yaml: String, periodDays: Int = 7) async throws -> PolicySimulation {
        let data = try await sendRPC(
            method: "agent.policy.simulate",
            params: ["yaml": yaml, "periodDays": periodDays]
        )
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "policy.simulate failed")
        }
        guard let result = dict["result"],
              JSONSerialization.isValidJSONObject(result),
              let rd = try? JSONSerialization.data(withJSONObject: result)
        else {
            throw DaemonChannelError.badResponse
        }
        return try JSONDecoder().decode(PolicySimulation.self, from: rd)
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

    public func getHostHealth() async throws -> HostHealth {
        let data = try await sendRPC(method: "agent.host.health", params: [String: String]())
        guard let response = DaemonRPCResponse.decode(from: data) else {
            throw DaemonChannelError.badResponse
        }
        switch response {
        case .hostHealth(let health): return health
        case .error(_, let message): throw DaemonChannelError.rpc(message)
        default: throw DaemonChannelError.badResponse
        }
    }

    // MARK: - CI Events

    /// Fetch recent CI/PR events for a repository from the push-backend.
    /// The daemon proxies this request to the webhook store.
    public func recentCIEvents(repo: String, limit: Int = 50) async throws -> [CIEvent] {
        var params: [String: Any] = ["repo": repo]
        if limit != 50 { params["limit"] = limit }
        let data = try await sendRPC(method: "agent.ci.recent", params: params)
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "ci.recent failed")
        }
        // conduitd returns the event array directly as the result (not wrapped).
        let raw: Any = dict["result"] ?? []
        guard JSONSerialization.isValidJSONObject(raw) || raw is [Any],
              let rd = try? JSONSerialization.data(withJSONObject: raw)
        else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // Go time.Time marshals as RFC3339.
        return (try? decoder.decode([CIEvent].self, from: rd)) ?? []
    }

    // MARK: - Git (review + ship the agent's work; routed through conduitd for audit/policy)

    /// Current branch + ahead/behind + dirty/clean for the agent's workdir.
    public func gitStatus(workdir: String) async throws -> GitStatus {
        let data = try await sendRPC(method: "agent.git.status", params: ["workdir": workdir])
        let result = try Self.gitResultObject(data)
        let branch = result["branch"] as? String ?? "HEAD"
        let upstream = result["upstream"] as? String
        let ahead = result["ahead"] as? Int ?? 0
        let behind = result["behind"] as? Int ?? 0
        let changes: [GitFileChange] = (result["changes"] as? [[String: Any]] ?? []).map {
            GitFileChange(
                path: $0["path"] as? String ?? "",
                code: $0["code"] as? String ?? "",
                staged: $0["staged"] as? Bool ?? false
            )
        }
        return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, changes: changes)
    }

    /// Unified diff text for the workdir (optionally scoped to a path / the index).
    public func gitDiff(workdir: String, path: String? = nil, staged: Bool = false) async throws -> String {
        var params: [String: Any] = ["workdir": workdir, "staged": staged]
        if let path { params["path"] = path }
        let data = try await sendRPC(method: "agent.git.diff", params: params)
        return try Self.gitResultObject(data)["diff"] as? String ?? ""
    }

    /// Changed files between base and branch (name-status), for the "Changes" list.
    public func gitChangedFiles(workdir: String, baseBranch: String? = nil, branch: String? = nil) async throws -> [Worktree.ChangedFile] {
        var params: [String: Any] = ["workdir": workdir]
        if let baseBranch { params["baseBranch"] = baseBranch }
        if let branch { params["branch"] = branch }
        let data = try await sendRPC(method: "agent.git.changedFiles", params: params)
        let files = try Self.gitResultObject(data)["files"] as? [[String: Any]] ?? []
        return files.compactMap { f in
            guard let path = f["path"] as? String else { return nil }
            let status = Worktree.ChangedFile.FileStatus(rawValue: f["status"] as? String ?? "modified") ?? .modified
            return Worktree.ChangedFile(path: path, status: status)
        }
    }

    /// One-tap "Ship it": stage + commit + push (+ open PR). Idempotent on partial
    /// failure — `committed`/`pushed` report exactly which stages completed so the
    /// caller can surface a precise state and retry safely.
    public func gitShip(
        workdir: String,
        message: String,
        openPR: Bool,
        base: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) async throws -> GitShipResult {
        var params: [String: Any] = ["workdir": workdir, "message": message, "openPR": openPR]
        if let base { params["base"] = base }
        if let title { params["title"] = title }
        if let body { params["body"] = body }
        let data = try await sendRPC(method: "agent.git.ship", params: params)
        let result = try Self.gitResultObject(data)
        return GitShipResult(
            committed: result["committed"] as? Bool ?? false,
            pushed: result["pushed"] as? Bool ?? false,
            prURL: result["prURL"] as? String,
            message: result["message"] as? String
        )
    }

    /// Real worktree list for the host (replaces the old `return []` stub).
    public func listWorktrees(workdir: String) async throws -> [Worktree] {
        let data = try await sendRPC(method: "agent.worktree.list", params: ["workdir": workdir])
        let result = try Self.gitResultObject(data)
        guard let trees = result["worktrees"],
              let rd = try? JSONSerialization.data(withJSONObject: trees) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Worktree].self, from: rd)) ?? []
    }

    /// Unwrap a JSON-RPC `result` object or throw the daemon's error message.
    private static func gitResultObject(_ data: Data) throws -> [String: Any] {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "git rpc error")
        }
        return (dict["result"] as? [String: Any]) ?? [:]
    }

    // MARK: - Loop updates

    /// Push a loop update to the daemon for persistence and broadcast.
    public func updateLoop(_ loop: Loop) async throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(loop),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        _ = try await sendRPC(method: "agent.loop.update", params: dict)
    }

    // MARK: - Proactive dispatch & schedule (WS-B2)

    /// Start an agent run on the host, bounded by policy + budget on the daemon.
    public func dispatchAgent(agent: String, cwd: String, prompt: String, budgetUSD: Double = 0, model: String? = nil) async throws -> DispatchResult {
        var params: [String: Any] = ["agent": agent, "cwd": cwd, "prompt": prompt]
        if budgetUSD > 0 { params["budgetUSD"] = budgetUSD }
        if let model, !model.isEmpty { params["model"] = model }
        let data = try await sendRPC(method: "agent.dispatch", params: params)
        return try Self.decodeResult(data, as: DispatchResult.self)
    }

    /// Continue an existing run with a follow-up prompt. The daemon re-launches the
    /// vendor CLI under a NEW runId (re-passing policy + budget); output streams back
    /// under that new runId via the existing agent.run.output path.
    public func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
        let params: [String: Any] = ["runId": runId, "prompt": prompt]
        let data = try await sendRPC(method: "agent.run.continue", params: params)
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

    // MARK: - E2E Relay

    /// Fetch the current E2E relay connection state from the daemon.
    public func fetchRelayState() async throws -> Session.RelayState {
        let data = try await sendRPC(method: "conduit.relay.state", params: [:])
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if dict["error"] != nil {
            return .none
        }
        if let result = dict["result"] as? [String: Any],
           let raw = result["state"] as? String,
           let state = Session.RelayState(rawValue: raw) {
            return state
        }
        return .none
    }

    // MARK: - Quota / Spend Guardrails

    /// Fetch per-provider quota status and alerts from the daemon.
    public func getQuotaStatus() async throws -> QuotaGuard {
        let data = try await sendRPC(method: "agent.quota.status", params: [String: Any]())
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "quota.status failed")
        }
        guard let result = dict["result"],
              JSONSerialization.isValidJSONObject(result),
              let rd = try? JSONSerialization.data(withJSONObject: result)
        else {
            throw DaemonChannelError.badResponse
        }
        return try JSONDecoder().decode(QuotaGuard.self, from: rd)
    }

    /// Set daily and/or monthly USD caps for a provider. Pass 0 to leave unchanged.
    @discardableResult
    public func setProviderCap(provider: String, dailyUSD: Double, monthlyUSD: Double) async throws -> Bool {
        let data = try await sendRPC(
            method: "agent.quota.setCap",
            params: ["provider": provider, "dailyUSD": dailyUSD, "monthlyUSD": monthlyUSD]
        )
        return (try Self.decodeResultObject(data)["ok"] as? Bool) ?? false
    }

    /// Update cumulative spend for a provider (called by the bridge when usage data arrives).
    @discardableResult
    public func updateProviderSpend(provider: String, usd: Double) async throws -> Bool {
        let data = try await sendRPC(
            method: "agent.quota.updateSpend",
            params: ["provider": provider, "usd": usd]
        )
        return (try Self.decodeResultObject(data)["ok"] as? Bool) ?? false
    }

    // MARK: - Secrets Broker

    /// Store a secret on the daemon (called from phone after manual entry or import).
    @discardableResult
    public func storeSecret(name: String, type: String, scope: String, value: String) async throws -> String {
        let data = try await sendRPC(
            method: "agent.secret.store",
            params: ["name": name, "type": type, "scope": scope, "value": value]
        )
        return (try Self.decodeResultObject(data)["id"] as? String) ?? ""
    }

    /// Agent requests access to a secret — escalates to phone if not already authorized.
    public func requestSecret(request: SecretRequest) async throws -> Bool {
        let encoder = JSONEncoder()
        guard let requestData = try? encoder.encode(request),
              let dict = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any]
        else { return false }
        let data = try await sendRPC(method: "agent.secret.request", params: dict)
        return (try Self.decodeResultObject(data)["pending"] as? Bool) ?? false
    }

    /// Phone authorizes a secret for a specific scope.
    @discardableResult
    public func authorizeSecret(requestID: String, scope: String, expiresAt: Date? = nil, oneTime: Bool = false) async throws -> Bool {
        var params: [String: Any] = [
            "requestId": requestID,
            "scope": scope,
            "oneTime": oneTime,
        ]
        if let expiresAt {
            let formatter = ISO8601DateFormatter()
            params["expiresAt"] = formatter.string(from: expiresAt)
        }
        let data = try await sendRPC(method: "agent.secret.authorize", params: params)
        return (try Self.decodeResultObject(data)["ok"] as? Bool) ?? false
    }

    /// Revoke a secret authorization.
    @discardableResult
    public func revokeSecret(requestID: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.secret.revoke", params: ["requestId": requestID])
        return (try Self.decodeResultObject(data)["removed"] as? Bool) ?? false
    }

    /// Delete a stored secret.
    @discardableResult
    public func deleteSecret(secretID: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.secret.delete", params: ["secretId": secretID])
        return (try Self.decodeResultObject(data)["removed"] as? Bool) ?? false
    }

    /// List all stored secrets (metadata only) and pending requests.
    public func listSecrets() async throws -> SecretsListResult {
        let data = try await sendRPC(method: "agent.secret.list", params: [String: Any]())
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DaemonChannelError.badResponse
        }
        if let err = dict["error"] as? [String: Any] {
            throw DaemonChannelError.rpc(err["message"] as? String ?? "secret.list failed")
        }
        guard let result = dict["result"],
              JSONSerialization.isValidJSONObject(result),
              let rd = try? JSONSerialization.data(withJSONObject: result)
        else {
            throw DaemonChannelError.badResponse
        }
        return try JSONDecoder().decode(SecretsListResult.self, from: rd)
    }

    // MARK: - Private helpers

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
