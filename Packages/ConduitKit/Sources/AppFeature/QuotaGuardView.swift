#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

public struct QuotaGuardView: View {
    @State private var store: QuotaGuardStore
    @Environment(\.conduitTokens) private var t

    public init(store: QuotaGuardStore) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if store.providers.isEmpty && !store.isLoading {
                        emptyCard
                    } else {
                        heroCard
                        alertsSection
                        providerCards
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task { await store.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("quota guard")
                    .font(.dsSansPt(28, weight: .bold))
                    .foregroundStyle(t.text)
                Text("per-provider budget caps & burn rate")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            DSIconButton(.refresh) {
                Haptics.selection()
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("total spend today")
                        .font(.dsMonoPt(10, weight: .medium))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(t.text3)

                    Text(String(format: "$%.2f", store.totalSpendToday))
                        .font(.dsSansPt(36, weight: .bold))
                        .foregroundStyle(t.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer()

                let worstPercent = store.providers.map { provider in
                    guard let cap = provider.dailyCapUSD, cap > 0 else { return 0 }
                    return Int((provider.spentTodayUSD / cap) * 100)
                }.max() ?? 0
                ProgressRing(
                    fraction: Double(worstPercent) / 100.0,
                    color: thresholdColor(for: Double(worstPercent) / 100.0),
                    size: 64,
                    lineWidth: 5
                )
            }

            if store.hasOverLimit {
                Label("At least one provider is over its daily cap", systemImage: "exclamationmark.circle.fill")
                    .font(.dsMonoPt(11, weight: .medium))
                    .foregroundStyle(t.danger)
            } else if store.hasNearLimit {
                Label("At least one provider is near its daily cap", systemImage: "exclamationmark.triangle.fill")
                    .font(.dsMonoPt(11, weight: .medium))
                    .foregroundStyle(t.warn)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 14)
        .padding(.horizontal, 18)
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Group {
            if !store.alerts.isEmpty {
                DSListSectionHead("Alerts", count: store.alerts.count)
                ForEach(store.alerts) { alert in
                    alertRow(alert)
                        .padding(.horizontal, 18)
                }
            }
        }
    }

    private func alertRow(_ alert: QuotaGuard.SpendAlert) -> some View {
        HStack(spacing: 10) {
            Image(systemName: alertIcon(alert.type))
                .font(.system(size: 13))
                .foregroundStyle(alertColor(alert.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                Text(alert.provider)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(alertColor(alert.type).opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(alertColor(alert.type).opacity(0.2), lineWidth: 1)
        )
    }

    private func alertIcon(_ type: QuotaGuard.SpendAlert.AlertType) -> String {
        switch type {
        case .overLimit: return "exclamationmark.circle.fill"
        case .nearLimit: return "exclamationmark.triangle.fill"
        case .projectedExceed: return "chart.line.uptrend.xyaxis"
        case .burnRateHigh: return "flame.fill"
        }
    }

    private func alertColor(_ type: QuotaGuard.SpendAlert.AlertType) -> Color {
        switch type {
        case .overLimit: return t.danger
        case .nearLimit: return t.warn
        case .projectedExceed: return t.accent
        case .burnRateHigh: return t.warn
        }
    }

    // MARK: - Provider Cards

    private var providerCards: some View {
        Group {
            DSListSectionHead("Providers", count: store.providers.count)
            ForEach(store.providers) { provider in
                providerCard(provider)
                    .padding(.horizontal, 18)
            }
        }
    }

    private func providerCard(_ provider: QuotaGuard.ProviderQuota) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let pct = provider.percentUsed {
                    ProgressRing(
                        fraction: pct,
                        color: providerThresholdColor(pct),
                        size: 44,
                        lineWidth: 4
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(t.text)

                    HStack(spacing: 8) {
                        if let dailyCap = provider.dailyCapUSD {
                            Text(String(format: "$%.2f / $%.2f daily", provider.spentTodayUSD, dailyCap))
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                        }
                        if let monthlyCap = provider.monthlyCapUSD {
                            Text(String(format: "$%.2f / $%.2f mo", provider.spentThisMonthUSD, monthlyCap))
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                        }
                    }
                }

                Spacer()

                if let pct = provider.percentUsed {
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.dsMonoPt(13, weight: .bold))
                        .foregroundStyle(providerThresholdColor(pct))
                        .monospacedDigit()
                }
            }

            if let dailyCap = provider.dailyCapUSD {
                spendBar(
                    label: "Daily",
                    spent: provider.spentTodayUSD,
                    cap: dailyCap,
                    color: provider.isOverLimit ? t.danger : t.accent
                )
            }

            if let monthlyCap = provider.monthlyCapUSD {
                spendBar(
                    label: "Monthly",
                    spent: provider.spentThisMonthUSD,
                    cap: monthlyCap,
                    color: t.accent
                )
            }

            HStack(spacing: 12) {
                metricBox(label: "burn rate", value: String(format: "$%.2f/hr", provider.burnRateUSDPerHour))
                metricBox(label: "projected", value: String(format: "$%.2f", provider.projectedDailyTotal))
                if let remaining = provider.quotaRemainingUSD {
                    metricBox(label: "remaining", value: String(format: "$%.2f", max(0, remaining)))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .dsCard()
    }

    private func spendBar(label: String, spent: Double, cap: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
                Spacer()
                Text(String(format: "$%.2f / $%.2f", spent, cap))
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
            }

            GeometryReader { geo in
                let fraction = min(spent / max(cap, 0.001), 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(t.text4.opacity(0.2))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private func metricBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMonoPt(9))
                .foregroundStyle(t.text4)
            Text(value)
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.text2)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Threshold Colors

    private func thresholdColor(for fraction: Double) -> Color {
        if fraction >= 0.90 { return t.danger }
        if fraction >= 0.75 { return t.warn }
        if fraction >= 0.50 { return Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1) }
        return t.ok
    }

    private func providerThresholdColor(_ fraction: Double) -> Color {
        if fraction >= 0.90 { return t.danger }
        if fraction >= 0.75 { return t.warn }
        if fraction >= 0.50 { return Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1) }
        return t.ok
    }

    // MARK: - Empty

    private var emptyCard: some View {
        DSEmptyState(
            icon: .shield,
            title: "No providers tracked",
            subtitle: "Spend data will appear here once agents report usage to the daemon."
        )
    }
}
#endif
