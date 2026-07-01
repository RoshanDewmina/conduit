#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem
import PersistenceKit
import AgentKit

public struct LancerHomeView: View {
    private let fleetStore: FleetStore
    private let recentThreads: [ChatConversation]
    private let pendingApprovalCount: Int
    private let profileEmail: String?
    /// A relay-paired host, if any. Relay hosts aren't `fleetStore` slots (they're
    /// the E2E bridge), so Home must be told about them explicitly or they never
    /// appear here even while connected. Passed whenever a pairing is *stored* (so a
    /// known host doesn't vanish during reconnect), with `relayHostConnected`
    /// carrying whether the bridge is live right now (drives the status dot).
    private let relayHostName: String?
    private let relayHostConnected: Bool
    private let onOpenSidebar: (() -> Void)?
    private let onNewChat: () -> Void
    private let onOpenInbox: () -> Void
    private let onOpenMachines: () -> Void
    private let onOpenThread: (String) -> Void
    private let onOpenObservedSession: (ObservedSession) -> Void
    /// Fetches watch-only sessions discovered on the host (Claude Code, etc.) —
    /// separate from `recentThreads`, which are Lancer-dispatched runs. Defaults to
    /// `{ [] }` so previews/tests compile without a live daemon.
    private let loadSessions: () async -> [ObservedSession]

    @Environment(\.lancerTokens) private var t
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var collapsed: Set<String> = []
    @State private var observedSessions: [ObservedSession] = []
    @State private var sessionsLoading = true
    @State private var reviewingApproval: Approval?

    public init(
        fleetStore: FleetStore,
        recentThreads: [ChatConversation],
        pendingApprovalCount: Int,
        profileEmail: String? = nil,
        relayHostName: String? = nil,
        relayHostConnected: Bool = false,
        onOpenSidebar: (() -> Void)? = nil,
        onNewChat: @escaping () -> Void,
        onOpenInbox: @escaping () -> Void,
        onOpenMachines: @escaping () -> Void,
        onOpenThread: @escaping (String) -> Void,
        onOpenObservedSession: @escaping (ObservedSession) -> Void = { _ in },
        loadSessions: @escaping () async -> [ObservedSession] = { [] }
    ) {
        self.fleetStore = fleetStore
        self.recentThreads = recentThreads
        self.pendingApprovalCount = pendingApprovalCount
        self.profileEmail = profileEmail
        self.relayHostName = relayHostName
        self.relayHostConnected = relayHostConnected
        self.onOpenSidebar = onOpenSidebar
        self.onNewChat = onNewChat
        self.onOpenInbox = onOpenInbox
        self.onOpenMachines = onOpenMachines
        self.onOpenThread = onOpenThread
        self.onOpenObservedSession = onOpenObservedSession
        self.loadSessions = loadSessions
    }

