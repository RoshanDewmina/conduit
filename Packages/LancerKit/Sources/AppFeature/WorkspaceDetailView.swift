#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Chat list for one workspace on one machine — pushed to from a Home
/// workspace card (see `HomeWorkspaceRef`/`SidebarDestination.workspace`).
/// This is the "depth" screen Option B's redesign calls for: a workspace no
/// longer expands inline on Home, it gets its own scrollable list here.
public struct WorkspaceDetailView: View {
    let machineName: String
    let path: String
    let displayName: String
    let sessions: [ChatConversation]
    let onOpenThread: (String) -> Void
    let onNewChatHere: () -> Void
    let onBack: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        machineName: String,
        path: String,
        displayName: String,
        sessions: [ChatConversation],
        onOpenThread: @escaping (String) -> Void,
        onNewChatHere: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.machineName = machineName
        self.path = path
        self.displayName = displayName
        self.sessions = sessions
        self.onOpenThread = onOpenThread
        self.onNewChatHere = onNewChatHere
        self.onBack = onBack
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(displayName, breadcrumb: "\(machineName) · \(path)", onBack: onBack)
                content
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            DSEmptyState(
                icon: .terminal,
                title: "No chats yet",
                subtitle: "Start a chat in \(displayName) on \(machineName).",
                action: ("New chat", onNewChatHere)
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    newChatRow
                    ForEach(sessions.sorted(by: { $0.lastActivityAt > $1.lastActivityAt })) { session in
                        sessionRow(session)
                    }
                }
                .padding(16)
            }
        }
    }

    private var newChatRow: some View {
        Button(action: onNewChatHere) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New chat in \(displayName)")
                    .font(.dsSansPt(12.5, weight: .semibold))
            }
            .foregroundStyle(t.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(t.border)
            )
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ session: ChatConversation) -> some View {
        Button { onOpenThread(session.id) } label: {
            HStack(spacing: 10) {
                Text(Self.initial(for: session))
                    .font(.dsDisplayPt(11, weight: .bold))
                    .foregroundStyle(t.accentFg)
                    .frame(width: 26, height: 26)
                    .background(t.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title.isEmpty ? session.hostName : session.title)
                        .font(.dsSansPt(13.5, weight: .semibold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    Text(relativeTime(session.lastActivityAt))
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text4)
                }
                Spacer(minLength: 0)
                statusGlyph(session.status)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusGlyph(_ status: ChatConversation.Status) -> some View {
        switch status {
        case .active:
            DSStatusDot(tone: .ok, pulse: true, size: 8)
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(t.ok)
        case .failed:
            DSStatusDot(tone: .danger, size: 8)
        case .archived:
            DSStatusDot(tone: .off, size: 8)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "just now" }
        if interval < 3600 { let m = Int(interval / 60); return "\(m) min\(m == 1 ? "" : "s") ago" }
        if interval < 86400 { let h = Int(interval / 3600); return "\(h) hr\(h == 1 ? "" : "s") ago" }
        let d = Int(interval / 86400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }

    private static func initial(for session: ChatConversation) -> String {
        let key = (session.vendor ?? session.agentID).lowercased()
        if key.contains("codex") { return "Cx" }
        if key.contains("claude") { return "C" }
        if key.contains("kimi") { return "K" }
        if key.contains("opencode") || key.contains("open") { return "O" }
        return String((session.vendor ?? session.agentID).prefix(1)).uppercased()
    }
}
#endif
