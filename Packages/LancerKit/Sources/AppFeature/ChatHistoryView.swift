#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import PersistenceKit
import LancerCore

/// Read-only transcript for a persisted conversation opened from the sidebar.
///
/// Compose and live-run state lives in `NewChatTabView`; history is deliberately
/// a separate, stateless view so reopening a past thread can never inherit a stale
/// `activeRun` or get stuck on a "thinking" indicator. It renders persisted turns
/// straight from the repository — it does not touch the shared `RunOutputStore`.
public struct ChatHistoryView: View {
    let conversationID: String
    let chatRepo: ChatConversationRepository?
    let runOutputStore: RunOutputStore?
    let onBack: () -> Void
    let onNewChat: () -> Void
    /// Resolves a live channel + new run to continue this conversation. AppRoot
    /// resolves the host's channel, calls continueRun, registers the new run, and
    /// returns the ActiveChatRun (or nil if the host is unreachable). nil disables
    /// resume — the view stays read-only.
    let onContinue: ((_ conversation: ChatConversation, _ lastRunID: String, _ prompt: String) async -> ActiveChatRun?)?

    @State private var conversation: ChatConversation?
    @State private var title: String = "chat"
    @State private var hostName: String = "relay"
    @State private var agentLabel: String = "Agent"
    @State private var turns: [LancerCore.ChatTurn] = []
    @State private var artifactsByRun: [String: [ChatArtifact]] = [:]
    @State private var selectedArtifact: ChatArtifact?
    @State private var loaded = false

    // Live continuation appended this session (rendered from runOutputStore, not
    // the repo). Persisted turns above render from their stored text.
    private struct LiveTurn: Identifiable { let prompt: String; let runID: String; var id: String { runID } }
    @State private var liveTurns: [LiveTurn] = []
    @State private var activeRun: ActiveChatRun?
    @State private var controlStore: RunControlStore?
    @State private var followUpText: String = ""
    @State private var resumeError: String?

    @Environment(\.lancerTokens) private var t

