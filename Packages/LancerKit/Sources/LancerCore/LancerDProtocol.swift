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

/// Result of `agent.emergencyStop` / relay `agentEmergencyStop`.
public struct EmergencyStopResult: Codable, Sendable, Equatable {
    public let emergencyStopped: Bool
    public let stoppedRuns: Int

    public init(emergencyStopped: Bool, stoppedRuns: Int) {
        self.emergencyStopped = emergencyStopped
        self.stoppedRuns = stoppedRuns
    }
}

/// Legacy single-YAML response (older lancerd); prefer PolicyGetResult.
public struct PolicyYAMLResult: Codable, Sendable {
    public let yaml: String
}

/// The three coarse policy-decision modes a relay-only phone may read/set —
/// mirrors the daemon's `policy.Effect` (deny/ask/allow), i.e. the global
/// policy document's `default` field. Never a full rules-file round-trip; see
/// `agentPermissionModeGet`/`agentPermissionModeSet` in `e2e_router.go` and
/// `docs/product/2026-07-16-policy-audit-relay-port-map.md`.
public enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case deny
    case ask
    case allow
}

/// Result of relay `agentPermissionModeGet`.
public struct PermissionModeGetResult: Codable, Sendable {
    public let mode: String
}

/// Result of relay `agentPermissionModeSet`. `ok == false` means the daemon
/// rejected the mode (invalid value) and left the policy file untouched.
public struct PermissionModeSetResult: Codable, Sendable {
    public let ok: Bool
    public let mode: String?
    public let error: String?
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
    /// Absolute path of the daemon-managed per-run worktree, when `useWorktree` was set.
    public let worktreePath: String?
    /// True when the run launched in an isolated managed worktree (not the repo root).
    public let isolated: Bool?

