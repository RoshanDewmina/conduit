#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

public struct FleetView: View {
    private let store: FleetStore
    private let onConnectHost: () -> Void
    @State private var summary = FleetSummary(snapshots: [])

    @Environment(\.conduitTokens) private var t

    public init(store: FleetStore, onConnectHost: @escaping () -> Void) {
        self.store = store
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        List {
            Section { summaryStrip }
            if store.slots.isEmpty {
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
            }
        }
        .navigationTitle("Fleet")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
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
    }
}
#endif
