#if os(iOS)
import SwiftUI
import DesignSystem
import PersistenceKit

public struct ConduitSidebarView: View {
    @Bindable var state: SidebarShellState
    let onNavigate: (SidebarDestination) -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        state: SidebarShellState,
        onNavigate: @escaping (SidebarDestination) -> Void
    ) {
        self.state = state
        self.onNavigate = onNavigate
    }

    public var body: some View {
        List {
            profileSection
            newChatSection
            searchSection
            recentThreadsSection
            sessionsSection
        }
        .scrollIndicators(.hidden)
        .listStyle(.plain)
        .background(t.bg)
        .tint(t.accent)
        .task { await state.loadRecent() }
    }

    private var newChatSection: some View {
        Section {
            Button {
                onNavigate(.newChat)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.plus, size: 18, color: t.accentFg)
                    Text("New Task")
                        .font(.dsMono(.body, weight: .medium))
                        .foregroundStyle(t.accentFg)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(t.accent)
                .clipShape(RoundedRectangle(cornerRadius: t.r3))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, t.s1)
        }
    }

    private var searchSection: some View {
        Section {
            HStack(spacing: t.s2) {
                DSIconView(.search, size: 16, color: t.text3)
                TextField("Search threads...", text: $state.searchQuery)
                    .font(.dsMono(.callout))
                    .foregroundStyle(t.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: state.searchQuery) {
                        Task { await state.performSearch() }
                    }
            }
            .padding(t.s3)
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r2))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var recentThreads: [ChatConversation] {
        state.searchQuery.isEmpty
            ? state.recentThreads
            : state.searchResults.map(\.conversation)
    }

    private var recentThreadsSection: some View {
        Section {
            if recentThreads.isEmpty {
                Text("No threads yet")
                    .font(.dsMono(.callout))
                    .foregroundStyle(t.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, t.s2)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(recentThreads) { thread in
                    Button {
                        onNavigate(.thread(id: thread.id))
                    } label: {
                        ThreadRow(thread: thread, isSelected: false)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            if !recentThreads.isEmpty {
                Text("HISTORY")
                    .dsCapsStyle()
                    .foregroundStyle(t.text3)
            }
        }
    }

    private var profileSection: some View {
        Section {
            Button {
                onNavigate(.settings)
            } label: {
                HStack(spacing: t.s3) {
                    PixelAvatar(seed: "conduit-user", size: 32)
                    Text("Conduit")
                        .font(.dsMono(.callout, weight: .semibold))
                        .foregroundStyle(t.text)
                    Spacer()
                    DSIconView(.settings, size: 16, color: t.text3)
                }
                .padding(.vertical, t.s1)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var sessionsSection: some View {
        Section {
            Button {
                onNavigate(.newChat)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.terminal, size: 18, color: t.text)
                    Text("Sessions")
                        .font(.dsMono(.callout, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer()
                    if state.pendingApprovalCount > 0 {
                        Text("\(state.pendingApprovalCount)")
                            .font(.dsMono(.caption2, weight: .bold))
                            .foregroundStyle(t.accentFg)
                            .padding(.horizontal, t.s2)
                            .padding(.vertical, t.s1)
                            .background(t.warn)
                            .clipShape(Capsule())
                    } else if state.fleetSlotCount > 0 {
                        DSChip("\(state.fleetSlotCount)", tone: .ok, variant: .soft, size: .sm)
                    }
                }
                .padding(.vertical, t.s1)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

}

private struct ThreadRow: View {
    let thread: ChatConversation
    let isSelected: Bool

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: t.s3) {
            Circle()
                .fill(thread.status == .active ? t.ok : t.text3)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: t.s1) {
                Text(thread.title.isEmpty ? thread.hostName : thread.title)
                    .font(.dsMono(.callout, weight: .medium))
                    .foregroundStyle(isSelected ? t.accent : t.text)
                    .lineLimit(1)
                HStack(spacing: t.s1) {
                    Text(thread.hostName)
                        .font(.dsMono(.caption2))
                        .foregroundStyle(t.text3)
                    Text("·")
                        .foregroundStyle(t.text4)
                    Text(thread.lastActivityAt, style: .relative)
                        .font(.dsMono(.caption2))
                        .foregroundStyle(t.text4)
                }
            }
            Spacer()
        }
        .padding(.vertical, t.s1)
    }
}
#endif
