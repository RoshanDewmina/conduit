#if os(iOS)
import SwiftUI

/// Amber approval quick-action strip for pending tool approvals.
public struct CursorApprovalBanner: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let count: Int
    let onApprove: () -> Void
    let onReject: () -> Void

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
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.riskMedium)
            Text(count == 1 ? "1 pending approval" : "\(count) pending approvals")
                .font(CursorType.statusPill)
                .foregroundColor(colors.secondaryText)
            Spacer()
            Button {
                Haptics.selection()
                onReject()
            } label: {
                Text("DENY")
                    .font(CursorType.statusPill)
                    .foregroundColor(colors.dangerRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(colors.dangerRed.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.medium()
                onApprove()
            } label: {
                Text("APPROVE")
                    .font(CursorType.statusPill)
                    .foregroundColor(colors.pillPrimaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(colors.pillPrimaryBackground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.riskMedium.opacity(0.12))
        .overlay(Rectangle().fill(colors.riskMedium.opacity(0.25)).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: count)
    }
}
#endif