    public init(runId: String? = nil, status: String, decision: String? = nil, rule: String? = nil, message: String? = nil, cwd: String? = nil, worktreePath: String? = nil, isolated: Bool? = nil) {
        self.runId = runId
        self.status = status
        self.decision = decision
        self.rule = rule
        self.message = message
        self.cwd = cwd
        self.worktreePath = worktreePath
        self.isolated = isolated
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
    /// Mirrors the Go `SessionMessage.Role` values a vendor adapter can emit
    /// (`daemon/lancerd/claude_transcript_adapter.go`: user, assistant, system,
    /// toolCall, toolResult, thinking/redacted_thinking → "thinking", unknown).
    /// Decodes any *unrecognized* raw string to `.unknown` rather than failing
    /// the whole struct's decode — a real Claude Code transcript's `thinking`
    /// role (extended-thinking blocks) previously wasn't a case here at all,
    /// so `JSONDecoder` threw `dataCorrupted` on every real session containing
    /// one, which `E2ERelayBridge.handle(_:)`'s `sessionsTranscriptResult` arm
    /// (`try? decoder.decode(...)`) silently turned into the misleading
    /// "Decryption failed" error surfaced to the user. Widening this enum to
    /// tolerate any future vendor-side role string (rather than re-breaking on
    /// the next new one) is deliberate — see the `sessionsTranscriptResult`
    /// case comment in E2ERelayBridge.swift.
    public enum Role: String, Sendable {
        case user
        case assistant
        case toolCall
        case toolResult
        case system
        case thinking
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

extension SessionMessage.Role: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionMessage.Role(rawValue: raw) ?? .unknown
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

// MARK: - Question pipeline wire types

/// Wire mirror of `QuestionOption` (daemon/lancerd/question.go).
public struct QuestionOptionWire: Codable, Sendable, Equatable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// Wire mirror of `QuestionItem` (daemon/lancerd/question.go).
public struct QuestionItemWire: Codable, Sendable, Equatable {
    public let header: String?
    public let question: String
    public let options: [QuestionOptionWire]?
    public let multiSelect: Bool?

    public init(header: String? = nil, question: String, options: [QuestionOptionWire]? = nil, multiSelect: Bool? = nil) {
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// Wire mirror of `QuestionEvent` (daemon/lancerd/question.go) — params for
/// the `agent.question.pending` JSON-RPC notification.
public struct QuestionPendingParams: Codable, Sendable, Equatable {
    public let id: String
    public let agent: String
    public let runId: String?
    public let cwd: String?
    public let toolUseID: String?
    public let timestamp: String
    public let questions: [QuestionItemWire]
    public let allowFreeText: Bool
    public let confidence: String

    public init(
        id: String, agent: String, runId: String? = nil, cwd: String? = nil,
        toolUseID: String? = nil, timestamp: String = "",
        questions: [QuestionItemWire] = [], allowFreeText: Bool = false,
        confidence: String = "bestEffort"
    ) {
        self.id = id
        self.agent = agent
        self.runId = runId
        self.cwd = cwd
        self.toolUseID = toolUseID
        self.timestamp = timestamp
        self.questions = questions
        self.allowFreeText = allowFreeText
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case id, agent, runId, cwd, toolUseID, timestamp, questions, allowFreeText, confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        toolUseID = try c.decodeIfPresent(String.self, forKey: .toolUseID)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        questions = try c.decodeIfPresent([QuestionItemWire].self, forKey: .questions) ?? []
        allowFreeText = try c.decodeIfPresent(Bool.self, forKey: .allowFreeText) ?? false
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence) ?? "bestEffort"
    }
}

/// Wire mirror of `QuestionItemAnswer` (daemon/lancerd/question.go).
public struct QuestionItemAnswerWire: Codable, Sendable, Equatable {
    public let selectedLabels: [String]?
    public let freeText: String?

    public init(selectedLabels: [String]? = nil, freeText: String? = nil) {
        self.selectedLabels = selectedLabels
        self.freeText = freeText
    }
}

/// Wire params for the `agent.question.answer` JSON-RPC method —
/// mirrors `QuestionAnswer` (daemon/lancerd/question.go).
public struct QuestionAnswerParams: Codable, Sendable, Equatable {
    public let questionId: String
    public let items: [QuestionItemAnswerWire]

    public init(questionId: String, items: [QuestionItemAnswerWire]) {
        self.questionId = questionId
        self.items = items
    }
}

/// Artifact payload stored for a `.question` ChatArtifact. The `event` field
/// carries the full QuestionEvent; `answer` is nil until the question is resolved
/// and non-nil once the user submits a response (QuestionCardModel.mergeAnswer).
public struct QuestionArtifactPayload: Codable, Sendable, Equatable {
    public let event: QuestionPendingParams
    public var answer: QuestionAnswerParams?

    public init(event: QuestionPendingParams, answer: QuestionAnswerParams? = nil) {
        self.event = event
        self.answer = answer
    }
}

public enum DaemonEvent: Sendable {
    case approvalPending(ApprovalPendingParams)
    case agentStatus(AgentStatusSnapshot)
    case secretRequest(SecretRequestEvent)
    case runOutput(RunOutputParams)
    case runStatus(RunStatusParams)
    case runReceipt(ProofReceipt)
    case toolStart(ToolStartParams)
    case artifact(AgentArtifactEvent)
    case sessionDiscovered(SessionDiscoveredParams)
    case questionPending(QuestionPendingParams)
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
        case "agent.run.receipt":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(ProofReceipt.self, from: paramsData)
            else { return .unknown(method: method) }
            return .runReceipt(p)
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
        case "agent.question.pending":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let p = try? JSONDecoder().decode(QuestionPendingParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .questionPending(p)
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

// MARK: - Conversation sync (agent.conversations.*)
//
// Wire-level Codable mirrors of the Go types in daemon/lancerd/conversation_store.go
// and daemon/lancerd/conversation_rpc.go for cross-device conversation sync. These are
// shared between the SSH JSON-RPC transport (DaemonChannel) and
// the E2E relay transport (E2ERelayBridge): conversation_rpc.go's server methods are
// called by both server.go's SSH switch and e2e_router.go's relay switch, so both
// transports return an identical payload shape by construction — one Swift type per
// RPC covers both, rather than a duplicate "Relay"-prefixed type per response (see
// this file's `error` field comment on each *Response type below).

/// Mirrors Go's `conversationSummary` (daemon/lancerd/conversation_store.go:199).
public struct ConversationSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let provider: String
    public let agentID: String
    public let hostID: String?
    public let hostName: String
    public let cwd: String
    public let model: String?
    public let budgetUSD: Double?
    public let state: String
    public let source: String
    public let createdAt: String
    public let updatedAt: String
    public let lastActivityAt: String
    public let lastSeq: Int
    public let archivedAt: String?
    /// Latest turn id from `agent.conversations.list` (additive; absent on
    /// older daemons / conversations with no turns).
    public let lastTurnID: String?
    /// Latest turn status from list (e.g. `running` / `completed` / `failed`).
    public let lastTurnStatus: String?

    public init(
        id: String, title: String, provider: String, agentID: String, hostID: String? = nil,
        hostName: String, cwd: String, model: String? = nil, budgetUSD: Double? = nil,
        state: String, source: String, createdAt: String, updatedAt: String,
        lastActivityAt: String, lastSeq: Int, archivedAt: String? = nil,
        lastTurnID: String? = nil, lastTurnStatus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.agentID = agentID
        self.hostID = hostID
        self.hostName = hostName
        self.cwd = cwd
        self.model = model
        self.budgetUSD = budgetUSD
        self.state = state
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.lastSeq = lastSeq
        self.archivedAt = archivedAt
        self.lastTurnID = lastTurnID
        self.lastTurnStatus = lastTurnStatus
    }
}

/// Structured attachment metadata for a conversation turn — transport-only
/// `hostPath` must never surface in UI (see attachment message design).
///
/// `contentDigest` is the lowercase hex SHA-256 of the exact bytes finalized by
/// `attachment.put` (camelCase wire field, locked). New outgoing attachments
/// must include a valid 64-hex digest; historical rows may omit it (decode
/// tolerates absence) but daemon dispatch fails closed until re-upload.
public struct ConversationAttachmentReference: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case image, file }

    public let id: String
    public let name: String
    public let mimeType: String?
    public let byteCount: Int
    public let kind: Kind
    public let hostPath: String
    public let previewCacheKey: String
    /// Lowercase hex SHA-256 from `attachment.put`. Optional for backward
    /// decode of historical turns; required nonempty for new outgoing appends.
    public let contentDigest: String?

    public init(
        id: String, name: String, mimeType: String?, byteCount: Int, kind: Kind,
        hostPath: String, previewCacheKey: String, contentDigest: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.kind = kind
        self.hostPath = hostPath
        self.previewCacheKey = previewCacheKey
        self.contentDigest = contentDigest
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mimeType, byteCount, kind, hostPath, previewCacheKey, contentDigest
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        byteCount = try c.decode(Int.self, forKey: .byteCount)
        kind = try c.decode(Kind.self, forKey: .kind)
        hostPath = try c.decode(String.self, forKey: .hostPath)
        previewCacheKey = try c.decode(String.self, forKey: .previewCacheKey)
        contentDigest = try c.decodeIfPresent(String.self, forKey: .contentDigest)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        try c.encode(byteCount, forKey: .byteCount)
        try c.encode(kind, forKey: .kind)
        try c.encode(hostPath, forKey: .hostPath)
        try c.encode(previewCacheKey, forKey: .previewCacheKey)
        try c.encodeIfPresent(contentDigest, forKey: .contentDigest)
    }
}

/// Validates the locked `contentDigest` wire shape (64 lowercase hex chars).
public enum AttachmentContentDigest {
    public static func isValid(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9") || (scalar >= "a" && scalar <= "f")
        }
    }
}

/// Mirrors Go's `conversationTurn` (daemon/lancerd/conversation_store.go:218).
public struct ConversationTurnEnvelope: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let conversationId: String
    public let ordinal: Int
    public let clientTurnId: String
    public let prompt: String
    public let runId: String
    public let provider: String
    public let vendorSessionId: String?
    public let status: String
    public let startedAt: String
    public let completedAt: String?
    public let errorMessage: String?
    public let attachments: [ConversationAttachmentReference]

    public init(
        id: String, conversationId: String, ordinal: Int, clientTurnId: String, prompt: String,
        runId: String, provider: String, vendorSessionId: String? = nil, status: String,
        startedAt: String, completedAt: String? = nil, errorMessage: String? = nil,
        attachments: [ConversationAttachmentReference] = []
    ) {
        self.id = id
        self.conversationId = conversationId
        self.ordinal = ordinal
        self.clientTurnId = clientTurnId
        self.prompt = prompt
        self.runId = runId
        self.provider = provider
        self.vendorSessionId = vendorSessionId
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, conversationId, ordinal, clientTurnId, prompt, runId, provider
        case vendorSessionId, status, startedAt, completedAt, errorMessage, attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        ordinal = try c.decode(Int.self, forKey: .ordinal)
        clientTurnId = try c.decode(String.self, forKey: .clientTurnId)
        prompt = try c.decode(String.self, forKey: .prompt)
        runId = try c.decode(String.self, forKey: .runId)
        provider = try c.decode(String.self, forKey: .provider)
        vendorSessionId = try c.decodeIfPresent(String.self, forKey: .vendorSessionId)
        status = try c.decode(String.self, forKey: .status)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        attachments = try c.decodeIfPresent([ConversationAttachmentReference].self, forKey: .attachments) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(conversationId, forKey: .conversationId)
        try c.encode(ordinal, forKey: .ordinal)
        try c.encode(clientTurnId, forKey: .clientTurnId)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(runId, forKey: .runId)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(vendorSessionId, forKey: .vendorSessionId)
        try c.encode(status, forKey: .status)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        if !attachments.isEmpty {
            try c.encode(attachments, forKey: .attachments)
        }
    }
}

/// Mirrors Go's `conversationEvent` (daemon/lancerd/conversation_store.go:233).
public struct ConversationEvent: Codable, Sendable, Hashable {
    public let conversationId: String
    public let seq: Int
    public let turnId: String?
    public let runId: String?
    public let kind: String
    public let role: String?
    public let stream: String?
    public let text: String?
    public let payloadJson: String?
    public let createdAt: String

