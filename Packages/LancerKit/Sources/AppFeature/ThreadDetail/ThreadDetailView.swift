#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Thread detail for a real conversation row. Renders the local-mirror
/// transcript (user + assistant) with Flight Recorder per turn, plus follow-up
/// send into the thread's real cwd.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @State private var isFollowUpPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?
    @State private var turns: [ChatTurn] = []
    @State private var eventsByTurnID: [String: [ChatEvent]] = [:]
    /// How many of the most-recent turns to render. Extended via "Show earlier…".
    @State private var visibleTurnLimit = Self.initialWindowSize
    @State private var showScrollToBottom = false
    @State private var turnDiffByTurnID: [String: RepoDiffSummary] = [:]
    @State private var sessionDiff: RepoDiffSummary?
    @State private var reviewPresentation: ReviewPresentation?
    @State private var queuedReviewComments: [QueuedReviewComment] = []

    private static let initialWindowSize = 100
    private static let windowExtendStep = 100
    private static let scrollTailID = "thread-detail-tail"
    /// Same as LiveThreadView — never paint G2 fixture diffs on real threads.
    private var reviewDataSource: any ReviewDataSource { RelayReviewDataSource() }

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

                            if turns.isEmpty {
                                Text("No turns in the local mirror yet. Follow up below to continue in this repo.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
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

                                ForEach(visibleTurns.filter(LiveThreadTranscript.shouldRenderTurn)) { turn in
                                    VStack(alignment: .leading, spacing: 12) {
                                        if LiveThreadTranscript.shouldRenderPromptBubble(for: turn) {
                                            ChatUserBubble(text: turn.prompt)
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
                                if let last = visibleTurns.last {
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
                Button {
                    isFollowUpPresented = true
                } label: {
                    ChatFollowUpPlaceholderBar()
                }
                .buttonStyle(.plain)
                .disabled(thread.cwd.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadTurns() }
        .sheet(isPresented: $isFollowUpPresented) {
            NewChatComposerView(
                initialRepo: thread.cwd.isEmpty
                    ? nil
                    : WorkspaceRepo(
                        name: WorkspaceRepoCatalog.displayName(forCwd: thread.cwd),
                        cwd: thread.cwd,
                        threadCount: 0,
                        isUserAdded: false
                    ),
                lockRepo: true,
                onSend: handleSend
            )
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
        .liveThreadPresentation($activeLiveThread)
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
                    emptyFallback: turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText
                )
            } else {
                let body = turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText
                ChatMarkdownBody(markdown: body)
            }
            // Same proof chip as the live view — reopened threads previously
            // dropped receipts entirely (owner report 2026-07-12).
            if let receipt = receiptForTurn(turn) {
                ReceiptChipRow(receipt: receipt)
            }
        }
    }

    private func receiptForTurn(_ turn: ChatTurn) -> ProofReceipt? {
        guard let event = (eventsByTurnID[turn.id] ?? []).last(where: { $0.kind == "receipt" }),
              let payload = event.payloadJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProofReceipt.self, from: payload)
    }


    private func loadTurns() async {
        guard thread.id != "preview" else { return }
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        turns = (try? await repo.turns(conversationID: thread.id)) ?? []
        // Backfilled conversations carry summaries only — pull the turns and
        // events from the host on first open (fetch-on-open), then re-read.
        if turns.isEmpty, let refresh = workspaceData.refreshThreadFromHost {
            await refresh(thread.id)
            turns = (try? await repo.turns(conversationID: thread.id)) ?? []
        }
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

    private func handleSend(_ prompt: String, _ cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(normalized) else { return }
        let composed = ReviewCommentFormatting.composerPrefix(
            comments: queuedReviewComments,
            prompt: prompt
        )
        queuedReviewComments.removeAll()
        activeLiveThread = LiveThreadIdentifier(prompt: composed, cwd: normalized)
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

            HStack(spacing: 6) {
                Text(thread.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)

            Spacer()

            Menu {
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
