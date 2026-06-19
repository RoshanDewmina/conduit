#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import PersistenceKit

public struct FleetView: View {
    private let store: FleetStore
    private let hostRepo: HostRepository?
    private let demoHosts: [Host]
    private let loopStore: LoopStore?
    private let quotaGuardStore: QuotaGuardStore?
    private let hostHealthStore: HostHealthStore?
    private let onConnectHost: () -> Void
    private let onReconnect: (Host) -> Void
    private let onDelete: (Host) -> Void
    private let onQuotaGuard: (() -> Void)?
    /// Open the live block terminal for a given slot (Finding #5 drill-in).
    private let onOpenTerminal: ((UUID) -> Void)?
    @State private var summary = FleetSummary(snapshots: [])
    @State private var savedHosts: [Host] = []

    @Environment(\.conduitTokens) private var t

    public init(
        store: FleetStore,
        hostRepo: HostRepository? = nil,
        loopStore: LoopStore? = nil,
        quotaGuardStore: QuotaGuardStore? = nil,
        hostHealthStore: HostHealthStore? = nil,
        onConnectHost: @escaping () -> Void,
        onReconnect: @escaping (Host) -> Void,
        onDelete: @escaping (Host) -> Void,
        onQuotaGuard: (() -> Void)? = nil,
        onOpenTerminal: ((UUID) -> Void)? = nil,
        demoHosts: [Host] = []
    ) {
        self.store = store
        self.hostRepo = hostRepo
        self.demoHosts = demoHosts
        self.loopStore = loopStore
        self.quotaGuardStore = quotaGuardStore
        self.hostHealthStore = hostHealthStore
        self.onConnectHost = onConnectHost
        self.onReconnect = onReconnect
        self.onDelete = onDelete
        self.onQuotaGuard = onQuotaGuard
        self.onOpenTerminal = onOpenTerminal
    }

