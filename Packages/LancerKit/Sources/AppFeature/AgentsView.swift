#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SSHTransport
import SettingsFeature

// MARK: - Agents (provider list)

public struct AgentsView: View {
    @Bindable var store: AgentStore
    private let statusChannel: DaemonChannel?
    @State private var pm = PurchaseManager.shared
    @State private var showingCreate = false
    @State private var showingBilling = false
    @State private var selectedAgent: HostedAgent?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    public init(store: AgentStore, statusChannel: DaemonChannel? = nil) {
        self.store = store
        self.statusChannel = statusChannel
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                headerSection
                if !store.hasCloudEntitlement {
                    cloudGate
                } else {
                    providerList
                    addButton
                }
                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .task {
            await pm.refreshCloudEntitlement()
            await store.loadAgents()
            await store.loadBillingSnapshot()
            if let statusChannel {
                await store.refreshBridgeStatus(using: statusChannel)
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateAgentSheet(store: store)
        }
        .sheet(isPresented: $showingBilling) {
            AgentBillingSheet(store: store)
        }
        .navigationDestination(item: $selectedAgent) { agent in
            AgentDetailView(store: store, agent: agent, gitChannel: statusChannel)
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Text("Settings")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
            if store.hasCloudEntitlement {
                Button {
                    showingBilling = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 36, height: 36)
                        .background(t.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents")
                .font(.dsDisplayPt(24, weight: .bold))
                .foregroundStyle(t.text)
            Text("Configure providers for agent execution")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: - Provider list

    private var providerList: some View {
        VStack(spacing: 10) {
            if store.isLoading {
                DSSkeletonList(count: 3, showAvatar: true)
            } else if store.agents.isEmpty {
                Spacer()
                DSEmptyState(
                    icon: .sparkles,
                    title: "no agents",
                    subtitle: "Create a hosted agent to run claude or codex on your SSH host or cloud runtime."
                )
                Spacer()
            } else {
                ForEach(store.agents) { agent in
                    Button {
                        selectedAgent = agent
                    } label: {
                        providerRow(agent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func providerRow(_ agent: HostedAgent) -> some View {
        HStack(spacing: 12) {
            providerIcon(for: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                Text("\(agent.runtimeKind.displayName) · \(agent.model)")
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
            }
            Spacer()
            if agent.isActive {
                HStack(spacing: 6) {
                    DSStatusDot(tone: .ok, size: 5)
                    Text("ready")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.ok)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(t.okSoft.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .strokeBorder(t.ok.opacity(0.3), lineWidth: 1))
            } else {
                Text("not configured")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1))
            }
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private func providerIcon(for agent: HostedAgent) -> some View {
        let name = agent.name.lowercased()
        if name.contains("claude") {
            // Orange dot grid — Claude's brand mark
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(t.accent)
                    .frame(width: 20, height: 20)
                Text("C")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else if name.contains("codex") {
            // Dark icon — Codex
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(t.text4)
                    .frame(width: 20, height: 20)
                Text("X")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else if name.contains("gemini") {
            // G letter tile
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(t.surface2)
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(t.border, lineWidth: 1))
                Text("G")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(t.text3)
            }
        } else {
            PixelAvatar(seed: agent.name, size: 32)
        }
    }

    // MARK: - Add provider button

    private var addButton: some View {
        Button {
            showingCreate = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("Add provider")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(t.borderStrong))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    // MARK: - Cloud gate

    private var cloudGate: some View {
        VStack(spacing: 16) {
            Spacer()
            DSEmptyState(
                icon: .sparkles,
                title: "Lancer Cloud required",
                subtitle: "Hosted agents need an active Lancer Cloud subscription. Manage billing in Settings."
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
}
#endif
