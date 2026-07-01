#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem
import PersistenceKit

public struct FleetView: View {
    private let store: FleetStore
    private let hostRepo: HostRepository?
    private let chatRepo: ChatConversationRepository?
    private let demoHosts: [Host]
    private let loopStore: LoopStore?
    private let quotaGuardStore: QuotaGuardStore?
    private let hostHealthStore: HostHealthStore?
    private let onConnectHost: () -> Void
    private let onReconnect: (Host) -> Void
    private let onDelete: (Host) -> Void
    private let onQuotaGuard: (() -> Void)?
    /// Legacy direct-terminal callback. V1 Machines is a health and trusted-device
    /// surface, so this view no longer renders terminal entry points.
    private let onOpenTerminal: ((UUID) -> Void)?
    private let onOpenThread: ((String) -> Void)?
    /// Relay-paired machine: the daemon is reachable over the blind relay rather
    /// than a direct SSH slot, so it has no FleetStore slot. Surfaced as its own
    /// card so a relay-only user sees their connected machine here.
    private let relayActive: Bool
    private let relayHostName: String?
    private let relayAgentLabels: [String]
    private let onOpenRelayChat: (() -> Void)?
    @State private var summary = FleetSummary(snapshots: [])
    @State private var savedHosts: [Host] = []
    @State private var showingDriftFindings = false

    @Environment(\.lancerTokens) private var t

