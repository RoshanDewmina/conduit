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
        List {
            Section { summaryStrip }
            if store.slots.isEmpty && reconnectableHosts.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No agents connected", systemImage: "server.rack")
                    } description: {
                        Text("Connect a host running conduitd to see your agents, their status, and spend.")
                    } actions: {
                        Button("Connect a host", action: onConnectHost)
                    }
                }
            } else {
                ForEach(store.slots) { slot in
                    Section(slot.hostName) {
                        if let snap = slot.bridgeStatus {
                            ForEach(snap.agents) { agent in
                                agentRow(agent)
                            }
                        } else {
                            Text("Refreshing…").font(.caption).foregroundStyle(t.text3)
                        }
                    }
                }
                if !reconnectableHosts.isEmpty {
                    Section("Saved hosts") {
                        ForEach(reconnectableHosts) { host in
                            savedHostRow(host)
                        }
                        .onDelete { offsets in
                            let hosts = offsets.map { reconnectableHosts[$0] }
                            for host in hosts {
                                onDelete(host)
                                savedHosts.removeAll { $0.id == host.id }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fleet")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
        .onChange(of: store.slots.count) { Task { await refresh() } }
    }

    private func savedHostRow(_ host: Host) -> some View {
        Button { onReconnect(host) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name).font(.dsSansPt(14)).foregroundStyle(t.text)
                    Text(host.displayAddress).font(.dsMonoPt(11)).foregroundStyle(t.text3)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(t.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            stat("\(summary.loggedInVendors)", "vendors")
            stat("\(summary.activeSessions)", "sessions")
            stat(String(format: "$%.2f", summary.totalSpendUSD), "today")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.dsMonoPt(16)).foregroundStyle(t.text)
            Text(label).font(.caption2).foregroundStyle(t.text3)
        }
    }

    private func agentRow(_ a: AgentVendorStatus) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName).font(.dsSansPt(14)).foregroundStyle(t.text)
                Text(a.model ?? (a.loggedIn == true ? "logged in" : "not logged in"))
                    .font(.dsMonoPt(11)).foregroundStyle(t.text3)
            }
            Spacer()
            if let usd = a.usageUSD {
                Text(String(format: "$%.2f", usd)).font(.dsMonoPt(12)).foregroundStyle(t.text2)
            }
            Circle()
                .fill(a.loggedIn == true ? t.ok : t.text4)
                .frame(width: 8, height: 8)
        }
    }

    @MainActor
    private func refresh() async {
        await store.refreshBridgeStatus()
        summary = FleetSummary(snapshots: store.slots.compactMap(\.bridgeStatus))
        savedHosts = (try? await hostRepo.all()) ?? []
    }
}
#endif
