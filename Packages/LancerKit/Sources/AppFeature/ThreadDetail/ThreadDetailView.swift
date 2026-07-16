#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Thread detail for a real conversation row. Renders the local-mirror
/// transcript (user + assistant) with Flight Recorder per turn, plus follow-up
/// send into the thread's real cwd.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @Environment(ShellLiveBridge.self) private var bridge
    @Environment(RelayApprovalIngest.self) private var approvalIngest
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator
    /// Inline follow-up text, typed directly on this thread — mirrors
    /// LiveThreadView's own follow-up bar instead of popping the full New
    /// Chat composer (vendor/model pickers included) as a second sheet on
    /// top of an already-open thread.
    @State private var followUpText: String = ""
    @FocusState private var isFollowUpFocused: Bool
    /// True from the moment a follow-up is dispatched until it reaches a
    /// terminal state — drives an inline "sending" row instead of ever
    /// navigating to a separate screen (owner report 2026-07-15: every send
    /// was popping a full-screen "Chat" sheet with its own Close button on
    /// top of the thread the user was already looking at).
    @State private var isSendingFollowUp = false
    @State private var pendingFollowUpPrompt: String?
    @State private var followUpError: String?
    @State private var followUpDispatchGeneration = 0
    @State private var hasPerformedInitialScroll = false
    @State private var turns: [ChatTurn] = []
    @State private var eventsByTurnID: [String: [ChatEvent]] = [:]
    /// How many of the most-recent turns to render. Extended via "Show earlier…".
    @State private var visibleTurnLimit = Self.initialWindowSize
    @State private var showScrollToBottom = false
    @State private var turnDiffByTurnID: [String: RepoDiffSummary] = [:]
    @State private var sessionDiff: RepoDiffSummary?
    @State private var reviewPresentation: ReviewPresentation?
    @State private var queuedReviewComments: [QueuedReviewComment] = []
    @State private var transcriptRefreshFailed = false
    /// Bumped on open and each Retry so only the latest load may mutate the banner.
    @State private var transcriptLoadGeneration = 0
    @State private var transcriptLoadGate = TranscriptRefreshLoadGate()
    @State private var isBackgroundTasksPresented = false
    /// True while `refreshThreadFromHost` is in flight (not just local mirror read).
    @State private var isHostTranscriptRefreshing = false

    private static let initialWindowSize = 100
    private static let windowExtendStep = 100
    private static let scrollTailID = "thread-detail-tail"
    /// Same as LiveThreadView — never paint G2 fixture diffs on real threads.
    private var reviewDataSource: any ReviewDataSource {
        RelayReviewDataSource(bridge: relayFleetStore.firstConnectedMachine?.bridge)
    }

    let thread: ThreadListItem

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

    init(thread: ThreadListItem) {
        self.thread = thread
    }

    /// Most-recent `visibleTurnLimit` turns (oldest→newest within the window).
    private var visibleTurns: [ChatTurn] {
        guard turns.count > visibleTurnLimit else { return turns }
        return Array(turns.suffix(visibleTurnLimit))
    }

    private var renderedVisibleTurns: [ChatTurn] {
        visibleTurns.filter {
            LiveThreadTranscript.shouldRenderTurn(
                $0,
                hasAssistantArtifacts: hasAssistantArtifacts(for: $0)
            )
        }
    }

    /// Falls back to the sole connected machine when `bridge.activeMachineID`
    /// hasn't been set yet this app session (e.g. thread reopened cold after
    /// a relaunch, before any new send from this view) — a genuinely pending
    /// approval from before the relaunch must still surface (owner report
    /// 2026-07-15: two tool-use approvals sat unresolved with no card shown).
    private var pendingApprovalMachineID: RelayMachineID? {
        bridge.activeMachineID ?? relayFleetStore.firstConnectedMachine?.id
    }

    private var pendingApproval: Approval? {
        guard let machineID = pendingApprovalMachineID,
              let approval = approvalIngest.latestPendingApproval[machineID],
              approval.isPending
        else { return nil }
        return approval
    }

    private var hasEarlierTurns: Bool {
        turns.count > visibleTurnLimit
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Text(thread.title)
                                .font(.system(size: 22, weight: .bold))
                                .padding(.top, 16)

                            HStack(spacing: 8) {
                                Text(thread.statusLabel)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                if !thread.cwd.isEmpty {
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(thread.cwd)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            if isHostTranscriptRefreshing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Refreshing transcript…")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text("Refreshing transcript"))
                            }

                            if transcriptRefreshFailed {
                                InlineRetryBanner(
                                    title: "Transcript refresh failed or timed out.",
                                    message: "Cached turns stay available. Tap Retry to try again.",
                                    retryTitle: "Retry refresh",
                                    accessibilityRetryLabel: "Retry transcript refresh"
                                ) {
                                    transcriptLoadGeneration += 1
                                }
                            }

                            if turns.isEmpty && !isHostTranscriptRefreshing {
                                Text("No turns in the local mirror yet. Follow up below to continue in this repo.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !turns.isEmpty {
                                if hasEarlierTurns {
                                    Button {
                                        visibleTurnLimit = min(
                                            turns.count,
                                            visibleTurnLimit + Self.windowExtendStep
                                        )
                                    } label: {
                                        Text("Show earlier…")
                                            .font(.system(size: 15, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("Show earlier turns"))
                                }

                                ForEach(renderedVisibleTurns) { turn in
                                    VStack(alignment: .leading, spacing: 12) {
                                        if LiveThreadTranscript.shouldRenderPromptBubble(for: turn) {
                                            ChatUserBubble(
                                                text: turn.prompt,
                                                attachments: turn.attachments
                                            )
                                        }
                                        threadAssistant(turn)
                                        if let diff = turnDiffByTurnID[turn.id], diff.hasChanges {
                                            TurnDiffCard(summary: diff) {
                                                reviewPresentation = ReviewPresentation(scope: .turn(turn.id))
                                            }
                                        }
                                    }
                                }
                            }

                            if let pendingFollowUpPrompt {
                                VStack(alignment: .leading, spacing: 12) {
                                    ChatUserBubble(text: pendingFollowUpPrompt, attachments: [])
                                    if let followUpError {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                            Text(followUpError)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text("Working…")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("thread-detail-pending-followup")
                            }

                            ForEach(bridge.queuedFeedback.items) { item in
                                ChatUserBubble(
                                    text: item.text,
                                    attachments: item.attachments,
                                    isQueued: true
                                )
                            }

                            if let machineID = pendingApprovalMachineID, let pendingApproval {
                                ChatPendingApprovalCard(approval: pendingApproval, machineID: machineID)
                            }

                            // Tail marker doubles as the bar-clearance spacer
                            // (96pt): anchoring it .bottom lands the last
                            // message fully above the ZStack-overlaid follow-up
                            // bar, and its visibility drives the jump arrow
                            // (geometry math went stale under keyboard resize).
                            Color.clear
                                .frame(height: 96)
                                .id(Self.scrollTailID)
                                .onScrollVisibilityChange(threshold: 0.1) { visible in
                                    withAnimation { showScrollToBottom = !visible }
                                }
                        }
                        .padding(.horizontal, 20)
                    }
                    .overlay(alignment: .bottom) {
                        if showScrollToBottom {
                            ChatScrollToBottomButton {
                                // Two hops: land on the last lazy item to force
                                // tail layout, then anchor the true tail marker
                                // (direct marker scrollTo no-ops from far away;
                                // single-hop leaves the tail under the bar —
                                // both sim-reproduced).
                                if let last = renderedVisibleTurns.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                    withAnimation {
                                        proxy.scrollTo(Self.scrollTailID, anchor: .bottom)
                                    }
                                }
                            }
                            // This view's root ZStack overlays the follow-up bar
                            // on the scroll bottom; 108 clears it or the bar wins
                            // the hit test (sim-reproduced twice).
                            .padding(.bottom, 108)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    // Land at the tail by default when a thread first opens —
                    // it previously opened at the top, requiring a manual
                    // scroll or the jump-arrow tap every time (owner report
                    // 2026-07-15). Same two-hop technique as the jump arrow;
                    // only once per view instance (own turn appends already
                    // get the jump-arrow affordance, not a forced re-scroll).
                    .onChange(of: turns.count) { _, newValue in
                        guard !hasPerformedInitialScroll, newValue > 0 else { return }
                        hasPerformedInitialScroll = true
                        if let last = renderedVisibleTurns.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            proxy.scrollTo(Self.scrollTailID, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                if let sessionDiff {
                    SessionDiffPill(summary: sessionDiff) {
                        reviewPresentation = ReviewPresentation(scope: .session)
                    }
                }
                if !queuedReviewComments.isEmpty {
                    reviewCommentChips
                }
                if backgroundTasksRunningCount > 0 {
                    BackgroundTasksPill(runningCount: backgroundTasksRunningCount) {
                        isBackgroundTasksPresented = true
                    }
                }
                HStack {
                    ChatPermissionModePill()
                    Spacer(minLength: 0)
                }
                ChatFollowUpComposerBar(
                    text: $followUpText,
                    isFocused: $isFollowUpFocused,
                    placeholder: bridge.isSendInFlight ? "Add feedback…" : "Follow up…",
                    isDisabled: thread.cwd.isEmpty,
                    canSend: !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !thread.cwd.isEmpty,
                    onSend: {
                        let prompt = followUpText
                        followUpText = ""
                        handleSend(prompt, thread.cwd)
                    }
                )
                if !bridge.queuedFeedback.isEmpty {
                    Text("Will send when the agent finishes")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mid-run-feedback-caption")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isBackgroundTasksPresented) {
            BackgroundTasksSheet(rows: backgroundTaskRows)
        }
        .task(id: transcriptLoadGeneration) {
            await loadTurns()
        }
        .sheet(item: $reviewPresentation) { presentation in
            ReviewSheetView(
                conversationID: thread.id,
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
    }

    @ViewBuilder
    private func threadAssistant(_ turn: ChatTurn) -> some View {
        if turn.status == .failed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(turn.errorMessage ?? "Run failed")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        } else {
            let items = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
            if items.contains(where: {
                if case .toolChip = $0 { return true }
                if case .thinking = $0 { return true }
                return false
            }) || items.contains(where: {
                if case .prose(let p) = $0 { return !p.text.isEmpty }
                return false
            }) {
                TurnTranscriptItemsView(
                    items: items,
                    emptyFallback: LiveThreadTranscript.assistantFallback(for: turn)
                )
            } else if let body = LiveThreadTranscript.assistantFallback(for: turn) {
                ChatMarkdownBody(markdown: body)
            }
            // Same proof chip as the live view — reopened threads previously
            // dropped receipts entirely (owner report 2026-07-12).
            if let receipt = receiptForTurn(turn) {
                ReceiptChipRow(receipt: receipt)
            }
        }
    }

    private func hasAssistantArtifacts(for turn: ChatTurn) -> Bool {
        let items = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
        let hasTranscriptItems = items.contains {
            switch $0 {
            case .toolChip, .thinking:
                return true
            case .prose(let prose):
                return !prose.text.isEmpty
            }
        }
        return hasTranscriptItems
            || receiptForTurn(turn) != nil
            || turnDiffByTurnID[turn.id]?.hasChanges == true
    }

    private func receiptForTurn(_ turn: ChatTurn) -> ProofReceipt? {
        guard let event = (eventsByTurnID[turn.id] ?? []).last(where: { $0.kind == "receipt" }),
              let payload = event.payloadJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProofReceipt.self, from: payload)
    }


    private func loadTurns() async {
        guard thread.id != "preview" else { return }
        let loadToken = transcriptLoadGate.beginLoad()
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        turns = (try? await repo.turns(conversationID: thread.id)) ?? []
        let localEvents = (try? await repo.events(conversationID: thread.id, limit: 10_000)) ?? []
        eventsByTurnID = Dictionary(grouping: localEvents.filter { $0.turnID != nil }, by: { $0.turnID! })
        // Always reconcile on open. Older builds could create turn skeletons
        // while incorrectly advancing the event cursor from a list summary;
        // checking only `turns.isEmpty` made that poisoned mirror permanent.
        // Local events render before this await so offline opens do not hide
        // already-hydrated tool or assistant content during the timeout.
        if let refresh = workspaceData.refreshThreadFromHost {
            isHostTranscriptRefreshing = true
            defer { isHostTranscriptRefreshing = false }
            do {
                try await refresh(thread.id)
                guard !Task.isCancelled else { return }
                if transcriptLoadGate.clearBanner(onSuccessFor: loadToken) {
                    transcriptRefreshFailed = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Ephemeral banner only — coordinator publishes `.cloudStale`
                // for refresh timeouts without claiming the machine is offline.
                if transcriptLoadGate.setBanner(failedFor: loadToken) {
                    transcriptRefreshFailed = true
                }
            }
            guard !Task.isCancelled, transcriptLoadGate.allowsMutation(loadToken) else { return }
            turns = (try? await repo.turns(conversationID: thread.id)) ?? []
        }
        guard !Task.isCancelled, transcriptLoadGate.allowsMutation(loadToken) else { return }
        let events = (try? await repo.events(conversationID: thread.id, limit: 10_000)) ?? []
        eventsByTurnID = Dictionary(grouping: events.filter { $0.turnID != nil }, by: { $0.turnID! })
        await loadReviewDiffs()
    }

    private func loadReviewDiffs() async {
        let pending = turns.filter { $0.status != .failed && turnDiffByTurnID[$0.id] == nil }
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
                    let conversationID = thread.id
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
        if let session = try? await reviewDataSource.sessionDiff(conversationID: thread.id),
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

    private func handleSend(_ prompt: String, _ cwd: String, _ attachments: [ConversationAttachmentReference] = []) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(normalized) else { return }
        let composed = ReviewCommentFormatting.composerPrefix(
            comments: queuedReviewComments,
            prompt: prompt
        )
        queuedReviewComments.removeAll()
        // Mid-run: bridge enqueues and returns immediately — don't paint the
        // inline "Working…" row for queued guidance.
        let enqueueOnly = bridge.isSendInFlight
        followUpDispatchGeneration += 1
        let generation = followUpDispatchGeneration
        if !enqueueOnly {
            pendingFollowUpPrompt = composed
            followUpError = nil
            isSendingFollowUp = true
        }
        Task {
            await bridge.sendFollowUp(
                prompt: composed,
                conversationID: thread.id,
                cwd: normalized,
                attachments: attachments
            )
            guard generation == followUpDispatchGeneration else { return }
            if enqueueOnly { return }
            isSendingFollowUp = false
            if case .failed(let message) = bridge.sendState {
                followUpError = message
            } else {
                pendingFollowUpPrompt = nil
                followUpError = nil
                transcriptLoadGeneration += 1
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            VStack(spacing: 1) {
                Text(thread.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(thread.repoName ?? WorkspaceRepoCatalog.displayName(forCwd: thread.cwd))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)

            Spacer()

            Menu {
                Button {
                    openTerminalAtCWD()
                } label: {
                    Label("Open terminal at this cwd", systemImage: "terminal")
                }
                .disabled(thread.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || relayFleetStore.firstConnectedMachine == nil)

                NavigationLink {
                    FlightRecorderTurnListView(thread: thread, turns: turns)
                } label: {
                    Label("Flight Recorder", systemImage: "waveform.path.ecg")
                }
            } label: {
                circleButton(systemImage: "ellipsis")
            }
            .accessibilityLabel(Text("Thread options"))
        }
    }

    private var backgroundTaskRows: [BackgroundTasksPresentation.TaskRow] {
        var rows: [BackgroundTasksPresentation.TaskRow] = []
        for turn in turns {
            let items = TurnTranscriptAssembler.items(from: eventsByTurnID[turn.id] ?? [])
            rows.append(contentsOf: BackgroundTasksPresentation.rows(
                items: items,
                events: eventsByTurnID[turn.id] ?? []
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

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }

    private func openTerminalAtCWD() {
        guard let startupCommand = TerminalShellCommand.cdToWorkingDirectory(thread.cwd) else { return }
        let cwd = thread.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        terminalCoordinator.openOnFirstConnectedMachine(
            cwd: cwd.isEmpty ? nil : cwd,
            startupCommand: startupCommand
        )
    }
}

/// Thread-level Flight Recorder entry: one row per turn, each opening that
/// turn's event timeline. Replaces the per-turn rows that repeated after
/// every reply (owner feedback 2026-07-12) now that tool chips render inline.
struct FlightRecorderTurnListView: View {
    let thread: ThreadListItem
    let turns: [ChatTurn]

    var body: some View {
        List(turns) { turn in
            NavigationLink {
                FlightRecorderView(
                    conversationID: thread.id,
                    turnID: turn.id,
                    prompt: turn.prompt,
                    runID: turn.runID
                )
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn \(turn.ordinal)")
                        .font(.system(size: 15, weight: .medium))
                    Text(turn.prompt)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle("Flight Recorder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Transcript refresh load gate

/// Generation gate so only the latest ThreadDetail load attempt may set or
/// clear the ephemeral refresh-failed banner (stale late failures cannot
/// overwrite a newer success; success clears a previous error).
public final class TranscriptRefreshLoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    public init() {}

    @discardableResult
    public func beginLoad() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    public func allowsMutation(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation
    }

    public func clearBanner(onSuccessFor token: UInt64) -> Bool {
        allowsMutation(token)
    }

    public func setBanner(failedFor token: UInt64) -> Bool {
        allowsMutation(token)
    }
}

// MARK: - Shared helpers (used by ThreadDetailView + PRDetailView)

func fileBadge(_ text: String) -> some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(.tertiarySystemFill))
        .frame(width: 28, height: 20)
        .overlay(
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        )
}

func diffStatText(added: Int, removed: Int) -> Text {
    chatDiffStatText(added: added, removed: removed)
}

#Preview {
    NavigationStack {
        ThreadDetailView(
            thread: ThreadListItem(
                id: "preview",
                title: "Untitled thread",
                statusKind: .idle,
                statusLabel: "No activity",
                repoName: nil,
                cwd: "/tmp/demo",
                lastActivityAt: .now
            )
        )
    }
}
#endif