    public init(
        store: FleetStore,
        hostRepo: HostRepository? = nil,
        chatRepo: ChatConversationRepository? = nil,
        loopStore: LoopStore? = nil,
        quotaGuardStore: QuotaGuardStore? = nil,
        hostHealthStore: HostHealthStore? = nil,
        onConnectHost: @escaping () -> Void,
        onReconnect: @escaping (Host) -> Void,
        onDelete: @escaping (Host) -> Void,
        onQuotaGuard: (() -> Void)? = nil,
        onOpenTerminal: ((UUID) -> Void)? = nil,
        onOpenThread: ((String) -> Void)? = nil,
        relayActive: Bool = false,
        relayHostName: String? = nil,
        relayAgentLabels: [String] = [],
        onOpenRelayChat: (() -> Void)? = nil,
        demoHosts: [Host] = []
    ) {
        self.store = store
        self.hostRepo = hostRepo
        self.chatRepo = chatRepo
        self.demoHosts = demoHosts
        self.loopStore = loopStore
        self.quotaGuardStore = quotaGuardStore
        self.hostHealthStore = hostHealthStore
        self.onConnectHost = onConnectHost
        self.onReconnect = onReconnect
        self.onDelete = onDelete
        self.onQuotaGuard = onQuotaGuard
        self.onOpenTerminal = onOpenTerminal
        self.onOpenThread = onOpenThread
        self.relayActive = relayActive
        self.relayHostName = relayHostName
        self.relayAgentLabels = relayAgentLabels
        self.onOpenRelayChat = onOpenRelayChat
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

    // MARK: - Board focus model

    /// The primary live slot — the board's machine-detail subject. Falls back to
    /// the first live slot so the single-machine composition always has a host.
    private var focusSlot: FleetStore.Slot? {
        store.slots.first { store.connectionState(for: $0).isLive } ?? store.slots.first
    }

    /// Agents on the focused host (board: "AGENTS ON THIS HOST").
    private var focusAgents: [AgentVendorStatus] {
        focusSlot?.bridgeStatus?.agents ?? []
    }

    /// Total spend across the focused host's agents (board: "USAGE TODAY").
    private var focusUsageUSD: Double {
        focusAgents.compactMap(\.usageUSD).reduce(0, +)
    }

    /// The live loop to surface in the "RUNNING NOW" band, if any.
    private var runningLoop: Loop? {
        loopStore?.activeLoops.first { $0.status == .running }
            ?? loopStore?.activeLoops.first
    }

    public var body: some View {
        LancerPage {
            VStack(spacing: 0) {
                machineHeader

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if localAgentCount > 0 {
                            localAgentBanner
                        }

                        if let agentName = pendingAgentName {
                            attentionBanner(agentName: agentName)
                        }

                        if let loop = runningLoop {
                            runningNowBand(loop)
                        }

                        if relayActive {
                            relayMachineCard
                        }

                        if store.slots.isEmpty && reconnectableHosts.isEmpty {
                            // No SSH host. Show the empty prompt only when there's
                            // also no relay machine above; either way keep the
                            // action buttons so the user can still add a machine.
                            if !relayActive {
                                emptyState
                                    .padding(.top, 4)
                            }
                            actionButtons
                        } else {
                            if !store.slots.isEmpty {
                                agentsSection
                                statCardsRow
                            }

                            if let onQuotaGuard, quotaGuardStore != nil {
                                Button(action: onQuotaGuard) { quotaGuardEntry }
                                    .buttonStyle(.plain)
                            }

                            if !reconnectableHosts.isEmpty {
                                savedHostsSection
                            }

                            actionButtons
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .refreshable { await refresh() }
            }
        }
        .task {
            startLiveStores()
            await refresh()
#if DEBUG
            // UI-test reseeding starts from the root task and can finish just
            // after this destination first queries the repository. One bounded
            // follow-up keeps the deterministic fixture honest without adding
            // polling behavior to production Fleet.
            if savedHosts.isEmpty, ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" {
                try? await Task.sleep(for: .seconds(1))
                await refresh()
            }
#endif
        }
        .onChange(of: store.slots.count) {
            startLiveStores()
            Task { await refresh() }
        }
        // Debug reseeding and a future external host import both write through the
        // repository rather than FleetStore. Refresh the persistent host slice so
        // an already-mounted Machines view never gets stuck on its empty state.
        .onReceive(NotificationCenter.default.publisher(for: .lancerSavedHostsDidChange)) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - Header (board: serif-italic status + Bricolage name + RELAY chip)

    private var machineHeader: some View {
        let slot = focusSlot
        // With no SSH slot but an active relay, the machine IS connected — reflect
        // relayPaired so the header reads "online · relay", not "no host connected".
        let state = slot.map { store.connectionState(for: $0) }
            ?? (relayActive ? .relayPaired : nil)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine(state))
                    .font(.dsEditorialPt(16))
                    .foregroundStyle(statusColor(state))
                    .lineLimit(1)
                Text(machineName)
                    .font(.dsDisplayPt(24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            relayChip(state)
            // Always-visible add affordance — the bottom "+ Add host" button sits
            // below the fold, so surface a glass + here too.
            DSCircleButton(
                "plus",
                kind: .accent,
                diameter: 38,
                accessibilityLabel: "Add a machine",
                action: onConnectHost
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var machineName: String {
        focusSlot?.hostName
            ?? (relayActive ? (relayHostName ?? "Relay machine") : (reconnectableHosts.first?.name ?? "Machines"))
    }

    @ViewBuilder
    private func relayChip(_ state: Session.ConnectionState?) -> some View {
        let paired = state == .relayPaired
        Text(paired ? "RELAY" : "DIRECT")
            .font(.dsMonoPt(9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(paired ? t.ok : t.text3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (paired ? t.ok : t.text3).opacity(0.16),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .accessibilityLabel(paired ? "Relay paired" : "Direct connection")
    }

    // MARK: - Relay machine card (the daemon reached over the blind relay)

    private var relayMachineCard: some View {
        let host = relayHostName ?? "Relay machine"
        let agentsLine = relayAgentLabels.isEmpty
            ? "Connected over relay"
            : relayAgentLabels.joined(separator: " · ")
        return Button {
            Haptics.selection()
            onOpenRelayChat?()
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    PixelAvatar(seed: host, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(host)
                                .font(.dsSansPt(16, weight: .semibold))
                                .foregroundStyle(t.text)
                                .lineLimit(1)
                            relayChip(.relayPaired)
                        }
                        Text(agentsLine)
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    MachineHealthBadge(label: "Online", tone: t.ok)
                }

                HStack(spacing: 8) {
                    MachineFactPill(label: "Last seen now")
                    MachineFactPill(label: "Relay handles dispatch and approvals")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(host), online over relay")
        .accessibilityHint("Opens work on this machine")
    }

    private func statusLine(_ state: Session.ConnectionState?) -> String {
        switch state {
        case .connected, .relayPaired: return "online · healthy"
        case .connecting:              return "connecting…"
        case .failed:                  return "offline · unreachable"
        case .offline, .none:          return reconnectableHosts.isEmpty ? "no host connected" : "offline · saved"
        }
    }

    private func statusColor(_ state: Session.ConnectionState?) -> Color {
        switch state {
        case .connected, .relayPaired: return t.ok
        case .connecting:              return t.warn
        case .failed:                  return t.danger
        case .offline, .none:          return t.text3
        }
    }

    // MARK: - RUNNING NOW band (board: accent fill, eyebrow + title + step + bar)

    private func runningNowBand(_ loop: Loop) -> some View {
        Button {
            Haptics.selection()
            if let slot = focusSlot {
                openLatestThread(for: slot)
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("RUNNING NOW")
                        .font(.dsMonoPt(9.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(t.accentFg.opacity(0.82))
                    Spacer(minLength: 8)
                    if let step = loop.currentStep {
                        Text(step)
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.accentFg.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Text(loop.goal)
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .lineLimit(2)
                loopProgressBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Running now: \(loop.goal)")
        .accessibilityHint("Opens the latest work thread when available")
    }

    private var loopProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(t.accentFg.opacity(0.22))
                Capsule()
                    .fill(t.accentFg)
                    .frame(width: max(12, geo.size.width * 0.62))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    // MARK: - Agents on this host

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LancerSectionLabel("Agents on this host")

            VStack(spacing: 0) {
                let slot = focusSlot
                let state = slot.map { store.connectionState(for: $0) }
                if let state, state.isLive, !focusAgents.isEmpty {
                    ForEach(Array(focusAgents.enumerated()), id: \.element.id) { index, agent in
                        agentRow(agent)
                        if index < focusAgents.count - 1 { rowDivider }
                    }
                    rowDivider
                } else if slot != nil {
                    statusRow(slotStatusLine(state ?? .offline), tone: state == .failed ? t.danger : t.text3)
                    rowDivider
                } else {
                    statusRow("No agents connected.", tone: t.text3)
                    rowDivider
                }

            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 15)
    }

    private func agentRow(_ a: AgentVendorStatus) -> some View {
        let running = a.loggedIn == true
        return Button {
            openRelatedThread(agent: a)
        } label: {
            HStack(spacing: 11) {
            initialTile(a.displayName)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.displayName)
                    .font(.dsSansPt(13.5, weight: .semibold))
                    .foregroundStyle(t.text)
                if let model = a.model {
                    Text(model)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text4)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge = privacyVariant(a) {
                PrivacyBadge(badge)
            }
            DSStatusDot(tone: running ? .ok : .off, pulse: running, size: 8)
            Text(running ? "running" : "idle")
                .font(.dsMonoPt(10.5))
                .foregroundStyle(running ? t.ok : t.text4)
                .frame(width: 52, alignment: .leading)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(a.displayName), \(running ? "running" : "idle")")
        .accessibilityHint("Opens this agent's latest related chat, or its terminal when none exists.")
    }

    private func openRelatedThread(agent: AgentVendorStatus) {
        guard let slot = focusSlot else { return }
        Haptics.selection()
        guard let chatRepo, let onOpenThread else {
            return
        }
        Task {
            let conversation = await FleetThreadMapper.findConversation(
                hostName: slot.hostName,
                agentID: agent.agent,
                cwd: slot.sessionViewModel.cwd,
                chatRepo: chatRepo
            )
            await MainActor.run {
                if let conversation {
                    onOpenThread(conversation.id)
                }
            }
        }
    }

    private func initialTile(_ name: String) -> some View {
        Text(agentInitial(name))
            .font(.dsDisplayPt(11, weight: .bold))
            .foregroundStyle(t.accentFg)
            .frame(width: 28, height: 28)
            .background(t.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func agentInitial(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("codex") { return "Cx" }
        if key.contains("claude") { return "C" }
        if key.contains("kimi") { return "K" }
        if key.contains("opencode") || key.contains("open") { return "O" }
        return String(name.prefix(1)).uppercased()
    }

    private func statusRow(_ text: String, tone: Color) -> some View {
        HStack {
            Text(text)
                .font(.dsMonoPt(12))
                .foregroundStyle(tone)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stat cards (board: USAGE TODAY / CONNECTION)

    private var statCardsRow: some View {
        let state = focusSlot.map { store.connectionState(for: $0) }
        return HStack(spacing: 11) {
            statCard(
                label: "Usage today",
                value: usageDisplay,
                valueColor: t.text
            )
            statCard(
                label: "Connection",
                value: connectionLabel(state),
                valueColor: statusColor(state)
            )
            driftStatCard
        }
        .sheet(isPresented: $showingDriftFindings) {
            if let report = focusDrift {
                DriftRemediationView(report: report, channel: focusSlot?.channel)
            }
        }
    }

    // Tappable only when there are findings to drill into; otherwise a plain
    // read-only summary (Clean / —), matching the other stat cards.
    @ViewBuilder
    private var driftStatCard: some View {
        let card = statCard(label: "Setup drift", value: driftDisplay, valueColor: driftColor)
        if let report = focusDrift, !report.findings.isEmpty {
            Button {
                Haptics.selection()
                showingDriftFindings = true
            } label: { card }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the \(report.findings.count) drift findings")
        } else {
            card
        }
    }

    private var focusDrift: DriftReport? {
        guard let hostHealthStore, let id = focusSlot?.hostID else { return nil }
        return hostHealthStore.drift(for: id)
    }

    private var driftDisplay: String {
        guard let report = focusDrift else { return "—" }
        return report.findings.isEmpty ? "Clean" : "\(report.findings.count)"
    }

    private var driftColor: Color {
        guard let report = focusDrift else { return t.text4 }
        return report.findings.isEmpty ? t.ok : t.danger
    }

    private var usageDisplay: String {
        let spend = focusUsageUSD
        if spend <= 0 { return "$0.00" }
        return String(format: "$%.2f", spend)
    }

    private func connectionLabel(_ state: Session.ConnectionState?) -> String {
        switch state {
        case .connected, .relayPaired: return "Healthy"
        case .connecting:              return "Connecting"
        case .failed:                  return "Unreachable"
        case .offline, .none:          return "Offline"
        }
    }

    private func statCard(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.dsMonoPt(9.5, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(t.text4)
            Text(value)
                .font(.dsDisplayPt(15, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 11) {
            DSButton("Reconnect", systemImage: "arrow.clockwise", variant: .secondary, fullWidth: true) {
                Haptics.selection()
                if let host = reconnectableHosts.first ?? savedHosts.first { onReconnect(host) }
            }
            .disabled(reconnectableHosts.isEmpty && savedHosts.isEmpty)
            .accessibilityLabel("Reconnect")

            DSButton("Add a machine", icon: .plus, variant: .primary, fullWidth: true) {
                Haptics.selection()
                onConnectHost()
            }
            .accessibilityLabel("Add a machine")
        }
    }

    // MARK: - Saved hosts (kept for multi-host data)

    private var savedHostsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LancerSectionLabel("Saved hosts", detail: "\(reconnectableHosts.count)")
            savedHostsGroup(reconnectableHosts)
        }
    }

    // MARK: - Live stores

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
        LancerAttentionBand(
            eyebrow: "Decision needed",
            title: agentName,
            detail: "\(agentName) is waiting for your approval.",
            tone: .attention,
            action: pendingApprovalAction
        )
    }

    private var pendingApprovalAction: (() -> Void)? {
        guard let slot = store.firstSlotWithPendingApprovals() else { return nil }
        return { openLatestThread(for: slot) }
    }

    private var emptyState: some View {
        DSEmptyState(
            icon: .server,
            title: "No machines paired",
            subtitle: "Pair the machine where your agents run. Lancer will use the relay for dispatch, output, and approvals without turning this phone into a terminal."
        )
    }

    private func openLatestThread(for slot: FleetStore.Slot) {
        guard let chatRepo, let onOpenThread else { return }
        let agentID = slot.inboxVM.approvals.first(where: \.isPending)?.agent.rawValue
            ?? slot.bridgeStatus?.agents.first?.agent
            ?? "claudeCode"
        Task {
            let conversation = await FleetThreadMapper.findConversation(
                hostName: slot.hostName,
                agentID: agentID,
                cwd: slot.sessionViewModel.cwd,
                chatRepo: chatRepo
            )
            await MainActor.run {
                if let conversation {
                    Haptics.selection()
                    onOpenThread(conversation.id)
                }
            }
        }
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

    private func privacyVariant(_ a: AgentVendorStatus) -> PrivacyBadgeVariant? {
        if let isLocalModel = a.isLocalModel {
            return isLocalModel ? .local : (a.dataLeavesHost == true ? .cloud(provider: a.displayName) : .e2eRelay)
        }
        if a.local {
            return .local
        }
        return nil
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

private struct MachineHealthBadge: View {
    let label: String
    let tone: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(.dsMonoPt(10, weight: .semibold))
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tone.opacity(0.12), in: Capsule())
    }
}

private struct MachineFactPill: View {
    let label: String
    @Environment(\.lancerTokens) private var t

    var body: some View {
        Text(label)
            .font(.dsMonoPt(10, weight: .medium))
            .foregroundStyle(t.text4)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
#endif
