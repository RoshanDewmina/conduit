import Foundation

// Framing helper: 4-byte big-endian length prefix
public enum DaemonFraming {
    public static func frame(_ json: Data) -> Data {
        var out = Data(capacity: 4 + json.count)
        let len = UInt32(json.count)
        out.append(UInt8((len >> 24) & 0xFF))
        out.append(UInt8((len >> 16) & 0xFF))
        out.append(UInt8((len >> 8) & 0xFF))
        out.append(UInt8(len & 0xFF))
        out.append(json)
        return out
    }

    public static func unframe(_ data: Data) -> (Data, Data)? {
        guard data.count >= 4 else { return nil }
        let b = data
        let len = (UInt32(b[b.startIndex]) << 24)
                | (UInt32(b[b.startIndex+1]) << 16)
                | (UInt32(b[b.startIndex+2]) << 8)
                | UInt32(b[b.startIndex+3])
        let needed = 4 + Int(len)
        guard data.count >= needed else { return nil }
        return (data.subdata(in: 4..<needed), data.subdata(in: needed..<data.count))
    }
}

/// Blast-radius metadata from lancerd policy escalation (WS-B).
public struct ApprovalBlastRadius: Codable, Sendable, Hashable {
    public let files: [String]?
    public let touchesGit: Bool?
    public let touchesNetwork: Bool?
    public let matchedRule: String?

    public init(
        files: [String]? = nil,
        touchesGit: Bool? = nil,
        touchesNetwork: Bool? = nil,
        matchedRule: String? = nil
    ) {
        self.files = files
        self.touchesGit = touchesGit
        self.touchesNetwork = touchesNetwork
        self.matchedRule = matchedRule
    }
}

public struct ApprovalPendingParams: Codable, Sendable {
    public let id: String
    public let sessionId: String?
    public let agent: String
    public let kind: String
    public let command: String?
    public let patch: String?
    public let cwd: String
    public let risk: Int
    // Optional: hook approvals (e.g. a user's own terminal session) carry no
    // Lancer runId; only dispatched runs do. Required → broke decode of every
    // approval the daemon sends (it emits ApprovalEvent, which has no runId).
    public let runId: String?

    public let toolName: String?
    public let toolUseID: String?
    public let agentSessionID: String?
    public let toolInput: String?

    public let files: [String]?
    public let touchesGit: Bool?
    public let touchesNetwork: Bool?
    public let matchedRule: String?

    /// The daemon's `computeContentHash` over (command, patch, cwd, toolInput),
    /// echoed verbatim in the decision so `approvalStore.resolve` can verify it —
    /// mirrors `ApprovalEvent.ContentHash` (`daemon/lancerd/approval.go`).
    public let contentHash: String?

    enum CodingKeys: String, CodingKey {
        case id, sessionId, agent, kind, command, patch, cwd, risk, runId
        case toolName, toolUseID, toolInput
        case agentSessionID = "agentSessionID"
        case files, touchesGit, touchesNetwork, matchedRule
        case contentHash
    }

    public var approvalRisk: Approval.Risk {
        Approval.Risk(rawValue: min(risk, 3)) ?? .high
    }
    public var approvalKind: Approval.Kind {
        Approval.Kind(rawValue: kind) ?? .command
    }
    public var approvalAgent: Approval.AgentSource {
        Approval.AgentSource(rawValue: agent) ?? .unknown
    }
    public var approvalToolName: String? { toolName }
    public var approvalToolUseID: String? { toolUseID }
    public var approvalAgentSessionID: String? { agentSessionID }
    public var approvalToolInput: String? { toolInput }
    public var approvalContentHash: String? { contentHash }
    public var blastRadius: ApprovalBlastRadius {
        ApprovalBlastRadius(
            files: files,
            touchesGit: touchesGit,
            touchesNetwork: touchesNetwork,
            matchedRule: matchedRule
        )
    }
}

public struct AuditLogEntry: Codable, Sendable, Identifiable, Hashable {
    public let timestamp: String
    public let action: String
    public let agent: String?
    public let kind: String?
    public let command: String?
    public let effect: String?
    public let rule: String?
    public let approvalId: String?
    public let hash: String?
    public let prevHash: String?

    public var id: String { "\(timestamp)-\(action)-\(approvalId ?? command ?? "")" }

    enum CodingKeys: String, CodingKey {
        case timestamp, action, agent, kind, command, effect, rule
        case approvalId, hash, prevHash
    }
}

public struct AuditTailResult: Codable, Sendable {
    public let entries: [AuditLogEntry]
}

/// Legacy single-YAML response (older lancerd); prefer PolicyGetResult.
public struct PolicyYAMLResult: Codable, Sendable {
    public let yaml: String
}

public struct PolicyGetResult: Codable, Sendable {
    public let documents: [PolicyDocument]?
    public let `default`: String?
    public let yaml: String?
}

