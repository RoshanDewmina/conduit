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
                        totalSpendCard
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("quota guard")
                    .font(.dsMonoPt(18, weight: .bold))
                    .foregroundStyle(t.text)
                Spacer()
                DSIconButton(.refresh) {
                    Haptics.selection()
                    Task { await store.refresh() }
                }
                .disabled(store.isLoading)
            }
            Text("per-provider budget caps & burn rate")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Total Spend

    private var totalSpendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "$%.2f", store.totalSpendToday))
                    .font(.dsMonoPt(28, weight: .bold))
                    .foregroundStyle(t.text)
                    .monospacedDigit()
                Text("today")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            }

            if store.hasOverLimit {
                Label("At least one provider is over its daily cap", systemImage: "exclamationmark.triangle.fill")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.danger)
            } else if store.hasNearLimit {
                Label("At least one provider is near its daily cap", systemImage: "exclamationmark.triangle")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.warn)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.displayName)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                if let pct = provider.percentUsed {
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.dsMonoPt(11))
                        .foregroundStyle(provider.isOverLimit ? t.danger : provider.isNearLimit ? t.warn : t.text3)
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