    public init(
        conversationID: String,
        chatRepo: ChatConversationRepository?,
        runOutputStore: RunOutputStore? = nil,
        onBack: @escaping () -> Void,
        onNewChat: @escaping () -> Void,
        onContinue: ((_ conversation: ChatConversation, _ lastRunID: String, _ prompt: String) async -> ActiveChatRun?)? = nil
    ) {
        self.conversationID = conversationID
        self.chatRepo = chatRepo
        self.runOutputStore = runOutputStore
        self.onBack = onBack
        self.onNewChat = onNewChat
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            DarkTranscriptHeader(
                title: title,
                subtitle: "\(agentLabel) · \(hostName)",
                isLive: false,
                onBack: { Haptics.selection(); onBack() },
                onWorkspace: { Haptics.selection(); onNewChat() },
                onNew: { Haptics.selection(); onNewChat() },
                shareText: { transcriptText() }
            )
            ConversationScrollView(bottomID: "history-bottom", scrollKey: turns.count + liveTurns.count + (runOutputStore?.run(activeRun?.runId ?? "")?.chunks.count ?? 0)) {
                VStack(alignment: .leading, spacing: 14) {
                    threadSummaryCard
                    if loaded && turns.isEmpty && liveTurns.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                            persistedTurnBlock(turn, ordinal: index + 1)
                        }
                        ForEach(Array(liveTurns.enumerated()), id: \.element.id) { index, turn in
                            liveTurnBlock(turn, ordinal: turns.count + index + 1)
                        }
                    }
                }
            }
            if canResume {
                RunFollowUpBar(
                    text: $followUpText,
                    isErrorState: false,
                    onSend: { followUp in Task { await sendFollowUp(followUp) } }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(t.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
            }
        }
        .background(t.bg.ignoresSafeArea())
        .task(id: conversationID) { await load() }
        .sheet(item: $selectedArtifact) { ChatArtifactDetailView(artifact: $0) }
        .alert("Couldn't continue", isPresented: Binding(
            get: { resumeError != nil }, set: { if !$0 { resumeError = nil } }
        )) {
            Button("OK", role: .cancel) { resumeError = nil }
        } message: { Text(resumeError ?? "") }
    }

    /// Resume is offered once the conversation has loaded and AppRoot supplied a
    /// continue resolver (i.e. a live transport is available).
    private var canResume: Bool { loaded && onContinue != nil && conversation != nil }

    /// A live continuation turn — renders from runOutputStore (streaming) in the
    /// same work-thread hierarchy as persisted turns.
    @ViewBuilder
    private func liveTurnBlock(_ turn: LiveTurn, ordinal: Int) -> some View {
        let run = runOutputStore?.run(turn.runID)
        WorkThreadTurnBlock(
            ordinal: ordinal,
            prompt: turn.prompt,
            status: .running,
            bodyText: run?.text ?? "",
            errorText: nil,
            createdAt: nil,
            completedAt: nil,
            artifacts: [],
            onArtifactTap: nil
        )
    }

    private func sendFollowUp(_ followUp: String) async {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conv = conversation, let onContinue else { return }
        followUpText = ""
        // Continue from the most recent run (a live turn this session, else the last
        // persisted turn). The daemon re-launches the vendor CLI under a new runId.
        let lastRunID = liveTurns.last?.runID ?? turns.last?.runID ?? ""
        guard let run = await onContinue(conv, lastRunID, trimmed) else {
            resumeError = "This machine is offline or no longer has this run. Open it from a connected host to continue."
            return
        }
        activeRun = run
        liveTurns.append(LiveTurn(prompt: trimmed, runID: run.runId))
        controlStore = RunControlStore(channel: run.channel, runId: run.runId)
        // A ledger-backed conversation's turn is already persisted by
        // `ConversationSyncCoordinator.continueConversation` (see `onContinue`
        // in AppRoot) — only legacy (pre-ledger) conversations need this
        // direct mirror write.
        if conv.syncState == .localOnly, let chatRepo {
            _ = try? await chatRepo.appendTurn(conversationID: conversationID, prompt: trimmed, runID: run.runId)
        }
    }

    private var threadSummaryCard: some View {
        let failedCount = turns.filter { $0.status == .failed }.count
        let runningCount = turns.filter { $0.status == .running }.count
        let artifactCount = artifactsByRun.values.reduce(0) { $0 + $1.count }
        let status: WorkThreadStatus = activeRun != nil || runningCount > 0 ? .running : failedCount > 0 ? .failed : loaded && turns.isEmpty && liveTurns.isEmpty ? .empty : loaded ? .completed : .loading
        return WorkThreadSummaryCard(
            title: title,
            status: status,
            machine: hostName,
            agent: agentLabel,
            cwd: conversation?.cwd,
            turnCount: turns.count + liveTurns.count,
            artifactCount: artifactCount
        )
    }

    @ViewBuilder
    private func persistedTurnBlock(_ turn: LancerCore.ChatTurn, ordinal: Int) -> some View {
        let text = turn.assistantText.isEmpty ? (turn.errorMessage ?? "") : turn.assistantText
        let artifacts = artifactsByRun[turn.runID] ?? []
        WorkThreadTurnBlock(
            ordinal: ordinal,
            prompt: turn.prompt,
            status: WorkThreadStatus(turn.status),
            bodyText: text,
            errorText: turn.status == .failed ? (turn.errorMessage ?? text) : nil,
            createdAt: turn.createdAt,
            completedAt: turn.completedAt,
            artifacts: artifacts,
            onArtifactTap: { artifact in
                Haptics.selection()
                selectedArtifact = artifact
            }
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSIconView(.list, size: 24, color: t.text4)
            Text("No activity in this work thread yet.")
                .font(.dsSansPt(15, weight: .semibold))
                .foregroundStyle(t.text)
            Text("Start a follow-up when this machine is connected. Lancer will show requests, agent progress, approvals, and artifacts here.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .padding(.top, 2)
    }

    /// Plain-text export of the conversation (persisted turns + this session's live
    /// turns), shared via the header's ShareLink.
    private func transcriptText() -> String {
        var out = "# \(title)\n\(agentLabel) · \(hostName)\n\n"
        for turn in turns {
            let reply = turn.assistantText.isEmpty ? (turn.errorMessage ?? "") : turn.assistantText
            out += "## Request\n\(turn.prompt)\n\n## \(agentLabel) activity\n\(reply)\n\n"
        }
        for turn in liveTurns {
            let reply = runOutputStore?.run(turn.runID)?.text ?? ""
            out += "## Request\n\(turn.prompt)\n\n## \(agentLabel) activity\n\(reply)\n\n"
        }
        return out
    }

    private func load() async {
        guard let repo = chatRepo,
              let conv = try? await repo.conversation(id: conversationID) else {
            loaded = true
            return
        }
        let persisted = (try? await repo.turns(conversationID: conversationID)) ?? []
        let artifacts = (try? await repo.artifacts(conversationID: conversationID)) ?? []
        conversation = conv
        title = conv.title
        hostName = conv.hostName
        agentLabel = conv.vendor ?? conv.agentID
        turns = persisted
        artifactsByRun = Dictionary(grouping: artifacts, by: \.runID)
        loaded = true
    }
}

private enum WorkThreadStatus: Equatable {
    case loading
    case empty
    case running
    case completed
    case failed

    init(_ status: LancerCore.ChatTurn.Status) {
        switch status {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        }
    }

    var label: String {
        switch self {
        case .loading: "Loading"
        case .empty: "Ready"
        case .running: "Working"
        case .completed: "Complete"
        case .failed: "Needs review"
        }
    }

    var headline: String {
        switch self {
        case .loading: "Loading thread"
        case .empty: "Ready for work"
        case .running: "Agent is working"
        case .completed: "Work captured"
        case .failed: "Run stopped"
        }
    }
}

private struct WorkThreadSummaryCard: View {
    let title: String
    let status: WorkThreadStatus
    let machine: String
    let agent: String
    let cwd: String?
    let turnCount: Int
    let artifactCount: Int

    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Work thread")
                        .font(.dsMonoPt(10, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.9)
                    Text(title)
                        .font(.dsSansPt(20, weight: .semibold))
                        .foregroundStyle(t.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                WorkThreadStatusBadge(status: status)
            }

            HStack(spacing: 8) {
                WorkThreadMetric(icon: .server, label: machine)
                WorkThreadMetric(icon: .terminal, label: agent)
            }

            if let cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                WorkThreadPill("\(turnCount) request\(turnCount == 1 ? "" : "s")")
                WorkThreadPill("\(artifactCount) artifact\(artifactCount == 1 ? "" : "s")")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }
}

private struct WorkThreadTurnBlock: View {
    let ordinal: Int
    let prompt: String
    let status: WorkThreadStatus
    let bodyText: String
    let errorText: String?
    let createdAt: Date?
    let completedAt: Date?
    let artifacts: [ChatArtifact]
    let onArtifactTap: ((ChatArtifact) -> Void)?

    @State private var showsRawOutput = false
    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkThreadEventRow(
                ordinal: ordinal,
                title: "Request",
                detail: prompt,
                timeLabel: createdAt?.formatted(date: .omitted, time: .shortened)
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    DSStatusDot(tone: status == .failed ? .danger : status == .running ? .accent : .ok, size: 7)
                    Text(status.headline)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Spacer(minLength: 8)
                    if let completedAt {
                        Text(completedAt.formatted(date: .omitted, time: .shortened))
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                    }
                }

                if status == .running && bodyText.isEmpty {
                    DarkTypingIndicator()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if status != .failed, !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(bodyText.trimmingCharacters(in: .whitespacesAndNewlines), textColor: t.text2)
                        .textSelection(.enabled)
                } else {
                    Text(displayText)
                        .font(.dsSansPt(13))
                        .foregroundStyle(status == .failed ? t.danger : t.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if status == .failed, let errorText, !errorText.isEmpty {
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showsRawOutput.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            DSIconView(.chevronDown, size: 12, color: t.text3)
                                .rotationEffect(.degrees(showsRawOutput ? 0 : -90))
                            Text(showsRawOutput ? "Hide output" : "Show output")
                                .font(.dsMonoPt(10, weight: .semibold))
                                .foregroundStyle(t.text3)
                        }
                    }
                    .buttonStyle(.plain)

                    if showsRawOutput {
                        Text(errorText)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                    }
                }

                if !artifacts.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Artifacts")
                            .font(.dsMonoPt(10, weight: .semibold))
                            .foregroundStyle(t.text4)
                            .tracking(0.8)
                        ForEach(artifacts) { artifact in
                            ChatArtifactCard(artifact: artifact) {
                                onArtifactTap?(artifact)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(status == .failed ? t.danger.opacity(0.45) : t.border, lineWidth: 1)
            )
        }
    }

    private var displayText: String {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == .failed {
            return "The agent stopped before completing this request. Review the output if you need the failure details."
        }
        if !trimmed.isEmpty { return trimmed }
        switch status {
        case .loading:
            return "Loading recorded activity."
        case .empty:
            return "No activity has been recorded yet."
        case .running:
            return "Waiting for the agent to report progress."
        case .completed:
            return "No output was recorded for this turn."
        case .failed:
            return "The agent stopped before completing this request."
        }
    }
}