public struct PolicyDocument: Codable, Sendable {
    public var `default`: String?
    public var rules: [PolicyRule]?
}

public struct PolicyRule: Codable, Sendable, Hashable {
    public var ruleID: String?
    public var effect: String
    public var agent: String?
    public var tool: String?
    public var kind: String?
    public var match: String?
    public var cwd: String?
    public var minRisk: String?
    public var maxRisk: String?

    enum CodingKeys: String, CodingKey {
        case ruleID = "id"
        case effect, agent, tool, kind, match, cwd, minRisk, maxRisk
    }
}

// Result of an agent.dispatch RPC (WS-B2). Status:
// running | needs-approval | denied | budget-exceeded | error.
public struct DispatchResult: Codable, Sendable, Hashable {
    public let runId: String?
    public let status: String
    public let decision: String?
    public let rule: String?
    public let message: String?
    /// The daemon's `~`-expanded absolute cwd the run actually launched in — the
    /// authoritative value to persist into `ChatConversation.cwd`, NOT the raw
    /// string the phone sent. Relay-dispatched agents default that raw string to
    /// the literal `"~"` (see `AppRoot.dispatchAgents()`), which only the daemon
    /// (the machine that actually has a home directory) can resolve. Without this,
    /// a phone-dispatched conversation and a terminal session in the exact same
    /// real directory silently fail to group/continue as the same project, since
    /// nothing else in the codebase normalizes cwd strings before comparing them.
    /// `nil` when talking to an older daemon build that doesn't send it yet —
    /// callers must fall back to the raw cwd they sent.
    public let cwd: String?

    public init(runId: String? = nil, status: String, decision: String? = nil, rule: String? = nil, message: String? = nil, cwd: String? = nil) {
        self.runId = runId
        self.status = status
        self.decision = decision
        self.rule = rule
        self.message = message
        self.cwd = cwd
    }

    /// The runId of a genuinely *started* run, or `nil` otherwise. A usable run
    /// requires `status == "started"` AND a non-empty runId — an empty-string
    /// runId from the daemon would pass a bare `if let` and then silently break
    /// approval/output matching on the follow-up turn (TEST-02).
    public var startedRunId: String? {
        guard status == "started", let runId, !runId.isEmpty else { return nil }
        return runId
    }
}

// A recurring interval dispatch on the resident bridge (WS-B2), persisted by
// lancerd. Distinct from AgentKit.AgentSchedule (the cloud hosted-agent schedule).
public struct BridgeSchedule: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var agent: String
    public var cwd: String
    public var prompt: String
    public var everySeconds: Int
    public var budgetUSD: Double
    public var lastRunUnix: Int

    public init(id: String = "", agent: String, cwd: String, prompt: String, everySeconds: Int, budgetUSD: Double = 0, lastRunUnix: Int = 0) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.prompt = prompt
        self.everySeconds = everySeconds
        self.budgetUSD = budgetUSD
        self.lastRunUnix = lastRunUnix
    }
}

/// An agent's request for a secret, pushed to the phone for authorization.
public struct SecretRequestEvent: Codable, Sendable {
    public let id: String
    public let agent: String
    public let toolName: String
    public let credentialType: String
    public let requestedScope: String
    public let hostName: String

    public init(id: String, agent: String, toolName: String, credentialType: String, requestedScope: String, hostName: String) {
        self.id = id
        self.agent = agent
        self.toolName = toolName
        self.credentialType = credentialType
        self.requestedScope = requestedScope
        self.hostName = hostName
    }
}

/// Result of listing secrets and pending requests from the daemon.
public struct SecretsListResult: Codable, Sendable {
    public let secrets: [SecretEntry]?
    public let pending: [PendingSecretRequest]?
}

// Streamed stdout/stderr from a dispatched run (close-the-loop).
// Wire: {"method":"agent.run.output","params":{"runId","stream","chunk","seq"}}.
public struct RunOutputParams: Codable, Sendable, Hashable {
    public let runId: String
    public let stream: String
    public let chunk: String
    public let seq: Int

    public init(runId: String, stream: String, chunk: String, seq: Int) {
        self.runId = runId
        self.stream = stream
        self.chunk = chunk
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey { case runId, stream, chunk, seq }

    // Cross-module footgun: synthesized Decodable ignores memberwise defaults, so
    // decode defensively for forward-compat with daemons that omit a field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId = try c.decodeIfPresent(String.self, forKey: .runId) ?? ""
        stream = try c.decodeIfPresent(String.self, forKey: .stream) ?? "stdout"
        chunk = try c.decodeIfPresent(String.self, forKey: .chunk) ?? ""
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
    }
}

