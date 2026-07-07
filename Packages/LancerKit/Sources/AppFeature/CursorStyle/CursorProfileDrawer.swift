#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's own profile drawer (owner-supplied screenshots),
/// presented as a bottom sheet when the header avatar circle is tapped.
/// Identity/usage/streak sections are Cursor-account-flavored mock content;
/// the trailing "Lancer" section links out to Lancer's real product settings
/// (`CursorSettingsView`) via `onOpenSettings` — wiring that in is a later
/// integration pass. Static seed data only, forced light `cursorScheme`.
public struct CursorProfileDrawer: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onSignOut: () -> Void

    public init(
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onSignOut: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onSignOut = onSignOut
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Profile",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            ScrollView {
                VStack(spacing: 0) {
                    identitySection
                    usageSection
                    streakSection

                    CursorSectionHeader("Plan")
                    row(iconSystemName: "arrow.up.circle", title: "Manage Plan", showChevron: true)

                    CursorSectionHeader("Support")
                    externalLinkRow(iconSystemName: "questionmark.circle", title: "Help")
                    externalLinkRow(iconSystemName: "envelope", title: "Contact Sales")
                    row(iconSystemName: "shippingbox", title: "Acknowledgements", showChevron: true)

                    CursorSectionHeader("More")
                    row(
                        iconSystemName: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        showChevron: false,
                        action: onSignOut
                    )

                    CursorSectionHeader("Lancer")
                    row(
                        iconSystemName: "gearshape",
                        title: "App Settings",
                        showChevron: true,
                        action: onOpenSettings
                    )

                    CursorSectionHeader("Danger Zone")
                    row(
                        iconSystemName: "trash",
                        title: "Delete Account",
                        titleColor: CursorColors.resolve(cursorScheme).dangerRed,
                        showChevron: false
                    )

                    footer
                }
                .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
            }
        }
        .environment(\.cursorScheme, .light)
    }

    // MARK: Identity

    private var identitySection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 6) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.29, green: 0.42, blue: 0.94),
                            Color(red: 0.62, green: 0.31, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text("owner@lancer.dev")
                .font(CursorType.cardTitle)
                .foregroundColor(colors.primaryText)

            Text("owner@lancer.dev")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)

            Text("Away Mode Solo")
                .font(CursorType.statusPill)
                .foregroundColor(colors.pillPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(colors.pillPrimaryBackground))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    // MARK: Usage

    private static let monthLabels = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    private static let tokenMonthlyBars: [CGFloat] = [0.25, 0.30, 0.20, 0.35, 0.28, 0.40, 0.55, 0.85, 1.0, 0.60, 0.32, 0.45]
    private static let localAgentBars: [CGFloat] = [0.3, 0.5, 0.4, 0.7, 0.6, 1.0, 0.8]
    private static let cloudAgentBars: [CGFloat] = [0.2, 0.3, 0.5, 0.4, 0.9, 0.6, 0.7]

    private var usageSection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 0) {
            CursorSectionHeader("Usage")

            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.secondaryText)
                Text("372M")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(colors.primaryText)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 12)

            barChart(
                heights: Self.tokenMonthlyBars,
                labels: Self.monthLabels,
                color: colors.riskHigh,
                chartHeight: 64
            )
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 16) {
                statBlock(title: "Local Agents", value: "36", bars: Self.localAgentBars, color: colors.riskHigh)
                statBlock(title: "Cloud Agents", value: "9", bars: Self.cloudAgentBars, color: colors.riskHigh)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 20)
        }
    }

    private func statBlock(title: String, value: String, bars: [CGFloat], color: Color) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(colors.primaryText)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(height: max(2, height * 28))
                }
            }
            .frame(height: 28, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(colors.cardBackground))
    }

    private func barChart(heights: [CGFloat], labels: [String], color: Color, chartHeight: CGFloat) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: max(3, height * chartHeight))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight, alignment: .bottom)

            HStack(spacing: 6) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(colors.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Streak

    /// 5 weeks (rows) x 12 months (columns), 0-4 intensity levels.
    private static let heatmapGrid: [[Int]] = [
        [0, 1, 0, 2, 1, 0, 3, 4, 2, 1, 0, 1],
        [1, 0, 2, 1, 3, 2, 4, 3, 1, 0, 2, 0],
        [0, 2, 1, 0, 2, 4, 3, 2, 0, 1, 1, 2],
        [2, 0, 0, 3, 1, 2, 4, 4, 1, 0, 0, 1],
        [0, 1, 1, 0, 0, 3, 2, 1, 0, 2, 1, 0]
    ]

    private var streakSection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 8) {
            CursorSectionHeader("Activity")

            VStack(spacing: 4) {
                ForEach(Array(Self.heatmapGrid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, level in
                            Circle()
                                .fill(heatmapColor(level: level, colors: colors))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                HStack(spacing: 4) {
                    ForEach(Self.monthLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(colors.mutedText)
                            .frame(width: 8)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 8)
        }
    }

    private func heatmapColor(level: Int, colors: CursorColors) -> Color {
        switch level {
        case 0: return colors.hairline
        case 1: return colors.riskHigh.opacity(0.30)
        case 2: return colors.riskHigh.opacity(0.55)
        case 3: return colors.riskHigh.opacity(0.80)
        default: return colors.riskHigh
        }
    }

    // MARK: Rows

    private func row(
        iconSystemName: String,
        title: String,
        titleColor: Color? = nil,
        showChevron: Bool,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            CursorListRow(
                iconSystemName: iconSystemName,
                title: title,
                titleColor: titleColor,
                showChevron: showChevron
            )
        }
        .buttonStyle(.plain)
    }

    /// Same visual language as `CursorListRow` but with a trailing
    /// external-link icon instead of a chevron, for rows that leave the app.
    private func externalLinkRow(iconSystemName: String, title: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button(action: {}) {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: iconSystemName)
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                    Text(title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.mutedText)
                }
                .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                .padding(.vertical, CursorMetrics.rowVerticalPadding)
                Rectangle()
                    .fill(colors.hairline)
                    .frame(height: CursorMetrics.rowHairlineHeight)
                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
            }
            // Same dead-tap-zone fix as CursorListRow/CursorThreadRow: without
            // this, a tap in the `Spacer()` gap between the title and the
            // trailing external-link glyph doesn't register as hitting the Button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Text("LANCER V1.0.0 (1)")
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(colors.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }
}
#endif
