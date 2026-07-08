#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's own profile drawer (owner-supplied screenshots:
/// IMG_2418–2420 light, dark tokens per `docs/design-reference/cursor-mobile-2026-07-08/screen-map.md`),
/// presented as a bottom sheet when the header avatar circle is tapped.
///
/// Lancer has no real token/usage or run-history ledger yet (no account
/// system, no monthly usage telemetry, no activity-streak tracker) — the
/// `tokensTotal` / `monthlySamples` / `localAgentsCount` / `cloudAgentsCount` /
/// `currentStreakDays` / `longestStreakDays` / `streakIntensities` params all
/// default to an honest zero/empty state rather than inventing Cursor-shaped
/// numbers. Wiring real counts (e.g. `relayMachineCount` for `localAgentsCount`)
/// is a `CursorAppShell.swift` call-site change, out of this file's scope —
/// see the A3-R3 report for the gap.
public struct CursorProfileDrawer: View {
    /// One bar in the monthly/per-series chart (`MiniBarChart`).
    public struct ChartSample: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let value: Double

        public init(label: String, value: Double) {
            self.id = label
            self.label = label
            self.value = value
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let tokensTotal: Int
    private let monthlySamples: [ChartSample]
    private let localAgentsCount: Int
    private let cloudAgentsCount: Int
    private let currentStreakDays: Int
    private let longestStreakDays: Int
    /// Normalized 0...1 intensity per month index (0 = January), empty = untracked.
    private let streakIntensities: [Int: Double]

    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onSignOut: () -> Void

    public init(
        tokensTotal: Int = 0,
        monthlySamples: [ChartSample] = [],
        localAgentsCount: Int = 0,
        cloudAgentsCount: Int = 0,
        currentStreakDays: Int = 0,
        longestStreakDays: Int = 0,
        streakIntensities: [Int: Double] = [:],
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onSignOut: @escaping () -> Void = {}
    ) {
        self.tokensTotal = tokensTotal
        self.monthlySamples = monthlySamples
        self.localAgentsCount = localAgentsCount
        self.cloudAgentsCount = cloudAgentsCount
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.streakIntensities = streakIntensities
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
                    CursorHairlineDivider()
                    usageSection
                    CursorHairlineDivider()
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
        .accessibilityIdentifier("profile.sheet")
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
                .padding(.bottom, 14)

            Text("Local Lancer")
                .font(CursorType.prTitle)
                .foregroundColor(colors.primaryText)

            Text("Self-hosted device")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.secondaryText)

            Text("Away Mode Solo")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
        .accessibilityIdentifier("profile.identity")
    }

    // MARK: Usage (Tokens + Local/Cloud Agents)

    private var usageSection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tokens")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.secondaryText)
                Text(tokensTotal.formattedCompact)
                    .font(CursorType.prTitle)
                    .foregroundColor(colors.primaryText)
                MiniBarChart(samples: monthlySamples, colors: colors)
                    .frame(height: 140)
                    .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local Agents")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Text("\(localAgentsCount)")
                        .font(CursorType.prTitle)
                        .foregroundColor(colors.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cloud Agents")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Text("\(cloudAgentsCount)")
                        .font(CursorType.prTitle)
                        .foregroundColor(colors.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AgentsTwoUpChart(
                localCount: localAgentsCount,
                cloudCount: cloudAgentsCount,
                colors: colors
            )
            .frame(height: 90)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 20)
        .accessibilityIdentifier("profile.usage")
    }

    // MARK: Streak

    private var streakSection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Streak")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Text("\(currentStreakDays)d")
                        .font(CursorType.prTitle)
                        .foregroundColor(colors.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Longest")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Text("\(longestStreakDays)d")
                        .font(CursorType.prTitle)
                        .foregroundColor(colors.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            StreakDotGrid(intensities: streakIntensities, colors: colors)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 20)
        .accessibilityIdentifier("profile.streak")
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
            .font(CursorType.versionFooter)
            .foregroundColor(colors.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }
}

// MARK: - Charts

/// Simple bar chart: one `RoundedRectangle` per sample, scaled to the tallest
/// value, with a light dashed gridline every quarter and the sample labels
/// along the bottom — no charting dependency, per A3-R3 design rules.
private struct MiniBarChart: View {
    let samples: [CursorProfileDrawer.ChartSample]
    let colors: CursorColors

    var body: some View {
        let maxValue = max(samples.map(\.value).max() ?? 0, 1)
        GeometryReader { proxy in
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Divider().overlay(colors.hairline)
                            Spacer(minLength: 0)
                        }
                        Divider().overlay(colors.hairline)
                    }

                    if samples.isEmpty {
                        Text("Not tracked yet")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.mutedText)
                    } else {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(samples) { sample in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colors.orangeAccent)
                                    .frame(
                                        height: max(4, proxy.size.height * CGFloat(sample.value / maxValue))
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: proxy.size.height - 20)

                if !samples.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(samples) { sample in
                            Text(sample.label)
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(colors.mutedText)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("profile.chart.tokens")
    }
}

/// Two-bar comparison of local vs. cloud agent counts.
private struct AgentsTwoUpChart: View {
    let localCount: Int
    let cloudCount: Int
    let colors: CursorColors

    var body: some View {
        let maxValue = max(Double(max(localCount, cloudCount)), 1)
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 24) {
                bar(value: Double(localCount), maxValue: maxValue, height: proxy.size.height)
                bar(value: Double(cloudCount), maxValue: maxValue, height: proxy.size.height)
            }
        }
        .accessibilityIdentifier("profile.chart.agents")
    }

    private func bar(value: Double, maxValue: Double, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(colors.orangeAccent.opacity(value > 0 ? 1 : 0.15))
            .frame(maxWidth: .infinity)
            .frame(height: max(4, height * CGFloat(value / maxValue)))
    }
}

/// Year-grid of streak-intensity dots: 12 month columns × 7 rows, month
/// initials along the bottom, orange opacity encodes intensity (0 = gray).
private struct StreakDotGrid: View {
    let intensities: [Int: Double]
    let colors: CursorColors

    private static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    private static let rowCount = 7

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<Self.rowCount, id: \.self) { _ in
                HStack(spacing: 8) {
                    ForEach(0..<12, id: \.self) { month in
                        Circle()
                            .fill(dotColor(forMonth: month))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(Self.monthInitials, id: \.self) { initial in
                    Text(initial)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundColor(colors.mutedText)
                        .frame(width: 8)
                }
            }
        }
        .accessibilityIdentifier("profile.streak.grid")
    }

    private func dotColor(forMonth month: Int) -> Color {
        guard let intensity = intensities[month], intensity > 0 else {
            return colors.statusDotIdle.opacity(0.5)
        }
        return colors.orangeAccent.opacity(0.35 + 0.65 * min(intensity, 1))
    }
}

private extension Int {
    /// "835M" / "16K" / "412" style compact formatting for the Tokens stat.
    var formattedCompact: String {
        let value = self
        switch value {
        case 1_000_000...:
            return String(format: "%.0fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }
}
#endif
