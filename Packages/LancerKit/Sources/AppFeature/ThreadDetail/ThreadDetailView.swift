#if os(iOS)
import SwiftUI

/// Thread detail for a real conversation row. Live transcript lives in
/// `LiveThreadView` (owned by chat-polish); this surface shows honest
/// metadata + follow-up send into the thread's real cwd — no invented
/// PR/markdown filler.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFollowUpPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?

    let thread: ThreadListItem

    init(thread: ThreadListItem) {
        self.thread = thread
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
                    VStack(alignment: .leading, spacing: 18) {
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

                        Text("Full transcript opens from a live send. Follow up below to continue in this repo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func handleSend(_ prompt: String, _ cwd: String) {
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        guard !normalized.isEmpty else { return }
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