// Run lifecycle transition from the daemon (close-the-loop).
// Wire: {"method":"agent.run.status","params":{"runId","status","exitCode"?}}.
public struct RunStatusParams: Codable, Sendable, Hashable {
    public let runId: String
    public let status: String
    public let exitCode: Int?

    public init(runId: String, status: String, exitCode: Int? = nil) {
        self.runId = runId
        self.status = status
        self.exitCode = exitCode
    }

    enum CodingKeys: String, CodingKey { case runId, status, exitCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId = try c.decodeIfPresent(String.self, forKey: .runId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
    }
}

public struct ToolStartParams: Codable, Sendable {
    public let runId: String
    public let toolId: String
    public let toolName: String
    public let inputJSON: String

    public init(runId: String, toolId: String, toolName: String, inputJSON: String) {
        self.runId = runId
        self.toolId = toolId
        self.toolName = toolName
        self.inputJSON = inputJSON
    }
}

/// A durable, vendor-neutral artifact emitted by lancerd. The same identifier
/// is reused while an artifact moves from running to done/failed, letting the
/// iOS history store upsert without a schema migration.
public struct AgentArtifactEvent: Codable, Sendable, Hashable {
    public let artifactID: String
    public let runID: String
    public let kind: String
    public let title: String
    public let summary: String?
    public let payloadJSON: String
    public let status: String

    public init(
        artifactID: String,
        runID: String,
        kind: String,
        title: String,
        summary: String? = nil,
        payloadJSON: String = "{}",
        status: String = "running"
    ) {
        self.artifactID = artifactID
        self.runID = runID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case artifactID, runID, kind, title, summary, payloadJSON, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artifactID = try c.decodeIfPresent(String.self, forKey: .artifactID) ?? ""
        runID = try c.decodeIfPresent(String.self, forKey: .runID) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "tool"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Tool"
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        payloadJSON = try c.decodeIfPresent(String.self, forKey: .payloadJSON) ?? "{}"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "running"
    }
}

/// Lifecycle state of a Claude Code (or other vendor) session observed on the
/// host, as reported by `agent.sessions.list`. Distinct from `ChatConversation.Status`,
/// which models a Lancer-dispatched run, not an arbitrary host-side session.
public enum ObservedSessionState: String, Codable, Sendable {
    case working
    case waitingForInput
    case idle
    case completed
    case recentlyActive
    case historical
    case unknown
}

/// Where a session's transcript comes from / how much Lancer can do with it.
/// `lancerManaged` sessions were dispatched by Lancer (full control: stop/continue).
/// `providerManaged` sessions are running in the vendor CLI's own session store but
/// not started by Lancer (read-only watch). `transcriptObserved` sessions are
/// inferred purely from on-disk transcript files (read-only, least live).
public enum SessionSource: String, Codable, Sendable {
    case lancerManaged
    case providerManaged
    case transcriptObserved
}

/// A read-only list-item describing a Claude Code (or other vendor) session
/// discovered on the host. Returned by `agent.sessions.list`.
public struct ObservedSession: Codable, Sendable, Identifiable, Hashable {
    public let sessionId: String
    public let provider: String
    public let title: String
    public let cwd: String
    public let state: ObservedSessionState
    public let source: SessionSource
    public let lastActivity: Date
    public let messageCount: Int

    public var id: String { sessionId }

    public init(
        sessionId: String,
        provider: String,
        title: String,
        cwd: String,
        state: ObservedSessionState,
        source: SessionSource,
        lastActivity: Date,
        messageCount: Int
    ) {
        self.sessionId = sessionId
        self.provider = provider
        self.title = title
        self.cwd = cwd
        self.state = state
        self.source = source
        self.lastActivity = lastActivity
        self.messageCount = messageCount
    }
}

/// Params for `agent.sessions.list`. No filters in Phase 1 — the daemon returns
/// every session it knows about for the host.
public struct SessionsListParams: Codable, Sendable {
    public init() {}
}

public struct SessionsListResult: Codable, Sendable {
    public let sessions: [ObservedSession]
}

/// Vendor ids (e.g. "claudeCode", "codex") whose CLI is installed on the host, so
/// the phone only offers agents the user actually has.
public struct AgentsInstalledResult: Codable, Sendable {
    public let agents: [String]
}

/// One transcript turn returned by `agent.sessions.transcript`.
public struct SessionMessage: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case toolCall
        case toolResult
        case system
        case unknown
    }

    public let role: Role
    public let text: String
    public let toolName: String?
    public let timestamp: Date?

    public init(role: Role, text: String, toolName: String? = nil, timestamp: Date? = nil) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.timestamp = timestamp
    }
}

/// Params for `agent.sessions.transcript`.
public struct SessionsTranscriptParams: Codable, Sendable {
    public let sessionId: String
    public let sinceLine: Int

    public init(sessionId: String, sinceLine: Int) {
        self.sessionId = sessionId
        self.sinceLine = sinceLine
    }
}

