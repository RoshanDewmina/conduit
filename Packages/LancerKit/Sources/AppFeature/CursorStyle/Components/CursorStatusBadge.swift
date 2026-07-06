#if os(iOS)
import SwiftUI

/// Small pill/circle badge for status states: a success checkmark-circle style
/// ("All Checks Passed", IMG_2364) or a risk-level label (Review/Diff risk
/// tags — low/medium/high/critical).
public struct CursorStatusBadge: View {
    public enum RiskLevel: Sendable {
        case low
        case medium
        case high
        case critical
    }

    public enum Kind: Sendable {
        case success
        case risk(level: RiskLevel)
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let kind: Kind
    private let label: String

    public init(kind: Kind, label: String) {
        self.kind = kind
        self.label = label
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: CursorMetrics.statusBadgeSpacing) {
            iconView(colors: colors)
            Text(label)
                .font(CursorType.statusPill)
                .foregroundColor(colors.primaryText)
        }
        .padding(.horizontal, CursorMetrics.statusBadgeHorizontalPadding)
        .padding(.vertical, CursorMetrics.statusBadgeVerticalPadding)
    }

    @ViewBuilder
    private func iconView(colors: CursorColors) -> some View {
        switch kind {
        case .success:
            ZStack {
                Circle().fill(colors.successGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(colors.pillPrimaryText)
            }
            .frame(width: CursorMetrics.statusBadgeIconSize, height: CursorMetrics.statusBadgeIconSize)
        case .risk(let level):
            Circle()
                .fill(riskColor(level, colors: colors))
                .frame(width: 8, height: 8)
        }
    }

    private func riskColor(_ level: RiskLevel, colors: CursorColors) -> Color {
        switch level {
        case .low: return colors.riskLow
        case .medium: return colors.riskMedium
        case .high: return colors.riskHigh
        case .critical: return colors.riskCritical
        }
    }
}
#endif