private struct WorkThreadEventRow: View {
    let ordinal: Int
    let title: String
    let detail: String
    let timeLabel: String?

    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", ordinal))
                .font(.dsMonoPt(10, weight: .semibold))
                .foregroundStyle(t.text4)
                .frame(width: 30, height: 30)
                .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.r1, style: .continuous).strokeBorder(t.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.dsMonoPt(10, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer(minLength: 8)
                    if let timeLabel {
                        Text(timeLabel)
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                    }
                }
                Text(detail)
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct WorkThreadStatusBadge: View {
    let status: WorkThreadStatus
    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 6) {
            DSStatusDot(tone: status == .failed ? .danger : status == .running || status == .loading ? .accent : status == .empty ? .info : .ok, size: 6)
            Text(status.label.uppercased())
                .font(.dsMonoPt(10, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(foreground.opacity(0.24), lineWidth: 1))
    }

    private var foreground: Color {
        switch status {
        case .failed: t.danger
        case .running, .loading: t.accent
        case .empty: t.text3
        case .completed: t.ok
        }
    }

    private var background: Color {
        foreground.opacity(0.11)
    }
}

private struct WorkThreadMetric: View {
    let icon: DSIcon
    let label: String
    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 6) {
            DSIconView(icon, size: 12, color: t.text3)
            Text(label)
                .font(.dsSansPt(12, weight: .medium))
                .foregroundStyle(t.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(t.surfaceSunk, in: Capsule())
    }
}

private struct WorkThreadPill: View {
    let label: String
    @Environment(\.lancerTokens) private var t

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.dsMonoPt(10, weight: .semibold))
            .foregroundStyle(t.text4)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
#endif
