#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Manage/archive sheet for chat threads. Lists conversations with
/// `status == .archived` and lets the user restore or permanently delete them.
/// Presented locally from `LancerSidebarView` (no AppRoot routing).
public struct ChatArchiveView: View {
    @Bindable var state: SidebarShellState

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var deletingThread: ChatConversation?

    public init(state: SidebarShellState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSDetailHeader("Archived", breadcrumb: "Chats", onBack: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if state.archivedThreads.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    } else {
                        VStack(spacing: 1) {
                            ForEach(state.archivedThreads) { thread in
                                ArchivedThreadRow(thread: thread)
                                    .contextMenu {
                                        Button {
                                            Task { await state.unarchiveConversation(thread.id) }
                                        } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                                        Button(role: .destructive) {
                                            deletingThread = thread
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deletingThread = thread
                                        } label: { Label("Delete", systemImage: "trash") }
                                        Button {
                                            Task { await state.unarchiveConversation(thread.id) }
                                        } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                                        .tint(t.accent)
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(t.surface)
        .task { await state.loadArchived() }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { deletingThread != nil }, set: { if !$0 { deletingThread = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = deletingThread?.id {
                    Task { await state.deleteConversation(id) }
                }
                deletingThread = nil
            }
            Button("Cancel", role: .cancel) { deletingThread = nil }
        } message: {
            Text("This permanently removes the conversation and its history from this device.")
        }
    }

    private var emptyState: some View {
        DSEmptyState(
            icon: .folder,
            title: "No archived chats",
            subtitle: "Chats you archive from the sidebar show up here."
        )
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Archived thread row (title + machine, restore/delete via context menu or swipe)

private struct ArchivedThreadRow: View {
    let thread: ChatConversation

    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "archivebox")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.text4)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title.isEmpty ? thread.hostName : thread.title)
                    .font(.dsSansPt(13.5, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(thread.hostName) · archived")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.title.isEmpty ? thread.hostName : thread.title), \(thread.hostName), archived")
    }
}
#endif