    public init(
        conversationId: String, seq: Int, turnId: String? = nil, runId: String? = nil,
        kind: String, role: String? = nil, stream: String? = nil, text: String? = nil,
        payloadJson: String? = nil, createdAt: String
    ) {
        self.conversationId = conversationId
        self.seq = seq
        self.turnId = turnId
        self.runId = runId
        self.kind = kind
        self.role = role
        self.stream = stream
        self.text = text
        self.payloadJson = payloadJson
        self.createdAt = createdAt
    }
}

/// Mirrors Go's `conversationArtifact` (daemon/lancerd/conversation_store.go:246).
public struct ConversationArtifactEnvelope: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let conversationId: String
    public let turnId: String?
    public let runId: String
    public let kind: String
    public let title: String
    public let summary: String?
    public let payloadJson: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String, conversationId: String, turnId: String? = nil, runId: String, kind: String,
        title: String, summary: String? = nil, payloadJson: String, status: String,
        createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.turnId = turnId
        self.runId = runId
        self.kind = kind
        self.title = title
        self.summary = summary
        self.payloadJson = payloadJson
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Request for `agent.conversations.list` — mirrors Go's `conversationListRequest`
/// (daemon/lancerd/conversation_rpc.go:32). None of its fields are `,omitempty` on
/// the Go side, but all three are always sent by the phone regardless.
public struct ConversationListRequest: Codable, Sendable {
    public let limit: Int
    public let cursor: String
    public let includeArchived: Bool

