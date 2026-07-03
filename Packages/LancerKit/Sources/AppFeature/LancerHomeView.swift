#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem
import PersistenceKit
import AgentKit
import InboxFeature

/// A relay-paired host entry, as told to `LancerHomeView` from outside. Relay
/// hosts aren't `fleetStore` slots (they're the E2E bridge), so Home must be told
/// about them explicitly or they never appear here even while connected. One
/// entry per known pairing (so a known host doesn't vanish during reconnect),
/// with `connected` carrying whether that host's bridge is live right now
/// (drives the status dot).
public struct RelayHomeEntry: Sendable {
    public let id: RelayMachineID
    public let name: String
    public let connected: Bool
    public init(id: RelayMachineID, name: String, connected: Bool) {
        self.id = id
        self.name = name
        self.connected = connected
    }
}

/// Identifies one workspace on one machine, passed to `onOpenWorkspace` — enough
/// for the caller to push the dedicated workspace screen and, if the user renames
/// or deletes the workspace there, to know which persisted `Workspace` (if any)
/// to update.
public struct HomeWorkspaceRef: Sendable {
    public let machineKey: String?
    public let machineName: String
    public let path: String
    public let displayName: String
    public let workspaceID: String?
    public init(machineKey: String?, machineName: String, path: String, displayName: String, workspaceID: String?) {
        self.machineKey = machineKey
        self.machineName = machineName
        self.path = path
        self.displayName = displayName
        self.workspaceID = workspaceID
    }
}

public struct LancerHomeView: View {
    private let fleetStore: FleetStore
    /// The relay-only fallback inbox VM — `fleetStore.slot(forApprovalID:)` only
    /// resolves for legacy SSH-connected hosts (`FleetStore.Slot` is created solely
    /// in `AppRoot`'s SSH-connect flow); a relay-only approval (V1's primary
    /// transport, no SSH session ever held) has no matching slot, so the review
    /// sheet must fall back to this VM or its decide() calls silently no-op.
    private let defaultInboxVM: InboxViewModel
    private let recentThreads: [ChatConversation]
    private let pendingApprovalCount: Int
    private let profileEmail: String?
    /// Every relay-paired host currently known to the app (see `RelayHomeEntry`).
    private let relayMachines: [RelayHomeEntry]
    /// Persisted workspace records (see `Workspace`/`WorkspaceRepository`), across
    /// every machine — grouped per-machine below so a workspace with a saved name
    /// shows that name instead of its raw `cwd`, and so a freshly-created empty
    /// workspace (no chats yet) still has a row to tap into.
    private let workspaces: [Workspace]
    private let onOpenSidebar: (() -> Void)?
    private let onNewChat: () -> Void
    private let onOpenInbox: () -> Void
    private let onOpenMachines: () -> Void
    private let onOpenThread: (String) -> Void
    private let onOpenObservedSession: (ObservedSession) -> Void
    /// Opens the dedicated workspace screen (Option B: a workspace is its own pushed
    /// screen, not an inline-expanding list) for one workspace on one machine.
    private let onOpenWorkspace: (HomeWorkspaceRef) -> Void
    /// Starts a new workspace on the given machine (`machineKey` is the relay
    /// machine's UUID string, matching `DispatchAgent.hostID`, or `nil` for a
    /// legacy SSH machine — the New Chat composer preselects that machine when
    /// non-nil, and falls back to its normal default-machine behavior otherwise).
    private let onCreateWorkspace: (_ machineKey: String?) -> Void
    /// Fetches watch-only sessions discovered on a given host (Claude Code, etc.) —
    /// separate from `recentThreads`, which are Lancer-dispatched runs. Takes the
    /// host name to query so it can be fanned out per live machine. Defaults to
    /// `{ _ in [] }` so previews/tests compile without a live daemon.
    private let loadSessions: @Sendable (String) async -> [ObservedSession]

    @Environment(\.lancerTokens) private var t
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var observedSessionsByHost: [String: [ObservedSession]] = [:]
    @State private var sessionsLoading = true
    @State private var reviewingApproval: Approval?

