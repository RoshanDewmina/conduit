#if os(iOS)
import Foundation
import LancerCore
import PersistenceKit

/// Transport-agnostic view of the `agent.conversations.*` RPCs, constructed
/// by the caller from whichever channel actually reaches the host right now
/// (a connected SSH slot's `DaemonChannel`, or a paired machine's
/// `E2ERelayBridge`) — mirrors the existing `RelayRunControl` pattern
/// (AppRoot.swift) that already unifies SSH/relay for run control instead of
/// making this coordinator aware of either transport concretely.
public struct ConversationTransport: Sendable {
    public let append: @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse
    public let fetch: @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse
    public let archive: @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse

    public init(
        append: @escaping @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse,
        fetch: @escaping @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse,
        archive: @escaping @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse
    ) {
        self.append = append
        self.fetch = fetch
        self.archive = archive
    }
}

/// Where a conversation stands for the sync status banner (ChatHistoryView /
/// NewChatTabView / sidebar rows) — a superset of `ChatConversation.SyncState`
/// that also covers states the UI cares about but the mirror row doesn't
/// persist (host offline, stale mirror, etc.).
public enum ConversationSyncUIState: Sendable, Equatable {
    /// No banner — mirror matches the host's last known state.
    case synced
    /// An append/fetch is in flight.
    case syncing
    /// The host could not be reached; cached history is shown, sending is
    /// disabled or kept as an explicit local draft (never auto-sent).
    case hostOffline
    /// The mirror hasn't been refreshed from the host in a while and may be
    /// behind another device's writes — a pull-to-refresh hint, not a hard error.
    case cloudStale
    /// The host rejected an append because `baseSeq` was stale — another
    /// device (or turn) moved the conversation first. Resolved by refetching.
    case conflict
    /// The last turn started without an exact vendor-session match (fell
    /// back to "continue latest in cwd") — still usable, but the UI should
    /// disclose that resume may not be exact.
    case degradedResume
    /// Another device's turn is currently running on this conversation.
    case streamingElsewhere
}

