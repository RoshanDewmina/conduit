#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import SecurityKit
import LancerCore

/// Read-only transcript viewer for a session discovered on the host (Claude
/// Code, etc.) but not dispatched by Lancer — watch-only in Phase 1, no
/// composer, no send/stop control. Fetches once on appear; no polling yet.
public struct ObservedSessionView: View {
    let sessionId: String
    let title: String
    let hostName: String
    /// Fetches transcript turns starting at `sinceLine`. AppRoot resolves this to
    /// the connected SSH slot's `DaemonChannel.fetchTranscript` or the relay
    /// bridge's `relayFetchTranscript`.
    let loadTranscript: (_ sinceLine: Int) async -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool)
    let onBack: () -> Void

    @State private var messages: [SessionMessage] = []
    @State private var loaded = false
    @State private var unlocked = false

    @Environment(\.lancerTokens) private var t

    public init(
        sessionId: String,
        title: String,
        hostName: String,
        loadTranscript: @escaping (_ sinceLine: Int) async -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool),
        onBack: @escaping () -> Void
    ) {
        self.sessionId = sessionId
        self.title = title
        self.hostName = hostName
        self.loadTranscript = loadTranscript
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            DarkTranscriptHeader(
                title: title,
                subtitle: "Watching · \(hostName)",
                isLive: false,
                onBack: { Haptics.selection(); onBack() },
                onWorkspace: { Haptics.selection(); onBack() },
                shareText: { transcriptText() }
            )
            .overlay(alignment: .topTrailing) {
                watchingBadge.padding(.top, 8).padding(.trailing, 64)
            }
            content
        }
        .background(t.bg.ignoresSafeArea())
        .task(id: sessionId) { await loadAndUnlock() }
    }

    @ViewBuilder
    private var content: some View {
        if !unlocked {
            lockedState
        } else if !loaded {
            // Fetch in flight. Without this the unlocked-but-not-loaded state fell
            // through to an empty scroll view — a confusing permanent blank if the
            // transcript reply was slow or never arrived.
            loadingState
        } else if messages.isEmpty {
            emptyState
        } else {
            ConversationScrollView(bottomID: "observed-bottom", scrollKey: messages.count) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    row(for: message)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading transcript…")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var watchingBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye").font(.system(size: 10, weight: .semibold))
            Text("Watching").font(.dsMonoPt(11, weight: .medium))
        }
        .foregroundStyle(t.text3)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(t.surface2, in: Capsule())
    }

    @ViewBuilder
    private func row(for message: SessionMessage) -> some View {
        switch message.role {
        case .user:
            DarkUserBubble(message.text)
        case .assistant:
            DarkAssistantBubble(message.text)
        case .toolCall, .toolResult:
            DarkTerminalBlockCard(
                host: hostName,
                command: message.role == .toolCall ? message.toolName : nil,
                output: message.text,
                state: .done
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system, .unknown:
            Text(message.text)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            DSIconView(.sparkles, size: 28, color: t.text4)
            Text("No transcript recorded for this session yet.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var lockedState: some View {
        VStack(spacing: 8) {
            DSIconView(.shield, size: 28, color: t.text4)
            Text("Authenticate to view this transcript.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func transcriptText() -> String {
        var out = "# \(title)\n\(hostName)\n\n"
        for message in messages {
            out += "## \(message.role.rawValue)\n\(message.text)\n\n"
        }
        return out
    }

    // TODO: this gates the fetch behind BiometricGate (reused from SecurityKit,
    // same pattern as KeysView/InboxView), but doesn't yet re-prompt on app
    // foreground the way the chat composer's app-lock does — fine for Phase 1
    // (watch-only, no write capability), revisit if observed transcripts ever
    // carry write-adjacent actions.
    private func loadAndUnlock() async {
        do {
            try await BiometricGate.shared.unlock(reason: "Authenticate to view this session's transcript")
            unlocked = true
        } catch {
            unlocked = false
            loaded = true
            return
        }
        let result = await loadTranscript(0)
        messages = result.messages
        loaded = true
    }
}
#endif