    public init(
        fleetStore: FleetStore,
        defaultInboxVM: InboxViewModel,
        recentThreads: [ChatConversation],
        pendingApprovalCount: Int,
        profileEmail: String? = nil,
        relayMachines: [RelayHomeEntry] = [],
        workspaces: [Workspace] = [],
        onOpenSidebar: (() -> Void)? = nil,
        onNewChat: @escaping () -> Void,
        onOpenInbox: @escaping () -> Void,
        onOpenMachines: @escaping () -> Void,
        onOpenThread: @escaping (String) -> Void,
        onOpenObservedSession: @escaping (ObservedSession) -> Void = { _ in },
        onOpenWorkspace: @escaping (HomeWorkspaceRef) -> Void = { _ in },
        onCreateWorkspace: @escaping (_ machineKey: String?) -> Void = { _ in },
        loadSessions: @escaping @Sendable (String) async -> [ObservedSession] = { _ in [] }
    ) {
        self.fleetStore = fleetStore
        self.defaultInboxVM = defaultInboxVM
        self.recentThreads = recentThreads
        self.pendingApprovalCount = pendingApprovalCount
        self.profileEmail = profileEmail
        self.relayMachines = relayMachines
        self.workspaces = workspaces
        self.onOpenSidebar = onOpenSidebar
        self.onNewChat = onNewChat
        self.onOpenInbox = onOpenInbox
        self.onOpenMachines = onOpenMachines
        self.onOpenThread = onOpenThread
        self.onOpenObservedSession = onOpenObservedSession
        self.onOpenWorkspace = onOpenWorkspace
        self.onCreateWorkspace = onCreateWorkspace
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
            if let cached = ObservedSessionsCache.loadByHost() {
                observedSessionsByHost = cached
                sessionsLoading = false
            } else {
                sessionsLoading = true
            }
            let liveHosts = liveHostNames
            guard !liveHosts.isEmpty else {
                sessionsLoading = false
                return
            }
            let fresh = await withTaskGroup(of: (String, [ObservedSession]).self) { group in
                for host in liveHosts {
                    group.addTask { (host, await loadSessions(host)) }
                }
                var results: [String: [ObservedSession]] = [:]
                for await (host, sessions) in group {
                    results[host] = sessions
                }
                return results
            }
            observedSessionsByHost = fresh
            sessionsLoading = false
            ObservedSessionsCache.saveByHost(fresh)
        }
    }

    /// Host names currently live — either a connected/relay-paired fleet slot or
    /// a relay entry reporting `connected == true`. Drives which hosts get a
    /// `loadSessions(host:)` fan-out (dead/reconnecting hosts don't query).
    private var liveHostNames: [String] {
        let liveSlotHosts = fleetStore.slots
            .filter { slot in
                let state = fleetStore.connectionState(for: slot)
                return state == .connected || state == .relayPaired
            }
            .map(\.hostName)
        let liveRelayHosts = relayMachines.filter(\.connected).map(\.name)
        return Array(Set(liveSlotHosts).union(liveRelayHosts))
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
        Button { onOpenInbox() } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(t.ok)
                Text("You're caught up — nothing needs review.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Inbox")
        .accessibilityHint("Nothing needs review right now")
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
                Button("See all") { onOpenInbox() }
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.accent)
                    .buttonStyle(.plain)
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
        // No fleet slot exists for a relay-only approval (see defaultInboxVM's doc
        // comment) — fall back to it so decide() below actually forwards the
        // decision instead of silently no-oping on a nil slot.
        let resolvedVM = slot?.inboxVM ?? defaultInboxVM
        // Read the LIVE version from the observable inbox so remote resolution is detected
        let live = resolvedVM.approvals.first(where: { $0.id == capturedApproval.id }) ?? capturedApproval
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
                        resolvedVM.decide(capturedApproval.id, decision: .rejected)
                        reviewingApproval = nil
                    },
                    onApprove: {
                        resolvedVM.decide(capturedApproval.id, decision: .approved)
                        reviewingApproval = nil
                    },
                    onChoose: { idx in
                        resolvedVM.decide(capturedApproval.id, decision: .approved, choiceIndex: idx)
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

    // MARK: Machines → Workspaces → Sessions

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
                    MachineWorkspacesCard(
                        machine: machine,
                        sessionsLoading: sessionsLoading,
                        onOpenMachine: { Haptics.selection(); onOpenMachines() },
                        onOpenWorkspace: { workspace in
                            Haptics.selection()
                            onOpenWorkspace(HomeWorkspaceRef(
                                machineKey: machine.relayID?.uuidString,
                                machineName: machine.name,
                                path: workspace.path,
                                displayName: workspace.displayName,
                                workspaceID: workspace.workspaceID
                            ))
                        },
                        onCreateWorkspace: {
                            Haptics.selection()
                            onCreateWorkspace(machine.relayID?.uuidString)
                        },
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

    // MARK: Derived model

    /// Machines built from every paired fleet host plus every known relay host,
    /// grouped host → workspace (cwd) → session, enriched with recent threads and
    /// live connection state. Seeding from `fleetStore.slots` (not just
    /// `recentThreads`) means a freshly paired machine shows here immediately,
    /// before it has any chat history — matching what the Machines page lists.
    private var machines: [HomeMachine] {
        let byHost = Dictionary(grouping: recentThreads, by: \.hostName)
        let sshHostNames = Set(fleetStore.slots.map(\.hostName)).union(byHost.keys)
        let workspacesByMachine = Dictionary(grouping: workspaces, by: \.machineID)

        // Rows are keyed by hostName for SSH/thread-history hosts (no relay
        // identity), but by RelayMachineID for relay-paired ones. Two relay
        // machines must never collapse into one row just because they share
        // a display name — every newly-paired machine defaults to the same
        // name ("Relay host") until renamed, and a plain name-keyed Set here
        // silently merged distinct machines into a single Home card even
        // though the Machines tab (keyed by id) correctly listed both.
        var rows: [(key: String, name: String, relayID: RelayMachineID?)] =
            sshHostNames.map { (key: $0, name: $0, relayID: nil) }
        // Tracks which names have already been given to a relay machine —
        // separate from `sshHostNames` itself, because a name can pre-exist
        // there (chat history) before ANY relay entry is processed. Only the
        // FIRST relay machine to claim a given name may fold into that
        // pre-existing row; every subsequent one (e.g. a second machine still
        // carrying the same unrenamed default name) must get its own row.
        var relayClaimedNames = Set<String>()
        for entry in relayMachines {
            if !relayClaimedNames.contains(entry.name) {
                relayClaimedNames.insert(entry.name)
                if sshHostNames.contains(entry.name) {
                    // Folds into the existing SSH/thread-history row (the
                    // common single-real-machine case — a relay host isn't a
                    // fleet slot, so this is how it shows before it has any
                    // chat history of its own). That row must still carry
                    // THIS relay machine's real identity — leaving relayID nil
                    // here permanently breaks "+ New workspace" machine
                    // preselection (onCreateWorkspace(machine.relayID?...))
                    // for every machine that's ever had a single chat, since
                    // `recentThreads` keeps that name in `sshHostNames` forever.
                    if let idx = rows.firstIndex(where: { $0.name == entry.name }) {
                        rows[idx].relayID = entry.id
                    }
                    continue
                }
            }
            rows.append((key: "relay:\(entry.id.uuidString)", name: entry.name, relayID: entry.id))
        }

        return rows
            .map { row -> HomeMachine in
                let host = row.name
                let byWorkspace = Dictionary(grouping: byHost[host] ?? [], by: \.cwd)
                let machineWorkspaces = row.relayID.flatMap { workspacesByMachine[$0] } ?? []
                var workspaces = byWorkspace
                    .map { path, sessions -> HomeWorkspace in
                        let workspace = machineWorkspaces.first { $0.path == path }
                        return HomeWorkspace(
                            path: path,
                            displayName: workspace?.name ?? Self.shortDisplayPath(path),
                            workspaceID: workspace?.id,
                            sessions: sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
                        )
                    }
                // A freshly-created workspace has no chats yet — still give it a row
                // (with an empty session list) so "+ New workspace" doesn't create
                // something invisible.
                let pathsWithSessions = Set(workspaces.map(\.path))
                let emptyWorkspaces = machineWorkspaces
                    .filter { !pathsWithSessions.contains($0.path) }
                    .map { HomeWorkspace(path: $0.path, displayName: $0.name, workspaceID: $0.id, sessions: []) }
                workspaces.append(contentsOf: emptyWorkspaces)
                workspaces.sort { ($0.sessions.first?.lastActivityAt ?? .distantPast) > ($1.sessions.first?.lastActivityAt ?? .distantPast) }

                var liveState = fleetStore.slots.first { $0.hostName == host }.map { fleetStore.connectionState(for: $0) }
                // The relay host isn't a fleet slot, so derive its dot from the live
                // bridge state instead: paired-and-live vs. known-but-reconnecting.
                let relayEntry = row.relayID.flatMap { id in relayMachines.first { $0.id == id } }
                    ?? relayMachines.first { $0.name == host }
                if liveState == nil, let entry = relayEntry {
                    liveState = entry.connected ? .relayPaired : .connecting
                }
                // `loadSessions(host:)` is fanned out per live host in `.task`, so
                // every live machine (not just one implicit "the" live host) gets
                // its own observed list now.
                let isLiveHost = liveState == .connected || liveState == .relayPaired
                return HomeMachine(
                    id: row.key,
                    name: host,
                    relayID: row.relayID,
                    workspaces: workspaces,
                    liveState: liveState,
                    observedSessions: isLiveHost ? (observedSessionsByHost[host] ?? []) : []
                )
            }
            .sorted { ($0.workspaces.first?.sessions.first?.lastActivityAt ?? .distantPast) > ($1.workspaces.first?.sessions.first?.lastActivityAt ?? .distantPast) }
    }

    /// A short label for a workspace with no saved `Workspace` name yet — the
    /// last path component (e.g. `/Users/roshansilva/lancer-ios` → `lancer-ios`),
    /// or the raw path itself for a bare `~`/`/` with nothing to shorten.
    private static func shortDisplayPath(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    private var runningCount: Int {
        machines.filter { machine in
            machine.liveState == .connected || machine.workspaces.contains { $0.sessions.contains { $0.status == .active } }
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
    let id: String
    let name: String
    /// `nil` for a legacy SSH machine with no relay identity — see
    /// `HomeWorkspaceRef.machineKey`'s doc comment.
    let relayID: RelayMachineID?
    let workspaces: [HomeWorkspace]
    let liveState: Session.ConnectionState?
    let observedSessions: [ObservedSession]
}

private struct HomeWorkspace: Identifiable {
    let path: String
    /// The persisted `Workspace` name when one matches this path, else a
    /// shortened form of the raw path (see `LancerHomeView.shortDisplayPath`).
    let displayName: String
    let workspaceID: String?
    let sessions: [ChatConversation]
    var id: String { path }
}

// MARK: - Machine pill + workspace cards (each workspace pushes to its own screen)

private struct MachineWorkspacesCard: View {
    let machine: HomeMachine
    var sessionsLoading: Bool = false
    let onOpenMachine: () -> Void
    let onOpenWorkspace: (HomeWorkspace) -> Void
    let onCreateWorkspace: () -> Void
    let onOpenObservedSession: (ObservedSession) -> Void

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var skeletonPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 8) {
                ForEach(machine.workspaces) { workspace in
                    workspaceCard(workspace)
                }
                newWorkspaceRow
                if !machine.observedSessions.isEmpty {
                    observedSessionsBlock
                } else if isLiveMachine && sessionsLoading {
                    observedSessionsSkeletonBlock
                }
            }
        }
    }

    private var header: some View {
        Button(action: onOpenMachine) {
            HStack(spacing: 9) {
                DSStatusDot(tone: dotTone, pulse: machine.liveState == .connected, size: 8)
                Text(machine.name)
                    .font(.dsSansPt(14.5, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(workspaceSummary) ›")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func workspaceCard(_ workspace: HomeWorkspace) -> some View {
        Button { onOpenWorkspace(workspace) } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(t.accent)
                    .frame(width: 32, height: 32)
                    .background(t.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.displayName)
                        .font(.dsSansPt(13.5, weight: .bold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    Text(workspace.path)
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 8)
                if !workspace.sessions.isEmpty {
                    Text("\(workspace.sessions.count)")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(t.surface2, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var newWorkspaceRow: some View {
        Button(action: onCreateWorkspace) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New workspace")
                    .font(.dsSansPt(12.5, weight: .semibold))
            }
            .foregroundStyle(t.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(t.border)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New workspace on \(machine.name)")
    }

    private var isLiveMachine: Bool {
        machine.liveState == .connected || machine.liveState == .relayPaired
    }

    // Shadcn-style pulsing skeleton, shown only on first-ever load (no cache yet)
    // while sessions are fetched, so the section never looks empty/broken.
    private var observedSessionsSkeletonBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSIONS ON THIS MAC")
                .font(.dsMonoPt(9.5, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(t.text4)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(0..<3, id: \.self) { _ in
                observedSessionSkeletonRow
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.text4.opacity(0.4)).frame(width: 1.5)
        }
        .padding(.top, 4)
        .onAppear {
            guard !reduceMotion else { return }
            skeletonPulsing = true
        }
    }

    private var observedSessionSkeletonRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(t.surface2)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(t.surface2)
                    .frame(width: 130, height: 13)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(t.surface2)
                        .frame(width: 64, height: 10)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(t.surface2)
                        .frame(width: 36, height: 10)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Capsule().fill(t.surface2).frame(width: 56, height: 14)
                Capsule().fill(t.surface2).frame(width: 64, height: 14)
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
        .opacity(skeletonPulsing ? 0.5 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: skeletonPulsing)
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

    private var dotTone: DSStatusDotTone {
        switch machine.liveState {
        case .connected, .relayPaired: return .ok
        case .connecting: return .warn
        case .failed: return .danger
        case .offline, .none: return machine.workspaces.contains { $0.sessions.contains { $0.status == .active } } ? .ok : .off
        }
    }

    private var workspaceSummary: String {
        machine.workspaces.count == 1 ? "1 workspace" : "\(machine.workspaces.count) workspaces"
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
