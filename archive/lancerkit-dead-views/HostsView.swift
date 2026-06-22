#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit
import DesignSystem
import SessionFeature
import InboxFeature
import WorkspacesFeature

// MARK: - HostsView
// Merged Hosts + Sessions view with ACTIVE (live sessions) and SAVED (saved hosts) sections.

public struct HostsView: View {

    // MARK: - Inputs

    let liveSessions: [FleetStore.Slot]
    let selectedLiveSessionID: UUID?
    let hostRepo: HostRepository
    let blockRepo: BlockRepository
    let snapshotRepo: SessionSnapshotRepository

    // MARK: - Callbacks

    let onTapLiveSession: (UUID) -> Void
    let onDisconnectLiveSession: (UUID) -> Void
    let onJumpToUnread: () -> Void
    let onAddHost: () -> Void
    let onSelect: (Host) -> Void
    let onEdit: (Host) -> Void

    // MARK: - Private state

    @State private var vm: WorkspacesViewModel
    @State private var searchText = ""
    @State private var snapshots: [SessionSnapshot] = []
    @State private var hostsByID: [HostID: Host] = [:]
    @State private var managedHost: Host? = nil
    @State private var isLoading = true

    @Environment(\.lancerTokens) private var t

    // MARK: - Init

    public init(
        liveSessions: [FleetStore.Slot],
        selectedLiveSessionID: UUID?,
        hostRepo: HostRepository,
        blockRepo: BlockRepository,
        snapshotRepo: SessionSnapshotRepository,
        onTapLiveSession: @escaping (UUID) -> Void,
        onDisconnectLiveSession: @escaping (UUID) -> Void,
        onJumpToUnread: @escaping () -> Void,
        onAddHost: @escaping () -> Void,
        onSelect: @escaping (Host) -> Void,
        onEdit: @escaping (Host) -> Void
    ) {
        self.liveSessions = liveSessions
        self.selectedLiveSessionID = selectedLiveSessionID
        self.hostRepo = hostRepo
        self.blockRepo = blockRepo
        self.snapshotRepo = snapshotRepo
        self.onTapLiveSession = onTapLiveSession
        self.onDisconnectLiveSession = onDisconnectLiveSession
        self.onJumpToUnread = onJumpToUnread
        self.onAddHost = onAddHost
        self.onSelect = onSelect
        self.onEdit = onEdit
        _vm = State(initialValue: WorkspacesViewModel(repository: hostRepo))
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader(
                    "hosts",
                    breadcrumb: "connections",
                    count: countLabel,
                    spectrumMode: spectrumMode
                ) {
                    HStack(spacing: 8) {
                        if hasUnreadLiveSession {
                            DSButton("UNREAD", variant: .secondary, size: .sm, mono: true, action: onJumpToUnread)
                        }
                        DSIconButton(.plus) { onAddHost() }
                    }
                }

                DSSearchField(text: $searchText, placeholder: "Search or \"ssh user@host\"")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                if isLoading {
                    DSSkeletonList(count: 4)
                } else if everythingEmpty {
                    hostsEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if let qcHost = quickConnectHost {
                                quickConnectRow(qcHost)
                                DSDivider(.line)
                            }

                            if !activeSummaries.isEmpty {
                                DSListSectionHead("ACTIVE", count: activeSummaries.count)
                                ForEach(activeSummaries) { s in
                                    activeRow(s)
                                    if s.id != activeSummaries.last?.id {
                                        DSDivider(.soft, leadingInset: 70)
                                    }
                                }
                                DSDivider(.line)
                            }

                            if !savedHostsFiltered.isEmpty {
                                DSListSectionHead("SAVED")
                                ForEach(savedHostsFiltered) { h in
                                    savedHostRow(h)
                                    if h.id != savedHostsFiltered.last?.id {
                                        DSDivider(.soft, leadingInset: 70)
                                    }
                                }
                                DSDivider(.line)
                            } else if !searchText.isEmpty && activeSummaries.isEmpty && quickConnectHost == nil {
                                noResultsState
                            }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
        }
        .alert("Error", isPresented: .constant(vm.loadError != nil), actions: {
            Button("OK") { vm.loadError = nil }
        }, message: {
            Text(vm.loadError ?? "")
        })
        .sheet(item: $managedHost) { host in
            NavigationStack {
                HostDetailView(hostName: host.name, hostAddress: host.displayAddress)
            }
        }
        .task { await loadData() }
    }