    public init(limit: Int = 50, cursor: String = "", includeArchived: Bool = false) {
        self.limit = limit
        self.cursor = cursor
        self.includeArchived = includeArchived
    }
}

/// Response for `agent.conversations.list` — mirrors Go's `conversationListResult`
/// (daemon/lancerd/conversation_store.go:260).
public struct ConversationListResponse: Codable, Sendable {
    public let conversations: [ConversationSummary]
    public let nextCursor: String
    /// Populated only over the E2E relay path when the RPC fails —
    /// e2e_router.go's `conversationRelayPayload` flattens the (zero-value)
    /// result struct into a map and adds this key on failure. Always nil over
    /// SSH, where a JSON-RPC failure is a separate top-level `{"error":{...}}`
    /// envelope handled generically by `DaemonChannel.decodeResultObject`.
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case conversations, nextCursor, error
    }

    public init(conversations: [ConversationSummary] = [], nextCursor: String = "", error: String? = nil) {
        self.conversations = conversations
        self.nextCursor = nextCursor
        self.error = error
    }

    // Go's `[]conversationSummary` marshals a nil slice as JSON `null` (not
    // `[]`) when there are zero conversations — `decodeIfPresent` treats both
    // a missing key and an explicit null as "absent" and defaults to [],
    // where a plain `decode([ConversationSummary].self, ...)` would throw.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try c.decodeIfPresent([ConversationSummary].self, forKey: .conversations) ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor) ?? ""
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Request for `agent.conversations.fetch` — mirrors Go's `conversationFetchRequest`
/// (daemon/lancerd/conversation_rpc.go:39).
public struct ConversationFetchRequest: Codable, Sendable {
    public let conversationId: String
    public let sinceSeq: Int
    public let limit: Int

