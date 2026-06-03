#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

/// Subscription / credit management sheet for hosted agents. Surfaces the credit
/// balance breakdown, today's spend vs the daily limit, and a link into the
/// Stripe customer portal (with a conduit.dev fallback when unavailable).
public struct AgentBillingSheet: View {
    @Bindable var store: AgentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.conduitTokens) private var t

    @State private var portalUnavailable = false

    public init(store: AgentStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        creditSection
                        DSDivider()
                        spendSection
                        DSDivider()
                        manageSection
                    }
                    .padding(18)
                }
            }
            .navigationTitle("billing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }
        }
    }

    // MARK: - Credit balance

    @ViewBuilder
    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSListSectionHead("CREDIT BALANCE")
            if let balance = store.creditBalance {
                Text(balance.creditsRemainingLabel)
                    .font(.dsMonoPt(28, weight: .semibold))
                    .foregroundStyle(t.text)

                billingRow("prepaid", value: String(format: "$%.2f", balance.prepaidUSD))
                billingRow(
                    "overage",
                    value: String(format: "$%.2f", balance.overageUSD),
                    tone: balance.overageUSD > 0 ? t.danger : nil
                )
                billingRow("allow overage", value: balance.allowOverage ? "yes" : "no")
            } else {
                Text("No billing data")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text3)
            }
        }
    }

    // MARK: - Today's spend

    @ViewBuilder
    private var spendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSListSectionHead("TODAY'S SPEND")
            let limit = store.quota.dailyUsageLimitUSD
            let spendLabel: String = limit > 0
                ? String(format: "$%.2f / $%.2f", store.quota.usageTodayUSD, limit)
                : store.usageSpendTodayLabel()
            billingRow("usage today", value: spendLabel, tone: spendTone)
            if limit > 0 {
                billingRow("daily limit", value: String(format: "$%.2f", limit))
            }
        }
    }

    private var spendTone: Color? {
        let limit = store.quota.dailyUsageLimitUSD
        guard limit > 0 else { return nil }
        let used = store.quota.usageTodayUSD
        if used >= limit { return t.danger }
        if used >= 0.8 * limit { return t.warn }
        return nil
    }

    // MARK: - Manage subscription

    @ViewBuilder
    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSButton(
                "Manage subscription",
                variant: .primary,
                mono: true,
                fullWidth: true
            ) {
                Task {
                    if let url = await store.billingPortalURL() {
                        openURL(url)
                    } else {
                        portalUnavailable = true
                    }
                }
            }

            if portalUnavailable {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Billing portal unavailable — manage at conduit.dev")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                    Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                        Text("Open conduit.dev/subscribe")
                            .font(.dsSansPt(13, weight: .semibold))
                            .foregroundStyle(t.accent)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func billingRow(_ label: String, value: String, tone: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text3)
            Spacer()
            Text(value)
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(tone ?? t.text2)
        }
        .padding(.vertical, 2)
    }
}
#endif
