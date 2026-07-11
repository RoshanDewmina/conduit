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
/// Hardcodes vendor `"claudeCode"` (no vendor picker UI exists yet — see the
/// M3 brief). Polls `ChatConversationRepository.turnByRunID` after each host
/// refresh and publishes partial `assistantText` while the turn is still
/// `.running` (daemon ledger already streams stdout chunks; this bridge was
/// the missing mid-run publisher — 2026-07-11 dogfood).
@MainActor
@Observable
public final class ShellLiveBridge {
    public enum SendState: Equatable {
        case idle
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
            case (.idle, .idle), (.working, .working):
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

    /// Armed by the Agents section's "Continue in Lancer" before presenting
    /// `LiveThreadPresentation`. The next `send(prompt:cwd:)` consumes this
    /// and routes through `agent.observedSession.continue` instead of
    /// starting a brand-new conversation.
    public private(set) var pendingObservedContinue: ObservedContinueTarget?

    /// True while a send/follow-up is still awaiting a terminal turn
    /// (including degraded unreachable polling). Composer must stay disabled.
    public var isSendInFlight: Bool {
        switch sendState {
        case .working, .streaming, .degraded:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    public func markHydrated() { isHydrated = true }

    /// Arms the next `send` to resume an observed host session by vendor + id.
    public func armObservedContinue(vendor: String, sessionId: String, cwd: String) {
        pendingObservedContinue = ObservedContinueTarget(
            vendor: vendor,
            sessionId: sessionId,
            cwd: cwd
        )
    }

    public func clearObservedContinue() {
        pendingObservedContinue = nil
    }

    private let relayFleetStore: RelayFleetStore
    private let conversationSyncCoordinator: ConversationSyncCoordinator
    private let chatRepo: ChatConversationRepository

    /// This milestone hardcodes the vendor CLI — no picker UI exists yet.
    private static let vendor = "claudeCode"

    public struct ObservedContinueTarget: Equatable, Sendable {
        public let vendor: String
        public let sessionId: String
        public let cwd: String
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

    /// Starts a brand-new conversation on the first connected paired machine
    /// and polls for the reply. No-op if a send is already in flight.
    ///
    /// When `pendingObservedContinue` is armed (Agents → Continue in Lancer),
    /// routes through `relayContinueObservedSession` instead of
    /// `startConversation`, then polls the observed transcript for the reply.
    public func send(prompt: String, cwd: String) async {
        guard !isSendInFlight else { return }
        guard let machine = await waitForConnectedMachine() else {
            pendingObservedContinue = nil
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        activeMachineID = machine.id

        if let target = pendingObservedContinue {
            pendingObservedContinue = nil
            await sendObservedContinue(prompt: prompt, cwd: cwd, target: target, machine: machine)
            return
        }

        sendState = .working
        activeConversationID = nil
        transcriptTurns = []
        inFlightPrompt = prompt

        let transport = Self.transport(for: machine.bridge)
        let model = DispatchModelSelection.load().slug
        let outcome = await conversationSyncCoordinator.startConversation(
            agent: "relay|\(machine.id.uuidString)|\(Self.vendor)",
            cwd: cwd,
            prompt: prompt,
            model: model,
            budgetUSD: nil,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            clientTurnID: UUID().uuidString,
            transport: transport
        )

        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            await refreshTranscript(conversationID: started.conversationID)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
        case .blocked(let message):
            // Blocked reasons from startConversation (policy / approval /
            // budget / transport) are surfaced via `.failed` — not silent.
            inFlightPrompt = nil
            sendState = .failed(message)
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
        sendState = .working
        activeConversationID = nil
        transcriptTurns = []
        inFlightPrompt = prompt

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
            inFlightPrompt = nil
            sendState = .failed(error.localizedDescription)
            return
        }

        switch result.status {
        case "started":
            let runID = result.startedRunId ?? UUID().uuidString
            await pollObservedTranscriptReply(
                sessionId: target.sessionId,
                prompt: prompt,
                runID: runID,
                bridge: machine.bridge
            )
        case "needsApproval":
            inFlightPrompt = nil
            sendState = .failed("Waiting for approval on \(machine.record.displayName).")
        case "denied":
            inFlightPrompt = nil
            let rule = result.rule.map { " (\($0))" } ?? ""
            sendState = .failed("Denied by policy on \(machine.record.displayName)\(rule).")
        case "budgetExceeded":
            inFlightPrompt = nil
            sendState = .failed("Daily budget reached on \(machine.record.displayName).")
        default:
            inFlightPrompt = nil
            sendState = .failed(result.message ?? "Couldn't continue session on \(machine.record.displayName).")
        }
    }

    /// Observed continue writes into the vendor transcript (not the conversation
    /// ledger). Re-poll `agent.sessions.transcript` for a new assistant turn.
    private func pollObservedTranscriptReply(
        sessionId: String,
        prompt: String,
        runID: String,
        bridge: E2ERelayBridge
    ) async {
        let turnID = UUID().uuidString
        let baselineCount: Int
        if let baseline = try? await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: 0) {
            baselineCount = baseline.messages.count
        } else {
            baselineCount = 0
        }

        var turn = LancerCore.ChatTurn(
            id: turnID,
            conversationID: "observed:\(sessionId)",
            ordinal: 0,
            prompt: prompt,
            runID: runID,
            transportKind: "relay",
            status: .running,
            assistantText: "",
            vendorSessionID: sessionId
        )
        transcriptTurns = [turn]
        sendState = .working

        for _ in 0..<20 {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            guard let result = try? await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: 0)
            else { continue }

            let newMessages = Array(result.messages.dropFirst(baselineCount))
            let assistantText = newMessages
                .filter { $0.role == .assistant }
                .map(\.text)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !assistantText.isEmpty {
                turn.assistantText = assistantText
                turn.status = .running
                transcriptTurns = [turn]
                sendState = .streaming(turn)
                // Keep polling briefly for more chunks, then complete.
                for _ in 0..<5 {
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        inFlightPrompt = nil
                        turn.status = .completed
                        turn.completedAt = .now
                        transcriptTurns = [turn]
                        sendState = .completed(turn)
                        return
                    }
                    if let later = try? await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: 0) {
                        let laterText = Array(later.messages.dropFirst(baselineCount))
                            .filter { $0.role == .assistant }
                            .map(\.text)
                            .joined(separator: "\n\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if laterText.count > assistantText.count {
                            turn.assistantText = laterText
                            transcriptTurns = [turn]
                            sendState = .streaming(turn)
                        }
                    }
                }
                inFlightPrompt = nil
                turn.status = .completed
                turn.completedAt = .now
                transcriptTurns = [turn]
                sendState = .completed(turn)
                return
            }
        }

