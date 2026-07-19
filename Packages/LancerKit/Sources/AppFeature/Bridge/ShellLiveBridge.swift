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
        /// Sync returned needsApproval; daemon will resume under the same runID.
        case awaitingApproval(String)
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
            case (.awaitingApproval(let l), .awaitingApproval(let r)):
                return l == r
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
    /// True while a followed *observed* session (one Lancer didn't dispatch —
    /// see `startObservedFollow`) has appended new transcript lines within
    /// the last few poll ticks. `sendState` stays `.idle` for the whole
    /// observed-follow lifetime (it only models Lancer-dispatched sends), so
    /// without this the reply area shows nothing while a remote agent is
    /// visibly still working — no spinner, no "Working…" (owner report,
    /// 2026-07-18). Cleared after `observedFollowIdleGracePolls` consecutive
    /// empty polls so it goes honest-idle once activity actually stops,
    /// matching the "never claim Working… over stale data" rule already
    /// applied to `sendState.degraded` above.
    public private(set) var isObservedSessionWorking = false
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

    /// Live Activity key for the conversation currently surfaced on the Lock
    /// Screen / Dynamic Island. Stable per conversation so follow-ups reuse
    /// rather than stack. Nil when no activity is owned by this bridge.
    private var liveActivityKey: String?
    private var liveActivityAgentName: String?
    private var lastLiveActivitySnapshot: LiveActivitySnapshot?

    /// Equality-dedup payload for Live Activity status updates so identical
    /// polls don't spam ActivityKit. Pending-approval fields deliberately
    /// absent: `RelayApprovalIngest` owns those and the bridge's updates go
    /// through the field-preserving `updateStatus`, never full `update`.
    private struct LiveActivitySnapshot: Equatable {
        let status: String
        let agentName: String?
    }

    /// Live follow of an adopted observed session's vendor transcript, so
    /// desktop-side activity appears while the thread is open. Cancelled by
    /// `resetForNewThread` (LiveThreadPresentation binding-clear path).
    private var observedFollowTask: Task<Void, Never>?

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

    /// True while a Lancer-dispatched send/follow-up itself is still awaiting
    /// a terminal turn (including degraded unreachable polling) — `sendState`
    /// only, deliberately excluding `isObservedSessionWorking`. This is the
    /// guard `observedFollowLoop` checks internally ("don't double-render
    /// while a real send is happening"); if it included the observed-session
    /// signal too, the loop would see itself as permanently in-flight the
    /// moment it sets `isObservedSessionWorking = true` and could never poll
    /// again to notice the session going idle. Use `isSendInFlight` (below)
    /// everywhere else — this one is for the loop only.
    private var isDispatchSendInFlight: Bool {
        switch sendState {
        case .working, .awaitingApproval, .streaming, .degraded:
            return true
        case .idle, .adoptedNoHistory, .completed, .failed:
            return false
        }
    }

    /// True while a send/follow-up is in flight OR the currently-followed
    /// observed session looks busy (`isObservedSessionWorking`). `sendFollowUp`
    /// gates on this so a follow-up typed while watching a still-running
    /// observed session queues locally (`enqueueFeedback`) instead of firing
    /// `agent.observedSession.continue` immediately — Claude Code's CLI has no
    /// "inject into a live process" mechanism, so `resumeObservedSession`
    /// launches a brand-new `--resume` invocation every time; racing that
    /// against a session the daemon can't see is busy is what the 2026-07-18
    /// investigation found (daemon-side reservation guard added in
    /// `dispatch.go` covers overlapping Lancer-initiated resumes; this client
    /// gate is the only signal for "busy in the original terminal it was
    /// started in", which the daemon has no handle on at all).
    public var isSendInFlight: Bool {
        isDispatchSendInFlight || isObservedSessionWorking
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

    /// Stops the single in-flight run (`inFlightRunID`) via relay
    /// `agentRunControl` action `"stop"` — same path as
    /// `CommandGateway.execute(.cancel(runId:))` / `DaemonChannel.cancelRun`.
    /// Does **not** call fleet-wide `agentEmergencyStop`. Returns false when
    /// there is no run ID yet or no connected machine bridge.
    @discardableResult
    public func stopCurrentRun() async -> Bool {
        guard let runID = inFlightRunID else { return false }
        let machine = activeMachineID.flatMap { relayFleetStore.machine($0) }
            ?? relayFleetStore.firstConnectedMachine
        guard let machine else { return false }
        let stopped = await machine.bridge.sendRunControl(runId: runID, action: "stop")
        if stopped {
            await endLiveActivity()
        }
        return stopped
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
    /// How many `refreshTranscript` calls actually reassigned `transcriptTurns`
    /// (content changed). Together with `testTranscriptRefreshSkipCount`,
    /// proves the WP1 diff-before-publish fix (2026-07-17): unchanged polls
    /// during a live-follow no longer republish the whole transcript.
    private(set) var testTranscriptRefreshPublishCount = 0
    /// How many `refreshTranscript` calls fetched from the DB but skipped the
    /// `transcriptTurns` write because nothing changed.
    private(set) var testTranscriptRefreshSkipCount = 0
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
    /// Shrinks the observed-follow tick so tests don't wait real seconds.
    var testObservedFollowIntervalNanoseconds: UInt64?

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

    func testSetSendState(_ state: SendState) {
        sendState = state
    }

    func testSetInFlight(runID: String?, prompt: String?) {
        inFlightRunID = runID
        inFlightPrompt = prompt
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
    private let failedCwds: FailedCwdStore

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
        chatRepo: ChatConversationRepository,
        failedCwds: FailedCwdStore = FailedCwdStore()
    ) {
        self.relayFleetStore = relayFleetStore
        self.conversationSyncCoordinator = conversationSyncCoordinator
        self.chatRepo = chatRepo
        self.failedCwds = failedCwds
    }

    /// Clears in-flight UI state when the live thread pops so the next New
    /// Chat is not wedged behind a stale `isSendInFlight` / prior transcript.
    /// The host-side run may keep going; list sync keeps its status honest.
    public func resetForNewThread() {
        sessionEpoch &+= 1
        observedFollowTask?.cancel()
        observedFollowTask = nil
        isObservedSessionWorking = false
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
        // Dismiss any Lock Screen / Dynamic Island activity owned by this
        // thread — same teardown role as SessionViewModel.disconnect().
        let activityKeyToEnd = liveActivityKey
        liveActivityKey = nil
        liveActivityAgentName = nil
        lastLiveActivitySnapshot = nil
        if #available(iOS 16.2, *), let activityKeyToEnd {
            Task { await LancerLiveActivityManager.shared.end(activityKey: activityKeyToEnd) }
        }
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
            startObservedFollow(sessionId: resolved.sessionId, machine: machine)
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
            startObservedFollow(sessionId: resolved.sessionId, machine: machine)
        } catch {
            guard epoch == sessionEpoch else { return }
            sendState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Observed live follow

    /// Starts live-following the vendor transcript of an adopted observed
    /// session. Orca's equivalent is a push subscription over its RPC socket;
    /// this is the poll analogue over the existing `agent.sessions.transcript`
    /// incremental fetch — no relay protocol change. The loop pauses (and
    /// re-baselines) around phone-initiated sends so the reply the send path
    /// renders is never duplicated from the vendor transcript.
    private func startObservedFollow(sessionId: String, machine: RelayFleetStore.Machine) {
        observedFollowTask?.cancel()
        let epoch = sessionEpoch
        observedFollowTask = Task { [weak self] in
            await self?.observedFollowLoop(sessionId: sessionId, machine: machine, epoch: epoch)
        }
    }

    private func fetchObservedTranscript(
        machine: RelayFleetStore.Machine,
        sessionId: String,
        sinceLine: Int
    ) async throws -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool) {
        if let override = testRelayFetchTranscript {
            return try await override(sessionId, sinceLine)
        }
        return try await machine.bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: sinceLine)
    }

    private func observedFollowLoop(
        sessionId: String,
        machine: RelayFleetStore.Machine,
        epoch: UInt64
    ) async {
        // nextLine < 0 means "needs (re)baseline": take the current transcript
        // tail as the new zero so history already rendered (adopted ledger
        // turns, or a send-path reply) is never re-appended.
        var nextLine = -1
        var buffered: [SessionMessage] = []
        var baselineTurnCount = transcriptTurns.count
        var failures = 0
        var idlePolls = 0

        let tick = testObservedFollowIntervalNanoseconds ?? LivePollPolicy.observedFollowIntervalNanoseconds
        while !Task.isCancelled, epoch == sessionEpoch {
            try? await Task.sleep(nanoseconds: tick)
            guard !Task.isCancelled, epoch == sessionEpoch else { return }
            if isDispatchSendInFlight || isSendDispatchInFlight {
                // The send path renders its own reply turn; whatever lands in
                // the vendor transcript meanwhile must not be double-rendered.
                nextLine = -1
                continue
            }
            do {
                if nextLine < 0 {
                    let baseline = try await fetchObservedTranscript(
                        machine: machine, sessionId: sessionId, sinceLine: 0
                    )
                    guard !Task.isCancelled, epoch == sessionEpoch else { return }
                    if isDispatchSendInFlight || isSendDispatchInFlight { continue }
                    nextLine = baseline.nextLine
                    buffered = []
                    baselineTurnCount = transcriptTurns.count
                    failures = 0
                    continue
                }
                let delta = try await fetchObservedTranscript(
                    machine: machine, sessionId: sessionId, sinceLine: nextLine
                )
                guard !Task.isCancelled, epoch == sessionEpoch else { return }
                if isDispatchSendInFlight || isSendDispatchInFlight {
                    nextLine = -1
                    continue
                }
                failures = 0
                if delta.resetRequired {
                    nextLine = -1
                    continue
                }
                nextLine = delta.nextLine
                guard !delta.messages.isEmpty else {
                    idlePolls += 1
                    if idlePolls >= LivePollPolicy.observedFollowIdleGracePolls {
                        isObservedSessionWorking = false
                    }
                    continue
                }
                idlePolls = 0
                isObservedSessionWorking = true
                buffered.append(contentsOf: delta.messages)
                renderObservedFollowSuffix(
                    buffered: buffered,
                    sessionId: sessionId,
                    baselineTurnCount: baselineTurnCount
                )
            } catch {
                failures += 1
                if failures >= LivePollPolicy.consecutiveFailureLimit {
                    isObservedSessionWorking = false
                    return
                }
            }
        }
        isObservedSessionWorking = false
    }

    /// Re-renders the post-baseline suffix from the full buffered delta each
    /// tick (the mapper is pure), with deterministic ids/ordinals offset past
    /// the adopted prefix so SwiftUI row identity survives suffix growth.
    private func renderObservedFollowSuffix(
        buffered: [SessionMessage],
        sessionId: String,
        baselineTurnCount: Int
    ) {
        let conversationID = activeConversationID ?? "observed:\(sessionId)"
        let suffix = LiveThreadTranscript.turns(
            fromObservedMessages: buffered,
            conversationID: conversationID,
            vendorSessionID: sessionId
        )
        guard !suffix.isEmpty else { return }
        let offsetSuffix = suffix.enumerated().map { index, turn in
            ChatTurn(
                id: "observedFollow:\(sessionId):\(baselineTurnCount + index)",
                conversationID: turn.conversationID,
                ordinal: baselineTurnCount + index,
                prompt: turn.prompt,
                runID: turn.runID,
                transportKind: turn.transportKind,
                status: turn.status,
                assistantText: turn.assistantText,
                completedAt: turn.completedAt,
                vendorSessionID: turn.vendorSessionID
            )
        }
        transcriptTurns = Array(transcriptTurns.prefix(baselineTurnCount)) + offsetSuffix
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
            await startLiveActivity(
                activityKey: started.conversationID,
                hostID: machine.id.uuidString,
                hostName: machine.record.displayName,
                agentName: vendor.displayName
            )
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .awaitingApproval(let started, let message):
            activeConversationID = started.conversationID
            inFlightRunID = started.runID
            sendState = .awaitingApproval(message)
            await startLiveActivity(
                activityKey: started.conversationID,
                hostID: machine.id.uuidString,
                hostName: machine.record.displayName,
                agentName: vendor.displayName
            )
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .blocked(let message):
            // Blocked reasons from startConversation (policy / approval /
            // budget / transport) are surfaced via `.failed` — not silent.
            surfaceBlockedSendFailure(message: message, cwd: cwd)
            await endLiveActivity()
            await flushNextQueuedFeedback()
        }
    }

    /// Maps daemon `cwd does not exist` into a failed-cwd record + clearer copy.
    /// Fail-closed: no auto-retry to a different cwd without user intent.
    private func surfaceBlockedSendFailure(message: String, cwd: String) {
        var userMessage = message
        if message.localizedCaseInsensitiveContains("cwd does not exist") {
            failedCwds.markFailed(cwd)
            let label = WorkspaceRepoCatalog.displayName(forCwd: cwd)
            userMessage = "Repo path \"\(label)\" isn't on the host anymore — pick another folder."
        }
        inFlightPrompt = nil
        inFlightAttachments = []
        inFlightRunID = nil
        sendState = .failed(userMessage)
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
            await startLiveActivity(
                activityKey: conversationID,
                hostID: machine.id.uuidString,
                hostName: machine.record.displayName,
                agentName: DispatchVendorSelection.resolve(target.vendor).displayName
            )
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
            await endLiveActivity()
        case "denied":
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            let rule = result.rule.map { " (\($0))" } ?? ""
            sendState = .failed("Denied by policy on \(machine.record.displayName)\(rule).")
            await endLiveActivity()
        case "budgetExceeded":
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed("Daily budget reached on \(machine.record.displayName).")
            await endLiveActivity()
        default:
            inFlightPrompt = nil
            inFlightAttachments = []
            inFlightRunID = nil
            sendState = .failed(result.message ?? "Couldn't continue session on \(machine.record.displayName).")
            await endLiveActivity()
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
                        await updateLiveActivityIfNeeded()
                    } else if !tracker.isDegraded {
                        guard epoch == sessionEpoch else { return }
                        sendState = .working
                        await updateLiveActivityIfNeeded()
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
                            await endLiveActivity()
                        case .failed(let message):
                            turn.status = .failed
                            turn.errorMessage = message
                            turn.completedAt = .now
                            turn.assistantText = assistantText
                            guard epoch == sessionEpoch else { return }
                            transcriptTurns = priorTurns + [turn]
                            sendState = .failed(message)
                            await endLiveActivity()
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
                    await updateLiveActivityIfNeeded()
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
            await startLiveActivity(
                activityKey: started.conversationID,
                hostID: machine.id.uuidString,
                hostName: machine.record.displayName,
                agentName: followUpVendor.displayName
            )
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .awaitingApproval(let started, let message):
            activeConversationID = started.conversationID
            inFlightRunID = started.runID
            sendState = .awaitingApproval(message)
            await startLiveActivity(
                activityKey: started.conversationID,
                hostID: machine.id.uuidString,
                hostName: machine.record.displayName,
                agentName: followUpVendor.displayName
            )
            await refreshTranscript(conversationID: started.conversationID, epoch: epoch)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
            await flushNextQueuedFeedback()
        case .blocked(let message):
            // Surface blocked reason in the UI (same `.failed` path as send).
            surfaceBlockedSendFailure(message: message, cwd: cwd)
            await endLiveActivity()
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
                    await updateLiveActivityIfNeeded()
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
                    await endLiveActivity()
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    return
                case .failed:
                    inFlightPrompt = nil
                    inFlightAttachments = []
                    inFlightRunID = nil
                    guard epoch == sessionEpoch else { return }
                    let failMessage: String
                    if case .awaitingApproval = sendState {
                        failMessage = turn.errorMessage ?? "Approval denied — the run did not start."
                    } else {
                        failMessage = turn.errorMessage ?? "Run failed"
                    }
                    sendState = .failed(failMessage)
                    await endLiveActivity()
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    return
                case .running:
                    await refreshTranscript(conversationID: conversationID, epoch: epoch)
                    guard epoch == sessionEpoch else { return }
                    if !tracker.isDegraded {
                        // Host maps needsApproval → `.running`; keep the honest
                        // awaiting card until text streams or the turn terminates.
                        if case .awaitingApproval = sendState {
                            if !turn.assistantText.isEmpty {
                                sendState = .streaming(turn)
                            }
                        } else {
                            switch LivePollPolicy.runningPublish(assistantText: turn.assistantText) {
                            case .working:
                                sendState = .working
                            case .streaming:
                                sendState = .streaming(turn)
                            }
                        }
                    }
                    await updateLiveActivityIfNeeded()
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

    /// Re-reads turns from the local mirror and republishes `transcriptTurns`
    /// only if they actually changed. Called on essentially every
    /// `pollUntilTerminal` tick (~1s while a run is in-flight), so without the
    /// equality gate every tick re-triggers every downstream observer keyed
    /// off `transcriptTurns` (e.g. `LiveThreadView.receiptRefreshToken`,
    /// which itself re-fetches up to 10k events) even when the host had
    /// nothing new to report. Measured 2026-07-17 — see
    /// docs/test-runs/2026-07-17-perf/README.md.
    private func refreshTranscript(conversationID: String, epoch: UInt64) async {
        if let turns = try? await chatRepo.turns(conversationID: conversationID) {
            if let hold = testPostTranscriptFetchHold {
                await hold()
            }
            guard epoch == sessionEpoch else { return }
            if turns != transcriptTurns {
                transcriptTurns = turns
                testTranscriptRefreshPublishCount += 1
            } else {
                testTranscriptRefreshSkipCount += 1
            }
        }
    }

    /// Bridges the gap between app launch (while `RelayFleetHydration.hydrate`
    /// is still reconnecting a previously-paired machine) and the first send.
    /// Without this, opening a live thread immediately after launch/relaunch
    /// races ahead of reconnection and dead-ends on "No connected machine"
    /// with no auto-retry (found 2026-07-10 sim dogfood: `firstConnectedMachine`
    /// was read once, synchronously, at call time). Default timeout is 30s —
    /// a 2026-07-16 daily-use audit measured auto-pair completion at ~21s from
    /// launch under the same conditions, so the previous 8s default raced the
    /// first send and surfaced a spurious "No connected machine" even though
    /// the pair finished moments later. Skips the wait entirely when no
    /// machine is paired at all, so the true no-host path still fails fast
    /// instead of stalling for `timeout`.
    private func waitForConnectedMachine(timeout: TimeInterval = 30) async -> RelayFleetStore.Machine? {
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

    // MARK: - Live Activity (production relay path)

    /// Maps in-flight `SendState` to a Live Activity status string. Nil means
    /// the activity should end (terminal / idle). Package-visible for tests.
    nonisolated static func liveActivityStatus(for state: SendState) -> String? {
        switch state {
        case .working, .streaming, .awaitingApproval, .degraded:
            return "running"
        case .idle, .adoptedNoHistory, .completed, .failed:
            return nil
        }
    }

    /// Starts (or reuses) a Live Activity keyed by conversation so follow-ups
    /// don't stack. Mirrors `SessionViewModel.connect()` success.
    private func startLiveActivity(
        activityKey: String,
        hostID: String,
        hostName: String,
        agentName: String
    ) async {
        guard #available(iOS 16.2, *) else { return }
        // Same conversation follow-up — keep the existing activity; don't
        // re-`start` (that would rewrite content and clobber pending-approval
        // counts pushed by `RelayApprovalIngest`).
        if liveActivityKey == activityKey {
            liveActivityAgentName = agentName
            await updateLiveActivityIfNeeded()
            return
        }
        if let previous = liveActivityKey, previous != activityKey {
            await LancerLiveActivityManager.shared.end(activityKey: previous)
            lastLiveActivitySnapshot = nil
        }
        liveActivityKey = activityKey
        liveActivityAgentName = agentName
        lastLiveActivitySnapshot = nil
        await LancerLiveActivityManager.shared.start(
            hostID: hostID,
            hostName: hostName,
            activityKey: activityKey,
            deviceSessionID: DeviceIdentity.sessionID(),
            status: "running",
            agentName: agentName,
            pendingApprovals: 0,
            pendingApprovalID: nil
        )
        await updateLiveActivityIfNeeded()
    }

    /// Equality-deduped content update — same pattern as
    /// `SessionViewModel.updateLiveActivityIfNeeded`. Pending-approval count
    /// is owned by `RelayApprovalIngest.updatePendingApprovals` and is not
    /// rewritten here (snapshot pending stays at the last value we ourselves
    /// wrote, usually 0, so dedup prevents mid-poll clobbers).
    private func updateLiveActivityIfNeeded() async {
        guard #available(iOS 16.2, *),
              let activityKey = liveActivityKey,
              let liveStatus = Self.liveActivityStatus(for: sendState)
        else { return }
        let snapshot = LiveActivitySnapshot(
            status: liveStatus,
            agentName: liveActivityAgentName
        )
        guard snapshot != lastLiveActivitySnapshot else { return }
        lastLiveActivitySnapshot = snapshot
        await LancerLiveActivityManager.shared.updateStatus(
            activityKey: activityKey,
            status: snapshot.status,
            agentName: snapshot.agentName
        )
    }

    private func endLiveActivity() async {
        guard #available(iOS 16.2, *), let activityKey = liveActivityKey else {
            liveActivityKey = nil
            liveActivityAgentName = nil
            lastLiveActivitySnapshot = nil
            return
        }
        liveActivityKey = nil
        liveActivityAgentName = nil
        lastLiveActivitySnapshot = nil
        await LancerLiveActivityManager.shared.end(activityKey: activityKey)
    }

    /// Focuses a paired machine so `LiveThreadView` can render that machine's
    /// pending-approval card without sending a new turn (home-banner entry).
    public func focusMachineForPendingApproval(_ id: RelayMachineID) {
        activeMachineID = id
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