    public var body: some View {
        LancerPage {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    topRow
                    greeting
                    let items = fleetStore.attentionItems
                    if !items.isEmpty {
                        attentionSection(items: items)
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                    } else {
                        allClearRow
                            .padding(.horizontal, 26)
                            .padding(.top, 14)
                    }
                    machinesSection.padding(.top, 26)
                }
                .padding(.bottom, 36)
            }
        }
        .accessibilityIdentifier("commandHome")
        .sheet(item: $reviewingApproval) { approval in
            approvalReviewSheet(for: approval)
        }
        .task {
            sessionsLoading = true
            observedSessions = await loadSessions()
            sessionsLoading = false
        }
    }

    // MARK: Top row — hamburger (glass) + new-chat (accent)

    private var topRow: some View {
        HStack(spacing: 12) {
            if let onOpenSidebar {
                DSCircleButton(
                    "line.3.horizontal",
                    diameter: 38,
                    accessibilityLabel: "Open navigation",
                    action: onOpenSidebar
                )
            }
            Spacer(minLength: 0)
            DSCircleButton(
                "plus",
                kind: .accent,
                diameter: 38,
                accessibilityLabel: "Start a new chat",
                action: onNewChat
            )
            .shadow(color: .black.opacity(0.3), radius: 9, x: 0, y: 6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timeGreeting)
                .font(.dsEditorialPt(19))
                .foregroundStyle(t.accent)
            Text(homeHeadline)
                .font(.dsDisplayPt(28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
    }

    // MARK: - Needs Attention section

    /// Shown instead of `attentionSection` whenever `fleetStore.attentionItems` is empty —
    /// a calm confirmation line, not an illustrated empty state, per the Mobbin "all caught up"
    /// references in the workflow-02 redesign report.
    private var allClearRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(t.ok)
            Text("You're caught up — nothing needs review.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
        }
    }

    @ViewBuilder
    private func attentionSection(items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NEEDS ATTENTION")
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(t.text4)
                Spacer()
                if items.count > 2 {
                    Button("See all") { onOpenInbox() }
                        .font(.dsSansPt(13, weight: .medium))
                        .foregroundStyle(t.accent)
                        .buttonStyle(.plain)
                }
            }
            ForEach(items.prefix(2)) { item in
                attentionCard(for: item)
            }
        }
    }

    @ViewBuilder
    private func attentionCard(for item: AttentionItem) -> some View {
        switch item.kind {
        case .approval(let approval):
            approvalAttentionCard(approval: approval, isExpired: item.isExpired)
        case .blockedRun(_, let hostName, _, let title):
            blockedRunCard(hostName: hostName, title: title)
        case .offlineMachine(_, let hostName):
            offlineMachineCard(hostName: hostName)
        }
    }

    private func approvalAttentionCard(approval: Approval, isExpired: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isExpired ? "clock.badge.xmark" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isExpired ? t.text3 : t.warn)
                    Text(isExpired ? "Approval expired" : "Approval needed")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(isExpired ? t.text3 : t.text)
                    Spacer()
                    Text(riskLabel(approval.risk))
                        .font(.dsSansPt(11, weight: .semibold))
                        .foregroundStyle(t.risk(approval.risk.rawValue))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(t.riskSoft(approval.risk.rawValue), in: Capsule())
                }
                HStack(spacing: 6) {
                    Text(approval.agent.initial)
                        .font(.dsMonoPt(9.5, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 22, height: 22)
                        .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(approvalSubtitle(approval))
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
            }
            DSButton(isExpired ? "View" : "Review", variant: .quiet, size: .sm, mono: true) {
                Haptics.selection()
                reviewingApproval = approval
            }
        }
        .padding(14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(isExpired ? t.border.opacity(0.4) : t.border, lineWidth: 1)
        )
        .opacity(isExpired ? 0.6 : 1.0)
    }

    private func blockedRunCard(hostName: String, title: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(t.warn)
                    Text("Run paused")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                }
                Text("\(title) · \(hostName)")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private func offlineMachineCard(hostName: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(t.text3)
                    Text("Machine offline")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                }
                Text("\(hostName) · has pending approvals")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .opacity(0.7)
    }

    // MARK: - Approval review sheet

    @ViewBuilder
    private func approvalReviewSheet(for capturedApproval: Approval) -> some View {
        let slot = fleetStore.slot(forApprovalID: capturedApproval.id)
        // Read the LIVE version from the observable inbox so remote resolution is detected
        let live = slot?.inboxVM.approvals.first(where: { $0.id == capturedApproval.id }) ?? capturedApproval
        let isOffline = slot.map { fleetStore.connectionState(for: $0) == .offline } ?? false
        let resolvedDecision: Approval.Decision? = live.isPending ? nil : live.decision

        DSReviewSheet("Review") {
            VStack(spacing: 0) {
                // Fixture 7: offline banner — decision will be queued and sent on reconnect
                if isOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 13))
                            .foregroundStyle(t.text3)
                        Text("Machine offline — your decision will be sent when reconnected")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.surfaceSunk)
                }

                InboxApprovalDetail(
                    agentKey: capturedApproval.agent.agentKey,
                    agentName: capturedApproval.agent.displayName,
                    hostLabel: slot?.hostName ?? capturedApproval.cwd,
                    cwd: capturedApproval.cwd,
                    sessionID: capturedApproval.agentSessionID,
                    timeLabel: relativeTimeLabel(capturedApproval.createdAt),
                    summary: ApprovalSummary.derive(from: capturedApproval).headline,
                    question: capturedApproval.question,
                    choices: capturedApproval.choices,
                    toolName: capturedApproval.toolName ?? capturedApproval.command.map { Redactor.shared.redact($0).redacted },
                    args: (capturedApproval.toolInput ?? capturedApproval.command).map { Redactor.shared.redact($0).redacted },
                    command: capturedApproval.command,
                    risk: capturedApproval.risk.rawValue,
                    matchedRule: capturedApproval.blastRadius?.matchedRule,
                    resolvedDecision: resolvedDecision,
                    onDeny: {
                        slot?.inboxVM.decide(capturedApproval.id, decision: .rejected)
                        reviewingApproval = nil
                    },
                    onApprove: {
                        slot?.inboxVM.decide(capturedApproval.id, decision: .approved)
                        reviewingApproval = nil
                    },
                    onChoose: { idx in
                        slot?.inboxVM.decide(capturedApproval.id, decision: .approved, choiceIndex: idx)
                        reviewingApproval = nil
                    }
                )
            }
        }
    }

    // MARK: - Helpers for attention cards

    private func riskLabel(_ risk: Approval.Risk) -> String {
        switch risk {
        case .low:      "Low"
        case .medium:   "Medium"
        case .high:     "High"
        case .critical: "Critical"
        }
    }

    private func approvalSubtitle(_ approval: Approval) -> String {
        let tool = approval.toolName ?? approval.kind.rawValue
        let host = fleetStore.slot(forApprovalID: approval.id)?.hostName ?? ""
        let age = relativeTimeLabel(approval.createdAt)
        let agent = approval.agent.displayName
        // Host is the lowest-priority segment here — drop it first at large Dynamic Type
        // sizes so the line stays readable instead of truncating mid-word.
        if dynamicTypeSize >= .accessibility1 || host.isEmpty {
            return "\(agent) · \(tool) · \(age)"
        }
        return "\(agent) · \(tool) · \(host) · \(age)"
    }

    private func relativeTimeLabel(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }

    // MARK: Machines → Projects → Sessions

    private var machinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR MACHINES")
                    .font(.dsMonoPt(10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(t.text4)
                Spacer(minLength: 8)
                if runningCount > 0 {
                    HStack(spacing: 5) {
                        DSStatusDot(tone: .ok, pulse: true, size: 6)
                        Text("\(runningCount) running")
                            .font(.dsMonoPt(10.5))
                            .foregroundStyle(t.ok)
                    }
                }
            }
            .padding(.horizontal, 26)

            if machines.isEmpty {
                connectMachineCard.padding(.horizontal, 18)
            } else {
                ForEach(machines) { machine in
                    MachineTreeCard(
                        machine: machine,
                        isExpanded: !collapsed.contains(machine.id),
                        sessionsLoading: sessionsLoading,
                        onToggle: { toggle(machine.id) },
                        onOpenMachine: { Haptics.selection(); onOpenMachines() },
                        onOpenSession: { id in Haptics.selection(); onOpenThread(id) },
                        onOpenObservedSession: { session in Haptics.selection(); onOpenObservedSession(session) }
                    )
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private var connectMachineCard: some View {
        Button {
            Haptics.selection()
            onOpenMachines()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 38, height: 38)
                    .background(t.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect a machine")
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("Pair a host to dispatch and supervise agents.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.text4)
            }
            .lancerSurfaceCard()
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        Haptics.selection()
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    // MARK: Derived model

    /// Machines built from every paired fleet host, grouped host → project (cwd)
    /// → session, enriched with recent threads and live connection state. Seeding
    /// from `fleetStore.slots` (not just `recentThreads`) means a freshly paired
    /// machine shows here immediately, before it has any chat history — matching
    /// what the Machines page lists.
    private var machines: [HomeMachine] {
        let byHost = Dictionary(grouping: recentThreads, by: \.hostName)
        var allHosts = Set(fleetStore.slots.map(\.hostName)).union(byHost.keys)
        // Relay-paired hosts aren't fleet slots — fold the active one in so a
        // connected relay machine shows even before it has any chat history.
        if let relayHostName { allHosts.insert(relayHostName) }
        return allHosts
            .map { host -> HomeMachine in
                let byProject = Dictionary(grouping: byHost[host] ?? [], by: \.cwd)
                let projects = byProject
                    .map { path, sessions in
                        HomeProject(path: path, sessions: sessions.sorted { $0.lastActivityAt > $1.lastActivityAt })
                    }
                    .sorted { ($0.sessions.first?.lastActivityAt ?? .distantPast) > ($1.sessions.first?.lastActivityAt ?? .distantPast) }
                var liveState = fleetStore.slots.first { $0.hostName == host }.map { fleetStore.connectionState(for: $0) }
                // The relay host isn't a fleet slot, so derive its dot from the live
                // bridge state instead: paired-and-live vs. known-but-reconnecting.
                if liveState == nil, host == relayHostName {
                    liveState = relayHostConnected ? .relayPaired : .connecting
                }
                // `loadSessions()` queries whichever host is currently live (the
                // connected SSH slot or the active relay bridge) — there's no
                // per-host fan-out yet, so only that machine gets the observed list.
                let isLiveHost = liveState == .connected || liveState == .relayPaired
                return HomeMachine(
                    name: host,
                    projects: projects,
                    liveState: liveState,
                    observedSessions: isLiveHost ? observedSessions : []
                )
            }
            .sorted { ($0.projects.first?.sessions.first?.lastActivityAt ?? .distantPast) > ($1.projects.first?.sessions.first?.lastActivityAt ?? .distantPast) }
    }

    private var runningCount: Int {
        machines.filter { machine in
            machine.liveState == .connected || machine.projects.contains { $0.sessions.contains { $0.status == .active } }
        }.count
    }

    private var homeHeadline: String {
        guard pendingApprovalCount > 0 else { return "All clear tonight." }
        return pendingApprovalCount == 1 ? "1 agent needs you." : "\(pendingApprovalCount) agents need you."
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good evening"
        }
        return profileEmail.map { "\(part), \($0)" } ?? part
    }
}

// MARK: - Tree model

private struct HomeMachine: Identifiable {
    let name: String
    let projects: [HomeProject]
    let liveState: Session.ConnectionState?
    let observedSessions: [ObservedSession]
    var id: String { name }
}

private struct HomeProject: Identifiable {
    let path: String
    let sessions: [ChatConversation]
    var id: String { path }
}

// MARK: - Machine card with expandable project/session tree

private struct MachineTreeCard: View {
    let machine: HomeMachine
    let isExpanded: Bool
    var sessionsLoading: Bool = false
    let onToggle: () -> Void
    let onOpenMachine: () -> Void
    let onOpenSession: (String) -> Void
    let onOpenObservedSession: (ObservedSession) -> Void

    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(machine.projects) { project in
                        projectBlock(project)
                    }
                    if !machine.observedSessions.isEmpty {
                        observedSessionsBlock
                    } else if isLiveMachine && sessionsLoading {
                        sessionsLoadingRow
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 14)
                .padding(.bottom, 12)
            }
        }
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.border, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(t.text4)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(machine.name)" : "Expand \(machine.name)")

            DSStatusDot(tone: dotTone, pulse: machine.liveState == .connected, size: 9)

            Button(action: onOpenMachine) {
                Text(machine.name)
                    .font(.dsDisplayPt(16, weight: .bold))
                    .foregroundStyle(t.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onOpenMachine) {
                Text("\(projectSummary) ›")
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func projectBlock(_ project: HomeProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.path)
                .font(.dsMonoPt(10.5, weight: .medium))
                .foregroundStyle(t.accent)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(project.sessions) { session in
                sessionRow(session)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.border).frame(width: 1.5)
        }
        .padding(.top, 4)
    }

    private var isLiveMachine: Bool {
        machine.liveState == .connected || machine.liveState == .relayPaired
    }

    // Scanning + titling the host's sessions can take many seconds; show a row
    // instead of a blank gap so the section doesn't look empty/broken while loading.
    private var sessionsLoadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text("Loading sessions on this Mac…")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Visually distinct from the dispatched-thread tree above (dashed rule, dimmer
    // row chrome) so users don't assume these support approvals/stop — Phase 1 is
    // watch-only.
    private var observedSessionsBlock: some View {
        // Home is a glance: show only the most-recent sessions so the list stays
        // light to scroll. The daemon already caps + sorts by recency.
        let shown = Array(machine.observedSessions.prefix(15))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSIONS ON THIS MAC")
                    .font(.dsMonoPt(9.5, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(t.text4)
                Spacer(minLength: 8)
                if machine.observedSessions.count > shown.count {
                    Text("\(shown.count) of \(machine.observedSessions.count)")
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            ForEach(shown) { session in
                observedSessionRow(session)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.text4.opacity(0.4)).frame(width: 1.5)
        }
        .padding(.top, 4)
    }

    private func observedSessionRow(_ session: ObservedSession) -> some View {
        Button { onOpenObservedSession(session) } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.text3)
                    .frame(width: 24, height: 24)
                    .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title.isEmpty ? cwdBasename(session.cwd) : session.title)
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(cwdBasename(session.cwd))
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                            .lineLimit(1)
                        Text("·").foregroundStyle(t.text4)
                        Text(relativeTime(session.lastActivity))
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    capabilityBadge(session.source)
                    stateChip(session.state)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(t.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(t.border)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func capabilityBadge(_ source: SessionSource) -> some View {
        let label: String
        switch source {
        case .lancerManaged: label = "Managed"
        case .providerManaged: label = "Background"
        case .transcriptObserved: label = "Observed"
        }
        return Text(label)
            .font(.dsMonoPt(9, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(t.surface2, in: Capsule())
    }

    private func stateChip(_ state: ObservedSessionState) -> some View {
        let (label, tone): (String, DSStatusDotTone) = {
            switch state {
            case .working: return ("Working", .ok)
            case .waitingForInput: return ("Needs input", .warn)
            case .recentlyActive: return ("Recently active", .accent)
            case .idle: return ("Idle", .off)
            case .completed: return ("Completed", .off)
            case .historical: return ("Historical", .off)
            case .unknown: return ("Unknown", .off)
            }
        }()
        return HStack(spacing: 4) {
            DSStatusDot(tone: tone, pulse: state == .working, size: 6)
            Text(label)
                .font(.dsMonoPt(9.5))
                .foregroundStyle(t.text3)
        }
    }

    private func cwdBasename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "just now" }
        if interval < 3600 { let m = Int(interval / 60); return "\(m) min\(m == 1 ? "" : "s") ago" }
        if interval < 86400 { let h = Int(interval / 3600); return "\(h) hr\(h == 1 ? "" : "s") ago" }
        let d = Int(interval / 86400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }

    private func sessionRow(_ session: ChatConversation) -> some View {
        Button { onOpenSession(session.id) } label: {
            HStack(spacing: 10) {
                Text(Self.initial(for: session))
                    .font(.dsDisplayPt(11, weight: .bold))
                    .foregroundStyle(t.accentFg)
                    .frame(width: 24, height: 24)
                    .background(t.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(session.title.isEmpty ? session.hostName : session.title)
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                statusGlyph(session.status)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(t.bg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusGlyph(_ status: ChatConversation.Status) -> some View {
        switch status {
        case .active:
            DSStatusDot(tone: .ok, pulse: true, size: 8)
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(t.ok)
        case .failed:
            DSStatusDot(tone: .danger, size: 8)
        case .archived:
            DSStatusDot(tone: .off, size: 8)
        }
    }

    private var dotTone: DSStatusDotTone {
        switch machine.liveState {
        case .connected, .relayPaired: return .ok
        case .connecting: return .warn
        case .failed: return .danger
        case .offline, .none: return machine.projects.contains { $0.sessions.contains { $0.status == .active } } ? .ok : .off
        }
    }

    private var projectSummary: String {
        machine.projects.count == 1 ? "1 project" : "\(machine.projects.count) projects"
    }

    static func initial(for session: ChatConversation) -> String {
        let key = (session.vendor ?? session.agentID).lowercased()
        if key.contains("codex") { return "Cx" }
        if key.contains("claude") { return "C" }
        if key.contains("kimi") { return "K" }
        if key.contains("opencode") || key.contains("open") { return "O" }
        return String((session.vendor ?? session.agentID).prefix(1)).uppercased()
    }
}

private extension Approval.AgentSource {
    var agentKey: AgentKey {
        switch self {
        case .claudeCode: .claudeCode
        case .codex:      .codex
        case .cursor:     .cursor
        case .opencode:   .opencode
        case .devin, .unknown: .unknown
        }
    }
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }
    var initial: String {
        switch self {
        case .claudeCode: "C"
        case .codex:      "Cx"
        case .cursor:     "Cu"
        case .opencode:   "O"
        case .devin:      "D"
        case .unknown:    "A"
        }
    }
}
#endif