    public init(conversationId: String, sinceSeq: Int = 0, limit: Int = 500) {
        self.conversationId = conversationId
        self.sinceSeq = sinceSeq
        self.limit = limit
    }
}

/// Response for `agent.conversations.fetch` — mirrors Go's `conversationFetchResult`
/// (daemon/lancerd/conversation_store.go:265).
public struct ConversationFetchResponse: Codable, Sendable {
    public let conversation: ConversationSummary
    public let turns: [ConversationTurnEnvelope]
    public let events: [ConversationEvent]
    public let artifacts: [ConversationArtifactEnvelope]
    public let nextSeq: Int
    public let hasMore: Bool
    /// Relay-only failure signal — see `ConversationListResponse.error`.
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case conversation, turns, events, artifacts, nextSeq, hasMore, error
    }

    public init(
        conversation: ConversationSummary, turns: [ConversationTurnEnvelope] = [],
        events: [ConversationEvent] = [], artifacts: [ConversationArtifactEnvelope] = [],
        nextSeq: Int = 0, hasMore: Bool = false, error: String? = nil
    ) {
        self.conversation = conversation
        self.turns = turns
        self.events = events
        self.artifacts = artifacts
        self.nextSeq = nextSeq
        self.hasMore = hasMore
        self.error = error
    }

    // Same nil-slice-marshals-null defense as ConversationListResponse, for
    // all three list fields — turns/events/artifacts are each independently a
    // Go nil slice when a conversation has none of that kind yet.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversation = try c.decode(ConversationSummary.self, forKey: .conversation)
        turns = try c.decodeIfPresent([ConversationTurnEnvelope].self, forKey: .turns) ?? []
        events = try c.decodeIfPresent([ConversationEvent].self, forKey: .events) ?? []
        artifacts = try c.decodeIfPresent([ConversationArtifactEnvelope].self, forKey: .artifacts) ?? []
        nextSeq = try c.decodeIfPresent(Int.self, forKey: .nextSeq) ?? 0
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Request for `agent.conversations.append` — mirrors Go's `conversationAppendRequest`
/// (daemon/lancerd/conversation_store.go:172), the store-level type
/// conversation_rpc.go's `conversationsAppend` handler takes directly (there is no
/// separate RPC-level request type on the Go side).
public struct ConversationAppendRequest: Codable, Sendable {
    public let conversationId: String?
    public let baseSeq: Int
    public let clientTurnId: String
    public let agent: String?
    public let cwd: String?
    public let prompt: String
    public let model: String?
    public let budgetUSD: Double?
    /// When true on a new conversation, the daemon creates a managed git worktree and dispatches into it.
    public let useWorktree: Bool?
    /// Optional run contract echoed in the terminal proof receipt.
    public let contract: ProofReceipt.Contract?
    public let attachments: [ConversationAttachmentReference]?
    /// Per-dispatch "Full tools" opt-in (claudeCode only — mirrors Go's
    /// `conversationAppendRequest.FullTools`, conversation_store.go). Default
    /// `false` (omitted from the wire — the daemon's zero-value decode) keeps
    /// the fast `--strict-mcp-config` path; `true` re-enables normal MCP
    /// loading (XcodeBuildMCP/apple-docs/context7/…) for this one turn at the
    /// cost of first-token latency. See `FullToolsSelection` (Composer/) for
    /// the persisted picker state this is read from.
    public let fullTools: Bool?

