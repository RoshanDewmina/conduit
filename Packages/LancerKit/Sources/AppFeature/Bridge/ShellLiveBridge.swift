#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit
import SessionFeature

/// M3: the one piece of "engine" glue code connecting the New Chat composer's
/// send action to the real host-mediated conversation pipeline —
/// `RelayFleetStore` (M2's paired machines) → `E2ERelayBridge` (the wire
/// transport) → `ConversationSyncCoordinator` (append/fetch orchestration +
/// local GRDB mirror). Everything else in `Chat/` is display only; this type
/// owns the send → poll-until-terminal → publish state machine.
///
/// Vendor comes from `DispatchVendorSelection` (New Chat agent picker). Polls
/// `ChatConversationRepository.turnByRunID` after each host refresh and
/// publishes partial `assistantText` while the turn is still `.running`
/// (daemon ledger already streams stdout chunks; this bridge was the missing
/// mid-run publisher — 2026-07-11 dogfood).
@MainActor
@Observable
public final class ShellLiveBridge {
    public enum SendState: Equatable {
        case idle
        /// Observed-session adopt succeeded but host returned zero transcript
        /// messages — composer stays usable; UI shows a no-history placeholder.
        case adoptedNoHistory
        /// Run in flight, no assistant text yet.
        case working
        /// Run in flight with accumulating `assistantText` from host refresh.
        case streaming(LancerCore.ChatTurn)
        case completed(LancerCore.ChatTurn)
        case failed(String)
        /// Host refreshes failing; keep polling in background. Never claim
        /// "Working…" over stale data — `message` carries data age.
        case degraded(message: String, turn: LancerCore.ChatTurn?)

        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.working, .working), (.adoptedNoHistory, .adoptedNoHistory):
                return true
            case (.streaming(let l), .streaming(let r)),
                 (.completed(let l), .completed(let r)):
                return l.id == r.id && l.status == r.status && l.assistantText == r.assistantText
            case (.failed(let l), .failed(let r)):
                return l == r
            case (.degraded(let lm, let lt), .degraded(let rm, let rt)):
                return lm == rm
                    && lt?.id == rt?.id
                    && lt?.assistantText == rt?.assistantText
                    && lt?.status == rt?.status
            default:
                return false
            }
        }
    }

    public private(set) var sendState: SendState = .idle
    public private(set) var activeConversationID: String?
    /// Full conversation transcript from `ChatConversationRepository`, refreshed
    /// on every poll tick. `LiveThreadView` renders these in order so follow-ups
    /// keep prior turns on screen (I2, 2026-07-11).
    public private(set) var transcriptTurns: [LancerCore.ChatTurn] = []
    /// Prompt for the in-flight send/follow-up before its turn row lands in
    /// the mirror — lets the live user bubble appear immediately.
    public private(set) var inFlightPrompt: String?
    /// Structured attachments for the in-flight send — rendered with the live
    /// user bubble until the mirrored turn arrives.
    public private(set) var inFlightAttachments: [ConversationAttachmentReference] = []
    /// The run ID this bridge is currently polling for (`send`/`sendFollowUp`/
    /// `sendObservedContinue`), if any. Set alongside `inFlightPrompt` and
    /// cleared alongside it. `LiveThreadView.liveTurnID` prefers matching
    /// `ChatTurn.runID` against this over inferring liveness from
    /// `ChatTurn.status == .running` — the mirrored `transcriptTurns` status
    /// can flip to `.completed` up to one poll tick before `sendState` catches
    /// up, and `.status` was the field driving that stale read (found in the
    /// 10x reconnect re-proof, 2026-07-15).
    public private(set) var inFlightRunID: String?
    /// M4: the machine the most recent send/follow-up resolved via
    /// `RelayFleetStore.firstConnectedMachine`. `LiveThreadView` reads this to
    /// look up `RelayApprovalIngest.latestPendingApproval[activeMachineID]` —
    /// see that type's doc comment for why this is machine-scoped, not
    /// run-scoped.
    public private(set) var activeMachineID: RelayMachineID?

    /// Set by `AppRoot` once `RelayFleetHydration.hydrate` returns. Needed
    /// because `waitForConnectedMachine` can't tell "no machine was ever
    /// paired" apart from "hydration hasn't populated `relayFleetStore.machines`
    /// yet" just by checking `machines.isEmpty` — checking too early reads an
    /// array that's still empty because hydration hasn't run, not because
    /// nothing is paired (found 2026-07-10 sim dogfood).
    public private(set) var isHydrated = false

    /// Armed by the Agents section before presenting `LiveThreadPresentation`.
    /// Consumed by the next `send(prompt:cwd:)` (or kept across empty-prompt
    /// adopt until the first typed follow-up) and routes through
    /// `agent.observedSession.continue` instead of starting a brand-new conversation.
    public private(set) var pendingObservedContinue: ObservedContinueTarget?

    /// Observed session bound to this live thread after adopt/continue — later
    /// follow-ups keep using `agent.observedSession.continue`.
    public private(set) var boundObservedContinue: ObservedContinueTarget?

    /// Last send/follow-up/observed-continue attempt — Retry re-dispatches this
    /// instead of the sheet's initial `prompt` (which is wrong after a follow-up
    /// failure and empty on observed-adopt sheets).
    public private(set) var lastAttempt: LastSendAttempt?

    /// Bumped by `resetForNewThread` so abandoned poll loops stop mutating UI.
    private var sessionEpoch: UInt64 = 0

    /// Single-flight gate for `retryLastAttempt` — claimed before any
    /// `waitForConnectedMachine` await so rapid repeated Retry taps cannot
    /// double-dispatch while `send`/`sendFollowUp` are still idle.
    private var isRetryDispatchInFlight = false

    /// Single-flight gate for `send`/`sendFollowUp` themselves — claimed
    /// synchronously before any `waitForConnectedMachine` await, mirroring
    /// `isRetryDispatchInFlight` exactly. `isSendInFlight` alone is not
    /// enough: `sendState` doesn't flip to `.working` until AFTER the
    /// (up to 8s) connection wait returns, so two concurrent calls to
    /// `send`/`sendFollowUp` (double-tap, or two call sites both firing)
    /// could both pass `!isSendInFlight`, each mint their own `clientTurnId`,
    /// and both reach the daemon — which has no conflict-check for a
    /// brand-new conversation and only a `baseSeq`-race-dependent check for
    /// follow-ups (found in the 2026-07-15 reconnect re-proof investigation).
    private var isSendDispatchInFlight = false

    /// True while a send/follow-up is still awaiting a terminal turn
    /// (including degraded unreachable polling). Mid-run feedback may still
    /// be typed and enqueued; the bridge flushes the queue when this flips false.
    public var isSendInFlight: Bool {
        switch sendState {
        case .working, .streaming, .degraded:
            return true
        case .idle, .adoptedNoHistory, .completed, .failed:
            return false
        }
    }

    /// Follow-ups typed while a turn is still in flight (FIFO). Survives view
    /// re-entry within the session; cleared by `resetForNewThread`.
    public private(set) var queuedFeedback: MidRunFeedbackQueue = MidRunFeedbackQueue()

    /// Enqueues mid-run guidance. Visible in the transcript as a pending user
    /// turn until the bridge flushes it after the current turn goes terminal.
    @discardableResult
    public func enqueueFeedback(
        prompt: String,
        conversationID: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = []
    ) -> MidRunFeedbackItem {
        let item = MidRunFeedbackItem(
            text: prompt,
            conversationID: conversationID,
            cwd: cwd,
            attachments: attachments
        )
        var queue = queuedFeedback
        queue.enqueue(item)
        queuedFeedback = queue
        return item
    }

    /// Pops and sends the next queued follow-up when the agent is idle.
    private func flushNextQueuedFeedback() async {
        var queue = queuedFeedback
        guard let next = queue.flushNext(agentInFlight: isSendInFlight) else { return }
        queuedFeedback = queue
        await sendFollowUp(
            prompt: next.text,
            conversationID: next.conversationID,
            cwd: next.cwd,
            attachments: next.attachments
        )
    }

    // MARK: - Test seams (@testable)

    /// Runs after `chatRepo.turns` returns and before the epoch-guarded write.
    var testPostTranscriptFetchHold: (@MainActor () async -> Void)?
    /// Runs after the retry single-flight gate is claimed (before dispatch).
    var testAfterRetryGateClaimed: (@MainActor () async -> Void)?
    /// How many times `retryLastAttempt` claimed the single-flight gate.
    private(set) var testRetryGateClaimCount = 0
    /// Runs after `send`/`sendFollowUp`'s dispatch gate is claimed (before
    /// `waitForConnectedMachine`) — mirrors `testAfterRetryGateClaimed`.
    var testAfterSendDispatchGateClaimed: (@MainActor () async -> Void)?
    /// How many times `send`/`sendFollowUp` claimed the dispatch single-flight gate.
    private(set) var testSendDispatchGateClaimCount = 0
    /// Overrides the real relay transport in `send`/`sendFollowUp` so tests
    /// can count/gate dispatch without a live relay connection.
    var testTransportOverride: ConversationTransport?
    var testSessionEpoch: UInt64 { sessionEpoch }
    /// When set, `adoptArmedObservedContinue`'s tail-transcript fallback uses
    /// this instead of the live `agent.sessions.transcript` RPC.
    var testRelayFetchTranscript: (@MainActor (String, Int) async throws -> (
        messages: [SessionMessage],
        nextLine: Int,
        resetRequired: Bool
    ))?
    /// When set, adopt prefers this over live `relayAttachObservedSession`.
    /// Return a response with a non-empty `error` (or throw) to force the
    /// tail-transcript fallback path in tests.
    var testRelayAttachObservedSession: (@MainActor (String, String, String) async throws -> ConversationAttachObservedSessionResponse)?

    func testArmLastAttempt(_ attempt: LastSendAttempt) {
        lastAttempt = attempt
    }

    func testRefreshTranscript(conversationID: String, epoch: UInt64) async {
        await refreshTranscript(conversationID: conversationID, epoch: epoch)
    }

    func testPollUntilTerminal(
        runID: String,
        conversationID: String,
        transport: ConversationTransport
    ) async {
        await pollUntilTerminal(runID: runID, conversationID: conversationID, transport: transport)
    }

    /// Composer can send when a Lancer conversation is active or an observed
    /// session is armed/bound (empty-prompt adopt path).
    public var canAcceptFollowUp: Bool {
        activeConversationID != nil
            || pendingObservedContinue != nil
            || boundObservedContinue != nil
    }

    public func markHydrated() { isHydrated = true }

    /// Arms the next `send` to resume an observed host session by vendor + id.
    public func armObservedContinue(vendor: String, sessionId: String, cwd: String) {
        boundObservedContinue = nil
        pendingObservedContinue = ObservedContinueTarget(
            vendor: vendor,
            sessionId: sessionId,
            cwd: cwd
        )
    }

    public func clearObservedContinue() {
        pendingObservedContinue = nil
        boundObservedContinue = nil
    }

    private let relayFleetStore: RelayFleetStore
    private let conversationSyncCoordinator: ConversationSyncCoordinator
    private let chatRepo: ChatConversationRepository

    public struct ObservedContinueTarget: Equatable, Sendable {
        public let vendor: String
        public let sessionId: String
        public let cwd: String
    }

    /// What Retry should re-dispatch — never the sheet's original prompt alone.
    /// `clientTurnId` is minted once per attempt and reused across automatic /
    /// user Retry so append stays idempotent with the same attachment refs.
    public enum LastSendAttempt: Equatable, Sendable {
        case newConversation(
            prompt: String,
            cwd: String,
            attachments: [ConversationAttachmentReference] = [],
            clientTurnId: String
        )
        case followUp(
            prompt: String,
            conversationID: String,
            cwd: String,
            attachments: [ConversationAttachmentReference] = [],
            clientTurnId: String
        )
        case observedContinue(prompt: String, cwd: String, target: ObservedContinueTarget)
    }

    public init(
        relayFleetStore: RelayFleetStore,
        conversationSyncCoordinator: ConversationSyncCoordinator,
        chatRepo: ChatConversationRepository
    ) {
        self.relayFleetStore = relayFleetStore
        self.conversationSyncCoordinator = conversationSyncCoordinator
        self.chatRepo = chatRepo
    }

    /// Clears in-flight UI state when the live sheet dismisses so the next New
    /// Chat is not wedged behind a stale `isSendInFlight` / prior transcript.
    /// The host-side run may keep going; list sync keeps its status honest.
    public func resetForNewThread() {
        sessionEpoch &+= 1
        isRetryDispatchInFlight = false
        isSendDispatchInFlight = false
        sendState = .idle
        activeConversationID = nil
        transcriptTurns = []
        inFlightPrompt = nil
        inFlightAttachments = []
        inFlightRunID = nil
        activeMachineID = nil
        lastAttempt = nil
        pendingObservedContinue = nil
        boundObservedContinue = nil
        queuedFeedback = MidRunFeedbackQueue()
    }

    /// Re-dispatches `lastAttempt` without inventing a brand-new conversation
    /// when the failure was a follow-up / observed continue.
    public func retryLastAttempt() async {
        guard !isRetryDispatchInFlight else { return }
        guard lastAttempt != nil else { return }
        isRetryDispatchInFlight = true
        testRetryGateClaimCount += 1
        defer { isRetryDispatchInFlight = false }
        if let hold = testAfterRetryGateClaimed {
            await hold()
        }
        // Re-read after the hold — resetForNewThread may have cleared it.
        guard let attempt = lastAttempt else { return }
        switch attempt {
        case .newConversation(let prompt, let cwd, let attachments, let clientTurnId):
            await send(
                prompt: prompt, cwd: cwd, attachments: attachments, clientTurnId: clientTurnId
            )
        case .followUp(let prompt, let conversationID, let cwd, let attachments, let clientTurnId):
            await sendFollowUp(
                prompt: prompt,
                conversationID: conversationID,
                cwd: cwd,
                attachments: attachments,
                clientTurnId: clientTurnId
            )
        case .observedContinue(let prompt, let cwd, let target):
            guard !isSendInFlight else { return }
            let epoch = sessionEpoch
            guard let machine = await waitForConnectedMachine() else {
                guard epoch == sessionEpoch else { return }
                pendingObservedContinue = nil
                boundObservedContinue = nil
                sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
                return
            }
            guard epoch == sessionEpoch else { return }
            activeMachineID = machine.id
            pendingObservedContinue = nil
            boundObservedContinue = target
            await sendObservedContinue(prompt: prompt, cwd: cwd, target: target, machine: machine)
        }
    }

    /// Adopts an armed observed session without sending: resolves a connected
    /// machine, hydrates history into `transcriptTurns`, and leaves
    /// `sendState` idle so the follow-up composer is active. The first typed
    /// follow-up consumes `pendingObservedContinue` via `send`.
    ///
    /// Prefer `attachObservedSession` + ledger fetch — the live
    /// `agent.sessions.transcript` RPC is intentionally tail-capped
    /// (`maxObservedTailLines`) for streaming payloads, which made past
    /// desktop sessions open with only recent messages. Attach imports the
    /// full vendor transcript into the host ledger; fetch-on-open pages it
    /// onto the phone. Falls back to the tail transcript RPC only when
    /// attach/refresh fails (session gone, transport blip).
    public func adoptArmedObservedContinue(fallbackCwd: String) async {
        guard let target = pendingObservedContinue else {
            sendState = .failed("No observed session to open.")
            return
        }
        let epoch = sessionEpoch
        guard let machine = await waitForConnectedMachine() else {
            guard epoch == sessionEpoch else { return }
            pendingObservedContinue = nil
            boundObservedContinue = nil
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        guard epoch == sessionEpoch else { return }
        activeMachineID = machine.id
        let resolved = ObservedContinueTarget(
            vendor: target.vendor,
            sessionId: target.sessionId,
            cwd: target.cwd.isEmpty ? fallbackCwd : target.cwd
        )
        pendingObservedContinue = resolved
        boundObservedContinue = resolved

        if await adoptViaAttachObservedSession(resolved: resolved, machine: machine, epoch: epoch) {
            return
        }
        guard epoch == sessionEpoch else { return }
        await adoptViaTailTranscript(resolved: resolved, machine: machine, epoch: epoch)
    }

    /// Full-history path: `attachObservedSession` → `refreshConversation` →
    /// local turns. Returns `true` when hydration succeeded (including empty
    /// history). Keeps `boundObservedContinue` so follow-ups still use
    /// `agent.observedSession.continue`.
    private func adoptViaAttachObservedSession(
        resolved: ObservedContinueTarget,
        machine: RelayFleetStore.Machine,
        epoch: UInt64
    ) async -> Bool {
        do {
            let attach: ConversationAttachObservedSessionResponse
            if let override = testRelayAttachObservedSession {
                attach = try await override(resolved.vendor, resolved.sessionId, resolved.cwd)
            } else {
                attach = try await machine.bridge.relayAttachObservedSession(
                    ConversationAttachObservedSessionRequest(
                        provider: resolved.vendor,
                        sessionId: resolved.sessionId,
                        cwd: resolved.cwd
                    )
                )
            }
            guard epoch == sessionEpoch else { return true }
            if let error = attach.error, !error.isEmpty {
                return false
            }
            let conversationID = attach.conversationId
            guard !conversationID.isEmpty else { return false }

            let transport = testTransportOverride ?? Self.transport(for: machine.bridge)
            // Partial page-cap still leaves usable merged turns — treat as success.
            _ = try? await conversationSyncCoordinator.refreshConversation(
                conversationID: conversationID,
                transport: transport
            )
            guard epoch == sessionEpoch else { return true }

            let turns = (try? await chatRepo.turns(conversationID: conversationID)) ?? []
            // Attach wrote events on the host but local mirror is still empty —
            // refresh likely failed; fall through to the tail transcript so the
            // user still sees *something* rather than a blank thread.
            if turns.isEmpty && (attach.importedEvents > 0 || attach.lastSeq > 0) {
                return false
            }
            activeConversationID = conversationID
            transcriptTurns = turns
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = turns.isEmpty ? .adoptedNoHistory : .idle
            return true
        } catch {
            return false
        }
    }

    /// Legacy live-view path: single tail-window `agent.sessions.transcript`
    /// fetch (capped on the daemon). Used only when attach/refresh fails.
    private func adoptViaTailTranscript(
        resolved: ObservedContinueTarget,
        machine: RelayFleetStore.Machine,
        epoch: UInt64
    ) async {
        do {
            let result: (messages: [SessionMessage], nextLine: Int, resetRequired: Bool)
            if let override = testRelayFetchTranscript {
                result = try await override(resolved.sessionId, 0)
            } else {
                result = try await machine.bridge.relayFetchTranscript(
                    sessionId: resolved.sessionId,
                    sinceLine: 0
                )
            }
            guard epoch == sessionEpoch else { return }
            let conversationID = "observed:\(resolved.sessionId)"
            activeConversationID = conversationID
            transcriptTurns = LiveThreadTranscript.turns(
                fromObservedMessages: result.messages,
                conversationID: conversationID,
                vendorSessionID: resolved.sessionId
            )
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            // Empty host transcript still adopts (composer usable) but must not
            // look like a blank failed tap — surface an explicit no-history state.
            sendState = LiveThreadTranscript.shouldShowAdoptedNoHistoryPlaceholder(
                transcriptMessageCount: result.messages.count
            ) ? .adoptedNoHistory : .idle
        } catch {
            guard epoch == sessionEpoch else { return }
            sendState = .failed(error.localizedDescription)
        }
    }

    /// Starts a brand-new conversation on the first connected paired machine
    /// and polls for the reply. No-op if a send is already in flight.
    ///
    /// When `pendingObservedContinue` / `boundObservedContinue` is set
    /// (Agents row tap → empty-prompt adopt, or a prior observed continue),
    /// routes through `relayContinueObservedSession` instead of
    /// `startConversation`, then polls the observed transcript for the reply.
    public func send(
        prompt: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = [],
        clientTurnId: String? = nil
    ) async {
        guard !isSendInFlight, !isSendDispatchInFlight else { return }
        isSendDispatchInFlight = true
        testSendDispatchGateClaimCount += 1
        defer { isSendDispatchInFlight = false }
        if let hold = testAfterSendDispatchGateClaimed {
            await hold()
        }
        let epoch = sessionEpoch
        guard let machine = await waitForConnectedMachine() else {
            guard epoch == sessionEpoch else { return }
            pendingObservedContinue = nil
            boundObservedContinue = nil
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        guard epoch == sessionEpoch else { return }
        activeMachineID = machine.id

        if let target = pendingObservedContinue {
            pendingObservedContinue = nil
            boundObservedContinue = target
            lastAttempt = .observedContinue(prompt: prompt, cwd: cwd, target: target)
            await sendObservedContinue(prompt: prompt, cwd: cwd, target: target, machine: machine)
            return
        }

        // Brand-new conversation — drop any stale observed bind from a prior sheet.
        boundObservedContinue = nil
        let turnId = clientTurnId ?? UUID().uuidString
        lastAttempt = .newConversation(
            prompt: prompt, cwd: cwd, attachments: attachments, clientTurnId: turnId
        )
        sendState = .working
        activeConversationID = nil
        transcriptTurns = []
        inFlightPrompt = prompt
        inFlightAttachments = attachments
        inFlightRunID = nil

        let transport = testTransportOverride ?? Self.transport(for: machine.bridge)
        let vendor = DispatchVendorSelection.load()
        let model = DispatchModelSelection.dispatchSlug(for: vendor)
        // "Full tools" only means anything for claudeCode — never send it true
        // for another vendor even if the toggle was left on from a prior
        // claudeCode send (the daemon ignores it for other agents anyway, but
        // don't rely on that: keep the wire payload honest per-vendor).
        let fullTools = vendor.usesClaudeModelPicker && FullToolsSelection.load()
        let outcome = await conversationSyncCoordinator.startConversation(
            agent: "relay|\(machine.id.uuidString)|\(vendor.wireID)",
            cwd: cwd,
            prompt: prompt,
            model: model,
            budgetUSD: nil,
            fullTools: fullTools,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            clientTurnID: turnId,
            transport: transport,
            attachments: attachments
        )

        guard epoch == sessionEpoch else { return }
        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            inFlightRunID = started.runID
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .blocked(let message):
            // Blocked reasons from startConversation (policy / approval /
            // budget / transport) are surfaced via `.failed` — not silent.
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed(message)
            await flushNextQueuedFeedback()
        }
    }

    /// Resumes an observed (terminal-started) session via
    /// `agent.observedSession.continue`, then polls that session's on-disk
    /// transcript for the assistant reply so `LiveThreadView` can render it.
    private func sendObservedContinue(
        prompt: String,
        cwd: String,
        target: ObservedContinueTarget,
        machine: RelayFleetStore.Machine
    ) async {
        let epoch = sessionEpoch
        sendState = .working
        let conversationID = "observed:\(target.sessionId)"
        activeConversationID = conversationID
        // Keep hydrated history; append the in-flight turn once polling starts.
        inFlightPrompt = prompt
        inFlightRunID = nil

        let resumeCwd = target.cwd.isEmpty ? cwd : target.cwd
        let result: DispatchResult
        do {
            result = try await machine.bridge.relayContinueObservedSession(
                vendor: target.vendor,
                sessionId: target.sessionId,
                cwd: resumeCwd,
                prompt: prompt
            )
        } catch {
            guard epoch == sessionEpoch else { return }
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed(error.localizedDescription)
            return
        }

        guard epoch == sessionEpoch else { return }
        switch result.status {
        case "started":
            let runID = result.startedRunId ?? UUID().uuidString
            inFlightRunID = runID
            await pollObservedTranscriptReply(
                sessionId: target.sessionId,
                prompt: prompt,
                runID: runID,
                priorTurns: transcriptTurns,
                bridge: machine.bridge
            )
        case "needsApproval":
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed("Waiting for approval on \(machine.record.displayName).")
        case "denied":
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            let rule = result.rule.map { " (\($0))" } ?? ""
            sendState = .failed("Denied by policy on \(machine.record.displayName)\(rule).")
        case "budgetExceeded":
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed("Daily budget reached on \(machine.record.displayName).")
        default:
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed(result.message ?? "Couldn't continue session on \(machine.record.displayName).")
        }
    }

    /// Observed continue writes into the vendor transcript (not the conversation
    /// ledger). Re-poll `agent.sessions.transcript` until a terminal run-status
    /// is observed and the transcript has stopped growing — never stamp
    /// `.completed` from a bounded timeout alone.
    private func pollObservedTranscriptReply(
        sessionId: String,
        prompt: String,
        runID: String,
        priorTurns: [LancerCore.ChatTurn],
        bridge: E2ERelayBridge
    ) async {
        let epoch = sessionEpoch
        let conversationID = "observed:\(sessionId)"
        activeConversationID = conversationID
        let turnID = UUID().uuidString
        let baselineCount: Int
        if let baseline = try? await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: 0) {
            baselineCount = baseline.messages.count
        } else {
            baselineCount = 0
        }

        var turn = LancerCore.ChatTurn(
            id: turnID,
            conversationID: conversationID,
            ordinal: priorTurns.count,
            prompt: prompt,
            runID: runID,
            transportKind: "relay",
            status: .running,
            assistantText: "",
            vendorSessionID: sessionId
        )
        guard epoch == sessionEpoch else { return }
        transcriptTurns = priorTurns + [turn]
        sendState = .working

        var tracker = LivePollPolicy.Tracker()
        var lastAssistantText = ""
        var stagnantPolls = 0
        let terminalSignal = ObservedTerminalSignal()

        let statusWatch = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(
                named: Notification.Name("lancerE2ERunStatus")
            ) {
                guard let params = notification.userInfo?["params"] as? RunStatusParams,
                      params.runId == runID,
                      let terminal = ObservedRunTerminal(params: params)
                else { continue }
                terminalSignal.value = terminal
                return
            }
        }
        defer { statusWatch.cancel() }

        while true {
            guard epoch == sessionEpoch else { return }

            let now = Date()
            do {
                let result = try await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: 0)
                _ = LivePollPolicy.recordRefreshSuccess(&tracker, at: now)

                let newMessages = Array(result.messages.dropFirst(baselineCount))
                let assistantText = newMessages
                    .filter { $0.role == .assistant }
                    .map(\.text)
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if assistantText != lastAssistantText {
                    lastAssistantText = assistantText
                    stagnantPolls = 0
                    if !assistantText.isEmpty {
                        turn.assistantText = assistantText
                        turn.status = .running
                        guard epoch == sessionEpoch else { return }
                        transcriptTurns = priorTurns + [turn]
                        sendState = .streaming(turn)
                    } else if !tracker.isDegraded {
                        guard epoch == sessionEpoch else { return }
                        sendState = .working
                    }
                } else if !assistantText.isEmpty {
                    stagnantPolls += 1
                }

                // Complete only when a real run-status terminal arrived and the
                // transcript has stopped growing (at least one stagnant tick after
                // first text, or immediately if terminal arrives with empty text).
                if let terminal = terminalSignal.value {
                    let transcriptSettled = assistantText.isEmpty || stagnantPolls >= 1
                    if transcriptSettled {
                        inFlightPrompt = nil
                        inFlightAttachments = []
                        inFlightRunID = nil
                        switch terminal {
                        case .completed:
                            turn.status = .completed
                            turn.completedAt = .now
                            turn.assistantText = assistantText
                            guard epoch == sessionEpoch else { return }
                            transcriptTurns = priorTurns + [turn]
                            sendState = .completed(turn)
                        case .failed(let message):
                            turn.status = .failed
                            turn.errorMessage = message
                            turn.completedAt = .now
                            turn.assistantText = assistantText
                            guard epoch == sessionEpoch else { return }
                            transcriptTurns = priorTurns + [turn]
                            sendState = .failed(message)
                        }
                        return
                    }
                }
            } catch {
                let result = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
                switch result {
                case .enteredDegraded, .stillDegraded:
                    let message = LivePollPolicy.degradedMessage(
                        lastSuccessfulRefreshAt: tracker.lastSuccessfulRefreshAt,
                        now: now
                    )
                    guard epoch == sessionEpoch else { return }
                    sendState = .degraded(message: message, turn: turn.assistantText.isEmpty ? nil : turn)
                case .failing, .healthy, .recovered:
                    break
                }
            }

            do {
                try await Task.sleep(nanoseconds: LivePollPolicy.pollIntervalNanoseconds)
            } catch {
                return
            }
        }
    }

    private final class ObservedTerminalSignal: @unchecked Sendable {
        var value: ObservedRunTerminal?
    }

    private enum ObservedRunTerminal: Sendable {
        case completed
        case failed(String)

        init?(params: RunStatusParams) {
            switch params.status {
            case "exited":
                if params.exitCode == 0 || params.exitCode == nil {
                    self = .completed
                } else {
                    self = .failed("Run exited with code \(params.exitCode ?? -1)")
                }
            case "failed":
                self = .failed("Run failed")
            case "completed", "succeeded":
                self = .completed
            case "cancelled", "stopped":
                self = .failed("Run \(params.status)")
            default:
                return nil
            }
        }
    }

    /// Appends a follow-up turn to the active conversation and polls for the
    /// reply. Reads the conversation's current `lastHostSeq` as `baseSeq`.
    /// No-op if there's no active conversation or a send is already in flight.
    ///
    /// Follow-up "broken" findings (2026-07-11):
    /// - `continueConversation` `.blocked` paths already map to `.failed(message)`
    ///   here (policy / approval / budget / conflict / transport) — those strings
    ///   reach `LiveThreadView.errorState`. They were not silent.
    /// - The dogfood "can't continue" feel was dominated by the old 90s poll
    ///   timeout: false `.failed("Timed out…")` while the host turn was still
    ///   `.running`, so a follow-up raced a live run (conflict / transport
    ///   blip) or Retry started a brand-new conversation instead of continuing.
    /// - Mid-run typing enqueues locally (`queuedFeedback`) and flushes when
    ///   the current turn reaches a terminal state — Claude-mobile parity.
    public func sendFollowUp(
        prompt: String,
        conversationID: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = [],
        clientTurnId: String? = nil
    ) async {
        if isSendInFlight {
            _ = enqueueFeedback(
                prompt: prompt,
                conversationID: conversationID,
                cwd: cwd,
                attachments: attachments
            )
            return
        }
        guard !isSendDispatchInFlight else { return }
        isSendDispatchInFlight = true
        testSendDispatchGateClaimCount += 1
        defer { isSendDispatchInFlight = false }
        if let hold = testAfterSendDispatchGateClaimed {
            await hold()
        }
        let epoch = sessionEpoch

        // Observed sessions are not in the conversation ledger — keep routing
        // follow-ups through `agent.observedSession.continue`.
        if let target = boundObservedContinue ?? pendingObservedContinue {
            guard let machine = await waitForConnectedMachine() else {
                guard epoch == sessionEpoch else { return }
                pendingObservedContinue = nil
                boundObservedContinue = nil
                sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
                await flushNextQueuedFeedback()
                return
            }
            guard epoch == sessionEpoch else { return }
            activeMachineID = machine.id
            pendingObservedContinue = nil
            boundObservedContinue = target
            lastAttempt = .observedContinue(prompt: prompt, cwd: cwd, target: target)
            await sendObservedContinue(prompt: prompt, cwd: cwd, target: target, machine: machine)
            await flushNextQueuedFeedback()
            return
        }

        guard let machine = await waitForConnectedMachine() else {
            guard epoch == sessionEpoch else { return }
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            await flushNextQueuedFeedback()
            return
        }
        guard epoch == sessionEpoch else { return }
        activeMachineID = machine.id

        let conversation = try? await chatRepo.conversation(id: conversationID)
        guard epoch == sessionEpoch else { return }
        let baseSeq = conversation?.lastHostSeq ?? 0
        let model = DispatchModelSelection.modelForFollowUp(
            conversationModel: conversation?.model,
            selected: DispatchModelSelection.load()
        )
        // Follow-up honors the CURRENT composer toggle for this new turn (not
        // whatever an earlier turn on this conversation sent) — same "thread
        // the request's own flag, don't re-derive from history" rule
        // buildConversationArgv follows on the daemon (dispatch.go).
        let followUpVendor = DispatchVendorSelection.resolve(conversation?.vendor)
        let fullTools = followUpVendor.usesClaudeModelPicker && FullToolsSelection.load()

        let turnId = clientTurnId ?? UUID().uuidString
        lastAttempt = .followUp(
            prompt: prompt,
            conversationID: conversationID,
            cwd: cwd,
            attachments: attachments,
            clientTurnId: turnId
        )
        sendState = .working
        inFlightPrompt = prompt
        inFlightAttachments = attachments
        inFlightRunID = nil

        let transport = testTransportOverride ?? Self.transport(for: machine.bridge)
        let outcome = await conversationSyncCoordinator.continueConversation(
            conversationID: conversationID,
            baseSeq: baseSeq,
            prompt: prompt,
            clientTurnID: turnId,
            model: model,
            fullTools: fullTools,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            transport: transport,
            attachments: attachments
        )

        guard epoch == sessionEpoch else { return }
        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            inFlightRunID = started.runID
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .blocked(let message):
            // Surface blocked reason in the UI (same `.failed` path as send).
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed(message)
            await flushNextQueuedFeedback()
        }
    }

    /// Polls the local GRDB mirror until the turn leaves `.running`.
    ///
    /// A plain local re-read alone is NOT enough: nothing updates the
    /// mirror's turn status after the initial append
    /// (`persistStartedTurn` in `ConversationSyncCoordinator` writes it once,
    /// at append time) until a host fetch happens
    /// (`refreshConversation`/`mergeFetchResponse`). Without periodically
    /// re-fetching from the host here, the local row never changes on its own.
    ///
    /// While the host reports `.running` and refreshes succeed, this loops
    /// indefinitely (no wall-clock timeout). Partial `assistantText` is
    /// published every tick. N consecutive refresh failures → degraded
    /// (honest data-age copy) while retries continue in the background.
    private func pollUntilTerminal(runID: String, conversationID: String, transport: ConversationTransport) async {
        let epoch = sessionEpoch
        var tracker = LivePollPolicy.Tracker()
        while true {
            guard epoch == sessionEpoch else { return }
            let now = Date()
            do {
                _ = try await conversationSyncCoordinator.refreshConversation(
                    conversationID: conversationID, transport: transport
                )
                guard epoch == sessionEpoch else { return }
                _ = LivePollPolicy.recordRefreshSuccess(&tracker, at: now)
            } catch {
                let result = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
                switch result {
                case .enteredDegraded, .stillDegraded:
                    let turn = try? await chatRepo.turnByRunID(runID)
                    let message = LivePollPolicy.degradedMessage(
                        lastSuccessfulRefreshAt: tracker.lastSuccessfulRefreshAt,
                        now: now
                    )
                    guard epoch == sessionEpoch else { return }
                    sendState = .degraded(message: message, turn: turn)
                case .failing, .healthy, .recovered:
                    break
                }
            }

            guard epoch == sessionEpoch else { return }

            // Decide terminal-vs-running and flip `sendState`/`inFlightPrompt`
            // BEFORE refreshing `transcriptTurns` — the reverse order left a
            // real await-window where `transcriptTurns` already showed this
            // turn `.completed` while `sendState` was still `.working` and
            // `inFlightPrompt` still set, so `LiveThreadView` rendered the
            // turn via both the frozen-history path and the live in-flight
            // path simultaneously (duplicate prompt bubble + phantom
            // "Working…", found in the 10x reconnect re-proof, 2026-07-15).
            // Flipping first closes the window instead of narrowing it.
            if let turn = try? await chatRepo.turnByRunID(runID) {
                switch turn.status {
                case .completed:
                    inFlightPrompt = nil
                    inFlightAttachments = []
                    inFlightRunID = nil
                    guard epoch == sessionEpoch else { return }
                    sendState = .completed(turn)
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    return
                case .failed:
                    inFlightPrompt = nil
                    inFlightAttachments = []
                    inFlightRunID = nil
                    guard epoch == sessionEpoch else { return }
                    sendState = .failed(turn.errorMessage ?? "Run failed")
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    return
                case .running:
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    guard epoch == sessionEpoch else { return }
                    if !tracker.isDegraded {
                        switch LivePollPolicy.runningPublish(assistantText: turn.assistantText) {
                        case .working:
                            sendState = .working
                        case .streaming:
                            sendState = .streaming(turn)
                        }
                    }
                }
            } else {
                await refreshTranscript(conversationID: conversationID, epoch: epoch)
            }

            do {
                try await Task.sleep(nanoseconds: LivePollPolicy.pollIntervalNanoseconds)
            } catch {
                // Task cancelled (sheet dismissed) — stop polling.
                return
            }
        }
    }

    private func refreshTranscript(conversationID: String, epoch: UInt64) async {
        if let turns = try? await chatRepo.turns(conversationID: conversationID) {
            if let hold = testPostTranscriptFetchHold {
                await hold()
            }
            guard epoch == sessionEpoch else { return }
            transcriptTurns = turns
        }
    }

    /// Bridges the gap between app launch (while `RelayFleetHydration.hydrate`
    /// is still reconnecting a previously-paired machine) and the first send.
    /// Without this, opening a live thread immediately after launch/relaunch
    /// races ahead of reconnection and dead-ends on "No connected machine"
    /// with no auto-retry (found 2026-07-10 sim dogfood: `firstConnectedMachine`
    /// was read once, synchronously, at call time). Skips the wait entirely
    /// when no machine is paired at all, so the true no-host path still fails
    /// fast instead of stalling for `timeout`.
    private func waitForConnectedMachine(timeout: TimeInterval = 8) async -> RelayFleetStore.Machine? {
        let deadline = Date().addingTimeInterval(timeout)
        while !isHydrated, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let machine = relayFleetStore.firstConnectedMachine { return machine }
        guard !relayFleetStore.machines.isEmpty else { return nil }
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let machine = relayFleetStore.firstConnectedMachine { return machine }
        }
        return nil
    }

    private static func transport(for bridge: E2ERelayBridge) -> ConversationTransport {
        ConversationTransport(
            append: { try await bridge.relayAppendConversation($0) },
            fetch: { try await bridge.relayFetchConversation($0) },
            archive: { try await bridge.relayArchiveConversation($0) }
        )
    }

    #if DEBUG
    /// Aligns the live thread with the UITest-hydrated approval machine id.
    public func configureUITestMachineContextIfNeeded() {
        guard ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" else { return }
        activeMachineID = RelayApprovalIngest.uitestMachineID
    }
    #endif
}
#endif
