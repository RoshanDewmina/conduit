#if os(iOS)
import Foundation
import LancerCore
import SSHTransport

/// Bridges E2E relay messages to the approval flow and dispatch.
/// When the relay is paired, approvals and dispatch go through E2E instead of SSH.
@MainActor
public final class E2ERelayBridge: ObservableObject {

    @Published public private(set) var isActive: Bool = false
    private let relayClient: E2ERelayClient
    private let approvalRelay: ApprovalRelay
    private var messageTask: Task<Void, Never>?
    private var dispatchContinuation: CheckedContinuation<DispatchResult, Error>?
    private var continueContinuation: CheckedContinuation<DispatchResult, Error>?
    private var fsListContinuation: CheckedContinuation<RelayDirListing, Error>?
    private var commandsListContinuation: CheckedContinuation<[AgentCommand], Error>?
    private var sessionsListContinuation: CheckedContinuation<[ObservedSession], Error>?
    private var installedAgentsContinuation: CheckedContinuation<[String], Error>?
    private var sessionsTranscriptContinuation: CheckedContinuation<(messages: [SessionMessage], nextLine: Int, resetRequired: Bool), Error>?

    public init(relayClient: E2ERelayClient, approvalRelay: ApprovalRelay) {
        self.relayClient = relayClient
        self.approvalRelay = approvalRelay
    }

    /// Start bridging E2E relay messages to the approval flow
    public func start() {
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.relayClient.messages {
                await self.handleRelayMessage(message)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await state in self.relayClient.$pairingState.values {
                self.isActive = (state == .paired)
            }
        }
    }

    public func stop() {
        messageTask?.cancel()
        messageTask = nil
        isActive = false
    }

    /// Send an approval decision through the E2E relay.
    /// Returns true if the message was sent, false if the relay is not active.
    @discardableResult
    public func sendDecision(approvalID: String, decision: String, editedToolInput: String?) async -> Bool {
        guard isActive else { return false }
        // Send the raw DecisionData as the payload (NOT the E2ERelayMessage enum):
        // send() already wraps it as {type, payload}, and the daemon handler
        // unmarshals the typed params directly from payload. Passing the enum
        // double-nests it as {"approvalResponse":{…}}, which the daemon can't read —
        // mirror sendDispatch, which passes its raw DispatchParams struct.
        let decisionData = E2ERelayMessage.DecisionData(
            approvalID: approvalID, decision: decision, editedToolInput: editedToolInput
        )
        do {
            try await relayClient.send(type: "approvalResponse", payload: decisionData)
            return true
        } catch {
            return false
        }
    }

    /// Register this device's APNs token with the relay-paired daemon so that
    /// approvals can be delivered by push when the app is CLOSED. The SSH path
    /// registers via the lancer.device.register(.apns) RPCs; the relay path had no
    /// equivalent, so the daemon never learned the token and push never fired on a
    /// relay-only device. The daemon handles this in e2e_router.go `deviceRegister`.
    @discardableResult
    public func registerDevice(apnsToken: String, sessionID: String, pushBackendURL: String) async -> Bool {
        guard isActive else { return false }
        struct DeviceRegisterParams: Codable {
            let sessionId: String
            let apnsToken: String
            let pushBackendURL: String
        }
        do {
            try await relayClient.send(type: "deviceRegister", payload: DeviceRegisterParams(
                sessionId: sessionID, apnsToken: apnsToken, pushBackendURL: pushBackendURL
            ))
            return true
        } catch {
            return false
        }
    }

