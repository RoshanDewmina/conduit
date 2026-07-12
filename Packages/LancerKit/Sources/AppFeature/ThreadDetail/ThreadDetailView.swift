#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Thread detail for a real conversation row. Renders the local-mirror
/// transcript (user + assistant) with Flight Recorder per turn, plus follow-up
/// send into the thread's real cwd.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFollowUpPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?
    @State private var turns: [ChatTurn] = []
    /// How many of the most-recent turns to render. Extended via "Show earlier…".
    @State private var visibleTurnLimit = Self.initialWindowSize

    private static let initialWindowSize = 100
    private static let windowExtendStep = 100

    let thread: ThreadListItem

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

                            ForEach(visibleTurns) { turn in
                                VStack(alignment: .leading, spacing: 12) {
                                    ChatUserBubble(text: turn.prompt)
                                    threadAssistant(turn)

                                    NavigationLink {
                                        FlightRecorderView(
                                            conversationID: thread.id,
                                            turnID: turn.id,
                                            prompt: turn.prompt,
                                            runID: turn.runID
                                        )
                                    } label: {
                                        flightRecorderRow(turn)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                }
            }

            Button {
                isFollowUpPresented = true
            } label: {
                ChatFollowUpPlaceholderBar()
            }
            .buttonStyle(.plain)
            .disabled(thread.cwd.isEmpty)
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
                        name: thread.repoName ?? WorkspaceRepoCatalog.displayName(forCwd: thread.cwd),
                        cwd: thread.cwd,
                        threadCount: 0,
                        isUserAdded: false
                    ),
                onSend: handleSend
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
            let body = turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText
            ChatMarkdownBody(markdown: body)
        }
    }

    private func flightRecorderRow(_ turn: ChatTurn) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Flight Recorder")
                    .font(.system(size: 15, weight: .medium))
                Text(turn.prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("Flight Recorder for turn \(turn.ordinal + 1)"))
    }

    private func loadTurns() async {
        guard thread.id != "preview" else { return }
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        turns = (try? await repo.turns(conversationID: thread.id)) ?? []
    }

    private func handleSend(_ prompt: String, _ cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(normalized) else { return }
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: normalized)
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

            circleButton(systemImage: "ellipsis")
                .accessibilityHidden(true)
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
