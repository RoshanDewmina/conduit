#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import PersistenceKit

public struct FleetView: View {
    private let store: FleetStore
    private let hostRepo: HostRepository
    private let onConnectHost: () -> Void
    private let onReconnect: (Host) -> Void
    private let onDelete: (Host) -> Void
    private let onNewTask: () -> Void
    @State private var summary = FleetSummary(snapshots: [])
    @State private var savedHosts: [Host] = []

    @Environment(\.conduitTokens) private var t

    public init(
        store: FleetStore,
        hostRepo: HostRepository,
        onConnectHost: @escaping () -> Void,
        onReconnect: @escaping (Host) -> Void,
        onDelete: @escaping (Host) -> Void,
        onNewTask: @escaping () -> Void = {}
    ) {
        self.store = store
        self.hostRepo = hostRepo
        self.onConnectHost = onConnectHost
        self.onReconnect = onReconnect
        self.onDelete = onDelete
        self.onNewTask = onNewTask
    }

    private var reconnectableHosts: [Host] {
        let liveIDs = Set(store.slots.map(\.hostID))
        return savedHosts.filter { !liveIDs.contains($0.id) }
    }

    private var vendorSpend: [(label: String, amount: Double)] {
        let snapshots = store.slots.compactMap(\.bridgeStatus)
        var totals: [String: Double] = [:]
        for snap in snapshots {
            for agent in snap.agents {
                guard let usd = agent.usageUSD, usd > 0 else { continue }
                totals[agent.agent, default: 0] += usd
            }
        }
        return totals.map { (label: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    private var concurrentCount: Int {
        store.slots.compactMap(\.bridgeStatus).flatMap(\.agents)
            .compactMap(\.runningCount).reduce(0, +)
    }

    private var pendingAgentName: String? {
        guard store.allPendingApprovals > 0,
              let slot = store.firstSlotWithPendingApprovals(),
              let approval = slot.inboxVM.approvals.first(where: \.isPending)
        else { return nil }
        return agentDisplayName(approval.agent)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader(
                    "fleet",
                    breadcrumb: "agents & spend",
                    count: reconnectableHosts.isEmpty && store.slots.isEmpty
                        ? nil
                        : "\(store.slots.count + reconnectableHosts.count) hosts"
                ) {
                    DSIconButton(.plus) {
                        Haptics.selection()
                        onNewTask()
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        DSSpendHero(
                            todayUSD: summary.totalSpendUSD,
                            vendors: vendorSpend,
                            runs: summary.activeSessions,
                            concurrent: concurrentCount,
                            capUSD: nil
                        )
                        .padding(.top, 4)

                        if let agentName = pendingAgentName {
                            attentionBanner(agentName: agentName)
                                .padding(.horizontal, 18)
                        }

                        if store.slots.isEmpty && reconnectableHosts.isEmpty {
                            emptyState
                                .padding(.horizontal, 18)
                                .padding(.top, 4)
                        } else {
                            ForEach(store.slots) { slot in
                                DSListSectionHead(slot.hostName, count: slot.bridgeStatus?.agents.count)
                                if let snap = slot.bridgeStatus {
                                    ForEach(snap.agents) { agent in
                                        agentRow(agent)
                                            .padding(.horizontal, 18)
                                    }
                                } else {
                                    Text("Refreshing…")
                                        .font(.dsMonoPt(12))
                                        .foregroundStyle(t.text3)
                                        .padding(.horizontal, 18)
                                }
                            }

                            if !reconnectableHosts.isEmpty {
                                DSListSectionHead("Saved hosts", count: reconnectableHosts.count)
                                ForEach(reconnectableHosts) { host in
                                    savedHostRow(host)
                                        .padding(.horizontal, 18)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .refreshable { await refresh() }
            }
        }
        .task { await refresh() }
        .onChange(of: store.slots.count) { Task { await refresh() } }
    }

    private func attentionBanner(agentName: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(t.warn)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("waiting for approval")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.warn)
                Text("\(agentName) needs your decision")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .background(t.warnSoft)
        .overlay(
            Rectangle()
                .strokeBorder(t.warn.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        DSEmptyState(
            icon: .server,
            title: "No agents connected",
            subtitle: "Connect the SSH host where your agents work. Conduit will attach the approval bridge so risky actions pause on this phone.",
            action: (label: "Connect a host", handler: onConnectHost)
        )
    }

    private func savedHostRow(_ host: Host) -> some View {
        Button { onReconnect(host) } label: {
            HStack(spacing: 12) {
                PixelAvatar(seed: host.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(host.displayAddress)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                DSIconView(.refresh, size: 15, color: t.accent)
                    .frame(width: 44, height: 44, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsCard()
        .contextMenu {
            Button(role: .destructive) {
                onDelete(host)
                savedHosts.removeAll { $0.id == host.id }
            } label: {
                Label("Remove host", systemImage: "trash")
            }
        }
    }

    private func agentRow(_ a: AgentVendorStatus) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(a.model ?? (a.loggedIn == true ? "logged in" : "not logged in"))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            if let usd = a.usageUSD {
                Text(String(format: "$%.2f", usd))
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
            }
            DSStatusDot(tone: a.loggedIn == true ? .ok : .off, size: 8)
        }
        .dsCard()
    }

    @MainActor
    private func refresh() async {
        await store.refreshBridgeStatus()
        summary = FleetSummary(snapshots: store.slots.compactMap(\.bridgeStatus))
        savedHosts = (try? await hostRepo.all()) ?? []
    }

    private func agentDisplayName(_ source: Approval.AgentSource) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }
}
#endif
