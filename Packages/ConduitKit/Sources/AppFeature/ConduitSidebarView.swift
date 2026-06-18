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
            newChatSection
            searchSection
            recentThreadsSection
            if state.pendingApprovalCount > 0 {
                needsAttentionSection
            }
            fleetSection
            settingsSection
        }
        .scrollIndicators(.hidden)
        .listStyle(.plain)
        .background(t.bg.ignoresSafeArea())
        .tint(t.accent)
        .task { await state.loadRecent() }
    }

    private var newChatSection: some View {
        Section {
            Button {
                state.selectedDestination = .newChat
                onNavigate(.newChat)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.plus, size: 18, color: t.accentFg)
                    Text("New Chat")
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
                        state.selectedDestination = .thread(id: thread.id)
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
                Text("RECENT")
                    .dsCapsStyle()
                    .foregroundStyle(t.text3)
            }
        }
    }

    private var needsAttentionSection: some View {
        Section {
            Button {
                state.selectedDestination = .needsAttention
                onNavigate(.needsAttention)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.alert, size: 18, color: t.warn)
                    Text("Needs Attention")
                        .font(.dsMono(.callout, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer()
                    Text("\(state.pendingApprovalCount)")
                        .font(.dsMono(.caption2, weight: .bold))
                        .foregroundStyle(t.accentFg)
                        .padding(.horizontal, t.s2)
                        .padding(.vertical, t.s1)
                        .background(t.warn)
                        .clipShape(Capsule())
                }
                .padding(.vertical, t.s1)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var fleetSection: some View {
        Section {
            Button {
                state.selectedDestination = .fleet
                onNavigate(.fleet)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.server, size: 18, color: t.text)
                    Text("Fleet")
                        .font(.dsMono(.callout, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer()
                    if state.fleetSlotCount > 0 {
                        DSChip("\(state.fleetSlotCount)", tone: .ok, variant: .soft, size: .sm)
                    }
                }
                .padding(.vertical, t.s1)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var settingsSection: some View {
        Section {
            Button {
                state.selectedDestination = .settings
                onNavigate(.settings)
            } label: {
                HStack(spacing: t.s3) {
                    DSIconView(.settings, size: 18, color: t.text2)
                    Text("Settings")
                        .font(.dsMono(.callout))
                        .foregroundStyle(t.text2)
                    Spacer()
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
