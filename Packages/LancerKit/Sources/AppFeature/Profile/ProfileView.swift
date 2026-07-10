#if os(iOS)
import SwiftUI
import Charts

/// Section 2 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Profile" sheet (owner reference screenshots showing
/// top/middle/bottom scroll positions). Visual-only for this milestone — all
/// identity, usage, and streak data is static sample data with no
/// networking, no persistence, and no live wiring. System `SF Symbols` +
/// semantic colors only, no DesignSystem module.
public struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    identitySection
                        .padding(.top, 28)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    tokensSection
                        .padding(.top, 24)

                    agentsSection
                        .padding(.top, 36)

                    streakSection
                        .padding(.top, 36)

                    planSection
                        .padding(.top, 28)

                    supportSection
                        .padding(.top, 28)

                    moreSection
                        .padding(.top, 28)

                    dangerZoneSection
                        .padding(.top, 28)

                    footer
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ZStack {
            Text("Profile")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        )
                }
                .accessibilityLabel(Text("Close"))

                Spacer()
            }
        }
    }

    private var identitySection: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.75), Color.purple.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 152, height: 152)

            Text(Self.sampleName)
                .font(.title2.bold())
                .padding(.top, 8)

            Text(Self.sampleEmail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Self.samplePlan)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var tokensSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(title: "Tokens")

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.tokenTotal)
                    .font(.title.bold())
                    .padding(.horizontal, 20)

                MonthlyBarChart(values: Self.tokenMonthlyValues, yAxisValues: [0, 250_000_000, 500_000_000, 750_000_000])
                    .frame(height: 180)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var agentsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Agents")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Self.localAgentCount)")
                    .font(.title.bold())
                MonthlyBarChart(values: Self.localAgentMonthlyValues, yAxisValues: [0, 50, 100])
                    .frame(height: 110)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud Agents")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Self.cloudAgentCount)")
                    .font(.title.bold())
                MonthlyBarChart(values: Self.cloudAgentMonthlyValues, yAxisValues: [0, 50, 100])
                    .frame(height: 110)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Self.currentStreak)
                        .font(.title.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Longest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Self.longestStreak)
                        .font(.title.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            StreakHeatmapGrid(intensities: Self.streakIntensities)
        }
        .padding(.horizontal, 20)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "Plan")

            VStack(spacing: 0) {
                ProfileRow(systemImage: "arrow.up.circle", title: "Manage Plan", accessory: .chevron)
            }
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "Support")

            VStack(spacing: 0) {
                ProfileRow(systemImage: "questionmark.circle", title: "Help", accessory: .externalLink)
                Divider().padding(.leading, 58)
                ProfileRow(systemImage: "envelope", title: "Contact Sales", accessory: .externalLink)
                Divider().padding(.leading, 58)
                ProfileRow(systemImage: "shippingbox", title: "Acknowledgements", accessory: .chevron)
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "More")

            VStack(spacing: 0) {
                ProfileRow(systemImage: "rectangle.portrait.and.arrow.right", title: "Sign out", accessory: .none)
            }
        }
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "Danger Zone")

            VStack(spacing: 0) {
                ProfileRow(systemImage: "trash", title: "Delete Account", accessory: .none, isDestructive: true)
            }
        }
    }

    private var footer: some View {
        Text(Self.versionString)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(.tertiaryLabel))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Static sample data

    private static let sampleName = "Sam Rivera"
    private static let sampleEmail = "sam.rivera@example.com"
    private static let samplePlan = "Pro"
    private static let tokenTotal = "835M"
    private static let localAgentCount = 91
    private static let cloudAgentCount = 16
    private static let currentStreak = "8d"
    private static let longestStreak = "8d"
    private static let versionString = "LANCER V0.1.0 (DEV)"

    /// Monthly token usage, Jan–Dec — spiky "early usage" sample: mostly
    /// empty with activity clustered in a couple of months.
    private static let tokenMonthlyValues: [Double] = [
        0, 0, 0, 0, 120_000_000, 810_000_000, 340_000_000, 0, 0, 0, 0, 0,
    ]

    private static let localAgentMonthlyValues: [Double] = [
        0, 0, 0, 0, 12, 91, 38, 0, 0, 0, 0, 0,
    ]

    private static let cloudAgentMonthlyValues: [Double] = [
        0, 0, 0, 0, 2, 16, 7, 0, 0, 0, 0, 0,
    ]

    /// Activity heatmap intensities: 12 columns (months) × 5 rows.
    /// 0 = inactive, otherwise opacity for the accent dot.
    private static let streakIntensities: [[Double]] = [
        [0, 0, 0, 0, 0.3, 1.0, 0.6, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0.6, 0.8, 0.4, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0.2, 1.0, 0.2, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0.5, 0.7, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0.9, 0.3, 0, 0, 0, 0, 0],
    ]
}

// MARK: - Section header

private struct ProfileSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }
}

// MARK: - Row

private enum ProfileRowAccessory {
    case chevron
    case externalLink
    case none
}

private struct ProfileRow: View {
    let systemImage: String
    let title: String
    let accessory: ProfileRowAccessory
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isDestructive ? Color.red : .secondary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(isDestructive ? Color.red : .primary)

            Spacer()

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .externalLink:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Monthly bar chart

private struct MonthlyBarChart: View {
    let values: [Double]
    let yAxisValues: [Double]

    private static let monthLabels = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Month", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(Color.orange)
            }
        }
        .chartYAxis {
            AxisMarks(values: yAxisValues) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(0..<Self.monthLabels.count)) { axisValue in
                AxisValueLabel {
                    if let index = axisValue.as(Int.self), Self.monthLabels.indices.contains(index) {
                        Text(Self.monthLabels[index])
                    }
                }
            }
        }
    }
}

// MARK: - Streak heatmap grid

private struct StreakHeatmapGrid: View {
    let intensities: [[Double]]

    private static let monthLabels = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    private static let dotSize: CGFloat = 7
    private static let dotSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Self.dotSpacing) {
            ForEach(0..<intensities.count, id: \.self) { row in
                HStack(spacing: Self.dotSpacing) {
                    ForEach(0..<intensities[row].count, id: \.self) { column in
                        let intensity = intensities[row][column]
                        Circle()
                            .fill(intensity > 0 ? Color.orange.opacity(intensity) : Color(.systemGray5))
                            .frame(width: Self.dotSize, height: Self.dotSize)
                    }
                }
            }

            HStack(spacing: Self.dotSpacing) {
                ForEach(Self.monthLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(width: Self.dotSize)
                }
            }
            .padding(.top, 2)
        }
    }
}

#Preview {
    ProfileView()
}
#endif