        // Started but no transcript reply appeared — still a successful continue.
        inFlightPrompt = nil
        turn.status = .completed
        turn.completedAt = .now
        turn.assistantText = turn.assistantText.isEmpty
            ? "Continued on the host. Open the session again to see later output."
            : turn.assistantText
        transcriptTurns = [turn]
        sendState = .completed(turn)
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
    /// - Composer now keys off `isSendInFlight` (working/streaming/degraded)
    ///   so follow-up can't fire mid-run / mid-degrade.
    public func sendFollowUp(prompt: String, conversationID: String, cwd: String) async {
        guard !isSendInFlight else { return }
        guard let machine = await waitForConnectedMachine() else {
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        activeMachineID = machine.id

        let conversation = try? await chatRepo.conversation(id: conversationID)
        let baseSeq = conversation?.lastHostSeq ?? 0
        let model = DispatchModelSelection.modelForFollowUp(
            conversationModel: conversation?.model,
            selected: DispatchModelSelection.load()
        )

        sendState = .working
        inFlightPrompt = prompt

        let transport = Self.transport(for: machine.bridge)
        let outcome = await conversationSyncCoordinator.continueConversation(
            conversationID: conversationID,
            baseSeq: baseSeq,
            prompt: prompt,
            clientTurnID: UUID().uuidString,
            model: model,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            transport: transport
        )

        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            await refreshTranscript(conversationID: started.conversationID)
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
        case .blocked(let message):
            // Surface blocked reason in the UI (same `.failed` path as send).
            inFlightPrompt = nil
            sendState = .failed(message)
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
        var tracker = LivePollPolicy.Tracker()
        while true {
            let now = Date()
            do {
                _ = try await conversationSyncCoordinator.refreshConversation(
                    conversationID: conversationID, transport: transport
                )
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
                    sendState = .degraded(message: message, turn: turn)
                case .failing, .healthy, .recovered:
                    break
                }
            }

            await refreshTranscript(conversationID: conversationID)

            if let turn = try? await chatRepo.turnByRunID(runID) {
                switch turn.status {
                case .completed:
                    inFlightPrompt = nil
                    sendState = .completed(turn)
                    return
                case .failed:
                    inFlightPrompt = nil
                    sendState = .failed(turn.errorMessage ?? "Run failed")
                    return
                case .running:
                    if !tracker.isDegraded {
                        switch LivePollPolicy.runningPublish(assistantText: turn.assistantText) {
                        case .working:
                            sendState = .working
                        case .streaming:
                            sendState = .streaming(turn)
                        }
                    }
                }
            }

            do {
                try await Task.sleep(nanoseconds: LivePollPolicy.pollIntervalNanoseconds)
            } catch {
                // Task cancelled (sheet dismissed) — stop polling.
                return
            }
        }
    }

    private func refreshTranscript(conversationID: String) async {
        if let turns = try? await chatRepo.turns(conversationID: conversationID) {
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
}
#endif
