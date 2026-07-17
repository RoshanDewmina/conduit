#if os(iOS)
import SwiftUI
import LancerCore
import Foundation
import PersistenceKit
import SessionFeature
import SSHTransport

/// M3: the real, live conversation view — reached only from the New Chat
/// composer's send action (a brand-new conversation flow). This is
/// deliberately separate from `ThreadDetailView` (Section 7's static,
/// owner-approved PR-review-style mockup for browsing sample thread rows) —
/// see the M3 brief's scope boundary. Apple-native `NavigationStack` /
/// `ScrollView` / `TextField` only, no DesignSystem module.
///
/// M4: also renders a pending-approval sheet (see `ApprovalDecisionSheet`,
/// opened from `approvalPendingRow`) — a fully
/// separate, orthogonal piece of UI state from `SendState` below. A pending
/// approval can appear at any point regardless of whether the current turn
/// is still working or already completed.
public struct LiveThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellLiveBridge.self) private var bridge
    @Environment(RelayApprovalIngest.self) private var approvalIngest
    @Environment(RelayQuestionIngest.self) private var questionIngest
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(WorkspaceDataStore.self) private var workspaceData

    let prompt: String
    let cwd: String
    let initialAttachments: [ConversationAttachmentReference]
    /// Non-nil ⇒ this presentation is a follow-up on an existing conversation
    /// (opened from `ThreadDetailView`); the initial send continues that
    /// conversation via `sendFollowUp` instead of starting a new one.
    let existingConversationID: String?

    @State private var hasSentInitialPrompt = false
    @State private var followUpText: String = ""
    @State private var followUpAttachments: [AttachmentDraft] = []
    @State private var isContextPresented = false
    @State private var isUploadingAttachments = false
    @State private var followUpUploadTask: Task<Void, Never>?
    @State private var streamingPacer = ChatStreamingTextPacer()
    @State private var receiptsByRunID: [String: ProofReceipt] = [:]
    @State private var eventsByTurnID: [String: [ChatEvent]] = [:]
    @State private var toolArtifactsByTurnID: [String: [ChatArtifact]] = [:]
    @State private var showScrollToBottom = false
    @State private var isNearBottom = true
    /// A freshly opened thread lands at the TOP, so `isNearBottom` is false
    /// and `scrollToTailIfFollowing` never fires for the initial transcript
    /// load — the first population must scroll unconditionally (WT-J).
    @State private var hasPerformedInitialScroll = false
    @State private var extrasRepo: ChatConversationRepository?
    /// Ephemeral runStatus events from the daemon (G3). Absent → legacy Working….
    @State private var liveRunStatus: LiveRunStatusParams?
    @State private var liveStatusFirstAt: Date?
    @State private var liveStatusLastAt: Date?
    @State private var liveStatusNow: Date = .now
    @State private var turnDiffByTurnID: [String: RepoDiffSummary] = [:]
    @State private var sessionDiff: RepoDiffSummary?
    @State private var reviewPresentation: ReviewPresentation?
    @State private var queuedReviewComments: [QueuedReviewComment] = []
    @State private var isBackgroundTasksPresented = false
    /// CC-6: the pending approval now presents as a bottom sheet
    /// (`ApprovalDecisionSheet`) instead of an inline card. Auto-opens when a
    /// new approval arrives; the inline compact row stays visible underneath
    /// so a manually-dismissed sheet can be reopened with a tap.
    @State private var isApprovalSheetPresented = false
    @State private var lastAutoPresentedApprovalID: Approval.ID?
    @FocusState private var isFollowUpFocused: Bool
    #if DEBUG
    @State private var hasAutoAnsweredQuestion = false
    @State private var hasAutoFollowedUp = false
    #endif

    private static let scrollTailID = "live-tail"
    /// Live path must not use G2 fixtures — it should bind to the active machine's
    /// relay bridge when available, and degrade to unsupported when no bridge is live.
    private var reviewDataSource: any ReviewDataSource {
        let connectedBridge: E2ERelayBridge? = {
            if let machineID = bridge.activeMachineID,
               relayFleetStore.isConnected(machineID),
               let machine = relayFleetStore.machine(machineID) {
                return machine.bridge
            }
            return relayFleetStore.firstConnectedMachine?.bridge
        }()
        return RelayReviewDataSource(bridge: connectedBridge)
    }

    private struct ReviewPresentation: Identifiable {
        enum Scope {
            case turn(String)
            case session
        }
        let scope: Scope
        var id: String {
            switch scope {
            case .turn(let turnID): return "turn:\(turnID)"
            case .session: return "session"
            }
        }
    }

    public init(
        prompt: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = [],
        existingConversationID: String? = nil
    ) {
        self.prompt = prompt
        self.cwd = cwd
        self.initialAttachments = attachments
        self.existingConversationID = existingConversationID
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy so opening a long thread doesn't build (and
                        // markdown-parse) every historical turn up front.
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(priorTurns) { turn in
                                if LiveThreadTranscript.shouldRenderPromptBubble(for: turn) {
                                    ChatUserBubble(
                                        text: turn.prompt,
                                        attachments: turn.attachments
                                    )
                                }
                                staticAssistant(turn)
                            }

                            if let liveUserPrompt {
                                ChatUserBubble(
                                    text: liveUserPrompt,
                                    attachments: liveUserAttachments
                                )
                            }

                            ForEach(bridge.queuedFeedback.items) { item in
                                ChatUserBubble(
                                    text: item.text,
                                    attachments: item.attachments,
                                    isQueued: true
                                )
                            }

                            replyState
                                .id(Self.scrollTailID)

                            // Tail visibility drives the jump arrow — geometry
                            // math goes stale when the keyboard resizes the
                            // viewport (arrow showed while at the tail).
                            Color.clear
                                .frame(height: 4)
                                .onScrollVisibilityChange(threshold: 0.1) { visible in
                                    withAnimation { showScrollToBottom = !visible }
                                }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                    // Open at the latest message (WT-J) — the lazy stack then
                    // materializes from the bottom up instead of the top down.
                    .defaultScrollAnchor(.bottom)
                    .onScrollGeometryChange(for: Double.self) { geometry in
                        ChatScrollPolicy.distanceFromBottom(
                            contentHeight: geometry.contentSize.height,
                            viewportHeight: geometry.containerSize.height,
                            contentOffsetY: geometry.contentOffset.y
                        )
                    } action: { _, distance in
                        isNearBottom = ChatScrollPolicy.isNearBottom(distanceFromBottom: distance)
                    }
                    .onChange(of: bridge.sendState) { _, _ in
                        scrollToTailIfFollowing(proxy)
                    }
                    .onChange(of: bridge.transcriptTurns.count) { _, newCount in
                        if !hasPerformedInitialScroll, newCount > 0 {
                            hasPerformedInitialScroll = true
                            scrollToTail(proxy)
                        } else {
                            scrollToTailIfFollowing(proxy)
                        }
                        Task { await refreshTranscriptExtras() }
                    }
                    // Within-turn growth (observed live-follow, mirrored
                    // streaming) changes the LAST turn's text without changing
                    // the count — follow it too or the thread stalls mid-story
                    // while the user sits at the bottom (CC-1 parity).
                    .onChange(of: bridge.transcriptTurns.last?.assistantText ?? "") { _, _ in
                        scrollToTailIfFollowing(proxy)
                    }
                    .onAppear {
                        if !hasPerformedInitialScroll, !bridge.transcriptTurns.isEmpty {
                            hasPerformedInitialScroll = true
                            scrollToTail(proxy)
                        }
                    }
                    .onChange(of: bridge.queuedFeedback.count) { _, _ in
                        scrollToTailIfFollowing(proxy)
                    }
                    .onChange(of: streamingAssistantText) { _, newValue in
                        if !newValue.isEmpty {
                            streamingPacer.ingest(newValue)
                        }
                        scrollToTailIfFollowing(proxy)
                    }
                    .onChange(of: streamingPacer.displayText) { _, _ in
                        scrollToTailIfFollowing(proxy)
                    }
                    .overlay(alignment: .bottom) {
                        if showScrollToBottom {
                            ChatScrollToBottomButton {
                                isNearBottom = true
                                showScrollToBottom = false
                                scrollToTail(proxy)
                            }
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }

                if let pendingApproval {
                    approvalPendingRow(pendingApproval) {
                        isApprovalSheetPresented = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                if let machineID = bridge.activeMachineID, let pendingQuestion {
                    questionCard(pendingQuestion, machineID: machineID)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if let sessionDiff {
                    SessionDiffPill(summary: sessionDiff) {
                        reviewPresentation = ReviewPresentation(scope: .session)
                    }
                    .padding(.bottom, 4)
                }

                if !queuedReviewComments.isEmpty {
                    reviewCommentChips
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                VStack(spacing: 0) {
                    if backgroundTasksRunningCount > 0 {
                        BackgroundTasksPill(runningCount: backgroundTasksRunningCount) {
                            isBackgroundTasksPresented = true
                        }
                        .padding(.bottom, 6)
                    }
                    followUpAttachmentChips
                    HStack {
                        ChatPermissionModePill()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 2)
                    ChatFollowUpComposerBar(
                        text: $followUpText,
                        isFocused: $isFollowUpFocused,
                        placeholder: bridge.isSendInFlight ? "Queue for after this turn…" : "Follow up…",
                        isDisabled: isUploadingAttachments,
                        canSend: canSendFollowUpWithAttachments,
                        isRunInFlight: bridge.isSendInFlight,
                        onSend: {
                            followUpUploadTask?.cancel()
                            followUpUploadTask = Task { await sendFollowUp() }
                        },
                        onStop: {
                            Task { await bridge.stopCurrentRun() }
                        },
                        onAddContext: { isContextPresented = true }
                    )
                    if !bridge.queuedFeedback.isEmpty {
                        Text("Will send when the agent finishes")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 6)
                            .accessibilityIdentifier("mid-run-feedback-caption")
                    }
                }
                .sheet(isPresented: $isContextPresented) {
                    ContextAttachView(attachments: $followUpAttachments)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(sessionNavTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(sessionNavSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .sheet(isPresented: $isBackgroundTasksPresented) {
                BackgroundTasksSheet(rows: backgroundTaskRows)
            }
        }
        .task {
            guard !hasSentInitialPrompt else { return }
            hasSentInitialPrompt = true
            if let conversationID = existingConversationID, LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
                await bridge.sendFollowUp(prompt: prompt, conversationID: conversationID, cwd: cwd, attachments: initialAttachments)
            } else if LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
                await bridge.send(prompt: prompt, cwd: cwd, attachments: initialAttachments)
            } else if bridge.activeMachineID != nil {
                // Home pending-approvals banner focuses the machine then opens
                // with an empty prompt — show the approval card, don't adopt.
                isFollowUpFocused = true
            } else {
                await bridge.adoptArmedObservedContinue(fallbackCwd: cwd)
                switch bridge.sendState {
                case .idle, .adoptedNoHistory:
                    isFollowUpFocused = true
                default:
                    break
                }
            }
        }
        .task {
            await observeLiveRunStatus()
        }
        .onChange(of: bridge.sendState) { _, newValue in
            let phase: LiveStatusSendPhase
            switch newValue {
            case .idle, .adoptedNoHistory: phase = .idle
            case .working, .awaitingApproval: phase = .working
            case .streaming: phase = .streaming
            case .completed: phase = .completed
            case .failed: phase = .failed
            case .degraded: phase = .degraded
            }
            if LiveStatusPresentation.shouldClearOnSendStatePhase(phase) {
                clearLiveRunStatus()
            }
        }
        .onChange(of: liveTurnRunID) { previous, next in
            // Cross-run leftovers: drop the pill when the bound run changes.
            // (runID filtering already blocks ingest of foreign runs.)
            if previous != next {
                clearLiveRunStatus()
            }
        }
        .task(id: receiptRefreshToken) {
            await refreshReceipts()
            await refreshTranscriptExtras()
            await refreshReviewDiffs()
        }
        .sheet(isPresented: $isApprovalSheetPresented) {
            if let pendingApproval {
                ApprovalDecisionSheet(approval: pendingApproval) { decision in
                    decideApproval(pendingApproval, decision: decision)
                }
            }
        }
        // Auto-open the sheet the moment a NEW approval arrives (CC-6 parity
        // with the reference app's auto-presented bottom sheet). Tracking
        // the last auto-presented id (rather than re-firing on every change)
        // lets a manually dismissed sheet stay closed — the compact row
        // above remains as the way back in — while still re-presenting for
        // a genuinely different approval that supersedes it.
        .onChange(of: pendingApproval) { _, newValue in
            guard let newValue, lastAutoPresentedApprovalID != newValue.id else { return }
            lastAutoPresentedApprovalID = newValue.id
            isApprovalSheetPresented = true
        }
        .sheet(item: $reviewPresentation) { presentation in
            ReviewSheetView(
                conversationID: bridge.activeConversationID ?? "fixture",
                scope: {
                    switch presentation.scope {
                    case .turn(let turnID): return .turn(turnID: turnID)
                    case .session: return .session
                    }
                }(),
                dataSource: reviewDataSource,
                onAttachComment: { comment in
                    queuedReviewComments.append(comment)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { note in
            let conversationID = note.userInfo?["conversationID"] as? String
            guard conversationID == nil || conversationID == bridge.activeConversationID else { return }
            Task {
                await refreshReceipts()
                await refreshTranscriptExtras()
                await refreshReviewDiffs()
            }
        }
        #if DEBUG
        // Simulator HID taps are unreliable on this iOS build (see
        // docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md), so
        // the Approve/Deny buttons above can't always be driven by a tap.
        // Gated on LANCER_DEBUG_APPROVAL_DECISION, this drives the exact same
        // `RelayApprovalIngest.decide` → `ApprovalRelay.enqueue` path the
        // buttons call — no bypass of the real decision/audit flow.
        .onChange(of: pendingApproval) { _, newValue in
            guard let approval = newValue,
                  let machineID = bridge.activeMachineID,
                  let decisionRaw = ProcessInfo.processInfo.environment["LANCER_DEBUG_APPROVAL_DECISION"]
            else { return }
            let decision: Approval.Decision = decisionRaw == "deny" ? .rejected : .approved
            Task { await approvalIngest.decide(approval, decision: decision, machineID: machineID) }
        }
        // Same rationale as the approval seam above, for the question card's
        // Submit button. Gated on LANCER_DEBUG_QUESTION_ANSWER (the free-text/
        // option text to answer with — applied to every item via the same
        // fuzzy-match-or-free-text rule `AnswerQuestionResolver` already uses),
        // drives the exact same `RelayQuestionIngest.submit` path the Submit
        // button calls. `hasAutoAnsweredQuestion` gates this to fire exactly
        // once: `toggleOption` mutating `latestPendingQuestion` re-triggers
        // this same onChange (the value it observes changed), and toggling
        // the SAME label a second time flips it back off (toggleOption is a
        // toggle, not a set) — an ungated version live-locked into flipping
        // the selection on/off forever and never reached `submit` (found live
        // 2026-07-10).
        .onChange(of: pendingQuestion) { _, newValue in
            guard !hasAutoAnsweredQuestion,
                  let question = newValue,
                  let machineID = bridge.activeMachineID,
                  let answerText = ProcessInfo.processInfo.environment["LANCER_DEBUG_QUESTION_ANSWER"]
            else { return }
            hasAutoAnsweredQuestion = true
            for idx in question.items.indices {
                if let matched = QuestionCardModel.fuzzyMatchOption(answerText, in: question.items[idx]) {
                    questionIngest.toggleOption(machineID: machineID, itemIndex: idx, label: matched)
                } else {
                    questionIngest.setFreeText(machineID: machineID, itemIndex: idx, text: answerText)
                }
            }
            Task { await questionIngest.submit(machineID: machineID, relayFleetStore: relayFleetStore) }
        }
        // Follow-up seam for the sim live-loop gate (HID taps dead on sim).
        // After the first terminal reply, auto-sends `LANCER_LIVETHREAD_FOLLOWUP`
        // through the exact production `bridge.sendFollowUp` path — mirrors
        // `LANCER_LIVETHREAD_PROMPT` / DebugSeeder-style env gating. Fires once.
        .onChange(of: bridge.sendState) { _, newValue in
            guard !hasAutoFollowedUp,
                  case .completed = newValue,
                  let followUp = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_FOLLOWUP"]
            else { return }
            let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let conversationID = bridge.activeConversationID else { return }
            hasAutoFollowedUp = true
            Task { await bridge.sendFollowUp(prompt: trimmed, conversationID: conversationID, cwd: cwd) }
        }
        #endif
    }

    private var canSendFollowUp: Bool {
        let hasText = !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasComments = !queuedReviewComments.isEmpty
        return (hasText || hasComments)
            && bridge.canAcceptFollowUp
    }

    private var canSendFollowUpWithAttachments: Bool {
        canSendFollowUp
            && !isUploadingAttachments
            && !followUpAttachments.contains(where: \.state.isError)
            && !followUpAttachments.contains(where: {
                if case .uploading = $0.state { return true }
                return false
            })
    }

    /// Turn id currently bound to `sendState` (streaming / completed / degraded /
    /// in-flight running / failed). Priors render frozen; this one uses replyState.
    private var liveTurnID: String? {
        switch bridge.sendState {
        case .streaming(let turn), .completed(let turn):
            return turn.id
        case .degraded(_, let turn):
            return turn?.id
        case .working, .awaitingApproval:
            // Prefer the bridge's own authoritative in-flight runID over
            // inferring liveness from `ChatTurn.status == .running` —
            // `transcriptTurns` can mirror a turn as `.completed` up to one
            // poll tick before `sendState` catches up (10x reconnect
            // re-proof, 2026-07-15), which made the `.status`-based lookup
            // resolve to nil right when it mattered most.
            if let inFlightRunID = bridge.inFlightRunID,
               let match = bridge.transcriptTurns.first(where: { $0.runID == inFlightRunID }) {
                return match.id
            }
            return bridge.transcriptTurns.last(where: { $0.status == .running })?.id
        case .failed:
            return bridge.transcriptTurns.last(where: { $0.status == .failed })?.id
        case .idle, .adoptedNoHistory:
            return nil
        }
    }

    private var priorTurns: [LancerCore.ChatTurn] {
        LiveThreadTranscript
            .priorTurns(turns: bridge.transcriptTurns, liveTurnID: liveTurnID)
            .filter {
                LiveThreadTranscript.shouldRenderTurn(
                    $0,
                    hasAssistantArtifacts: hasAssistantArtifacts(for: $0)
                )
            }
    }

    /// Session title for nav chrome — first line of the prompt, truncated.
    private var sessionNavTitle: String {
        let raw = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Chat" }
        let firstLine = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? raw
        if firstLine.count <= 40 { return firstLine }
        return String(firstLine.prefix(39)) + "…"
    }

    private var sessionNavSubtitle: String {
        WorkspaceRepoCatalog.displayName(forCwd: cwd)
    }

    private var backgroundTaskRows: [BackgroundTasksPresentation.TaskRow] {
        var rows: [BackgroundTasksPresentation.TaskRow] = []
        for turn in bridge.transcriptTurns {
            let eventItems = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
            // WT-B: a terminal turn cannot have running tasks — a tool_call
            // whose result never landed must not spin the pill forever.
            let terminalAdjusted: [TurnTranscriptItem] = eventItems.map { item in
                guard case .toolChip(let chip) = item else { return item }
                let forced = ToolChipGrouping.withTerminalTurnStatus(
                    [chip], turnIsTerminal: turn.status != .running
                )
                return .toolChip(forced[0])
            }
            let artifacts = toolArtifactsByTurnID[turn.id] ?? []
            rows.append(contentsOf: BackgroundTasksPresentation.rows(
                items: terminalAdjusted,
                events: eventsByTurnID[turn.id] ?? [],
                artifacts: artifacts
            ))
        }
        var byID: [String: BackgroundTasksPresentation.TaskRow] = [:]
        for row in rows {
            byID[row.id] = row
        }
        return Array(byID.values)
    }

    private var backgroundTasksRunningCount: Int {
        BackgroundTasksPresentation.runningCount(in: backgroundTaskRows)
    }

    /// User bubble for the live exchange — prefers the mirrored live turn,
    /// then in-flight prompt, then the sheet's initial prompt when empty.
    private var liveUserPrompt: String? {
        if let live = LiveThreadTranscript.liveTurn(turns: bridge.transcriptTurns, liveTurnID: liveTurnID) {
            guard LiveThreadTranscript.shouldRenderPromptBubble(for: live) else { return nil }
            return live.prompt
        }
        if let inFlight = bridge.inFlightPrompt {
            guard !LiveThreadTranscript.isObservedWrapperUserText(inFlight) else { return nil }
            return inFlight
        }
        if bridge.transcriptTurns.isEmpty, LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
            guard !LiveThreadTranscript.isObservedWrapperUserText(prompt) else { return nil }
            return prompt
        }
        return nil
    }

    private var liveUserAttachments: [ConversationAttachmentReference] {
        if let live = LiveThreadTranscript.liveTurn(turns: bridge.transcriptTurns, liveTurnID: liveTurnID) {
            return live.attachments
        }
        return bridge.inFlightAttachments
    }

    private var streamingAssistantText: String {
        switch bridge.sendState {
        case .streaming(let turn), .completed(let turn):
            return turn.assistantText
        case .degraded(_, let turn):
            return turn?.assistantText ?? ""
        case .idle, .adoptedNoHistory, .working, .awaitingApproval, .failed:
            return ""
        }
    }

    private func scrollToTail(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.scrollTailID, anchor: .bottom)
        }
    }

    private func scrollToTailIfFollowing(_ proxy: ScrollViewProxy) {
        guard isNearBottom else { return }
        scrollToTail(proxy)
    }

    @ViewBuilder
    private func staticAssistant(_ turn: LancerCore.ChatTurn) -> some View {
        if turn.status == .failed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(turn.errorMessage ?? "Run failed")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                turnTranscriptBody(turn)
                if let diff = turnDiffByTurnID[turn.id], diff.hasChanges {
                    TurnDiffCard(summary: diff) {
                        reviewPresentation = ReviewPresentation(scope: .turn(turn.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func turnTranscriptBody(_ turn: LancerCore.ChatTurn) -> some View {
        let receipt = receiptsByRunID[turn.runID]
        let eventItems = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
        let artifactChips = (toolArtifactsByTurnID[turn.id] ?? []).map(ToolChipItem.init(artifact:))
        let merged = mergeToolArtifacts(into: eventItems, artifacts: artifactChips)
        if merged.contains(where: {
            switch $0 {
            case .toolChip, .thinking: return true
            case .prose(let p): return !p.text.isEmpty
            }
        }) {
            TurnTranscriptItemsView(
                items: merged,
                emptyFallback: LiveThreadTranscript.assistantFallback(for: turn),
                activitySummary: activitySummary(for: turn, items: merged),
                receipt: receipt,
                turnIsTerminal: turn.status != .running
            )
        } else if let body = LiveThreadTranscript.assistantFallback(for: turn) {
            VStack(alignment: .leading, spacing: 12) {
                ChatMarkdownBody(markdown: body)
                if let summary = activitySummary(for: turn, items: []) {
                    TurnActivitySummaryRow(summary: summary, receipt: receipt)
                }
            }
        }
    }

    /// Post-turn activity row only after the turn leaves `.running`.
    private func activitySummary(
        for turn: LancerCore.ChatTurn,
        items: [TurnTranscriptItem]
    ) -> TurnActivitySummary? {
        guard turn.status != .running else { return nil }
        let startedAt = turn.createdAt
        let completedAt = turn.completedAt ?? Date()
        let turnSeconds = ToolChipGrouping.durationSeconds(
            startedAt: startedAt,
            completedAt: completedAt
        )
        if turnSeconds == 0, let events = eventsByTurnID[turn.id], !events.isEmpty {
            let times = events.map(\.createdAt)
            if let first = times.min(), let last = times.max(), last > first {
                return TurnActivitySummary.make(
                    from: items,
                    startedAt: first,
                    completedAt: last
                )
            }
        }
        return TurnActivitySummary.make(
            from: items,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    private func hasAssistantArtifacts(for turn: LancerCore.ChatTurn) -> Bool {
        let eventItems = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
        let artifactChips = (toolArtifactsByTurnID[turn.id] ?? []).map(ToolChipItem.init(artifact:))
        let merged = mergeToolArtifacts(into: eventItems, artifacts: artifactChips)
        let hasTranscriptItems = merged.contains {
            switch $0 {
            case .toolChip, .thinking:
                return true
            case .prose(let prose):
                return !prose.text.isEmpty
            }
        }
        return hasTranscriptItems
            || receiptsByRunID[turn.runID] != nil
            || turnDiffByTurnID[turn.id]?.hasChanges == true
    }

    /// Prefer structured event chips; append live tool artifacts not already paired by toolUseId.
    private func mergeToolArtifacts(
        into items: [TurnTranscriptItem],
        artifacts: [ToolChipItem]
    ) -> [TurnTranscriptItem] {
        guard !artifacts.isEmpty else { return items }
        let existingIDs = Set(items.compactMap { item -> String? in
            if case .toolChip(let chip) = item { return chip.toolUseId }
            return nil
        })
        var merged = items
        for artifact in artifacts where !existingIDs.contains(artifact.toolUseId) {
            merged.append(.toolChip(artifact))
        }
        // If events had no prose but the turn has assistantText, keep prose from assistantText.
        let hasProse = merged.contains {
            if case .prose(let p) = $0 { return !p.text.isEmpty }
            return false
        }
        if !hasProse {
            // Caller supplies assistantText via emptyFallback / separate path when merged is tool-only.
        }
        return merged
    }

    /// Stable token so receipt refresh re-runs when turns land or complete.
    private var receiptRefreshToken: String {
        bridge.transcriptTurns.map { "\($0.runID):\($0.status.rawValue)" }.joined(separator: "|")
    }

    private func refreshReceipts() async {
        var next: [String: ProofReceipt] = [:]
        for turn in bridge.transcriptTurns {
            if let receipt = await workspaceData.receipt(
                runID: turn.runID,
                conversationID: turn.conversationID
            ) {
                next[turn.runID] = receipt
            }
        }
        receiptsByRunID = next
    }

    private func refreshTranscriptExtras() async {
        guard let conversationID = bridge.activeConversationID else { return }
        // Reuse one DB handle per view — openShared() builds a fresh
        // DatabasePool each call, and this runs on every turn-count change.
        if extrasRepo == nil, let db = try? AppDatabase.openShared() {
            extrasRepo = ChatConversationRepository(db)
        }
        guard let repo = extrasRepo else { return }
        let events = (try? await repo.events(conversationID: conversationID, limit: 10_000)) ?? []
        eventsByTurnID = Dictionary(grouping: events.filter { $0.turnID != nil }, by: { $0.turnID! })
        let artifacts = (try? await repo.artifacts(conversationID: conversationID)) ?? []
        toolArtifactsByTurnID = Dictionary(
            grouping: artifacts.filter { $0.kind == .tool },
            by: \.turnID
        )
    }

    private func refreshReviewDiffs() async {
        let conversationID = bridge.activeConversationID ?? "fixture"
        let pending = bridge.transcriptTurns.filter {
            $0.status != .failed && turnDiffByTurnID[$0.id] == nil
        }
        var next = turnDiffByTurnID
        let source = reviewDataSource
        await withTaskGroup(of: (String, RepoDiffSummary?).self) { group in
            let cap = 4
            var iterator = pending.makeIterator()
            var inFlight = 0
            func enqueueNext() {
                while inFlight < cap, let turn = iterator.next() {
                    inFlight += 1
                    let turnID = turn.id
                    group.addTask {
                        let diff = try? await source.turnDiff(
                            conversationID: conversationID,
                            turnID: turnID
                        )
                        return (turnID, (diff?.hasChanges == true) ? diff : nil)
                    }
                }
            }
            enqueueNext()
            for await (turnID, diff) in group {
                inFlight -= 1
                if let diff {
                    next[turnID] = diff
                }
                enqueueNext()
            }
        }
        turnDiffByTurnID = next
        if let session = try? await reviewDataSource.sessionDiff(conversationID: conversationID),
           session.hasChanges {
            sessionDiff = session
        } else {
            sessionDiff = nil
        }
    }

    private var reviewCommentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(queuedReviewComments) { comment in
                    HStack(spacing: 6) {
                        Text(comment.chipLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Button {
                            queuedReviewComments.removeAll { $0.id == comment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove comment"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemFill)))
                }
            }
        }
        .accessibilityIdentifier("review-comment-chips")
    }

    // MARK: - Reply state (Orca rule: working indicator and visible reply text
    // are mutually exclusive on screen — except degraded, which never claims
    // "Working…" over stale data)

    @ViewBuilder
    private var replyState: some View {
        switch bridge.sendState {
        case .idle:
            EmptyView()
        case .adoptedNoHistory:
            Text("Connected to this session — no history synced yet. Send a message to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("adopted-no-history-placeholder")
        case .working:
            Group {
                if let text = liveStatusPillText(hasVisibleReplyText: false, isTerminalOrIdle: false) {
                    LiveStatusPill(text: text)
                } else {
                    workingIndicator
                }
            }
            .onAppear { streamingPacer.reset() }
        case .awaitingApproval(let message):
            awaitingApprovalCard(message)
                .onAppear { streamingPacer.reset() }
        case .streaming(let turn):
            VStack(alignment: .leading, spacing: 12) {
                liveToolChips(for: turn)
                let hasText = !turn.assistantText.isEmpty || !streamingPacer.displayText.isEmpty
                if let text = liveStatusPillText(hasVisibleReplyText: hasText, isTerminalOrIdle: false) {
                    LiveStatusPill(text: text)
                }
                streamingAssistantBody(target: turn.assistantText)
            }
        case .completed(let turn):
            if !LiveThreadTranscript.shouldRenderTurn(
                turn,
                hasAssistantArtifacts: hasAssistantArtifacts(for: turn)
            ) {
                EmptyView()
            } else if turn.status == .failed {
                errorState(turn.errorMessage ?? "Run failed")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    turnTranscriptBody(turn)
                        .onAppear { streamingPacer.reset(to: turn.assistantText) }
                    if let diff = turnDiffByTurnID[turn.id], diff.hasChanges {
                        TurnDiffCard(summary: diff) {
                            reviewPresentation = ReviewPresentation(scope: .turn(turn.id))
                        }
                    }
                }
            }
        case .failed(let message):
            errorState(message)
                .onAppear { streamingPacer.reset() }
        case .degraded(let message, let turn):
            VStack(alignment: .leading, spacing: 12) {
                if let turn, !turn.assistantText.isEmpty {
                    // Keep paced text if we were mid-reveal; otherwise show persisted.
                    let body = streamingPacer.displayText.isEmpty
                        ? turn.assistantText
                        : ChatStreamingTextSmoother.resolvedDisplayText(
                            overlayResponse: streamingPacer.displayText,
                            persistedAssistantText: turn.assistantText
                        )
                    if streamingPacer.isSettled {
                        ChatMarkdownBody(markdown: body)
                    } else {
                        streamingPlainText(streamingPacer.displayText.isEmpty ? body : streamingPacer.displayText)
                    }
                }
                degradedBanner(message)
            }
        }
    }

    private func liveStatusPillText(hasVisibleReplyText: Bool, isTerminalOrIdle: Bool) -> String? {
        LiveStatusPresentation.displayText(
            event: liveRunStatus,
            firstEventAt: liveStatusFirstAt,
            lastEventAt: liveStatusLastAt,
            now: liveStatusNow,
            hasVisibleReplyText: hasVisibleReplyText,
            isTerminalOrIdle: isTerminalOrIdle
        )
    }

    private func clearLiveRunStatus() {
        liveRunStatus = nil
        liveStatusFirstAt = nil
        liveStatusLastAt = nil
    }

    private func ingestLiveRunStatus(_ params: LiveRunStatusParams) {
        let at = LiveStatusPresentation.parseEventDate(params.at) ?? .now
        if liveStatusFirstAt == nil {
            liveStatusFirstAt = at
        }
        liveStatusLastAt = at
        liveRunStatus = params
        liveStatusNow = .now
    }

    @MainActor
    private func observeLiveRunStatus() async {
        let clock = ContinuousClock()
        let statusTask = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(
                named: Notification.Name("lancerE2ELiveRunStatus")
            ) {
                guard let params = notification.userInfo?["params"] as? LiveRunStatusParams else {
                    continue
                }
                let eventMachineID = (notification.userInfo?["machineID"] as? RelayMachineID)?.raw
                guard LiveStatusPresentation.shouldAcceptLiveRunStatus(
                    eventRunID: params.runId,
                    eventMachineID: eventMachineID,
                    liveTurnRunID: liveTurnRunID,
                    activeMachineID: bridge.activeMachineID?.raw
                ) else {
                    continue
                }
                ingestLiveRunStatus(params)
            }
        }
        defer { statusTask.cancel() }

        while !Task.isCancelled {
            liveStatusNow = .now
            try? await clock.sleep(for: .seconds(1))
        }
    }

    private var liveTurnRunID: String? {
        LiveThreadTranscript.liveTurn(turns: bridge.transcriptTurns, liveTurnID: liveTurnID)?.runID
    }

    /// Character/word-paced reveal between poll deltas; markdown only after settle.
    @ViewBuilder
    private func streamingAssistantBody(target: String) -> some View {
        Group {
            if streamingPacer.isSettled, !streamingPacer.markdownText.isEmpty {
                ChatMarkdownBody(markdown: streamingPacer.markdownText)
            } else if !streamingPacer.displayText.isEmpty {
                streamingPlainText(streamingPacer.displayText)
            } else if !target.isEmpty {
                streamingPlainText(target)
            } else {
                EmptyView()
            }
        }
        .onAppear { streamingPacer.ingest(target) }
        .onChange(of: target) { _, newValue in
            streamingPacer.ingest(newValue)
        }
    }

    @ViewBuilder
    private func liveToolChips(for turn: LancerCore.ChatTurn) -> some View {
        let eventItems = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
        let artifactChips = (toolArtifactsByTurnID[turn.id] ?? []).map(ToolChipItem.init(artifact:))
        let merged = mergeToolArtifacts(into: eventItems, artifacts: artifactChips)
        let turnIsTerminal = turn.status != .running
        let chips = merged.compactMap { item -> ToolChipItem? in
            if case .toolChip(let chip) = item { return chip }
            return nil
        }
        let thinking = merged.compactMap { item -> TurnThinkingItem? in
            if case .thinking(let t) = item { return t }
            return nil
        }
        if !thinking.isEmpty || !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(thinking) { row in
                    ThinkingRow(text: row.text)
                }
                if !chips.isEmpty {
                    let grouped = ToolChipGrouping.displayGroups(
                        from: chips.map { .toolChip($0) },
                        turnIsTerminal: turnIsTerminal
                    )
                    ForEach(grouped) { item in
                        if case .toolChips(let group) = item {
                            ToolCallChipView(chips: group, turnIsTerminal: turnIsTerminal)
                        }
                    }
                }
            }
        }
    }

    private func streamingPlainText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.interpolate)
            .animation(.easeOut(duration: 0.08), value: text)
    }

    private var workingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Working…")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private func awaitingApprovalCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("awaiting-approval-card")
    }

    private func degradedBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn't get a reply")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    switch LiveThreadErrorRetryPolicy.resolve(
                        hasLastAttempt: bridge.lastAttempt != nil,
                        shouldSendInitialPrompt: LiveThreadTranscript.shouldSendInitialPrompt(prompt),
                        initialAttachments: initialAttachments
                    ) {
                    case .retryLastAttempt:
                        await bridge.retryLastAttempt()
                    case .sendInitial(let attachments):
                        await bridge.send(prompt: prompt, cwd: cwd, attachments: attachments)
                    case .adoptObserved:
                        await bridge.adoptArmedObservedContinue(fallbackCwd: cwd)
                    }
                }
            }
            .font(.system(size: 14, weight: .medium))
        }
    }

    // MARK: - Pending approval card (M4)

    /// The most recent pending approval that arrived from the same paired
    /// machine this thread is talking to — see `RelayApprovalIngest`'s doc
    /// comment for why this is machine-scoped, not strictly run-scoped.
    private var pendingApproval: Approval? {
        guard let machineID = bridge.activeMachineID,
              let approval = approvalIngest.latestPendingApproval[machineID],
              approval.isPending
        else { return nil }
        return approval
    }

    /// CC-6: compact inline row that replaces the old inline approve/deny
    /// card. Tapping it (or the auto-present `onChange` below) opens
    /// `ApprovalDecisionSheet`, which owns the actual decision buttons.
    private func approvalPendingRow(_ approval: Approval, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Waiting on approval — \(approvalSummaryText(approval)) \u{203A}")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                riskLabel(approval.risk)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("approval-pending-row")
    }

    private func approvalSummaryText(_ approval: Approval) -> String {
        approval.command ?? approval.patch ?? approval.kind.rawValue.capitalized
    }

    /// Wires `ApprovalDecisionSheet`'s buttons to the exact same
    /// `RelayApprovalIngest.decide` call the old inline card made — see the
    /// sheet's doc comment for the plumbing guarantee.
    private func decideApproval(_ approval: Approval, decision: Approval.Decision) {
        guard let machineID = bridge.activeMachineID else { return }
        Task { await approvalIngest.decide(approval, decision: decision, machineID: machineID) }
    }

    private func riskLabel(_ risk: Approval.Risk) -> some View {
        let (text, color): (String, Color) = {
            switch risk {
            case .low: return ("Low", .secondary)
            case .medium: return ("Medium", .secondary)
            case .high: return ("High", .orange)
            case .critical: return ("Critical", .red)
            }
        }()
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    // MARK: - Pending question card (in-thread questions)

    /// The most recent pending question that arrived from the same paired
    /// machine this thread is talking to — see `RelayQuestionIngest`'s doc
    /// comment for why this is machine-scoped, not strictly run-scoped.
    /// Orthogonal to `SendState` and `pendingApproval`, same rule M4
    /// established for the approval card: any combination can be visible at once.
    private var pendingQuestion: QuestionCardModel.PresentationState? {
        guard let machineID = bridge.activeMachineID,
              let question = questionIngest.latestPendingQuestion[machineID],
              !question.isAnswered
        else { return nil }
        return question
    }

    private func questionCard(_ question: QuestionCardModel.PresentationState, machineID: RelayMachineID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                Text("Question")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let caption = QuestionCardModel.confidenceCaption(question.confidence) {
                    Text(caption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(question.items.enumerated()), id: \.offset) { index, item in
                questionItem(item, itemIndex: index, allowFreeText: question.allowFreeText, machineID: machineID)
            }

            Button("Submit") {
                Task { await questionIngest.submit(machineID: machineID, relayFleetStore: relayFleetStore) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!QuestionCardModel.isReadyToAnswer(question))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func questionItem(
        _ item: QuestionCardModel.ItemState,
        itemIndex: Int,
        allowFreeText: Bool,
        machineID: RelayMachineID
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = item.header {
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.question)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            ForEach(item.options, id: \.label) { option in
                Button {
                    questionIngest.toggleOption(machineID: machineID, itemIndex: itemIndex, label: option.label)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.isSelected(option.label) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isSelected(option.label) ? Color.blue : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                            if let description = option.description {
                                Text(description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if item.options.isEmpty || allowFreeText {
                TextField(
                    item.options.isEmpty ? "Type your answer…" : "Or type a free-text answer…",
                    text: Binding(
                        get: { item.freeText },
                        set: { questionIngest.setFreeText(machineID: machineID, itemIndex: itemIndex, text: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
            }
        }
    }

    // MARK: - Follow-up composer (Cursor docked bar chrome; same send path)

    /// Chip row only — context attach opens from the composer `+` (not a separate Attach label).
    @ViewBuilder
    private var followUpAttachmentChips: some View {
        if !followUpAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(followUpAttachments) { draft in
                        AttachmentChipView(draft: draft) {
                            removeFollowUpAttachment(draft)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
    }

    private func removeFollowUpAttachment(_ draft: AttachmentDraft) {
        followUpAttachments.removeAll { $0.id == draft.id }
        if case .uploading = draft.state {
            followUpUploadTask?.cancel()
            followUpUploadTask = nil
            isUploadingAttachments = false
        }
    }

    /// Writes progress/state updates without restoring chips the user removed.
    private func publishFollowUpDrafts(_ drafts: inout [AttachmentDraft]) {
        let surviving = Set(followUpAttachments.map(\.id))
        drafts.removeAll { !surviving.contains($0.id) }
        followUpAttachments = drafts
    }

    private func sendFollowUp() async {
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let composed = ReviewCommentFormatting.composerPrefix(
            comments: queuedReviewComments,
            prompt: text
        )
        guard !composed.isEmpty, bridge.canAcceptFollowUp, canSendFollowUpWithAttachments else { return }

        var drafts = followUpAttachments
        if !drafts.isEmpty {
            isUploadingAttachments = true
            let sshChannel = ApprovalRelay.shared.channel
            let relayMachine = relayFleetStore.machines.first(where: { $0.id == bridge.activeMachineID })
                ?? relayFleetStore.firstConnectedMachine
            guard sshChannel != nil || relayMachine != nil else {
                drafts = drafts.map { draft in
                    guard case .pending = draft.state else { return draft }
                    var copy = draft
                    copy.state = .error(message: AttachmentUploadError.noTransport.localizedDescription)
                    return copy
                }
                publishFollowUpDrafts(&drafts)
                isUploadingAttachments = false
                return
            }
            let conversationID = bridge.activeConversationID
            for draft in drafts {
                if Task.isCancelled { isUploadingAttachments = false; return }
                guard followUpAttachments.contains(where: { $0.id == draft.id }) else { continue }
                guard case .pending = draft.state else { continue }
                drafts = AttachmentDraftStore.withState(
                    drafts, id: draft.id, state: .uploading(progress: 0)
                )
                publishFollowUpDrafts(&drafts)
                do {
                    let receipt = try await AttachmentUploader.upload(
                        draft: draft,
                        conversationId: conversationID,
                        sendChunk: { params in
                            try Task.checkCancellation()
                            return try await self.putAttachmentChunk(
                                params,
                                sshChannel: sshChannel,
                                relayBridge: relayMachine?.bridge
                            )
                        },
                        onProgress: { progress in
                            drafts = AttachmentDraftStore.withState(
                                drafts, id: draft.id, state: .uploading(progress: progress)
                            )
                            publishFollowUpDrafts(&drafts)
                        }
                    )
                    if Task.isCancelled || !followUpAttachments.contains(where: { $0.id == draft.id }) {
                        isUploadingAttachments = false
                        return
                    }
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .done(receipt)
                    )
                    publishFollowUpDrafts(&drafts)
                } catch is CancellationError {
                    isUploadingAttachments = false
                    return
                } catch {
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .error(message: error.localizedDescription)
                    )
                    publishFollowUpDrafts(&drafts)
                    isUploadingAttachments = false
                    return
                }
            }
            isUploadingAttachments = false
            guard AttachmentDraftStore.canSend(drafts) else { return }
        }

        let refs = AttachmentDraftStore.references(from: drafts)
        if !refs.isEmpty {
            if Task.isCancelled { return }
            await AttachmentLocalMediaStore.persistSentDrafts(
                drafts,
                previewCache: try? AttachmentPreviewCache()
            )
        }

        followUpText = ""
        followUpAttachments = []
        queuedReviewComments.removeAll()
        isFollowUpFocused = false
        if let conversationID = bridge.activeConversationID {
            await bridge.sendFollowUp(
                prompt: composed, conversationID: conversationID, cwd: cwd, attachments: refs
            )
            return
        }
        await bridge.send(prompt: composed, cwd: cwd, attachments: refs)
    }

    private func putAttachmentChunk(
        _ params: AttachmentUploader.ChunkParams,
        sshChannel: DaemonChannel?,
        relayBridge: E2ERelayBridge?
    ) async throws -> AttachmentUploader.ChunkResult {
        // The prompt dispatches to the conversation's relay machine (ShellLiveBridge),
        // so the file must land on that same host; SSH is the no-relay fallback.
        if let relayBridge {
            let result = try await relayBridge.relayPutAttachment(
                conversationId: params.conversationId,
                name: params.name,
                totalBytes: params.totalBytes,
                seq: params.seq,
                dataBase64: params.dataBase64,
                done: params.done
            )
            return AttachmentUploader.ChunkResult(
                id: result.id,
                path: result.path,
                contentDigest: result.contentDigest,
                error: result.error
            )
        }
        guard let sshChannel else { throw AttachmentUploadError.noTransport }
        let result = try await sshChannel.putAttachment(
            conversationId: params.conversationId,
            name: params.name,
            totalBytes: params.totalBytes,
            seq: params.seq,
            dataBase64: params.dataBase64,
            done: params.done
        )
        return AttachmentUploader.ChunkResult(
            id: result.id,
            path: result.path,
            contentDigest: result.contentDigest,
            error: result.error
        )
    }
}
#endif
