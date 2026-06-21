#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import PersistenceKit
import ConduitCore

/// Read-only transcript for a persisted conversation opened from the sidebar.
///
/// Compose and live-run state lives in `NewChatTabView`; history is deliberately
/// a separate, stateless view so reopening a past thread can never inherit a stale
/// `activeRun` or get stuck on a "thinking" indicator. It renders persisted turns
/// straight from the repository — it does not touch the shared `RunOutputStore`.
public struct ChatHistoryView: View {
    let conversationID: String
    let chatRepo: ChatConversationRepository?
    let onBack: () -> Void
    let onNewChat: () -> Void

    @State private var title: String = "chat"
    @State private var hostName: String = "relay"
    @State private var agentLabel: String = "Agent"
    @State private var turns: [ConduitCore.ChatTurn] = []
    @State private var artifactsByRun: [String: [ChatArtifact]] = [:]
    @State private var selectedArtifact: ChatArtifact?
    @State private var loaded = false

    @Environment(\.conduitTokens) private var t

    public init(
        conversationID: String,
        chatRepo: ChatConversationRepository?,
        onBack: @escaping () -> Void,
        onNewChat: @escaping () -> Void
    ) {
        self.conversationID = conversationID
        self.chatRepo = chatRepo
        self.onBack = onBack
        self.onNewChat = onNewChat
    }

    public var body: some View {
        VStack(spacing: 0) {
            DarkTranscriptHeader(
                title: title,
                subtitle: "\(agentLabel) · \(hostName)",
                isLive: false,
                onBack: { Haptics.selection(); onBack() },
                onWorkspace: { Haptics.selection(); onNewChat() },
                onNew: { Haptics.selection(); onNewChat() }
            )
            ConversationScrollView(bottomID: "history-bottom", scrollKey: turns.count) {
                if loaded && turns.isEmpty {
                    emptyState
                } else {
                    ForEach(turns) { turn in
                        DarkUserBubble(turn.prompt)
                        assistantBlock(turn)
                    }
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .task(id: conversationID) { await load() }
        .sheet(item: $selectedArtifact) { ChatArtifactDetailView(artifact: $0) }
    }

    @ViewBuilder
    private func assistantBlock(_ turn: ConduitCore.ChatTurn) -> some View {
        let text = turn.assistantText.isEmpty ? (turn.errorMessage ?? "") : turn.assistantText
        VStack(alignment: .leading, spacing: 6) {
            DarkTerminalBlockCard(
                host: hostName,
                command: nil,
                output: text.isEmpty ? "(no output recorded)" : text,
                state: turn.status == .failed ? .error : .done
            )
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func load() async {
        guard let repo = chatRepo,
              let conv = try? await repo.conversation(id: conversationID) else {
            loaded = true
            return
        }
        let persisted = (try? await repo.turns(conversationID: conversationID)) ?? []
        let artifacts = (try? await repo.artifacts(conversationID: conversationID)) ?? []
        title = conv.title
        hostName = conv.hostName
        agentLabel = conv.vendor ?? conv.agentID
        turns = persisted
        artifactsByRun = Dictionary(grouping: artifacts, by: \.runID)
        loaded = true
    }
}
#endif
