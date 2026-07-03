#if os(iOS)
import SwiftUI
import DesignSystem

/// Inline, non-blocking sync status banner for a conversation thread — shown
/// above the composer/follow-up bar in `NewChatTabView` and `ChatHistoryView`.
/// Mirrors `DSApprovalBanner`'s shape (icon/spinner + message + trailing
/// action pill(s)) per the build handoff's Mobbin review: never a blocking
/// modal, and the "conflict" case is one inline Refresh/Resend pair, not a
/// multi-step review flow.
public struct ConversationSyncBanner: View {
    let state: ConversationSyncUIState
    var onRefresh: (() -> Void)?
    var onResend: (() -> Void)?

    @Environment(\.lancerTokens) private var t

    public init(
        state: ConversationSyncUIState,
        onRefresh: (() -> Void)? = nil,
        onResend: (() -> Void)? = nil
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onResend = onResend
    }

    public var body: some View {
        if let content = content(t) {
            HStack(spacing: 8) {
                if content.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .tint(content.tone)
                } else {
                    Image(systemName: content.icon)
                        .font(.dsSansPt(12, weight: .semibold))
                        .foregroundStyle(content.tone)
                }
                Text(content.message)
                    .font(.dsMonoPt(11.5, weight: .semibold))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let onRefresh, content.showsRefresh {
                    actionPill("Refresh", tone: content.tone, action: onRefresh)
                }
                if let onResend, content.showsResend {
                    actionPill("Resend", tone: t.accent, action: onResend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(content.background)
            .overlay(Rectangle().fill(content.tone.opacity(0.25)).frame(height: 1), alignment: .bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: state)
        }
    }

    private func actionPill(_ label: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label.uppercased())
                .font(.dsMonoPt(10.5, weight: .semibold))
                .foregroundStyle(tone)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tone.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private struct Content {
        let message: String
        let icon: String
        let tone: Color
        let background: Color
        let showsSpinner: Bool
        let showsRefresh: Bool
        let showsResend: Bool
    }

    /// `nil` for `.synced` — no banner. Every other state renders a single
    /// quiet strip; only `.conflict` offers a Resend alongside Refresh (see
    /// `NewChatTabView`'s conflict handling for how the failed prompt is
    /// preserved for that Resend tap).
    private func content(_ t: LancerTokens) -> Content? {
        switch state {
        case .synced:
            return nil
        case .syncing:
            return Content(
                message: "Syncing…", icon: "arrow.triangle.2.circlepath", tone: t.text3, background: t.surface,
                showsSpinner: true, showsRefresh: false, showsResend: false
            )
        case .hostOffline:
            return Content(
                message: "Host unreachable — showing cached history", icon: "wifi.slash",
                tone: t.warn, background: t.warnSoft, showsSpinner: false, showsRefresh: true, showsResend: false
            )
        case .cloudStale:
            return Content(
                message: "History may be outdated", icon: "arrow.clockwise",
                tone: t.info, background: t.infoSoft, showsSpinner: false, showsRefresh: true, showsResend: false
            )
        case .conflict:
            return Content(
                message: "This conversation changed on another device", icon: "exclamationmark.arrow.triangle.2.circlepath",
                tone: t.danger, background: t.dangerSoft, showsSpinner: false, showsRefresh: true, showsResend: true
            )
        case .degradedResume:
            return Content(
                message: "Resumed without an exact match — this reply may start fresh on the host",
                icon: "arrow.uturn.backward", tone: t.warn, background: t.warnSoft,
                showsSpinner: false, showsRefresh: false, showsResend: false
            )
        case .streamingElsewhere:
            return Content(
                message: "Streaming on another device", icon: "dot.radiowaves.left.and.right",
                tone: t.accent, background: t.accentSoft, showsSpinner: false, showsRefresh: false, showsResend: false
            )
        }
    }
}
#endif
