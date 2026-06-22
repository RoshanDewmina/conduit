#if os(iOS)
import SwiftUI

/// Shared approval banner: amber pill with DENY/APPROVE capsules.
/// Used by both ChatInputBar and RunDetailView for pending tool approvals.
public struct DSApprovalBanner: View {
    let count: Int
    let onApprove: () -> Void
    let onReject: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        count: Int,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.count = count
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.warn)
            Text(count == 1 ? "1 pending approval" : "\(count) pending approvals")
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(t.text2)
            Spacer()
            Button {
                Haptics.selection()
                onReject()
            } label: {
                Text("DENY")
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.dangerSoft)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.medium()
                onApprove()
            } label: {
                Text("APPROVE")
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.warnSoft)
        .overlay(Rectangle().fill(t.warn.opacity(0.25)).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: count)
    }
}
#endif
