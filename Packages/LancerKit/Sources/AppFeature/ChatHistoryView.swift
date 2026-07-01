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
                if loaded && turns.isEmpty && liveTurns.isEmpty {
                    emptyState
                } else {
                    ForEach(turns) { turn in
                        DarkUserBubble(turn.prompt)
                        assistantBlock(turn)
                    }
                    ForEach(liveTurns) { turn in
                        DarkUserBubble(turn.prompt)
                        liveAssistant(turn)
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

    /// A live continuation turn — renders from runOutputStore (streaming), mirroring
    /// NewChatTabView. Persisted turns above keep rendering their stored text.
    @ViewBuilder
    private func liveAssistant(_ turn: LiveTurn) -> some View {
        let run = runOutputStore?.run(turn.runID)
        if let run, !run.text.isEmpty {
            DarkAssistantBubble(run.text)
        } else {
            DarkTypingIndicator()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        if let chatRepo {
            _ = try? await chatRepo.appendTurn(conversationID: conversationID, prompt: trimmed, runID: run.runId)
        }
    }

    @ViewBuilder
    private func assistantBlock(_ turn: LancerCore.ChatTurn) -> some View {
        let text = turn.assistantText.isEmpty ? (turn.errorMessage ?? "") : turn.assistantText
        VStack(alignment: .leading, spacing: 6) {
            // History records prose only (no tool blocks are persisted), so a
            // recorded reply is a plain bubble. A failed turn keeps the dark
            // output card for visual consistency, but never claims shell chrome —
            // history has no way to know whether the failure ever touched a shell.
            if turn.status == .failed {
                DarkTerminalBlockCard(
                    host: hostName,
                    command: nil,
                    output: text.isEmpty ? "(no output recorded)" : text,
                    state: .error,
                    isShellSession: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DarkAssistantBubble(text.isEmpty ? "(no output recorded)" : text)
            }
            let artifacts = artifactsByRun[turn.runID] ?? []
            if !artifacts.isEmpty {
                ForEach(artifacts) { artifact in
                    ChatArtifactCard(artifact: artifact) {
                        Haptics.selection()
                        selectedArtifact = artifact
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            DSIconView(.sparkles, size: 28, color: t.text4)
            Text("No messages in this thread yet.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// Plain-text export of the conversation (persisted turns + this session's live
    /// turns), shared via the header's ShareLink.
    private func transcriptText() -> String {
        var out = "# \(title)\n\(agentLabel) · \(hostName)\n\n"
        for turn in turns {
            let reply = turn.assistantText.isEmpty ? (turn.errorMessage ?? "") : turn.assistantText
            out += "## You\n\(turn.prompt)\n\n## \(agentLabel)\n\(reply)\n\n"
        }
        for turn in liveTurns {
            let reply = runOutputStore?.run(turn.runID)?.text ?? ""
            out += "## You\n\(turn.prompt)\n\n## \(agentLabel)\n\(reply)\n\n"
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
#endif
