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
        case open
        case merged
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
                .foregroundColor(labelColor(colors))
        }
        .padding(.horizontal, CursorMetrics.statusBadgeHorizontalPadding)
        .padding(.vertical, CursorMetrics.statusBadgeVerticalPadding)
        .background(badgeBackground(colors))
        .clipShape(Capsule())
    }

    private func labelColor(_ colors: CursorColors) -> Color {
        switch kind {
        case .merged: return colors.mergedBadgeText
        case .open: return colors.openBadgeText
        default: return colors.primaryText
        }
    }

    @ViewBuilder
    private func badgeBackground(_ colors: CursorColors) -> some View {
        switch kind {
        case .merged:
            Capsule().fill(colors.mergedBadgeBackground)
        case .open:
            Capsule().fill(colors.openBadgeBackground)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func iconView(colors: CursorColors) -> some View {
        switch kind {
        case .success:
            ZStack {
                Circle().fill(colors.successGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(colors.mergeButtonText)
            }
            .frame(width: CursorMetrics.statusBadgeIconSize, height: CursorMetrics.statusBadgeIconSize)
        case .open:
            Circle()
                .fill(colors.successGreen)
                .frame(width: 8, height: 8)
        case .merged:
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.mergedBadgeText)
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