/// Orchestrates host-mediated conversation turns (`agent.conversations.append`)
/// and keeps the local GRDB mirror (Task 6) consistent with the host ledger's
/// responses, so UI code never has to hand-roll the append→mirror→publish
/// sequence itself. One instance is shared for the app's lifetime; sync state
/// is tracked per conversation ID.
///
/// This is the ONLY place that should call `ConversationTransport.append`/
/// `.fetch` for UI-driven turns — see the build handoff's non-negotiable #3
/// ("host mediates all appends") and #5 ("no silent offline execution").
public actor ConversationSyncCoordinator {
    private let chatRepo: ChatConversationRepository
    private var syncStates: [String: ConversationSyncUIState] = [:]
    private var continuations: [String: [UUID: AsyncStream<ConversationSyncUIState>.Continuation]] = [:]

    public init(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    /// The outcome of a single append call — deliberately mirrors
    /// `ChatDispatchOutcome`'s started/blocked shape so AppRoot's existing
    /// call sites need minimal changes to adopt this.
    public enum TurnOutcome: Sendable {
        case started(TurnStarted)
        case blocked(String)
    }

    public struct TurnStarted: Sendable {
        public let conversationID: String
        public let turnID: String?
        public let runID: String
        public let cwd: String
        public let baseSeqForNextTurn: Int
        public let resumeMode: String?
        public let vendorSessionID: String?
        public let worktreePath: String?
        public let isolated: Bool
    }

    // MARK: - Public API

    /// Starts a brand-new conversation. On success, creates the local mirror
    /// row (`syncState: .synced`) so History/sidebar immediately show it
    /// without waiting for a separate fetch.
    public func startConversation(
        agent: String, cwd: String, prompt: String, model: String?, budgetUSD: Double?,
        contract: ProofReceipt.Contract? = nil,
        hostName: String, hostID: String?, clientTurnID: String,
        transport: ConversationTransport
    ) async -> TurnOutcome {
        await append(
            ConversationAppendRequest(
                conversationId: nil, baseSeq: 0, clientTurnId: clientTurnID,
                agent: agent, cwd: cwd, prompt: prompt, model: model, budgetUSD: budgetUSD,
                contract: contract
            ),
            hostName: hostName, hostID: hostID, transport: transport
        )
    }

    /// Appends a follow-up turn to an existing conversation. `baseSeq` must be
    /// the caller's last-known `nextSeq` — a stale value is exactly what
    /// produces a host-reported conflict, which this method surfaces as
    /// `.conflict` sync state rather than silently retrying.
    public func continueConversation(
        conversationID: String, baseSeq: Int, prompt: String, clientTurnID: String,
        agent: String? = nil, model: String? = nil, budgetUSD: Double? = nil,
        contract: ProofReceipt.Contract? = nil,
        hostName: String, hostID: String?,
        transport: ConversationTransport
    ) async -> TurnOutcome {
        await append(
            ConversationAppendRequest(
                conversationId: conversationID, baseSeq: baseSeq, clientTurnId: clientTurnID,
                agent: agent, cwd: nil, prompt: prompt, model: model, budgetUSD: budgetUSD,
                contract: contract
            ),
            hostName: hostName, hostID: hostID, transport: transport
        )
    }

    /// Pulls everything after the mirror's last known seq and merges it in —
    /// used on thread-open, pull-to-refresh, and conflict recovery ("Refresh"
    /// in the conflict banner). Returns the merged conversation's fresh
    /// `lastHostSeq` so the caller can use it as the next `baseSeq`.
    @discardableResult
    public func refreshConversation(
        conversationID: String, transport: ConversationTransport
    ) async throws -> Int {
        publish(.syncing, for: conversationID)
        let local = try await chatRepo.conversation(id: conversationID)
        do {
            let response = try await transport.fetch(
                ConversationFetchRequest(conversationId: conversationID, sinceSeq: local?.lastHostSeq ?? 0, limit: 2000)
            )
            try await mergeFetchResponse(response)
            publish(.synced, for: conversationID)
            return response.nextSeq
        } catch {
            publish(.hostOffline, for: conversationID)
            throw error
        }
    }

    /// A live stream of sync-state changes for one conversation, for the
    /// banner view to observe. The current state (or `.synced` if never
    /// touched) is emitted immediately so a late subscriber isn't stuck on
    /// stale UI until the next transition.
    public func observeSyncState(conversationID: String) -> AsyncStream<ConversationSyncUIState> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[conversationID, default: [:]][token] = continuation
            continuation.yield(syncStates[conversationID] ?? .synced)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token, for: conversationID) }
            }
        }
    }

    public func currentSyncState(_ conversationID: String) -> ConversationSyncUIState {
        syncStates[conversationID] ?? .synced
    }

    // MARK: - Internals

    private func append(
        _ request: ConversationAppendRequest, hostName: String, hostID: String?, transport: ConversationTransport
    ) async -> TurnOutcome {
        let conversationIDForBanner = request.conversationId
        if let id = conversationIDForBanner { publish(.syncing, for: id) }

        let response: ConversationAppendResponse
        do {
            response = try await Self.appendWithRetry(request, transport: transport)
        } catch {
            if let id = conversationIDForBanner { publish(.hostOffline, for: id) }
            return .blocked(Self.transportErrorMessage(error))
        }

        switch response.status {
        case "started":
            await persistStartedTurn(request: request, response: response, hostName: hostName, hostID: hostID)
            let uiState: ConversationSyncUIState = response.resumeMode == "latestInCwdFallback" ? .degradedResume : .synced
            publish(uiState, for: response.conversationId)
            return .started(TurnStarted(
                conversationID: response.conversationId,
                turnID: response.turnId,
                runID: response.runId ?? "",
                cwd: response.cwd ?? request.cwd ?? "",
                baseSeqForNextTurn: response.nextSeq,
                resumeMode: response.resumeMode,
                vendorSessionID: response.vendorSessionId,
                worktreePath: response.worktreePath,
                isolated: response.isolated ?? false
            ))
        case "conflict":
            publish(.conflict, for: response.conversationId)
            try? await chatRepo.updateSyncState(conversationID: response.conversationId, state: .conflict)
            return .blocked(response.message ?? "This conversation changed on another device.")
        case "denied":
            publish(.synced, for: response.conversationId)
            return .blocked("Blocked by policy\(response.rule.map { " (\($0))" } ?? "").")
        case "needsApproval":
            publish(.synced, for: response.conversationId)
            return .blocked("Awaiting your approval — check the Inbox.")
        case "budgetExceeded":
            publish(.synced, for: response.conversationId)
            return .blocked(response.message ?? "Daily budget cap reached.")
        default:
            publish(.synced, for: response.conversationId)
            return .blocked(response.message ?? "Couldn't start the run.")
        }
    }

    private func persistStartedTurn(
        request: ConversationAppendRequest, response: ConversationAppendResponse, hostName: String, hostID: String?
    ) async {
        let isNew = request.conversationId == nil
        let existing = isNew ? nil : try? await chatRepo.conversation(id: response.conversationId)
        // A follow-up legitimately omits `agent` (inherited from the
        // conversation server-side) — fall back to what's already mirrored
        // locally rather than overwriting a known provider with "".
        let agentID = request.agent ?? existing?.agentID ?? ""
        let conversation = ChatConversation(
            id: response.conversationId,
            title: existing?.title ?? Self.titleFromPrompt(request.prompt),
            agentID: agentID,
            vendor: agentID,
            hostName: hostName,
            hostID: hostID,
            cwd: response.cwd ?? request.cwd ?? existing?.cwd ?? "",
            model: request.model ?? existing?.model,
            budgetUSD: request.budgetUSD ?? existing?.budgetUSD,
            status: .active,
            sourceHostID: hostID,
            sourceHostName: hostName
        )
        _ = try? await chatRepo.upsertConversationMirror(conversation, lastHostSeq: response.nextSeq, syncState: .synced)

        guard let runID = response.runId else { return }
        let turnID = response.turnId ?? runID
        let existingTurns = (try? await chatRepo.turns(conversationID: response.conversationId)) ?? []
        let ordinal = existingTurns.count
        let turn = LancerCore.ChatTurn(
            id: turnID, conversationID: response.conversationId, ordinal: ordinal,
            prompt: request.prompt, runID: runID, transportKind: "sync",
            clientTurnID: request.clientTurnId
        )
        _ = try? await chatRepo.upsertTurnMirror(
            turn, vendorSessionID: response.vendorSessionId, hostSeqStart: response.baseSeq, hostSeqEnd: nil
        )
    }

    private func mergeFetchResponse(_ response: ConversationFetchResponse) async throws {
        let existing = try await chatRepo.conversation(id: response.conversation.id)
        let conversation = Self.mapSummary(response.conversation, fallback: existing)
        _ = try await chatRepo.upsertConversationMirror(conversation, lastHostSeq: response.nextSeq, syncState: .synced)

        let events = response.events.map(Self.mapEvent)
        try await chatRepo.appendEventsMirror(conversationID: response.conversation.id, events: events)

        // `ConversationTurnEnvelope` carries no rolled-up reply text (only the
        // ledger's raw per-seq events do — see appendRunOutput in
        // conversation_store.go) — assemble each turn's `assistantText` from
        // ITS OWN mirrored events (this fetch's plus whatever was already
        // stored) before writing the turn row, so a device that never
        // streamed a turn live still renders its content in ChatHistoryView.
        let allEvents = (try? await chatRepo.events(conversationID: response.conversation.id, sinceSeq: 0, limit: 5000)) ?? []
        let eventsByTurn = Dictionary(grouping: allEvents, by: { $0.turnID })
        for turnEnvelope in response.turns {
            var turn = Self.mapTurn(turnEnvelope, conversationID: response.conversation.id)
            turn.assistantText = Self.assistantText(from: eventsByTurn[turn.id] ?? [])
            _ = try await chatRepo.upsertTurnMirror(
                turn, vendorSessionID: turnEnvelope.vendorSessionId, hostSeqStart: nil, hostSeqEnd: nil
            )
        }

        // A terminal `lancer.proof/v0` receipt is stored on the host ONLY as a
        // `conversation_events` row (kind "receipt" — see appendRunReceipt in
        // conversation_store.go); it is never itself a conversation_artifacts
        // row there. Live delivery (AppRoot's lancerE2ERunReceipt notification
        // handler) materializes it into a `chat_artifacts` row via
        // `upsertReceipt` the moment it arrives — but a receipt that lands
        // while this device is disconnected only ever reaches it as one of
        // `response.events` here, and ReceiptCardView reads exclusively from
        // `chat_artifacts`. Without this, a reconnect-and-refresh would mirror
        // the event into `chat_events` (above) but the receipt card would
        // never appear. Mirror the live path: materialize any receipt-kind
        // event into the SAME `chat_artifacts` row `upsertReceipt` would have
        // written live. Runs after the turns loop above so the `chat_turns`
        // row `upsertReceipt` keys off of (by run_id) already exists.
        // `upsertReceipt` upserts by the stable id `"receipt:\(runID)"`, so
        // re-running this merge for the same receipt (e.g. a re-fetch that
        // re-delivers already-seen events) is idempotent — no duplicate rows.
        var materializedReceipt = false
        for event in response.events where event.kind == "receipt" {
            guard let runID = event.runId, let payloadJSON = event.payloadJson else { continue }
            if (try? await chatRepo.upsertReceipt(runID: runID, payloadJSON: payloadJSON)) != nil {
                materializedReceipt = true
            }
        }
        // Same notification the live path posts after `upsertReceipt`
        // (AppRoot's lancerE2ERunReceipt handler) — lets an already-open
        // thread's artifact list pick up a receipt that arrived while this
        // device was disconnected, without requiring a manual re-open.
        if materializedReceipt {
            NotificationCenter.default.post(
                name: .lancerChatArtifactPersisted,
                object: nil,
                userInfo: ["conversationID": response.conversation.id]
            )
        }
    }

    /// Concatenates a turn's `kind == "output"` events (the ledger's mirror of
    /// the run's raw stdout/stderr stream — see `appendRunOutput`) in seq
    /// order, the same text `RunOutputStore` accumulates live for an active run.
    private static func assistantText(from events: [ChatEvent]) -> String {
        events
            .filter { $0.kind == "output" }
            .sorted { $0.seq < $1.seq }
            .compactMap(\.text)
            .joined()
    }

    private func publish(_ state: ConversationSyncUIState, for conversationID: String) {
        syncStates[conversationID] = state
        for continuation in continuations[conversationID, default: [:]].values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(_ token: UUID, for conversationID: String) {
        continuations[conversationID]?.removeValue(forKey: token)
        if continuations[conversationID]?.isEmpty == true {
            continuations.removeValue(forKey: conversationID)
        }
    }

    private static func transportErrorMessage(_ error: Error) -> String {
        "Couldn't reach the host: \(error.localizedDescription)"
    }

    /// A single failed `append` used to be treated as "host offline" outright,
    /// which turned a momentary relay hiccup (reconnect in progress, a dropped
    /// frame) into a hard "couldn't continue, open from a connected host"
    /// dead end — even while the machine was actively streaming the previous
    /// turn's output (found live 2026-07-03: a follow-up on a "WORKING" run
    /// failed this way). Retry a couple of times with a short backoff before
    /// concluding the host is actually unreachable.
    private static func appendWithRetry(
        _ request: ConversationAppendRequest, transport: ConversationTransport, attempts: Int = 3
    ) async throws -> ConversationAppendResponse {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await transport.append(request)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError ?? CancellationError()
    }

    private static func titleFromPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : (firstLine.isEmpty ? "New Chat" : firstLine)
    }

    // MARK: - Wire → local mapping (ConversationSummary/Turn/Event use Go's
    // RFC3339 string dates; the mirror repository deals only in Foundation
    // types, so this coordinator — not PersistenceKit — owns the conversion.)

    // `ISO8601DateFormatter` predates `Sendable`; it's only ever read here
    // (never mutated after creation), matching the pattern in AccountClient.swift.
    nonisolated(unsafe) private static let dateFormatter = ISO8601DateFormatter()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return dateFormatter.date(from: s)
    }

    private static func mapSummary(_ summary: ConversationSummary, fallback: ChatConversation?) -> ChatConversation {
        ChatConversation(
            id: summary.id,
            title: summary.title,
            agentID: summary.provider,
            vendor: summary.provider,
            hostName: summary.hostName,
            hostID: summary.hostID,
            cwd: summary.cwd,
            model: summary.model,
            budgetUSD: summary.budgetUSD,
            status: ChatConversation.Status(rawValue: summary.state) ?? .active,
            createdAt: parseDate(summary.createdAt) ?? fallback?.createdAt ?? .now,
            updatedAt: parseDate(summary.updatedAt) ?? .now,
            lastActivityAt: parseDate(summary.lastActivityAt) ?? .now,
            sourceHostID: summary.hostID,
            sourceHostName: summary.hostName,
            archivedAt: parseDate(summary.archivedAt)
        )
    }

    private static func mapTurn(_ turn: ConversationTurnEnvelope, conversationID: String) -> LancerCore.ChatTurn {
        LancerCore.ChatTurn(
            id: turn.id, conversationID: conversationID, ordinal: turn.ordinal,
            prompt: turn.prompt, runID: turn.runId, transportKind: "sync",
            status: LancerCore.ChatTurn.Status(rawValue: turn.status) ?? .running,
            errorMessage: turn.errorMessage,
            createdAt: parseDate(turn.startedAt) ?? .now,
            completedAt: parseDate(turn.completedAt),
            clientTurnID: turn.clientTurnId,
            vendorSessionID: turn.vendorSessionId
        )
    }

    private static func mapEvent(_ event: ConversationEvent) -> ChatEvent {
        ChatEvent(
            conversationID: event.conversationId, seq: event.seq,
            turnID: event.turnId, runID: event.runId, kind: event.kind,
            role: event.role, stream: event.stream, text: event.text,
            payloadJSON: event.payloadJson, createdAt: parseDate(event.createdAt) ?? .now
        )
    }
}
#endif
