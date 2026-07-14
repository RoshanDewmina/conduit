#if os(iOS)
import Foundation
import LancerCore
import OSLog
import SSHTransport

/// Bridges E2E relay messages to the approval flow and dispatch.
/// When the relay is paired, approvals and dispatch go through E2E instead of SSH.
@MainActor
public final class E2ERelayBridge: ObservableObject {

    private nonisolated static let logger = Logger(subsystem: "dev.lancer.mobile", category: "E2ERelayBridge")
    private nonisolated static let defaultBoundedRPCWaitTimeout: Duration = .seconds(15)

    @Published public private(set) var isActive: Bool = false
    public let machineID: RelayMachineID
    private let relayClient: E2ERelayClient
    private let approvalRelay: ApprovalRelay
    private var messageTask: Task<Void, Never>?
    /// Wall-clock time of the most recent transition into `isActive` (session
    /// key derived AND peer_joined observed) — every fresh pairing AND every
    /// re-pair after a reconnect, not just the first ever. Used to gate the
    /// one-shot dispatch retry below: a send that times out shortly after a
    /// re-key event is the known race (2026-07-12), not a genuinely
    /// unresponsive host.
    private var lastReadyAt: Date?
    /// Window after a re-key event within which a `sendDispatch` timeout is
    /// assumed to be the first-send race rather than a real non-response, so
    /// it gets ONE automatic retry instead of surfacing to the user.
    nonisolated static let firstSendRetryWindow: TimeInterval = 5
    private var dispatchContinuation: CheckedContinuation<DispatchResult, Error>?
    private var continueContinuation: CheckedContinuation<DispatchResult, Error>?
    private var fsListContinuation: CheckedContinuation<RelayDirListing, Error>?
    private var fsReadContinuation: CheckedContinuation<RelayFileContent, Error>?
    private var commandsListContinuation: CheckedContinuation<[AgentCommand], Error>?
    private var sessionsListContinuation: CheckedContinuation<[ObservedSession], Error>?
    private var installedAgentsContinuation: CheckedContinuation<[String], Error>?
    private var sessionsTranscriptContinuation: CheckedContinuation<(messages: [SessionMessage], nextLine: Int, resetRequired: Bool), Error>?
    private var sessionContinueContinuation: CheckedContinuation<DispatchResult, Error>?
    /// Keyed by approvalID so concurrent in-flight decisions for different
    /// approvals don't collide (unlike the single-slot continuations above,
    /// which only ever have one dispatch/list/etc. in flight at a time).
    private var pendingDecisionAcks: [String: CheckedContinuation<Bool, Never>] = [:]
    private var statusQueryContinuation: CheckedContinuation<AgentStatusSnapshot, Error>?
    private var conversationsListContinuation: CheckedContinuation<ConversationListResponse, Error>?
    private var conversationsFetchContinuation: CheckedContinuation<ConversationFetchResponse, Error>?
    private var conversationsAppendContinuation: CheckedContinuation<ConversationAppendResponse, Error>?
    private var conversationsArchiveContinuation: CheckedContinuation<ConversationArchiveResponse, Error>?
    private var conversationsAttachObservedSessionContinuation: CheckedContinuation<ConversationAttachObservedSessionResponse, Error>?
    private var repoTurnDiffContinuation: CheckedContinuation<Data, Error>?
    private var repoSessionDiffContinuation: CheckedContinuation<Data, Error>?
    private var repoFileDiffContinuation: CheckedContinuation<Data, Error>?
    private var repoTreeContinuation: CheckedContinuation<Data, Error>?
    private var repoFileContinuation: CheckedContinuation<Data, Error>?
    private var attachmentPutContinuation: CheckedContinuation<AttachmentPutResult, Error>?
#if DEBUG
    var boundedRPCWaitTimeoutOverride: Duration?
#endif

    private var boundedRPCWaitTimeout: Duration {
#if DEBUG
        boundedRPCWaitTimeoutOverride ?? Self.defaultBoundedRPCWaitTimeout
#else
        Self.defaultBoundedRPCWaitTimeout
#endif
    }

