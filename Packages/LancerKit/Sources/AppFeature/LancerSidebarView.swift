#if os(iOS)
import SwiftUI
import DesignSystem
import PersistenceKit
import LancerCore

public struct LancerSidebarView: View {
    @Bindable var state: SidebarShellState
    let onNavigate: (SidebarDestination) -> Void
    let profileLabel: String

    @Environment(\.lancerTokens) private var t

    // Rename/delete flow state for the recent-thread context menu.
    @State private var renamingThread: ChatConversation?
    @State private var renameText: String = ""
    @State private var deletingThread: ChatConversation?

    public init(
        state: SidebarShellState,
        profileLabel: String = "Lancer",
        onNavigate: @escaping (SidebarDestination) -> Void
    ) {
        self.state = state
        self.profileLabel = profileLabel
        self.onNavigate = onNavigate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader
                        .padding(.top, 60)
                        .padding(.horizontal, 20)

                    newChatButton
                        .padding(.top, 20)
                        .padding(.horizontal, 16)

                    searchField
                        .padding(.top, 14)
                        .padding(.horizontal, 16)

                    primaryNavigation
                        .padding(.top, 16)
                        .padding(.horizontal, 12)

                    recentLabel
                        .padding(.top, 18)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 10)

                    recentThreadsList
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                }
            }

            relayFooter
        }
        .background(t.surface)
        .tint(t.accent)
        .task { await state.loadRecent() }
        .alert("Rename chat", isPresented: Binding(
            get: { renamingThread != nil },
            set: { if !$0 { renamingThread = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let id = renamingThread?.id {
                    let title = renameText
                    Task { await state.renameConversation(id, to: title) }
                }
                renamingThread = nil
            }
            Button("Cancel", role: .cancel) { renamingThread = nil }
        }
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
            Text("This removes the conversation and its history from this device.")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 13) {
            Button { onNavigate(.settings) } label: {
                HStack(spacing: 13) {
                    SidebarBrandMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profileLabel)
                            .font(.dsDisplayPt(20, weight: .bold))
                            .tracking(-0.02 * 20)
                            .foregroundStyle(t.text)
                        Text("Settings & account ›")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings and account")
            .accessibilityHint("Opens settings")
            Spacer(minLength: 8)
            DSCircleButton(
                "gearshape",
                diameter: 40,
                accessibilityLabel: "Settings",
                action: { onNavigate(.settings) }
            )
        }
        .coachmarkAnchor("settings")
    }

    // MARK: - New chat CTA

    private var newChatButton: some View {
        Button { onNavigate(.newChat) } label: {
            HStack(spacing: 11) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .frame(width: 26, height: 26)
                    .background(t.accentFg.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("New chat")
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 15)
            .frame(minHeight: 54)
            .background(t.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New chat")
        .coachmarkAnchor("newChat")
    }

    // MARK: - Search (board hides it, but functionality is preserved)

    private var searchField: some View {
        HStack(spacing: 10) {
            DSIconView(.search, size: 16, color: t.text3)
            TextField("Search chats", text: $state.searchQuery)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: state.searchQuery) { _, _ in
                    Task { await state.performSearch() }
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(t.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Search chats")
    }

    // MARK: - Primary navigation

    private var primaryNavigation: some View {
        VStack(spacing: 2) {
            SidebarNavRow(
                icon: "house",
                title: "Home",
                badge: nil,
                selected: state.selectedDestination == .home,
                action: { onNavigate(.home) }
            )
            SidebarNavRow(
                icon: "sparkles",
                title: "Inbox",
                badge: state.pendingApprovalCount > 0 ? "\(state.pendingApprovalCount)" : nil,
                selected: state.selectedDestination == .needsAttention,
                action: { onNavigate(.needsAttention) }
            )
            .coachmarkAnchor("inbox")
            SidebarNavRow(
                icon: "desktopcomputer",
                title: "Machines",
                badge: nil,
                selected: state.selectedDestination == .machines,
                action: { onNavigate(.machines) }
            )
            .coachmarkAnchor("terminal")
        }
    }

    // MARK: - Recent

    private var recentLabel: some View {
        Text(state.searchQuery.isEmpty ? "Recent" : "Search results")
            .font(.dsMonoPt(10, weight: .medium))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(t.text4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentThreads: [ChatConversation] {
        state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? state.orderedRecentThreads
            : state.searchResults.map(\.conversation)
    }

    @ViewBuilder
    private var recentThreadsList: some View {
        if recentThreads.isEmpty {
            Text(state.searchQuery.isEmpty ? "No chats yet" : "No matching chats")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else {
            VStack(spacing: 1) {
                ForEach(recentThreads) { thread in
                    Button {
                        onNavigate(.thread(id: thread.id))
                    } label: {
                        ThreadRow(
                            thread: thread,
                            isSelected: state.selectedDestination == .thread(id: thread.id),
                            isPinned: state.isPinned(thread.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            state.togglePinned(thread.id)
                        } label: {
                            Label(state.isPinned(thread.id) ? "Unpin" : "Pin",
                                  systemImage: state.isPinned(thread.id) ? "pin.slash" : "pin")
                        }
                        Button {
                            renameText = thread.title
                            renamingThread = thread
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) {
                            deletingThread = thread
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var relayFooter: some View {
        HStack(spacing: 7) {
            DSStatusDot(tone: .ok, pulse: true, size: 6)
            Text("Relay connected · 3 hosts")
                .font(.dsMonoPt(10.5))
                .foregroundStyle(t.text4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(t.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay connected, 3 hosts")
    }
}

// MARK: - Brand mark (matches OnboardingBrandMark, sized for the drawer)

private struct SidebarBrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1), // #8b6fb0
                        Color(.sRGB, red: 0.690, green: 0.561, blue: 0.808, opacity: 1), // #b08fce
                        Color(.sRGB, red: 0.435, green: 0.353, blue: 0.588, opacity: 1), // #6f5a96
                        Color(.sRGB, red: 0.616, green: 0.498, blue: 0.753, opacity: 1), // #9d7fc0
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1)
                    ],
                    center: .center,
                    angle: .degrees(45)
                )
            )
            .overlay(
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x <= size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.12))); x += 9 }
                    var y: CGFloat = 0
                    while y <= size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12))); y += 9 }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .frame(width: 46, height: 46)
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Nav row (flat, board language)

private struct SidebarNavRow: View {
    let icon: String
    let title: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    @Environment(\.lancerTokens) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? t.text : t.text2)
                    .frame(width: 22)
                Text(title)
                    .font(.dsSansPt(14.5, weight: .semibold))
                    .foregroundStyle(selected ? t.text : t.text2)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.dsSansPt(11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 5)
                        .background(t.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(selected ? t.surface2 : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(badge.map { "\($0) waiting" } ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Recent thread row (status dot + title + machine · status)

private struct ThreadRow: View {
    let thread: ChatConversation
    let isSelected: Bool
    var isPinned: Bool = false

    @Environment(\.lancerTokens) private var t

    private var dotTone: DSStatusDotTone {
        switch thread.status {
        case .active:    return .orange
        case .completed: return .ok
        case .failed:    return .danger
        }
    }

    private var statusLabel: String {
        switch thread.status {
        case .active:    return "running"
        case .completed: return "done"
        case .failed:    return "failed"
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            DSStatusDot(tone: dotTone, pulse: thread.status == .active, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title.isEmpty ? thread.hostName : thread.title)
                    .font(.dsSansPt(13.5, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(thread.hostName) · \(statusLabel)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.text4)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? t.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.title.isEmpty ? thread.hostName : thread.title), \(thread.hostName), \(statusLabel)")
    }
}
#endif