public struct SessionsTranscriptResult: Codable, Sendable {
    public let messages: [SessionMessage]
    public let nextLine: Int
    public let resetRequired: Bool
}

public struct SessionDiscoveredParams: Codable, Sendable {
    public let sessionId: String
    public let tmuxName: String?
    public let agent: String?
    public let cwd: String?
    public let managed: Bool

    public init(sessionId: String, tmuxName: String?, agent: String?, cwd: String?, managed: Bool) {
        self.sessionId = sessionId
        self.tmuxName = tmuxName
        self.agent = agent
        self.cwd = cwd
        self.managed = managed
    }
}

public enum DaemonEvent: Sendable {
    case approvalPending(ApprovalPendingParams)
    case agentStatus(AgentStatusSnapshot)
    case secretRequest(SecretRequestEvent)
    case runOutput(RunOutputParams)
    case runStatus(RunStatusParams)
    case toolStart(ToolStartParams)
    case artifact(AgentArtifactEvent)
    case sessionDiscovered(SessionDiscoveredParams)
    case pong
    case unknown(method: String)
}

extension DaemonEvent {
    public static func decode(from data: Data) -> DaemonEvent? {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let method = dict["method"] as? String else { return nil }
        switch method {
        case "agent.approval.pending":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let pending = try? JSONDecoder().decode(ApprovalPendingParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .approvalPending(pending)
        case "agent.status":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let snapshot = try? JSONDecoder().decode(AgentStatusSnapshot.self, from: paramsData)
            else { return .unknown(method: method) }
            return .agentStatus(snapshot)
        case "agent.secret.request":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let event = try? JSONDecoder().decode(SecretRequestEvent.self, from: paramsData)
            else { return .unknown(method: method) }
            return .secretRequest(event)
        case "agent.run.output":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(RunOutputParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .runOutput(p)
        case "agent.run.status":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(RunStatusParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .runStatus(p)
        case "agent.tool.start":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(ToolStartParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .toolStart(p)
        case "agent.artifact":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(AgentArtifactEvent.self, from: paramsData)
            else { return .unknown(method: method) }
            return .artifact(p)
        case "session.discovered":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(SessionDiscoveredParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .sessionDiscovered(p)
        case "pong":
            return .pong
        default:
            return .unknown(method: method)
        }
    }
}

public enum DaemonRPCResponse: Sendable {
    case agentStatus(AgentStatusSnapshot)
    case auditTail(AuditTailResult)
    case auditVerification(AuditVerification)
    case auditExport(String)
    case policyGet(PolicyGetResult)
    case policyYAML(PolicyYAMLResult)
    case doctorReport(DoctorReport)
    case secretsList(SecretsListResult)
    case hostHealth(HostHealth)
    case driftReport(DriftReport)
    case pong
    case ok
    case error(code: Int, message: String)
    case unknown

    public static func decode(from data: Data) -> DaemonRPCResponse? {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let err = dict["error"] as? [String: Any], let message = err["message"] as? String {
            return .error(code: err["code"] as? Int ?? -1, message: message)
        }
        guard let result = dict["result"] else { return .unknown }
        if let s = result as? String {
            if s == "pong" { return .pong }
            if s == "ok" { return .ok }
        }
        guard JSONSerialization.isValidJSONObject(result),
              let rd = try? JSONSerialization.data(withJSONObject: result) else { return .unknown }
        let dec = JSONDecoder()
        // Drift first: its required root+scanned+findings keys are distinctive,
        // so this never shadows the looser-typed results below.
        if dict["result"] is [String: Any],
           let drift = try? dec.decode(DriftReport.self, from: rd),
           (result as? [String: Any])?["findings"] != nil {
            return .driftReport(drift)
        }
        if let snap = try? dec.decode(AgentStatusSnapshot.self, from: rd) { return .agentStatus(snap) }
        if let t = try? dec.decode(AuditTailResult.self, from: rd) { return .auditTail(t) }
        if let v = try? dec.decode(AuditVerification.self, from: rd) { return .auditVerification(v) }
        if let d = try? dec.decode([String: String].self, from: rd), let data = d["data"] {
            return .auditExport(data)
        }
        if let pol = try? dec.decode(PolicyGetResult.self, from: rd) { return .policyGet(pol) }
        if let yaml = try? dec.decode(PolicyYAMLResult.self, from: rd) { return .policyYAML(yaml) }
        if let doc = try? dec.decode(DoctorReport.self, from: rd) { return .doctorReport(doc) }
        if let secrets = try? dec.decode(SecretsListResult.self, from: rd) { return .secretsList(secrets) }
        if let health = try? dec.decode(HostHealth.self, from: rd) { return .hostHealth(health) }
        return .unknown
    }
}