    public init(
        conversationId: String? = nil, baseSeq: Int = 0, clientTurnId: String,
        agent: String? = nil, cwd: String? = nil, prompt: String, model: String? = nil,
        budgetUSD: Double? = nil, useWorktree: Bool? = nil,
        contract: ProofReceipt.Contract? = nil,
        attachments: [ConversationAttachmentReference]? = nil,
        fullTools: Bool? = nil
    ) {
        self.conversationId = conversationId
        self.baseSeq = baseSeq
        self.clientTurnId = clientTurnId
        self.agent = agent
        self.cwd = cwd
        self.prompt = prompt
        self.model = model
        self.budgetUSD = budgetUSD
        self.useWorktree = useWorktree
        self.contract = contract
        self.attachments = attachments
        self.fullTools = fullTools
    }

    enum CodingKeys: String, CodingKey {
        case conversationId, baseSeq, clientTurnId, agent, cwd, prompt, model, budgetUSD
        case useWorktree, contract, attachments, fullTools
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(conversationId, forKey: .conversationId)
        try c.encode(baseSeq, forKey: .baseSeq)
        try c.encode(clientTurnId, forKey: .clientTurnId)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encode(prompt, forKey: .prompt)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(budgetUSD, forKey: .budgetUSD)
        try c.encodeIfPresent(useWorktree, forKey: .useWorktree)
        try c.encodeIfPresent(contract, forKey: .contract)
        if let attachments, !attachments.isEmpty {
            try c.encode(attachments, forKey: .attachments)
        }
        if let fullTools, fullTools {
            try c.encode(fullTools, forKey: .fullTools)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId)
        baseSeq = try c.decodeIfPresent(Int.self, forKey: .baseSeq) ?? 0
        clientTurnId = try c.decode(String.self, forKey: .clientTurnId)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        prompt = try c.decode(String.self, forKey: .prompt)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        budgetUSD = try c.decodeIfPresent(Double.self, forKey: .budgetUSD)
        useWorktree = try c.decodeIfPresent(Bool.self, forKey: .useWorktree)
        contract = try c.decodeIfPresent(ProofReceipt.Contract.self, forKey: .contract)
        attachments = try c.decodeIfPresent([ConversationAttachmentReference].self, forKey: .attachments)
        fullTools = try c.decodeIfPresent(Bool.self, forKey: .fullTools)
    }
}

/// Response for `agent.conversations.append` — mirrors Go's `conversationAppendResponse`
/// (daemon/lancerd/conversation_rpc.go:49), the RPC-layer superset of the store's
/// `conversationAppendResult` (adds vendorSessionId/resumeMode/rule).
///
/// `clientTurnId` is optional for backward-compatible decode of older daemon
/// responses that omitted the echo. The relay bridge fail-closes (drops) results
/// that lack a matching echo so a late result for turn A cannot resolve wait B.
public struct ConversationAppendResponse: Codable, Sendable {
    public let status: String
    public let conversationId: String
    public let turnId: String?
    public let runId: String?
    public let vendorSessionId: String?
    public let cwd: String?
    public let baseSeq: Int
    public let nextSeq: Int
    public let resumeMode: String?
    public let message: String?
    public let rule: String?
    public let worktreePath: String?
    public let isolated: Bool?
    /// Echo of the request's `clientTurnId` (daemon ≥ correlated-append). Optional
    /// so legacy wire payloads still decode; bridge correlation treats missing
    /// as non-matching (fail-closed).
    public let clientTurnId: String?
    /// Relay-only failure signal — see `ConversationListResponse.error`.
    public let error: String?