    /// Dispatch an agent run through the E2E relay.
    /// Returns the dispatch result, or nil if the relay is not active.
    public func sendDispatch(agent: String, cwd: String, prompt: String, budgetUSD: Double?, model: String?) async throws -> DispatchResult {
        guard isActive else {
            throw E2EError.notPaired
        }
        let params = E2ERelayMessage.DispatchParams(
            agent: agent, cwd: cwd, prompt: prompt,
            model: model, budgetUSD: budgetUSD ?? 0
        )
        try await relayClient.send(type: "agentDispatch", payload: params)
        // The dispatch reached the daemon, but if its `dispatchResult` reply never
        // comes back (relay receive path stalled — e.g. after a host reconnect) the
        // await would hang forever and the Send button would look dead. Bound the
        // wait so a missing reply surfaces a clear error instead of a silent hang.
        // A newer dispatch supersedes an in-flight one (avoids a leaked continuation).
        dispatchContinuation?.resume(throwing: E2EError.superseded)
        dispatchContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.dispatchContinuation?.resume(throwing: E2EError.timedOut)
            self.dispatchContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.dispatchContinuation = c
        }
    }

    /// Sends a run-control action (stop / pause / resume) for a dispatched relay
    /// run. Fire-and-forget: the daemon applies it via dispatcher.cancel/pause/resume
    /// and the resulting status streams back over agent.run.status. Returns false
    /// only if the relay isn't active.
    @discardableResult
    public func sendRunControl(runId: String, action: String) async -> Bool {
        guard isActive else { return false }
        struct ControlParams: Codable, Sendable { let runId: String; let action: String }
        do {
            try await relayClient.send(
                type: "agentRunControl",
                payload: ControlParams(runId: runId, action: action)
            )
            return true
        } catch {
            return false
        }
    }

    /// Sends a follow-up prompt to continue a relay run. The daemon re-launches the
    /// vendor CLI under a NEW runId (re-passing policy + budget) and replies with
    /// `runContinueResult`; output then streams under the new runId. Returns the
    /// result (with the new runId) so the caller can attach the continued turn.
    public func sendRunContinue(
        runId: String, prompt: String,
        agent: String? = nil, cwd: String? = nil, model: String? = nil, budgetUSD: Double? = nil
    ) async throws -> DispatchResult {
        guard isActive else { throw E2EError.notPaired }
        // Optional fallback so a reopened chat continues even after the daemon forgot
        // the run (process ended / daemon restarted): the daemon reconstructs the
        // launch from this persisted-conversation context.
        struct ContinueParams: Codable, Sendable {
            let runId: String; let prompt: String
            let agent: String?; let cwd: String?; let model: String?; let budgetUSD: Double?
        }
        try await relayClient.send(
            type: "agentRunContinue",
            payload: ContinueParams(runId: runId, prompt: prompt, agent: agent, cwd: cwd, model: model, budgetUSD: budgetUSD)
        )
        // Bound the wait on the daemon's reply so a dropped `runContinueResult` shows
        // a clear error instead of a silently dead follow-up (same as sendDispatch).
        continueContinuation?.resume(throwing: E2EError.superseded)
        continueContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.continueContinuation?.resume(throwing: E2EError.timedOut)
            self.continueContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.continueContinuation = c
        }
    }

    /// Lists a host directory through the E2E relay. Mirrors `sendDispatch`:
    /// sends `agentFsList` with the requested path and awaits the daemon's
    /// `fsListResult`. The daemon's `fsList` is home-confined and fails closed,
    /// so an out-of-home path comes back as an `error` field, surfaced here as a
    /// thrown `RelayFSError.host`.
    public func relayListDir(_ path: String) async throws -> RelayDirListing {
        guard isActive else { throw E2EError.notPaired }
        struct ListParams: Codable, Sendable { let path: String }
        try await relayClient.send(type: "agentFsList", payload: ListParams(path: path))
        return try await withCheckedThrowingContinuation { c in
            self.fsListContinuation = c
        }
    }

    /// Lists the agent's slash-commands for a workspace through the E2E relay.
    /// Mirrors `relayListDir`: sends `agentCommandsList`, awaits `commandsListResult`.
    /// Returns [] on failure so the composer autocomplete degrades gracefully.
    public func relayListCommands(cwd: String, vendor: String) async throws -> [AgentCommand] {
        guard isActive else { throw E2EError.notPaired }
        struct CmdParams: Codable, Sendable { let cwd: String; let vendor: String }
        try await relayClient.send(type: "agentCommandsList", payload: CmdParams(cwd: cwd, vendor: vendor))
        return try await withCheckedThrowingContinuation { c in
            self.commandsListContinuation = c
        }
    }

    /// Lists Claude Code (and other vendor) sessions on the relay-paired host.
    /// Mirrors `relayListCommands`: sends `agentSessionsList`, awaits `sessionsListResult`.
    /// Read-only watch; Phase 1 has no send/stop control over these.
    public func relayListSessions() async throws -> [ObservedSession] {
        guard isActive else { throw E2EError.notPaired }
        struct ListParams: Codable, Sendable {}
        try await relayClient.send(type: "agentSessionsList", payload: ListParams())
        return try await withCheckedThrowingContinuation { c in
            self.sessionsListContinuation = c
        }
    }

    /// Vendor ids whose CLI is installed on the relay-paired host.
    public func relayInstalledAgents() async throws -> [String] {
        guard isActive else { throw E2EError.notPaired }
        struct Empty: Codable, Sendable {}
        try await relayClient.send(type: "agentAgentsInstalled", payload: Empty())
        return try await withCheckedThrowingContinuation { c in
            self.installedAgentsContinuation = c
        }
    }

    /// Fetches transcript turns for an observed session on the relay-paired host,
    /// starting at `sinceLine`. Mirrors `relayListCommands`: sends `agentSessionsTranscript`,
    /// awaits `sessionsTranscriptResult`.
    public func relayFetchTranscript(sessionId: String, sinceLine: Int) async throws -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool) {
        guard isActive else { throw E2EError.notPaired }
        struct TranscriptParams: Codable, Sendable { let sessionId: String; let sinceLine: Int }
        try await relayClient.send(
            type: "agentSessionsTranscript",
            payload: TranscriptParams(sessionId: sessionId, sinceLine: sinceLine)
        )
        // Bound the wait: if the `sessionsTranscriptResult` reply never arrives the
        // observed-session view would otherwise spin forever (no terminal state).
        sessionsTranscriptContinuation?.resume(throwing: E2EError.superseded)
        sessionsTranscriptContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.sessionsTranscriptContinuation?.resume(throwing: E2EError.timedOut)
            self.sessionsTranscriptContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.sessionsTranscriptContinuation = c
        }
    }

    // MARK: - Private

    private func handleRelayMessage(_ message: E2ERelayClient.ReceivedMessage) async {
        switch message.type {
        // message.payload is the FULL inner plaintext {type, payload:{…}} — every
        // case must unwrap RelayInnerEnvelope<T> to reach the typed params (same as
        // agentRunOutput/dispatchResult). Decoding the struct directly from the full
        // envelope silently fails (try? → nil), which is what dropped every relay
        // approval/status before this fix.
        case "approvalPending":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.ApprovalData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EApprovalReceived"),
                object: nil,
                userInfo: ["approvalData": env.payload]
            )

        case "agentStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.StatusData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EStatusUpdate"),
                object: nil,
                userInfo: ["status": env.payload]
            )

        case "loopUpdate":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.LoopData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ELoopUpdate"),
                object: nil,
                userInfo: ["loopData": env.payload]
            )

        case "dispatchResult":
            let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
            if let result = envelope?.payload {
                dispatchContinuation?.resume(returning: result)
                dispatchContinuation = nil
            } else {
                dispatchContinuation?.resume(throwing: E2EError.decryptFailed)
                dispatchContinuation = nil
            }

        case "runContinueResult":
            let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
            if let result = envelope?.payload {
                continueContinuation?.resume(returning: result)
            } else {
                continueContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            continueContinuation = nil

        case "agentRunOutput":
            // message.payload is the full inner plaintext {type, payload:{…}}, so
            // unwrap the envelope to the typed params — same pattern as dispatchResult.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RunOutputParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ERunOutput"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        case "agentRunStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RunStatusParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ERunStatus"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        case "agentToolStart":
            // The agent ran a tool (Bash/Edit/Read…) — surfaces as a terminal block
            // card in the transcript. Mirrors the run-output/status fan-out.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ToolStartParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EToolStart"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        case "commandsListResult":
            struct CommandsPayload: Codable { let commands: [AgentCommand] }
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<CommandsPayload>.self, from: message.payload
            )
            commandsListContinuation?.resume(returning: envelope?.payload.commands ?? [])
            commandsListContinuation = nil

        case "fsListResult":
            // Same envelope unwrap as dispatchResult. The daemon includes an
            // `error` field when fsList fails closed (e.g. path outside home);
            // surface it as a thrown error so the browser shows an error state.
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RelayDirListing>.self, from: message.payload
            )
            if let listing = envelope?.payload {
                if let err = listing.error, !err.isEmpty {
                    fsListContinuation?.resume(throwing: RelayFSError.host(err))
                } else {
                    fsListContinuation?.resume(returning: listing)
                }
            } else {
                fsListContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            fsListContinuation = nil

        case "sessionsListResult":
            struct SessionsPayload: Codable { let sessions: [ObservedSession] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try? decoder.decode(
                E2ERelayMessage.RelayInnerEnvelope<SessionsPayload>.self, from: message.payload
            )
            sessionsListContinuation?.resume(returning: envelope?.payload.sessions ?? [])
            sessionsListContinuation = nil

        case "agentsInstalledResult":
            struct AgentsPayload: Codable { let agents: [String] }
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AgentsPayload>.self, from: message.payload
            )
            installedAgentsContinuation?.resume(returning: envelope?.payload.agents ?? [])
            installedAgentsContinuation = nil

        case "sessionsTranscriptResult":
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try? decoder.decode(
                E2ERelayMessage.RelayInnerEnvelope<SessionsTranscriptResult>.self, from: message.payload
            )
            if let result = envelope?.payload {
                sessionsTranscriptContinuation?.resume(returning: (result.messages, result.nextLine, result.resetRequired))
            } else {
                sessionsTranscriptContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            sessionsTranscriptContinuation = nil

        case "agentArtifact":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AgentArtifactEvent>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EArtifact"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        default:
            break
        }
    }
}

/// A directory listing returned by the daemon's `fsList` over the relay. Keys
/// mirror the Go `fsListResult` JSON (`path`, `parent`, `entries[].name/.isDir`),
/// plus an optional `error` the router sets when the home-confined `fsList` fails.
public struct RelayDirListing: Codable, Sendable {
    public let path: String
    public let parent: String?
    public let entries: [RelayDirEntry]
    public let error: String?

    public init(path: String, parent: String?, entries: [RelayDirEntry], error: String? = nil) {
        self.path = path
        self.parent = parent
        self.entries = entries
        self.error = error
    }
}

public struct RelayDirEntry: Codable, Sendable, Identifiable, Hashable {
    public let name: String
    public let isDir: Bool

    public var id: String { name }

    public init(name: String, isDir: Bool) {
        self.name = name
        self.isDir = isDir
    }
}

/// A host-side filesystem error reported by the daemon over the relay (e.g. a
/// path outside the home directory, or a stat/readdir failure).
public enum RelayFSError: Error, LocalizedError {
    case host(String)

    public var errorDescription: String? {
        switch self {
        case .host(let message): return message
        }
    }
}
#endif
