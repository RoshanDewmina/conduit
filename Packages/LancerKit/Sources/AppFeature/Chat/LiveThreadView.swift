#if os(iOS)
import SwiftUI
import LancerCore
import Foundation
import PersistenceKit
import SessionFeature

/// M3: the real, live conversation view — reached only from the New Chat
/// composer's send action (a brand-new conversation flow). This is
/// deliberately separate from `ThreadDetailView` (Section 7's static,
/// owner-approved PR-review-style mockup for browsing sample thread rows) —
/// see the M3 brief's scope boundary. Apple-native `NavigationStack` /
/// `ScrollView` / `TextField` only, no DesignSystem module.
///
/// M4: also renders a pending-approval card (see `approvalCard`) — a fully
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

    @State private var hasSentInitialPrompt = false
    @State private var followUpText: String = ""
    @State private var streamingPacer = ChatStreamingTextPacer()
    @State private var receiptsByRunID: [String: ProofReceipt] = [:]
    @State private var eventsByTurnID: [String: [ChatEvent]] = [:]
    @State private var toolArtifactsByTurnID: [String: [ChatArtifact]] = [:]
    @State private var showScrollToBottom = false
    @State private var isNearBottom = true
    /// Ephemeral runStatus events from the daemon (G3). Absent → legacy Working….
    @State private var liveRunStatus: LiveRunStatusParams?
    @State private var liveStatusFirstAt: Date?
    @State private var liveStatusLastAt: Date?
    @State private var liveStatusNow: Date = .now
    @FocusState private var isFollowUpFocused: Bool
    #if DEBUG
    @State private var hasAutoAnsweredQuestion = false
    @State private var hasAutoFollowedUp = false
    #endif

    private static let scrollTailID = "live-tail"

    public init(prompt: String, cwd: String) {
        self.prompt = prompt
        self.cwd = cwd
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(priorTurns) { turn in
                                ChatUserBubble(text: turn.prompt)
                                staticAssistant(turn)
                            }

                            if let liveUserPrompt {
                                ChatUserBubble(text: liveUserPrompt)
                            }

                            replyState
                                .id(Self.scrollTailID)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                    .onScrollGeometryChange(for: Double.self) { geometry in
                        ChatScrollPolicy.distanceFromBottom(
                            contentHeight: geometry.contentSize.height,
                            viewportHeight: geometry.containerSize.height,
                            contentOffsetY: geometry.contentOffset.y
                        )
                    } action: { _, distance in
                        isNearBottom = ChatScrollPolicy.isNearBottom(distanceFromBottom: distance)
                        showScrollToBottom = ChatScrollPolicy.shouldShowJumpToLatest(
                            distanceFromBottom: distance
                        )
                    }
                    .onChange(of: bridge.sendState) { _, _ in
                        scrollToTailIfFollowing(proxy)
                    }
                    .onChange(of: bridge.transcriptTurns.count) { _, _ in
                        scrollToTailIfFollowing(proxy)
                        Task { await refreshTranscriptExtras() }
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
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToBottom {
                            ChatScrollToBottomButton {
                                isNearBottom = true
                                showScrollToBottom = false
                                scrollToTail(proxy)
                            }
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }

                if let machineID = bridge.activeMachineID, let pendingApproval {
                    approvalCard(pendingApproval, machineID: machineID)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if let machineID = bridge.activeMachineID, let pendingQuestion {
                    questionCard(pendingQuestion, machineID: machineID)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                ChatFollowUpComposerBar(
                    text: $followUpText,
                    isFocused: $isFollowUpFocused,
                    isDisabled: bridge.isSendInFlight,
                    canSend: canSendFollowUp,
                    onSend: sendFollowUp
                )
            }
            .background(Color(.systemBackground))
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            guard !hasSentInitialPrompt else { return }
            hasSentInitialPrompt = true
            if LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
                await bridge.send(prompt: prompt, cwd: cwd)
            } else {
                await bridge.adoptArmedObservedContinue(fallbackCwd: cwd)
                if case .idle = bridge.sendState {
                    isFollowUpFocused = true
                }
            }
        }
        .task {
            await observeLiveRunStatus()
        }
        .onChange(of: bridge.sendState) { _, newValue in
            let phase: LiveStatusSendPhase
            switch newValue {
            case .idle: phase = .idle
            case .working: phase = .working
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { note in
            let conversationID = note.userInfo?["conversationID"] as? String
            guard conversationID == nil || conversationID == bridge.activeConversationID else { return }
            Task {
                await refreshReceipts()
                await refreshTranscriptExtras()
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
        !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bridge.isSendInFlight
            && bridge.canAcceptFollowUp
    }

    /// Turn id currently bound to `sendState` (streaming / completed / degraded /
    /// in-flight running / failed). Priors render frozen; this one uses replyState.
    private var liveTurnID: String? {
        switch bridge.sendState {
        case .streaming(let turn), .completed(let turn):
            return turn.id
        case .degraded(_, let turn):
            return turn?.id
        case .working:
            return bridge.transcriptTurns.last(where: { $0.status == .running })?.id
        case .failed:
            return bridge.transcriptTurns.last(where: { $0.status == .failed })?.id
        case .idle:
            return nil
        }
    }

    private var priorTurns: [LancerCore.ChatTurn] {
        LiveThreadTranscript.priorTurns(turns: bridge.transcriptTurns, liveTurnID: liveTurnID)
    }

    /// User bubble for the live exchange — prefers the mirrored live turn,
    /// then in-flight prompt, then the sheet's initial prompt when empty.
    private var liveUserPrompt: String? {
        if let live = LiveThreadTranscript.liveTurn(turns: bridge.transcriptTurns, liveTurnID: liveTurnID) {
            return live.prompt
        }
        if let inFlight = bridge.inFlightPrompt {
            return inFlight
        }
        if bridge.transcriptTurns.isEmpty, LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
            return prompt
        }
        return nil
    }

    private var streamingAssistantText: String {
        switch bridge.sendState {
        case .streaming(let turn), .completed(let turn):
            return turn.assistantText
        case .degraded(_, let turn):
            return turn?.assistantText ?? ""
        case .idle, .working, .failed:
            return ""
        }
    }

    private func scrollToTail(_ proxy: ScrollViewProxy) {
        withAnimation {
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
                if let receipt = receiptsByRunID[turn.runID] {
                    ReceiptCardView(receipt: receipt)
                }
            }
        }
    }

    @ViewBuilder
    private func turnTranscriptBody(_ turn: LancerCore.ChatTurn) -> some View {
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
                emptyFallback: turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText
            )
        } else {
            let body = turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText
            ChatMarkdownBody(markdown: body)
        }
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
        guard let conversationID = bridge.activeConversationID,
              let db = try? AppDatabase.openShared()
        else { return }
        let repo = ChatConversationRepository(db)
        let events = (try? await repo.events(conversationID: conversationID, limit: 10_000)) ?? []
        eventsByTurnID = Dictionary(grouping: events.filter { $0.turnID != nil }, by: { $0.turnID! })
        let artifacts = (try? await repo.artifacts(conversationID: conversationID)) ?? []
        toolArtifactsByTurnID = Dictionary(
            grouping: artifacts.filter { $0.kind == .tool },
            by: \.turnID
        )
    }

    // MARK: - Reply state (Orca rule: working indicator and visible reply text
    // are mutually exclusive on screen — except degraded, which never claims
    // "Working…" over stale data)

    @ViewBuilder
    private var replyState: some View {
        switch bridge.sendState {
        case .idle:
            EmptyView()
        case .working:
            Group {
                if let text = liveStatusPillText(hasVisibleReplyText: false, isTerminalOrIdle: false) {
                    LiveStatusPill(text: text)
                } else {
                    workingIndicator
                }
            }
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
            if turn.status == .failed {
                errorState(turn.errorMessage ?? "Run failed")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    turnTranscriptBody(turn)
                        .onAppear { streamingPacer.reset(to: turn.assistantText) }
                    if let receipt = receiptsByRunID[turn.runID] {
                        ReceiptCardView(receipt: receipt)
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
                    let grouped = TurnTranscriptAssembler.groupedForDisplay(
                        chips.map { .toolChip($0) }
                    )
                    ForEach(grouped) { item in
                        if case .toolChips(let group) = item {
                            ToolCallChipView(chips: group)
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
                    if bridge.lastAttempt != nil {
                        await bridge.retryLastAttempt()
                    } else if LiveThreadTranscript.shouldSendInitialPrompt(prompt) {
                        await bridge.send(prompt: prompt, cwd: cwd)
                    } else {
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

    private func approvalCard(_ approval: Approval, machineID: RelayMachineID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.blue)
                Text(approval.kind.rawValue.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                riskLabel(approval.risk)
            }
            Text(approval.command ?? approval.patch ?? "(no detail)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
            HStack(spacing: 12) {
                Button("Deny", role: .destructive) {
                    Task { await approvalIngest.decide(approval, decision: .rejected, machineID: machineID) }
                }
                .buttonStyle(.bordered)

                Button("Approve") {
                    Task { await approvalIngest.decide(approval, decision: .approved, machineID: machineID) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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

    private func sendFollowUp() {
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, bridge.canAcceptFollowUp else { return }
        followUpText = ""
        isFollowUpFocused = false
        // After empty-prompt adopt, `activeConversationID` is the synthetic
        // `observed:…` id and `sendFollowUp` routes through observed continue.
        if let conversationID = bridge.activeConversationID {
            Task { await bridge.sendFollowUp(prompt: text, conversationID: conversationID, cwd: cwd) }
            return
        }
        Task { await bridge.send(prompt: text, cwd: cwd) }
    }
}
#endif
