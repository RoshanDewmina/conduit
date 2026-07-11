#if os(iOS)
import SwiftUI
import LancerCore

public struct CursorBlockedReasonRow: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let reason: BlockedReason

    public init(_ reason: BlockedReason) {
        self.reason = reason
    }

    public init?(context: AgentStateContext) {
        guard let reason = context.blockedReason else { return nil }
        self.reason = reason
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        let accent = severityColor(colors)
        HStack(spacing: 6) {
            Image(systemName: severityIcon)
                .font(.caption2)
                .foregroundColor(accent)
            Text(reason.displayReason)
                .font(.caption.weight(.medium))
                .foregroundColor(colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var severityIcon: String {
        switch reason.severity {
        case .info: return "clock"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func severityColor(_ colors: CursorColors) -> Color {
        switch reason.severity {
        case .info: return colors.mutedText
        case .warning: return colors.riskMedium
        case .critical: return colors.riskCritical
        }
    }
}
#endif
