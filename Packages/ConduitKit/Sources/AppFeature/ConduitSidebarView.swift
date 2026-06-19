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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                profileHeader
                newChatButton
                searchField
                primaryNavigation
                recentThreadsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 28)
        }
        .background(t.bg)
        .tint(t.accent)
        .task { await state.loadRecent() }
    }

    private var profileHeader: some View {
        Button { onNavigate(.settings) } label: {
            HStack(spacing: 12) {
                PixelAvatar(seed: "conduit-user", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conduit")
                        .font(.dsDisplayPt(24, weight: .bold))
                        .foregroundStyle(t.text)
                    Text(state.fleetSlotCount > 0 ? "Agents reachable" : "Control from your phone")
                        .font(.dsSansPt(12, weight: .medium))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                DSIconView(.settings, size: 17, color: t.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
    }

    private var newChatButton: some View {
        Button { onNavigate(.newChat) } label: {
            HStack(spacing: 9) {
                DSIconView(.plus, size: 18, color: t.accentFg)
                Text("New chat")
                    .font(.dsSansPt(16, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 18)
            .background(t.accent, in: Capsule())
            .shadow(color: t.accent.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New chat")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            DSIconView(.search, size: 17, color: t.text3)
            TextField("Search chats", text: $state.searchQuery)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: state.searchQuery) { _, _ in
                    Task { await state.performSearch() }
                }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border.opacity(0.75), lineWidth: 1)
        )
        .accessibilityLabel("Search chats")
    }

    private var primaryNavigation: some View {
        VStack(spacing: 6) {
            SidebarNavRow(
                title: "Needs attention",
                subtitle: state.pendingApprovalCount > 0 ? "\(state.pendingApprovalCount) waiting" : "Approvals and requests",
                icon: .inbox,
                badge: state.pendingApprovalCount > 0 ? "\(state.pendingApprovalCount)" : nil,
                selected: state.selectedDestination == .needsAttention,
                action: { onNavigate(.needsAttention) }
            )
            SidebarNavRow(
                title: "Fleet",
                subtitle: state.fleetSlotCount > 0 ? "\(state.fleetSlotCount) connected" : "Hosts and running agents",
                icon: .server,
                badge: state.fleetSlotCount > 0 ? "\(state.fleetSlotCount)" : nil,
                selected: state.selectedDestination == .fleet,
                action: { onNavigate(.fleet) }
            )
            SidebarNavRow(
                title: "Settings",
                subtitle: "Relay, security, and policy",
                icon: .settings,
                badge: nil,
                selected: state.selectedDestination == .settings,
                action: { onNavigate(.settings) }
            )
        }
        .padding(6)
        .background(t.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
        )
    }

    private var recentThreads: [ChatConversation] {
        state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? state.recentThreads
            : state.searchResults.map(\.conversation)
    }

    private var recentThreadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.searchQuery.isEmpty ? "Recent" : "Search results")
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text2)
                Spacer()
                if !recentThreads.isEmpty {
                    Text("\(recentThreads.count)")
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                }
            }

            if recentThreads.isEmpty {
                Text(state.searchQuery.isEmpty ? "No chats yet" : "No matching chats")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(recentThreads) { thread in
                        Button {
                            onNavigate(.thread(id: thread.id))
                        } label: {
                            ThreadRow(
                                thread: thread,
                                isSelected: state.selectedDestination == .thread(id: thread.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SidebarNavRow: View {
    let title: String
    let subtitle: String
    let icon: DSIcon
    let badge: String?
    let selected: Bool
    let action: () -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DSIconView(icon, size: 18, color: selected ? t.accent : t.text2)
                    .frame(width: 34, height: 34)
                    .background(selected ? t.accentSoft : t.surface2.opacity(0.7), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(selected ? t.text : t.text2)
                    Text(subtitle)
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.dsMonoPt(11, weight: .bold))
                        .foregroundStyle(t.accentFg)
                        .frame(minWidth: 24, minHeight: 24)
                        .padding(.horizontal, 4)
                        .background(t.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(selected ? t.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct ThreadRow: View {
    let thread: ChatConversation
    let isSelected: Bool

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(thread.status == .active ? t.ok : t.text4)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title.isEmpty ? thread.hostName : thread.title)
                    .font(.dsSansPt(15, weight: .medium))
                    .foregroundStyle(isSelected ? t.text : t.text2)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(thread.hostName)
                    Text("·")
                    Text(thread.lastActivityAt, style: .relative)
                }
                .font(.dsSansPt(12))
                .foregroundStyle(t.text3)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? t.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityLabel(thread.title.isEmpty ? thread.hostName : thread.title)
    }
}
#endif
