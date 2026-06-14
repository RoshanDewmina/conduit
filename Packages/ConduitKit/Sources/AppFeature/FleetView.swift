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
    @State private var summary = FleetSummary(snapshots: [])
    @State private var savedHosts: [Host] = []

    @Environment(\.conduitTokens) private var t

    public init(
        store: FleetStore,
        hostRepo: HostRepository,
        onConnectHost: @escaping () -> Void,
        onReconnect: @escaping (Host) -> Void,
        onDelete: @escaping (Host) -> Void
    ) {
        self.store = store
        self.hostRepo = hostRepo
        self.onConnectHost = onConnectHost
        self.onReconnect = onReconnect
        self.onDelete = onDelete
    }

    /// Saved hosts that aren't currently live — the reconnect candidates.
    private var reconnectableHosts: [Host] {
        let liveIDs = Set(store.slots.map(\.hostID))
        return savedHosts.filter { !liveIDs.contains($0.id) }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── BLOCKS header (matches Inbox / Settings)
                DSScreenHeader(
                    "fleet",
                    breadcrumb: "agents & spend",
                    count: reconnectableHosts.isEmpty && store.slots.isEmpty
                        ? nil
                        : "\(store.slots.count + reconnectableHosts.count) hosts"
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        if store.slots.isEmpty && reconnectableHosts.isEmpty {
                            emptyState
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        } else {
                            ForEach(store.slots) { slot in
                                DSListSectionHead(slot.hostName, count: slot.bridgeStatus?.agents.count)
                                if let snap = slot.bridgeStatus {
                                    ForEach(snap.agents) { agent in
                                        agentRow(agent)
                                            .padding(.horizontal, 16)
                                    }
                                } else {
                                    Text("Refreshing…")
                                        .font(.dsMonoPt(12))
                                        .foregroundStyle(t.text3)
                                        .padding(.horizontal, 16)
                                }
                            }

                            if !reconnectableHosts.isEmpty {
                                DSListSectionHead("Saved hosts", count: reconnectableHosts.count)
                                ForEach(reconnectableHosts) { host in
                                    savedHostRow(host)
                                        .padding(.horizontal, 16)
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
                    Text(host.name).font(.dsSansPt(14, weight: .semibold)).foregroundStyle(t.text)
                    Text(host.displayAddress).font(.dsMonoPt(11)).foregroundStyle(t.text3)
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

    private var summaryCard: some View {
        HStack(spacing: 16) {
            stat("\(summary.loggedInVendors)", "vendors")
            divider
            stat("\(summary.activeSessions)", "sessions")
            divider
            stat(String(format: "$%.2f", summary.totalSpendUSD), "today")
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private var divider: some View {
        Rectangle().fill(t.divider).frame(width: 1, height: 28)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.dsMonoPt(17)).foregroundStyle(t.text)
            Text(label).font(.dsMonoPt(11)).foregroundStyle(t.text2)
        }
        .frame(maxWidth: .infinity)
    }

    private func agentRow(_ a: AgentVendorStatus) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName).font(.dsSansPt(14, weight: .semibold)).foregroundStyle(t.text)
                Text(a.model ?? (a.loggedIn == true ? "logged in" : "not logged in"))
                    .font(.dsMonoPt(11)).foregroundStyle(t.text3)
            }
            Spacer()
            if let usd = a.usageUSD {
                Text(String(format: "$%.2f", usd)).font(.dsMonoPt(12)).foregroundStyle(t.text2)
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
}
#endif