    private var reconnectableHosts: [Host] {
        let liveIDs = Set(store.slots.map(\.hostID))
        let hosts = savedHosts.isEmpty ? demoHosts : savedHosts
        return hosts.filter { !liveIDs.contains($0.id) }
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

    private var localAgentCount: Int {
        store.slots.compactMap(\.bridgeStatus)
            .flatMap(\.agents)
            .filter(\.local)
            .count
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                fleetHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if localAgentCount > 0 {
                            localAgentBanner
                                .padding(.horizontal, 18)
                        }

                        if let agentName = pendingAgentName {
                            attentionBanner(agentName: agentName)
                                .padding(.horizontal, 18)
                        }

                        if let loopStore, !loopStore.activeLoops.isEmpty {
                            DSListSectionHead("Active Loops", count: loopStore.activeLoops.count)
                            ForEach(loopStore.activeLoops) { loop in
                                NavigationLink {
                                    LoopDetailView(loop: loop, ciEventLoader: ciEventLoader(for: loop), gitStore: gitStore(for: loop))
                                } label: {
                                    loopRow(loop)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 18)
                            }
                        }

                        if let onQuotaGuard, quotaGuardStore != nil {
                            Button(action: onQuotaGuard) {
                                quotaGuardEntry
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 18)
                        }

                        if store.slots.isEmpty && reconnectableHosts.isEmpty {
                            emptyState
                                .padding(.horizontal, 18)
                                .padding(.top, 4)
                        } else {
                            ForEach(store.slots) { slot in
                                let slotState = store.connectionState(for: slot)
                                HStack(spacing: 6) {
                                    DSStatusDot(tone: slotTone(slotState), pulse: slotState == .connecting, size: 7)
                                    DSListSectionHead(slot.hostName, count: slot.bridgeStatus?.agents.count)
                                    E2ERelayStatusBadge(state: .init(relayState: slot.relayState))
                                    if let health = hostHealthStore?.health(for: slot.hostID) {
                                        HostHealthBadge(health: health)
                                    }
                                    // Finding #5: explicit one-tap drill-in to the
                                    // block terminal. Connecting lands on monitoring;
                                    // the terminal is opened intentionally from here.
                                    if let onOpenTerminal, slotState.isLive {
                                        Button {
                                            Haptics.selection()
                                            onOpenTerminal(slot.id)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "terminal")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text("terminal")
                                                    .font(.dsMonoPt(11, weight: .medium))
                                            }
                                            .foregroundStyle(t.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(t.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 18)
                                        .accessibilityLabel("Open terminal for \(slot.hostName)")
                                    }
                                }
                                // Only surface agents / a "Refreshing…" placeholder
                                // once the bridge is actually live — a connecting or
                                // failed slot must say so honestly (Finding #9).
                                if slotState.isLive, let snap = slot.bridgeStatus {
                                    ForEach(snap.agents) { agent in
                                        agentRow(agent)
                                            .padding(.horizontal, 18)
                                    }
                                } else {
                                    Text(slotStatusLine(slotState))
                                        .font(.dsMonoPt(12))
                                        .foregroundStyle(slotState == .failed ? t.danger : t.text3)
                                        .padding(.horizontal, 18)
                                }
                            }

                            if !reconnectableHosts.isEmpty {
                                sectionHeader("Saved hosts", count: reconnectableHosts.count)
                                savedHostsGroup(reconnectableHosts)
                                    .padding(.horizontal, 16)
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
        .task {
            startLiveStores()
            await refresh()
        }
        .onChange(of: store.slots.count) {
            startLiveStores()
            Task { await refresh() }
        }
    }

    private var fleetHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Fleet")
                    .font(.dsDisplayPt(30, weight: .bold))
                    .foregroundStyle(t.text)
                Text(fleetSubtitle)
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            Button(action: onConnectHost) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .frame(width: 42, height: 42)
                    .background(t.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add host")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var fleetSubtitle: String {
        let hostCount = store.slots.count + reconnectableHosts.count
        if hostCount == 0 {
            return "Your connected workspaces"
        }
        return hostCount == 1 ? "1 host available" : "\(hostCount) hosts available"
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title)
                .font(.dsSansPt(15, weight: .semibold))
                .foregroundStyle(t.text2)
            if let count {
                Text("\(count)")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// Attach a daemon channel to the quota-guard store and start host-health
    /// polling once a connected slot exists. Both calls are idempotent.
    private func startLiveStores() {
        if let channel = store.slots.first?.channel {
            quotaGuardStore?.setChannel(channel)
        }
        if let hostHealthStore, !store.slots.isEmpty {
            hostHealthStore.startPolling(fleetStore: store)
        }
    }

    private var quotaGuardEntry: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 13))
                .foregroundStyle(t.info)
            Text("Usage & limits")
                .font(.dsSansPt(14, weight: .medium))
                .foregroundStyle(t.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private var worktreesLink: some View {
        HStack(spacing: 12) {
            DSIconView(.folder, size: 18, color: t.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Branches & Worktrees")
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                Text("Multi-branch supervision")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .dsCard()
    }

    private var localAgentBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(t.ok)
                .frame(width: 32, height: 32)
                .background(t.okSoft, in: Circle())
            Text("\(localAgentCount) agent\(localAgentCount == 1 ? "" : "s") run\(localAgentCount == 1 ? "s" : "") a local model — prompts and code never leave the host.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private func attentionBanner(agentName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(t.warn)
                .frame(width: 32, height: 32)
                .background(t.warnSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Decision needed")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("\(agentName) is waiting for your approval.")
                    .font(.dsSansPt(12.5))
                    .foregroundStyle(t.text3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private var emptyState: some View {
        DSEmptyState(
            icon: .server,
            title: "No agents connected",
            subtitle: "Connect the SSH host where your agents work. Conduit will attach the approval bridge so risky actions pause on this phone."
        )
    }

    private func savedHostsGroup(_ hosts: [Host]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                savedHostRow(host)
                if index < hosts.count - 1 {
                    Rectangle()
                        .fill(t.divider)
                        .frame(height: 1)
                        .padding(.leading, 66)
                }
            }
        }
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private func savedHostRow(_ host: Host) -> some View {
        Button { onReconnect(host) } label: {
            HStack(spacing: 12) {
                PixelAvatar(seed: host.name, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.name)
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(host.displayAddress)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 36, height: 36)
                    .background(t.accentSoft, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reconnect to \(host.name)")
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
                HStack(spacing: 6) {
                    DSStatusDot(tone: a.loggedIn == true ? .ok : .off, size: 7)
                    Text(a.loggedIn == true ? "running" : "idle")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                    if let badge = privacyVariant(a) {
                        PrivacyBadge(badge)
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
            if let usd = a.usageUSD {
                Text(String(format: "$%.2f", usd))
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
            }
        }
        .dsCard()
    }

    private func privacyVariant(_ a: AgentVendorStatus) -> PrivacyBadgeVariant? {
        if let isLocalModel = a.isLocalModel {
            return isLocalModel ? .local : (a.dataLeavesHost == true ? .cloud(provider: a.displayName) : .e2eRelay)
        }
        if a.local {
            return .local
        }
        return nil
    }

    private func loopRow(_ loop: Loop) -> some View {
        HStack(spacing: 12) {
            DSStatusDot(
                tone: loopStatusDotTone(loop.status),
                pulse: loop.status == .running,
                size: 8
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(loop.goal)
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(loop.agent)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                    if let model = loop.model {
                        Text("· \(model)")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text4)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                DSChip(loop.status.rawValue, tone: loopChipTone(loop.status), variant: .outlined, size: .sm)
                if loop.spendUSD > 0 {
                    Text(String(format: "$%.2f", loop.spendUSD))
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .dsCard()
    }

    /// Build a CI-event loader for a loop, sourced from the daemon channel of
    /// the slot hosting it (or the first slot as a fallback). Returns nil when
    /// the loop has no repo or no channel is available.
    private func ciEventLoader(for loop: Loop) -> (@Sendable () async -> [CIEvent])? {
        guard let repo = loop.repo, !repo.isEmpty else { return nil }
        let slot = store.slots.first { $0.hostID.uuidString == loop.hostID } ?? store.slots.first
        guard let channel = slot?.channel else { return nil }
        return { (try? await channel.recentCIEvents(repo: repo)) ?? [] }
    }

    /// Build a GitStore for a loop's worktree so the Loop detail can review +
    /// ship the agent's git work. Returns nil when the loop has no worktree path
    /// or no host channel — the "Changes" section is then hidden.
    private func gitStore(for loop: Loop) -> GitStore? {
        // The worktree field carries the agent's actual on-host path; loop.repo is
        // a slug ("owner/name"), not a workdir, so it can't seed git ops.
        guard let workdir = loop.worktree, !workdir.isEmpty else { return nil }
        let slot = store.slots.first { $0.hostID.uuidString == loop.hostID } ?? store.slots.first
        guard let channel = slot?.channel else { return nil }
        return GitStore(channel: channel, workdir: workdir)
    }

    private func loopStatusDotTone(_ status: Loop.Status) -> DSStatusDotTone {
        switch status {
        case .running:   return .ok
        case .blocked:   return .warn
        case .paused:    return .info
        case .completed: return .ok
        case .failed:    return .danger
        case .cancelled: return .off
        }
    }

    private func loopChipTone(_ status: Loop.Status) -> DSChipTone {
        switch status {
        case .running:   return .ok
        case .blocked:   return .warn
        case .paused:    return .info
        case .completed: return .ok
        case .failed:    return .danger
        case .cancelled: return .neutral
        }
    }

    @MainActor
    private func refresh() async {
        await store.refreshBridgeStatus()
        summary = FleetSummary(snapshots: store.slots.compactMap(\.bridgeStatus))
        if let hostRepo {
            savedHosts = (try? await hostRepo.all()) ?? []
        }
        await loopStore?.refresh()
        await hostHealthStore?.refresh(fleetStore: store)
    }

    private func slotTone(_ state: Session.ConnectionState) -> DSStatusDotTone {
        switch state {
        case .connected, .relayPaired: return .ok
        case .connecting:              return .warn
        case .failed:                  return .danger
        case .offline:                 return .off
        }
    }

    private func slotStatusLine(_ state: Session.ConnectionState) -> String {
        switch state {
        case .connected, .relayPaired: return "Refreshing…"
        case .connecting:              return "Connecting…"
        case .failed:                  return "Bridge unreachable — tap reconnect."
        case .offline:                 return "Offline."
        }
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