    // MARK: - Computed data

    /// Live summaries filtered by search text (ACTIVE section).
    private var activeSummaries: [SessionSummary] {
        let all = liveSessions.map { slot in
            let vm = slot.sessionViewModel
            let pending = slot.inboxVM.approvals.filter { $0.isPending && $0.sessionID == vm.sessionID }.count
            let snap = snapshots.first { $0.hostID == vm.host.id }
            let key = agentKey(for: snap?.agentID)
            return SessionSummary(
                id: slot.id,
                hostName: vm.host.name,
                hostname: vm.host.displayAddress,
                cwd: vm.cwd,
                lastUsedAt: .now,
                isLive: true,
                agentState: agentState(for: vm),
                agentKey: key == .unknown ? .claudeCode : key,
                pendingApprovals: pending,
                unreadCount: pending
            )
        }
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.hostName.lowercased().contains(q) || $0.hostname.lowercased().contains(q)
        }
    }

    /// Saved hosts filtered by search text, de-duped against live session host.
    private var savedHostsFiltered: [Host] {
        let liveHostIDs = Set(liveSessions.map(\.hostID))
        let base = vm.hosts.filter { !liveHostIDs.contains($0.id) }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            $0.hostname.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    private var quickConnectHost: Host? { parseSSHCommand(searchText) }

    private var everythingEmpty: Bool {
        activeSummaries.isEmpty && vm.hosts.isEmpty && quickConnectHost == nil
    }

    private var countLabel: String? {
        let a = activeSummaries.count
        let s = savedHostsFiltered.count
        switch (a, s) {
        case (0, 0): return nil
        case (_, 0): return "\(a) active"
        case (0, _): return "\(s) saved"
        default:     return "\(a) active · \(s) saved"
        }
    }

    private var hasUnreadLiveSession: Bool {
        activeSummaries.contains { $0.unreadCount > 0 }
    }

    private var spectrumMode: SpectrumMode {
        if liveSessions.contains(where: { slot in
            switch slot.sessionViewModel.status {
            case .connecting, .reconnecting:
                true
            default:
                false
            }
        }) {
            return .scan
        }
        if liveSessions.contains(where: { $0.sessionViewModel.status == .connected && $0.sessionViewModel.isExecutingUnified }) {
            return .working
        }
        return .idle
    }

    // MARK: - Active row (live session)

    @ViewBuilder
    private func activeRow(_ s: SessionSummary) -> some View {
        let isSelected = selectedLiveSessionID == s.id
        Button {
            if s.isLive { onTapLiveSession(s.id) }
        } label: {
            SessionRowView(summary: s)
        }
        .buttonStyle(SessionRowButtonStyle(t: t))
        .padding(.horizontal, 18)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.accent.opacity(0.4), lineWidth: 1)
                    .padding(.horizontal, 18)
            }
        }
        .accessibilityLabel(sessionRowLabel(s))
        .accessibilityHint("Opens live session")
        .contextMenu {
            Button(role: .destructive) {
                onDisconnectLiveSession(s.id)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }
        }
    }

    private func sessionRowLabel(_ s: SessionSummary) -> String {
        var parts: [String] = [s.hostName, s.subtitle]
        parts.append(s.agentState == .done ? "Connected" : s.agentState.islandLabel)
        if s.unreadCount > 0 {
            parts.append("\(s.unreadCount) pending approval\(s.unreadCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Saved host row

    @ViewBuilder
    private func savedHostRow(_ host: Host) -> some View {
        let attention = vm.attentionCounters[host.id] ?? 0
        Button { onSelect(host) } label: {
            HStack(spacing: 14) {
                // 44×44 pixel avatar tile + optional attention ring
                ZStack {
                    DSIconView(.server, size: 18, color: t.text2)
                        .frame(width: 44, height: 44)
                        .background(t.surface)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 1)
                        )
                    if attention > 0 {
                        AttentionFlashRing(
                            trigger: attention,
                            reason: vm.attentionReasons[host.id] ?? .generic,
                            cornerRadius: t.r3
                        )
                    }
                }
                .frame(width: 44, height: 44)

                // Host body
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.name)
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    Text(host.displayAddress)
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text2)
                        .lineLimit(1)
                    if let last = host.lastConnectedAt.map({ relativeTime($0) }) {
                        Text(last)
                            .font(.dsMonoPt(10.5))
                            .foregroundStyle(t.text3)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Spacer()

                // Fixed-width right column (status dot + label)
                ZStack(alignment: .trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        DSStatusDot(tone: .off, size: 8)
                        Text("offline")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text4)
                    }
                }
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await vm.remove(host) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { onEdit(host) } label: { Label("Edit", systemImage: "pencil") }
                .tint(t.accent)
            Button { managedHost = host } label: { Label("Manage", systemImage: "slider.horizontal.3") }
                .tint(t.info)
        }
    }

    // MARK: - Quick connect row

    @ViewBuilder
    private func quickConnectRow(_ host: Host) -> some View {
        Button { onSelect(host) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .fill(t.accentSoft)
                        .frame(width: 38, height: 38)
                    DSIconView(.server, size: 18, color: t.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick connect")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("\(host.username)@\(host.hostname):\(host.port)")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                DSIconView(.plus, size: 14, color: t.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty states

    private var hostsEmptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            DSEmptyState(
                icon: .server,
                title: "No hosts yet",
                subtitle: "Add any SSH-accessible server — a VPS, cloud VM, or local machine. You'll need a hostname, username, and a password or Ed25519 key.",
                action: ("Add host", onAddHost)
            )
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var noResultsState: some View {
        VStack {
            Spacer(minLength: 40)
            DSEmptyState(
                icon: .search,
                title: "No results",
                subtitle: "No hosts or sessions match \"\(searchText)\".",
                action: nil
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Load

    private func loadData() async {
        async let snapsTask = try? snapshotRepo.allRecent()
        async let hostsLoad: Void = vm.load()
        let (snaps, _) = await (snapsTask, hostsLoad)
        snapshots = snaps ?? []
        hostsByID = Dictionary(uniqueKeysWithValues: vm.hosts.map { ($0.id, $0) })
        isLoading = false
    }

    // MARK: - Helpers

    private func agentKey(for agentID: String?) -> AgentKey {
        switch agentID {
        case "claude":    return .claudeCode
        case "codex":     return .codex
        case "cursor":    return .cursor
        case "opencode":  return .opencode
        case "devin":     return .devin
        default:          return .unknown
        }
    }

    private func agentState(for vm: SessionViewModel) -> AgentState {
        switch vm.status {
        case .connecting:   return .thinking
        case .connected:    return vm.isExecutingUnified ? .streaming : .done
        case .suspended:    return .offline
        case .disconnected: return .offline
        case .reconnecting: return .thinking
        case .failed:       return .error
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date.now.timeIntervalSince(date)
        switch diff {
        case ..<60:     return "\(Int(diff))s ago"
        case ..<3600:   return "\(Int(diff/60))m ago"
        case ..<86400:  return "\(Int(diff/3600))h ago"
        default:        return "\(Int(diff/86400))d ago"
        }
    }
}

// MARK: - SSH quick-connect parser (mirrors WorkspacesView.parseSSHCommand)

private func parseSSHCommand(_ text: String) -> Host? {
    let pattern = #"^(?:ssh\s+)?([a-zA-Z0-9_.-]+)@([\w.-]+)(?:\s+-p\s*(\d+))?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { return nil }

    func group(_ i: Int) -> String? {
        guard let r = Range(match.range(at: i), in: trimmed) else { return nil }
        return String(trimmed[r])
    }

    guard let user = group(1), let host = group(2) else { return nil }
    let port = group(3).flatMap(Int.init) ?? 22
    return Host(
        id: HostID(),
        name: "\(user)@\(host)",
        hostname: host,
        port: port,
        username: user,
        authMethod: .password,
        tmuxSessionName: nil,
        lastConnectedAt: nil
    )
}

#endif
