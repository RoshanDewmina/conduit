#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

public struct AgentsView: View {
    @Bindable var store: AgentStore
    @State private var pm = PurchaseManager.shared
    @State private var showingCreate = false
    @State private var showingBilling = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(store: AgentStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("agents", onBack: { dismiss() }) {
                    if store.hasCloudEntitlement {
                        DSIconButton(.settings) { showingBilling = true }
                        DSIconButton(.plus) { showingCreate = true }
                    }
                }

                if !store.hasCloudEntitlement {
                    cloudGate
                } else {
                    quotaStrip
                    if store.isLoading {
                        DSSkeletonList(count: 3, showAvatar: true)
                        Spacer()
                    } else if store.agents.isEmpty {
                        Spacer()
                        DSEmptyState(
                            icon: .sparkles,
                            title: "no agents",
                            subtitle: "Create a hosted agent to run claude or codex on your SSH host or cloud runtime."
                        )
                        Spacer()
                    } else {
                        agentList
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await pm.refreshCloudEntitlement()
            await store.loadAgents()
            await store.loadBillingSnapshot()
        }
        .sheet(isPresented: $showingCreate) {
            CreateAgentSheet(store: store)
        }
        .sheet(isPresented: $showingBilling) {
            AgentBillingSheet(store: store)
        }
    }

    /// ≥80% of the daily usage limit warns; at/over the limit is danger.
    private var usageTone: Color {
        let limit = store.quota.dailyUsageLimitUSD
        guard limit > 0 else { return t.text2 }
        let used = store.quota.usageTodayUSD
        if used >= limit { return t.danger }
        if used >= 0.8 * limit { return t.warn }
        return t.text2
    }

    private var concurrentTone: Color {
        store.quota.concurrentRuns >= store.quota.concurrentRunsLimit ? t.danger : t.text2
    }

    private var quotaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                quotaChip("agents", value: "\(store.quota.agentsUsed)/\(store.quota.agentsLimit)")
                quotaChip("runs today", value: "\(store.quota.runsToday)")
                quotaChip(
                    "concurrent",
                    value: "\(store.quota.concurrentRuns)/\(store.quota.concurrentRunsLimit)",
                    tone: concurrentTone
                )
                if let credits = store.quota.creditsRemainingUSD {
                    quotaChip("credits", value: String(format: "$%.2f", credits))
                } else if store.quota.dailyUsageLimitUSD > 0 {
                    quotaChip(
                        "usage today",
                        value: String(
                            format: "$%.0f / $%.0f",
                            store.quota.usageTodayUSD,
                            store.quota.dailyUsageLimitUSD
                        ),
                        tone: usageTone
                    )
                } else {
                    quotaChip("usage today", value: store.usageSpendTodayLabel(), tone: usageTone)
                }
                if (store.creditBalance?.overageUSD ?? 0) > 0 {
                    quotaChip(
                        "overage",
                        value: String(format: "+$%.2f over", store.creditBalance?.overageUSD ?? 0),
                        tone: t.danger
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func quotaChip(_ label: String, value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text4)
            Text(value)
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(tone ?? t.text2)
        }
        .frame(minWidth: 88, alignment: .leading)
        .padding(10)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
    }

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.agents) { agent in
                    NavigationLink {
                        AgentDetailView(store: store, agent: agent)
                    } label: {
                        agentRow(agent)
                    }
                    .buttonStyle(.plain)
                    DSDivider()
                }
            }
        }
    }

    private var cloudGate: some View {
        VStack(spacing: 16) {
            Spacer()
            DSEmptyState(
                icon: .sparkles,
                title: "Conduit Cloud required",
                subtitle: "Hosted agents need an active Conduit Cloud subscription. Manage billing in Settings."
            )
            if pm.externalStripeEligible {
                Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                    Text("Subscribe at conduit.dev")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: HostedAgent) -> some View {
        HStack(spacing: 12) {
            PixelAvatar(seed: agent.name, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text("\(agent.runtimeKind.displayName) · \(agent.model)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                DSStatusDot(tone: agent.isActive ? .ok : .off, pulse: agent.isActive)
                Text(store.monthlyCostLabel(for: agent))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
#endif