    public init(
        status: String, conversationId: String, turnId: String? = nil, runId: String? = nil,
        vendorSessionId: String? = nil, cwd: String? = nil, baseSeq: Int = 0, nextSeq: Int = 0,
        resumeMode: String? = nil, message: String? = nil, rule: String? = nil,
        worktreePath: String? = nil, isolated: Bool? = nil, clientTurnId: String? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.conversationId = conversationId
        self.turnId = turnId
        self.runId = runId
        self.vendorSessionId = vendorSessionId
        self.cwd = cwd
        self.baseSeq = baseSeq
        self.nextSeq = nextSeq
        self.resumeMode = resumeMode
        self.message = message
        self.rule = rule
        self.worktreePath = worktreePath
        self.isolated = isolated
        self.clientTurnId = clientTurnId
        self.error = error
    }
}

/// Request for `agent.conversations.archive` — mirrors Go's `conversationArchiveRequest`
/// (daemon/lancerd/conversation_rpc.go:64).
public struct ConversationArchiveRequest: Codable, Sendable {
    public let conversationId: String
    public let archived: Bool

    public init(conversationId: String, archived: Bool) {
        self.conversationId = conversationId
        self.archived = archived
    }
}

/// Response for `agent.conversations.archive` — mirrors Go's `conversationArchiveResponse`
/// (daemon/lancerd/conversation_rpc.go:70).
public struct ConversationArchiveResponse: Codable, Sendable {
    public let ok: Bool
    public let conversationId: String
    public let lastSeq: Int
    /// Relay-only failure signal — see `ConversationListResponse.error`.
    public let error: String?

    public init(ok: Bool = false, conversationId: String = "", lastSeq: Int = 0, error: String? = nil) {
        self.ok = ok
        self.conversationId = conversationId
        self.lastSeq = lastSeq
        self.error = error
    }
}

/// Request for `agent.conversations.attachObservedSession` — mirrors Go's
/// `conversationAttachObservedSessionRequest` (daemon/lancerd/conversation_rpc.go:78).
public struct ConversationAttachObservedSessionRequest: Codable, Sendable {
    public let provider: String
    public let sessionId: String
    public let cwd: String

    public init(provider: String, sessionId: String, cwd: String) {
        self.provider = provider
        self.sessionId = sessionId
        self.cwd = cwd
    }
}

/// Response for `agent.conversations.attachObservedSession` — mirrors Go's
/// `conversationAttachObservedSessionResponse` (daemon/lancerd/conversation_rpc.go:86).
/// `error` is relay-only (see `ConversationListResponse.error`); the SSH
/// transport surfaces failures as a thrown JSON-RPC error instead.
public struct ConversationAttachObservedSessionResponse: Codable, Sendable {
    public let conversationId: String
    public let importedEvents: Int
    public let lastSeq: Int
    /// True when this session's provider+sessionId was already imported by an
    /// earlier call — `conversationId` still points at that original conversation.
    public let alreadyAttached: Bool
    /// Relay-only failure signal — see `ConversationListResponse.error`.
    public let error: String?

    public init(conversationId: String = "", importedEvents: Int = 0, lastSeq: Int = 0, alreadyAttached: Bool = false, error: String? = nil) {
        self.conversationId = conversationId
        self.importedEvents = importedEvents
        self.lastSeq = lastSeq
        self.alreadyAttached = alreadyAttached
        self.error = error
    }
}