    public init(relayClient: E2ERelayClient, approvalRelay: ApprovalRelay, machineID: RelayMachineID) {
        self.relayClient = relayClient
        self.approvalRelay = approvalRelay
        self.machineID = machineID
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
                let wasActive = self.isActive
                self.isActive = (state == .paired)
                if self.isActive {
                    self.lastReadyAt = Date()
                }
                // A machine coming back online may have decisions sitting in
                // ApprovalRelay's queue that failed to send while it was down
                // (the queue's SSH-attach drain never fires for a relay-only
                // pairing) — retry them now instead of leaving them stuck
                // until the daemon's 120s timeout auto-denies them.
                if self.isActive && !wasActive {
                    await self.approvalRelay.machineBridgeReconnected(self.machineID, bridge: self)
                }
            }
        }
    }

    public func stop() {
        messageTask?.cancel()
        messageTask = nil
        isActive = false
        for (_, continuation) in pendingDecisionAcks {
            continuation.resume(returning: false)
        }
        pendingDecisionAcks.removeAll()
    }

    /// Send an approval decision through the E2E relay and wait for the
    /// daemon's explicit ack. Returns true only once the daemon confirms it
    /// actually processed the decision — a successful *outgoing* send is not
    /// proof of delivery (the frame can be dropped, fail to decrypt, or land
    /// on an approval the daemon already resolved via timeout), and treating
    /// it as such is exactly how decisions used to vanish silently with no
    /// fallback ever triggering.
    @discardableResult
    public func sendDecision(approvalID: String, decision: String, editedToolInput: String?, contentHash: String? = nil) async -> Bool {
        guard isActive else {
            Self.logger.warning("sendDecision: bridge INACTIVE (machine=\(self.machineID.uuidString, privacy: .public)) — dropping approvalID=\(approvalID, privacy: .public)")
            return false
        }
        Self.logger.info("sendDecision: approvalID=\(approvalID, privacy: .public) decision=\(decision, privacy: .public) connection=\(self.relayClient.connectionState.description, privacy: .public) pairing=\(self.relayClient.pairingState.description, privacy: .public)")
        // Send the raw DecisionData as the payload (NOT the E2ERelayMessage enum):
        // send() already wraps it as {type, payload}, and the daemon handler
        // unmarshals the typed params directly from payload. Passing the enum
        // double-nests it as {"approvalResponse":{…}}, which the daemon can't read —
        // mirror sendDispatch, which passes its raw DispatchParams struct.
        let decisionData = E2ERelayMessage.DecisionData(
            approvalID: approvalID, decision: decision, editedToolInput: editedToolInput, contentHash: contentHash
        )
        do {
            try await relayClient.send(type: "approvalResponse", payload: decisionData)
        } catch {
            Self.logger.error("sendDecision: relay send FAILED for approvalID=\(approvalID, privacy: .public): \(error.localizedDescription, privacy: .public) connection=\(self.relayClient.connectionState.description, privacy: .public)")
            return false
        }

        // A stale in-flight wait for the same approvalID (e.g. a fast double-tap)
        // must be resumed before we replace it — CheckedContinuation traps if
        // dropped unresumed.
        pendingDecisionAcks[approvalID]?.resume(returning: false)
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.pendingDecisionAcks[approvalID]?.resume(returning: false)
            self.pendingDecisionAcks[approvalID] = nil
        }
        defer { timeoutTask.cancel() }
        let acked = await withCheckedContinuation { c in
            self.pendingDecisionAcks[approvalID] = c
        }
        Self.logger.info("sendDecision: ack for approvalID=\(approvalID, privacy: .public) → \(acked ? "ok" : "FAILED (daemon nack or 5s ack timeout)", privacy: .public)")
        return acked
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

    /// Register a Live Activity (ActivityKit) push or push-to-start token with the
    /// relay-paired daemon so it can forward it to push-backend on the phone's
    /// behalf (the app never holds APPROVAL_RELAY_SECRET) — the relay-only
    /// equivalent of `DaemonChannel.registerActivityToken` (SSH), which doesn't
    /// exist for a relay-only pairing. Mirrors `registerDevice` above: fire-and-
    /// forget, no ack expected. The daemon-side `activityTokenRegister` relay
    /// handler (mirroring e2e_router.go's `deviceRegister` case) is a required
    /// follow-up to complete the round trip to push-backend.
    @discardableResult
    public func registerActivityToken(
        sessionID: String, activityToken: String, isPushToStart: Bool, pushBackendURL: String
    ) async -> Bool {
        guard isActive else { return false }
        do {
            try await relayClient.send(type: "activityTokenRegister", payload: E2ERelayMessage.ActivityTokenRegisterData(
                sessionId: sessionID, activityToken: activityToken, isPushToStart: isPushToStart, pushBackendURL: pushBackendURL
            ))
            return true
        } catch {
            return false
        }
    }

    /// Dispatch an agent run through the E2E relay.
    /// Returns the dispatch result, or nil if the relay is not active.
    ///
    /// If the FIRST attempt times out shortly after a re-key event
    /// (`isFirstSendRace`), retries exactly once — the narrowest fix for the
    /// 2026-07-12 race where a dispatch sent in the window between
    /// socket-connected and session-key derivation/peer ack is lost, surfacing
    /// as "machine didn't respond" even though a manual Retry always recovers
    /// (re-sending the same dispatch envelope is already idempotent — Retry
    /// proves it). Deliberately not a general retry queue: only this one
    /// bounded, narrowly-gated retry.
    public func sendDispatch(
        agent: String, cwd: String, prompt: String, budgetUSD: Double?, model: String?,
        contract: ProofReceipt.Contract? = nil
    ) async throws -> DispatchResult {
        guard isActive else {
            throw E2EError.notPaired
        }
        let attemptedAt = Date()
        do {
            return try await sendDispatchOnce(agent: agent, cwd: cwd, prompt: prompt, budgetUSD: budgetUSD, model: model, contract: contract)
        } catch E2EError.timedOut where Self.isFirstSendRace(attemptedAt: attemptedAt, lastReadyAt: lastReadyAt) {
            Self.logger.warning("sendDispatch: first attempt timed out within \(Self.firstSendRetryWindow, privacy: .public)s of a re-key event (machine=\(self.machineID.uuidString, privacy: .public)) — retrying once")
            return try await sendDispatchOnce(agent: agent, cwd: cwd, prompt: prompt, budgetUSD: budgetUSD, model: model, contract: contract)
        }
    }

    private func sendDispatchOnce(
        agent: String, cwd: String, prompt: String, budgetUSD: Double?, model: String?,
        contract: ProofReceipt.Contract?
    ) async throws -> DispatchResult {
        let params = E2ERelayMessage.DispatchParams(
            agent: agent, cwd: cwd, prompt: prompt,
            model: model, budgetUSD: budgetUSD ?? 0, contract: contract
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

    /// Pure readiness-gate check (unit-testable without a live relay): was
    /// `attemptedAt` within `firstSendRetryWindow` of the most recent re-key
    /// event? A `nil` lastReadyAt (never paired this bridge instance) is never
    /// a race — there's no re-key to blame.
    nonisolated static func isFirstSendRace(attemptedAt: Date, lastReadyAt: Date?) -> Bool {
        guard let lastReadyAt else { return false }
        let delta = attemptedAt.timeIntervalSince(lastReadyAt)
        return delta >= 0 && delta < firstSendRetryWindow
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

    /// Queries the daemon's on-demand agent status over the relay — mirrors
    /// `DaemonChannel.fetchAgentStatus`'s SSH `agent.status` RPC. Unlike
    /// `agentStatus`'s periodic push (`StatusData` / `lancerE2EStatusUpdate`),
    /// this is a request/response round trip so a relay-only pairing (no SSH
    /// `DaemonChannel`) can support the same on-demand refresh `CommandGateway`
    /// needs for Siri's "how many agents are running" query.
    public func sendStatusQuery(homeDir: String?) async throws -> AgentStatusSnapshot {
        guard isActive else { throw E2EError.notPaired }
        struct StatusQueryParams: Codable, Sendable { let homeDir: String? }
        try await relayClient.send(type: "agentStatusQuery", payload: StatusQueryParams(homeDir: homeDir))
        // A stale in-flight query must be resumed before we replace it — mirrors
        // sendDispatch's supersede-then-bound-wait pattern.
        statusQueryContinuation?.resume(throwing: E2EError.superseded)
        statusQueryContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.statusQueryContinuation?.resume(throwing: E2EError.timedOut)
            self.statusQueryContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.statusQueryContinuation = c
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

    /// Uploads one attachment chunk through the E2E relay (`attachmentPut` →
    /// `attachmentPutResult`). Mirrors `DaemonChannel.putAttachment` / SSH
    /// `attachment.put`. Chunks must stay ≤256KB pre-encryption.
    public func relayPutAttachment(
        conversationId: String?,
        name: String,
        totalBytes: Int,
        seq: Int,
        dataBase64: String,
        done: Bool
    ) async throws -> AttachmentPutResult {
        guard isActive else { throw E2EError.notPaired }
        struct PutParams: Codable, Sendable {
            let conversationId: String?
            let name: String
            let totalBytes: Int
            let seq: Int
            let dataBase64: String
            let done: Bool
        }
        try await relayClient.send(
            type: "attachmentPut",
            payload: PutParams(
                conversationId: conversationId,
                name: name,
                totalBytes: totalBytes,
                seq: seq,
                dataBase64: dataBase64,
                done: done
            )
        )
        attachmentPutContinuation?.resume(throwing: E2EError.superseded)
        attachmentPutContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.attachmentPutContinuation?.resume(throwing: E2EError.timedOut)
            self.attachmentPutContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.attachmentPutContinuation = c
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
        fsListContinuation?.resume(throwing: E2EError.superseded)
        fsListContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.fsListContinuation?.resume(throwing: E2EError.timedOut)
            self.fsListContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.fsListContinuation = c
        }
    }

    /// Reads a host file's content through the E2E relay. Mirrors `relayListDir`:
    /// sends `agentFsRead`, awaits `fsReadResult`. The daemon's `fsRead` is
    /// home-confined, size-capped, and rejects binary content, all fail-closed —
    /// surfaced here as a thrown `RelayFSError.host`.
    public func relayReadFile(_ path: String) async throws -> RelayFileContent {
        guard isActive else { throw E2EError.notPaired }
        struct ReadParams: Codable, Sendable { let path: String }
        try await relayClient.send(type: "agentFsRead", payload: ReadParams(path: path))
        fsReadContinuation?.resume(throwing: E2EError.superseded)
        fsReadContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.fsReadContinuation?.resume(throwing: E2EError.timedOut)
            self.fsReadContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.fsReadContinuation = c
        }
    }

    /// Lists the agent's slash-commands for a workspace through the E2E relay.
    /// Mirrors `relayListDir`: sends `agentCommandsList`, awaits `commandsListResult`.
    /// Returns [] on failure so the composer autocomplete degrades gracefully.
    public func relayListCommands(cwd: String, vendor: String) async throws -> [AgentCommand] {
        guard isActive else { throw E2EError.notPaired }
        struct CmdParams: Codable, Sendable { let cwd: String; let vendor: String }
        try await relayClient.send(type: "agentCommandsList", payload: CmdParams(cwd: cwd, vendor: vendor))
        commandsListContinuation?.resume(throwing: E2EError.superseded)
        commandsListContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.commandsListContinuation?.resume(throwing: E2EError.timedOut)
            self.commandsListContinuation = nil
        }
        defer { timeout.cancel() }
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
        sessionsListContinuation?.resume(throwing: E2EError.superseded)
        sessionsListContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.sessionsListContinuation?.resume(throwing: E2EError.timedOut)
            self.sessionsListContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.sessionsListContinuation = c
        }
    }

    /// Vendor ids whose CLI is installed on the relay-paired host.
    public func relayInstalledAgents() async throws -> [String] {
        guard isActive else { throw E2EError.notPaired }
        struct Empty: Codable, Sendable {}
        try await relayClient.send(type: "agentAgentsInstalled", payload: Empty())
        installedAgentsContinuation?.resume(throwing: E2EError.superseded)
        installedAgentsContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.installedAgentsContinuation?.resume(throwing: E2EError.timedOut)
            self.installedAgentsContinuation = nil
        }
        defer { timeout.cancel() }
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

    /// Sends a follow-up prompt into an observed (not Lancer-dispatched) session on
    /// the relay-paired host, targeting it by its exact vendor + sessionId + cwd
    /// (mirrors `DaemonChannel.continueObservedSession` over SSH). The daemon
    /// re-passes the same policy/budget gates as the SSH path via
    /// `dispatcher.resumeObservedSession` and, once allowed, launches a fresh
    /// process under a new runId — output then streams under that runId like any
    /// other dispatch. Mirrors `relayFetchTranscript`'s bounded-wait shape.
    public func relayContinueObservedSession(vendor: String, sessionId: String, cwd: String, prompt: String) async throws -> DispatchResult {
        guard isActive else { throw E2EError.notPaired }
        struct SessionContinueParams: Codable, Sendable { let vendor: String; let sessionId: String; let cwd: String; let prompt: String }
        try await relayClient.send(
            type: "agentSessionContinue",
            payload: SessionContinueParams(vendor: vendor, sessionId: sessionId, cwd: cwd, prompt: prompt)
        )
        // Bound the wait: if the `sessionContinueResult` reply never arrives the
        // follow-up would otherwise spin forever (no terminal state).
        sessionContinueContinuation?.resume(throwing: E2EError.superseded)
        sessionContinueContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.sessionContinueContinuation?.resume(throwing: E2EError.timedOut)
            self.sessionContinueContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.sessionContinueContinuation = c
        }
    }

    // MARK: - Conversations (agent.conversations.*, cross-device sync)

    /// Lists Lancer-owned conversations from the relay-paired host's ledger, most-
    /// recently-active first. Mirrors `relayFetchTranscript`'s bounded-wait +
    /// supersede shape (mirrors `sendDispatch`).
    public func relayListConversations(_ request: ConversationListRequest = ConversationListRequest()) async throws -> ConversationListResponse {
        guard isActive else { throw E2EError.notPaired }
        try await relayClient.send(type: "agentConversationsList", payload: request)
        // A stale in-flight list must be resumed before we replace it — mirrors
        // sendDispatch's supersede-then-bound-wait pattern.
        conversationsListContinuation?.resume(throwing: E2EError.superseded)
        conversationsListContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.conversationsListContinuation?.resume(throwing: E2EError.timedOut)
            self.conversationsListContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.conversationsListContinuation = c
        }
    }

    /// Fetches one conversation's turns/artifacts plus events strictly after
    /// `request.sinceSeq` from the relay-paired host, for incremental paging
    /// through the append-only event log.
    public func relayFetchConversation(_ request: ConversationFetchRequest) async throws -> ConversationFetchResponse {
        guard isActive else { throw E2EError.notPaired }
        try await relayClient.send(type: "agentConversationsFetch", payload: request)
        conversationsFetchContinuation?.resume(throwing: E2EError.superseded)
        conversationsFetchContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.conversationsFetchContinuation?.resume(throwing: E2EError.timedOut)
            self.conversationsFetchContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.conversationsFetchContinuation = c
        }
    }

    /// Starts a new conversation (`request.conversationId == nil`) or appends a
    /// follow-up turn to an existing one, through the relay-paired host. The
    /// daemon is the single writer for executable turns — this is the host-
    /// mediated append the cross-device sync design requires. A 20s timeout
    /// (matching `sendDispatch`, not the 15s used by the read-only conversation
    /// RPCs above) since this can launch a vendor CLI process on the host.
    public func relayAppendConversation(_ request: ConversationAppendRequest) async throws -> ConversationAppendResponse {
        guard isActive else { throw E2EError.notPaired }
        try await relayClient.send(type: "agentConversationsAppend", payload: request)
        conversationsAppendContinuation?.resume(throwing: E2EError.superseded)
        conversationsAppendContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.conversationsAppendContinuation?.resume(throwing: E2EError.timedOut)
            self.conversationsAppendContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.conversationsAppendContinuation = c
        }
    }

    /// Archives or unarchives a conversation on the relay-paired host.
    public func relayArchiveConversation(_ request: ConversationArchiveRequest) async throws -> ConversationArchiveResponse {
        guard isActive else { throw E2EError.notPaired }
        try await relayClient.send(type: "agentConversationsArchive", payload: request)
        conversationsArchiveContinuation?.resume(throwing: E2EError.superseded)
        conversationsArchiveContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.conversationsArchiveContinuation?.resume(throwing: E2EError.timedOut)
            self.conversationsArchiveContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.conversationsArchiveContinuation = c
        }
    }

    /// Converts a terminal-originated Observed Session into a Lancer conversation
    /// on the relay-paired host by importing its full on-disk transcript into the
    /// host ledger as one completed turn (idempotent by provider+sessionId).
    public func relayAttachObservedSession(_ request: ConversationAttachObservedSessionRequest) async throws -> ConversationAttachObservedSessionResponse {
        guard isActive else { throw E2EError.notPaired }
        try await relayClient.send(type: "agentConversationsAttachObservedSession", payload: request)
        conversationsAttachObservedSessionContinuation?.resume(throwing: E2EError.superseded)
        conversationsAttachObservedSessionContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.conversationsAttachObservedSessionContinuation?.resume(throwing: E2EError.timedOut)
            self.conversationsAttachObservedSessionContinuation = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.conversationsAttachObservedSessionContinuation = c
        }
    }

    /// Read-only review RPC: per-turn repo diff summary for one conversation.
    public func relayRepoTurnDiff<Result: Decodable & Sendable>(
        conversationID: String,
        turnID: String,
        as type: Result.Type
    ) async throws -> Result {
        guard isActive else { throw E2EError.notPaired }
        struct Params: Codable, Sendable { let conversationId: String; let turnId: String }
        try await relayClient.send(
            type: "repoTurnDiff",
            payload: Params(conversationId: conversationID, turnId: turnID)
        )
        repoTurnDiffContinuation?.resume(throwing: E2EError.superseded)
        repoTurnDiffContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.repoTurnDiffContinuation?.resume(throwing: E2EError.timedOut)
            self.repoTurnDiffContinuation = nil
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { c in
            self.repoTurnDiffContinuation = c
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    /// Read-only review RPC: whole-session repo diff summary for one conversation.
    public func relayRepoSessionDiff<Result: Decodable & Sendable>(
        conversationID: String,
        as type: Result.Type
    ) async throws -> Result {
        guard isActive else { throw E2EError.notPaired }
        struct Params: Codable, Sendable { let conversationId: String }
        try await relayClient.send(
            type: "repoSessionDiff",
            payload: Params(conversationId: conversationID)
        )
        repoSessionDiffContinuation?.resume(throwing: E2EError.superseded)
        repoSessionDiffContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.repoSessionDiffContinuation?.resume(throwing: E2EError.timedOut)
            self.repoSessionDiffContinuation = nil
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { c in
            self.repoSessionDiffContinuation = c
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    /// Read-only review RPC: unified diff hunks for a file, scoped to an optional turn.
    public func relayRepoFileDiff<Result: Decodable & Sendable>(
        conversationID: String,
        path: String,
        turnID: String?,
        as type: Result.Type
    ) async throws -> Result {
        guard isActive else { throw E2EError.notPaired }
        struct Params: Codable, Sendable { let conversationId: String; let path: String; let turnId: String? }
        try await relayClient.send(
            type: "repoFileDiff",
            payload: Params(conversationId: conversationID, path: path, turnId: turnID)
        )
        repoFileDiffContinuation?.resume(throwing: E2EError.superseded)
        repoFileDiffContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.repoFileDiffContinuation?.resume(throwing: E2EError.timedOut)
            self.repoFileDiffContinuation = nil
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { c in
            self.repoFileDiffContinuation = c
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    /// Read-only review RPC: one directory listing under the conversation's cwd.
    public func relayRepoTree<Result: Decodable & Sendable>(
        conversationID: String,
        path: String,
        as type: Result.Type
    ) async throws -> Result {
        guard isActive else { throw E2EError.notPaired }
        struct Params: Codable, Sendable { let conversationId: String; let path: String }
        try await relayClient.send(
            type: "repoTree",
            payload: Params(conversationId: conversationID, path: path)
        )
        repoTreeContinuation?.resume(throwing: E2EError.superseded)
        repoTreeContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.repoTreeContinuation?.resume(throwing: E2EError.timedOut)
            self.repoTreeContinuation = nil
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { c in
            self.repoTreeContinuation = c
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    /// Read-only review RPC: file-content preview under the conversation's cwd.
    public func relayRepoFile<Result: Decodable & Sendable>(
        conversationID: String,
        path: String,
        maxBytes: Int,
        as type: Result.Type
    ) async throws -> Result {
        guard isActive else { throw E2EError.notPaired }
        struct Params: Codable, Sendable { let conversationId: String; let path: String; let maxBytes: Int }
        try await relayClient.send(
            type: "repoFile",
            payload: Params(conversationId: conversationID, path: path, maxBytes: maxBytes)
        )
        repoFileContinuation?.resume(throwing: E2EError.superseded)
        repoFileContinuation = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.boundedRPCWaitTimeout ?? Self.defaultBoundedRPCWaitTimeout)
            guard let self, !Task.isCancelled else { return }
            self.repoFileContinuation?.resume(throwing: E2EError.timedOut)
            self.repoFileContinuation = nil
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { c in
            self.repoFileContinuation = c
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    /// Send a question answer through the E2E relay to the paired daemon.
    /// Fire-and-forget — the daemon resolves the pending question via
    /// `questionStore.resolve` on receipt of a `"questionAnswer"` relay message.
    /// Mirrors `sendDecision` but without the ack wait: questions carry no risk
    /// decision, so a dropped answer is an inconvenience, not a security event.
    @discardableResult
    public func sendQuestionAnswer(_ answer: QuestionAnswerParams) async -> Bool {
        guard isActive else { return false }
        do {
            try await relayClient.send(type: "questionAnswer", payload: answer)
            return true
        } catch {
            Self.logger.error("sendQuestionAnswer: relay send FAILED for questionId=\(answer.questionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Private

    private func relayEnvelopePayloadObject(from data: Data) -> Any? {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return envelope["payload"]
    }

    private func relayEnvelopePayloadData(from data: Data) -> Data? {
        guard let payloadObject = relayEnvelopePayloadObject(from: data),
              JSONSerialization.isValidJSONObject(payloadObject),
              let payloadData = try? JSONSerialization.data(withJSONObject: payloadObject)
        else {
            return nil
        }
        return payloadData
    }

    private func relayEnvelopePayloadError(from data: Data) -> String? {
        guard let payload = relayEnvelopePayloadObject(from: data) as? [String: Any],
              let error = payload["error"] as? String,
              !error.isEmpty else {
            return nil
        }
        return error
    }

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
            ) else {
                Self.logger.error("handleRelayMessage: approvalPending decode failed for machine=\(self.machineID.uuidString, privacy: .public)")
                return
            }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EApprovalReceived"),
                object: nil,
                userInfo: ["approvalData": env.payload, "machineID": self.machineID]
            )

        case "agentStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.StatusData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EStatusUpdate"),
                object: nil,
                userInfo: ["status": env.payload, "machineID": self.machineID]
            )

        case "loopUpdate":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.LoopData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ELoopUpdate"),
                object: nil,
                userInfo: ["loopData": env.payload, "machineID": self.machineID]
            )

        case "approvalResponseAck":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.DecisionAckData>.self, from: message.payload
            ) else { return }
            pendingDecisionAcks[env.payload.approvalID]?.resume(returning: env.payload.ok)
            pendingDecisionAcks[env.payload.approvalID] = nil

        case "approvalResolved":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.ResolvedData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EApprovalResolved"),
                object: nil,
                userInfo: [
                    "approvalID": env.payload.approvalID,
                    "decision": env.payload.decision,
                    "machineID": self.machineID,
                ]
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
                userInfo: ["params": env.payload, "machineID": self.machineID]
            )

        case "agentRunStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RunStatusParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ERunStatus"),
                object: nil,
                userInfo: ["params": env.payload, "machineID": self.machineID]
            )

        case "runStatus":
            // Ephemeral live-status pill (G3). Never ledger-persisted.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<LiveRunStatusParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ELiveRunStatus"),
                object: nil,
                userInfo: ["params": env.payload, "machineID": self.machineID]
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
                userInfo: ["params": env.payload, "machineID": self.machineID]
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

        case "fsReadResult":
            // Same envelope unwrap as fsListResult. The daemon includes an
            // `error` field when fsRead fails closed (path escape, directory,
            // binary content, or a read error) — surface it as a thrown error
            // so the preview shows an error state instead of garbage.
            let readEnvelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RelayFileContent>.self, from: message.payload
            )
            if let file = readEnvelope?.payload {
                if let err = file.error, !err.isEmpty {
                    fsReadContinuation?.resume(throwing: RelayFSError.host(err))
                } else {
                    fsReadContinuation?.resume(returning: file)
                }
            } else {
                fsReadContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            fsReadContinuation = nil

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

        case "sessionContinueResult":
            let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
            if let result = envelope?.payload {
                sessionContinueContinuation?.resume(returning: result)
            } else {
                sessionContinueContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            sessionContinueContinuation = nil

        case "deviceRegistered":
            // The daemon's reply to `deviceRegister` (see `registerDevice` below),
            // carrying the per-session capability token `postDecisionToBackend`
            // needs for its `Authorization: Bearer` header. Without capturing this,
            // a relay-only pairing (no SSH channel — the only other place this
            // token is ever learned) has no working fallback when the direct
            // `approvalResponse` send doesn't get acked in time, and a decision
            // silently parks in the redelivery queue until the daemon's 120s
            // fail-closed timeout has already denied it.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.DeviceRegisteredData>.self, from: message.payload
            ) else { return }
            approvalRelay.setRelayToken(env.payload.relayToken)

        case "agentStatusQueryResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AgentStatusSnapshot>.self, from: message.payload
            )
            if let snap = envelope?.payload {
                statusQueryContinuation?.resume(returning: snap)
            } else {
                statusQueryContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            statusQueryContinuation = nil

        case "agentArtifact":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AgentArtifactEvent>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EArtifact"),
                object: nil,
                userInfo: ["params": env.payload, "machineID": self.machineID]
            )

        case "runReceipt":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ProofReceipt>.self, from: message.payload
            ) else {
                Self.logger.error("handleRelayMessage: runReceipt decode failed for machine=\(self.machineID.uuidString, privacy: .public)")
                return
            }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2ERunReceipt"),
                object: nil,
                userInfo: ["receipt": env.payload, "machineID": self.machineID]
            )

        case "agentConversationsListResult":
            // Same envelope unwrap as fsListResult. e2e_router.go's
            // conversationRelayPayload adds an "error" key into the flattened
            // payload on failure — surface it as a thrown error, same as fsList.
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ConversationListResponse>.self, from: message.payload
            )
            if let response = envelope?.payload {
                if let err = response.error, !err.isEmpty {
                    conversationsListContinuation?.resume(throwing: RelayConversationError.host(err))
                } else {
                    conversationsListContinuation?.resume(returning: response)
                }
            } else {
                conversationsListContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            conversationsListContinuation = nil

        case "agentConversationsFetchResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ConversationFetchResponse>.self, from: message.payload
            )
            if let response = envelope?.payload {
                if let err = response.error, !err.isEmpty {
                    conversationsFetchContinuation?.resume(throwing: RelayConversationError.host(err))
                } else {
                    conversationsFetchContinuation?.resume(returning: response)
                }
            } else {
                conversationsFetchContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            conversationsFetchContinuation = nil

        case "agentConversationsAppendResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ConversationAppendResponse>.self, from: message.payload
            )
            if let response = envelope?.payload {
                if let err = response.error, !err.isEmpty {
                    conversationsAppendContinuation?.resume(throwing: RelayConversationError.host(err))
                } else {
                    conversationsAppendContinuation?.resume(returning: response)
                }
            } else {
                conversationsAppendContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            conversationsAppendContinuation = nil

        case "agentConversationsArchiveResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ConversationArchiveResponse>.self, from: message.payload
            )
            if let response = envelope?.payload {
                if let err = response.error, !err.isEmpty {
                    conversationsArchiveContinuation?.resume(throwing: RelayConversationError.host(err))
                } else {
                    conversationsArchiveContinuation?.resume(returning: response)
                }
            } else {
                conversationsArchiveContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            conversationsArchiveContinuation = nil

        case "repoTurnDiffResult":
            if let error = relayEnvelopePayloadError(from: message.payload) {
                repoTurnDiffContinuation?.resume(throwing: RelayRepoError.host(error))
            } else if let payload = relayEnvelopePayloadData(from: message.payload) {
                repoTurnDiffContinuation?.resume(returning: payload)
            } else {
                repoTurnDiffContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            repoTurnDiffContinuation = nil

        case "repoSessionDiffResult":
            if let error = relayEnvelopePayloadError(from: message.payload) {
                repoSessionDiffContinuation?.resume(throwing: RelayRepoError.host(error))
            } else if let payload = relayEnvelopePayloadData(from: message.payload) {
                repoSessionDiffContinuation?.resume(returning: payload)
            } else {
                repoSessionDiffContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            repoSessionDiffContinuation = nil

        case "repoFileDiffResult":
            if let error = relayEnvelopePayloadError(from: message.payload) {
                repoFileDiffContinuation?.resume(throwing: RelayRepoError.host(error))
            } else if let payload = relayEnvelopePayloadData(from: message.payload) {
                repoFileDiffContinuation?.resume(returning: payload)
            } else {
                repoFileDiffContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            repoFileDiffContinuation = nil

        case "repoTreeResult":
            if let error = relayEnvelopePayloadError(from: message.payload) {
                repoTreeContinuation?.resume(throwing: RelayRepoError.host(error))
            } else if let payload = relayEnvelopePayloadData(from: message.payload) {
                repoTreeContinuation?.resume(returning: payload)
            } else {
                repoTreeContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            repoTreeContinuation = nil

        case "repoFileResult":
            if let error = relayEnvelopePayloadError(from: message.payload) {
                repoFileContinuation?.resume(throwing: RelayRepoError.host(error))
            } else if let payload = relayEnvelopePayloadData(from: message.payload) {
                repoFileContinuation?.resume(returning: payload)
            } else {
                repoFileContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            repoFileContinuation = nil

        case "agentQuestion":
            // Wire type is "agentQuestion" (matching `e2e_router.go`'s
            // `sendQuestion`, NOT a "questionPending" guess) with a
            // relay-specific payload shape — see `E2ERelayMessage.QuestionData`'s
            // doc comment for why this isn't `QuestionPendingParams`.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.QuestionData>.self, from: message.payload
            ) else {
                Self.logger.error("handleRelayMessage: agentQuestion decode failed for machine=\(self.machineID.uuidString, privacy: .public)")
                return
            }
            NotificationCenter.default.post(
                name: Notification.Name("lancerE2EQuestionPending"),
                object: nil,
                userInfo: ["questionData": env.payload, "machineID": self.machineID]
            )

        case "agentConversationsAttachObservedSessionResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<ConversationAttachObservedSessionResponse>.self, from: message.payload
            )
            if let response = envelope?.payload {
                if let err = response.error, !err.isEmpty {
                    conversationsAttachObservedSessionContinuation?.resume(throwing: RelayConversationError.host(err))
                } else {
                    conversationsAttachObservedSessionContinuation?.resume(returning: response)
                }
            } else {
                conversationsAttachObservedSessionContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            conversationsAttachObservedSessionContinuation = nil

        case "attachmentPutResult":
            let envelope = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AttachmentPutResult>.self, from: message.payload
            )
            if let result = envelope?.payload {
                if let err = result.error, !err.isEmpty {
                    attachmentPutContinuation?.resume(throwing: RelayFSError.host(err))
                } else {
                    attachmentPutContinuation?.resume(returning: result)
                }
            } else {
                attachmentPutContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            attachmentPutContinuation = nil

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

/// A host-side conversation-ledger error reported by the daemon over the relay
/// (e.g. "conversation store unavailable", a not-found `conversationId`, or an
/// `attachObservedSession` transcript-load failure) — mirrors `RelayFSError`.
/// Note: a stale `baseSeq` is NOT this error — it comes back as a normal
/// `ConversationAppendResponse` with `status == "conflict"`, not a thrown error.
public enum RelayConversationError: Error, LocalizedError {
    case host(String)

    public var errorDescription: String? {
        switch self {
        case .host(let message): return message
        }
    }
}

/// A host-side repository-review error reported by the daemon over the relay.
public enum RelayRepoError: Error, LocalizedError {
    case host(String)

    public var errorDescription: String? {
        switch self {
        case .host(let message): return message
        }
    }
}

#endif

import Foundation

/// Ephemeral live-status ticker from lancerd (`agent.run.liveStatus` → relay
/// `runStatus`). Drives the chat status pill only — never a ledger row.
public struct LiveRunStatusParams: Codable, Sendable, Hashable {
    public let runId: String
    public let state: String
    public let toolName: String?
    public let target: String?
    public let at: String?

    public init(
        runId: String,
        state: String,
        toolName: String? = nil,
        target: String? = nil,
        at: String? = nil
    ) {
        self.runId = runId
        self.state = state
        self.toolName = toolName
        self.target = target
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case runId, state, toolName, target, at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId = try c.decodeIfPresent(String.self, forKey: .runId) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        at = try c.decodeIfPresent(String.self, forKey: .at)
    }
}
