#if os(iOS)
import SwiftUI
import ConduitCore
import PersistenceKit
import DesignSystem
import SessionFeature
import InboxFeature

// MARK: - SessionSummary

struct SessionSummary: Identifiable {
    let id: UUID
    let hostName: String
    let hostname: String
    let cwd: String
    let lastUsedAt: Date
    let isLive: Bool
    let agentState: AgentState
    let agentKey: AgentKey
    let pendingApprovals: Int
    let unreadCount: Int

    var relativeTime: String {
        if isLive { return "Now" }
        let diff = Date.now.timeIntervalSince(lastUsedAt)
        if lastUsedAt == .distantPast { return "–" }
        switch diff {
        case ..<60:        return "\(Int(diff))s"
        case ..<3600:      return "\(Int(diff/60))m"
        case ..<86400:     return "\(Int(diff/3600))h"
        default:           return "\(Int(diff/86400))d"
        }
    }

    var subtitle: String {
        if isLive { return cwd.isEmpty ? hostname : cwd }
        return hostname
    }
}

// MARK: - Sessions Home View

struct SessionsHomeView: View {
    let liveSession: SessionViewModel?
    let liveInboxVM: InboxViewModel?
    let hostRepo: HostRepository
    let blockRepo: BlockRepository
    let snapshotRepo: SessionSnapshotRepository
    var statusHeaderAgents: [AgentInfo] = []
    var onTapStatusHeader: () -> Void = {}
    let onTapLiveSession: () -> Void
    let onAddSession: () -> Void
    var onDisconnectLiveSession: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var snapshots: [SessionSnapshot] = []
    @State private var hostsByID: [HostID: Host] = [:]

    @Environment(\.conduitTokens) private var t

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── BLOCKS header
                DSScreenHeader(
                    "sessions",
                    breadcrumb: "active workspaces",
                    count: liveSummaries.isEmpty ? nil : "\(liveSummaries.count) live"
                ) {
                    DSIconButton(.plus, action: onAddSession)
                }

                // ── Agent status header (only while a live session exists)
                if !statusHeaderAgents.isEmpty {
                    AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                        .padding(.top, 4)
                }

                // ── Search field
                DSSearchField(text: $searchText, placeholder: "search sessions")
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                // ── Session list
                if filteredSummaries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !liveSummaries.isEmpty {
                                DSListSectionHead("ACTIVE", count: liveSummaries.count)
                                ForEach(liveSummaries) { s in sessionRow(s) }
                            }
                            if !recentVisible.isEmpty {
                                DSListSectionHead("RECENT")
                                    .padding(.top, liveSummaries.isEmpty ? 0 : 6)
                                ForEach(recentVisible) { s in sessionRow(s) }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Data

    private var liveSummary: SessionSummary? {
        guard let vm = liveSession else { return nil }
        let pending = liveInboxVM?.approvals.filter { $0.isPending }.count ?? 0
        // Derive agent key from snapshot if available, else fall back to .claudeCode
        let snap = snapshots.first { $0.hostID == vm.host.id }
        let key = agentKey(for: snap?.agentID)
        return SessionSummary(
            id: vm.sessionID.raw,
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

    private var recentSummaries: [SessionSummary] {
        snapshots.compactMap { snap -> SessionSummary? in
            guard let host = hostsByID[snap.hostID] else { return nil }
            return SessionSummary(
                id: snap.hostID.raw,
                hostName: host.name,
                hostname: host.displayAddress,
                cwd: snap.agentWorkingDirectory ?? "~",
                lastUsedAt: snap.lastUsedTime,
                isLive: false,
                agentState: .offline,
                agentKey: agentKey(for: snap.agentID),
                pendingApprovals: 0,
                unreadCount: 0
            )
        }
    }

    private var filteredSummaries: [SessionSummary] {
        let liveID = liveSummary?.id
        let all = [liveSummary].compactMap { $0 }
            + recentSummaries.filter { $0.id != liveID }
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.hostName.lowercased().contains(q) || $0.hostname.lowercased().contains(q)
        }
    }

    private var liveSummaries: [SessionSummary]  { filteredSummaries.filter { $0.isLive } }
    private var recentVisible: [SessionSummary]  { filteredSummaries.filter { !$0.isLive } }

    // MARK: - Row

    @ViewBuilder
    private func sessionRow(_ s: SessionSummary) -> some View {
        Button(action: {
            if s.isLive { onTapLiveSession() } else { onAddSession() }
        }) {
            SessionRowView(summary: s)
        }
        .buttonStyle(SessionRowButtonStyle(t: t))
        .padding(.horizontal, 18)
        .accessibilityLabel(sessionRowLabel(s))
        .accessibilityHint(s.isLive ? "Opens live session" : "Reconnect to this host")
        .contextMenu {
            if s.isLive, let onDisconnectLiveSession {
                Button(role: .destructive) {
                    onDisconnectLiveSession()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            }
        }
    }

    private func sessionRowLabel(_ s: SessionSummary) -> String {
        var parts: [String] = [s.hostName, s.subtitle]
        if s.isLive {
            parts.append(s.agentState == .done ? "Connected" : s.agentState.islandLabel)
        } else {
            parts.append("Last used \(s.relativeTime) ago")
        }
        if s.unreadCount > 0 {
            parts.append("\(s.unreadCount) pending approval\(s.unreadCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            DSEmptyState(
                dotMatrix: .idle,
                title: "no sessions yet",
                subtitle: "Add your SSH host on the Hosts tab, then tap it to start a session. No Conduit account needed — just your own server and API key.",
                action: ("go to hosts", onAddSession)
            )
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Load

    private func loadData() async {
        async let hostsTask   = try? hostRepo.all()
        async let snapsTask   = try? snapshotRepo.allRecent()
        let (hosts, snaps) = await (hostsTask, snapsTask)
        hostsByID  = Dictionary(uniqueKeysWithValues: (hosts ?? []).map { ($0.id, $0) })
        snapshots  = snaps ?? []
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
}

// MARK: - Session Row View

struct SessionRowView: View {
    let summary: SessionSummary
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 0) {
            // ── Header tier: host · agent · status
            HStack(spacing: 7) {
                DSIconView(.server, size: 13, color: t.text3)
                Text(summary.hostName)
                    .font(.dsMonoPt(12, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                if summary.isLive && summary.agentKey != .unknown {
                    AgentIdentityBadge(agent: summary.agentKey, label: nil)
                }
                Spacer(minLength: 6)
                statusCluster
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            DSDivider(.soft)

            // ── Footer tier: cwd + meta
            HStack(spacing: 6) {
                Text("$").font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.accent)
                Text(summary.subtitle)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if summary.unreadCount > 0 {
                    Text("\(summary.unreadCount) pending")
                        .font(.dsMonoPt(10.5))
                        .foregroundStyle(t.warn)
                }
                Text(summary.relativeTime)
                    .font(.dsMonoPt(10.5))
                    .foregroundStyle(t.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .background(t.surface)
        .overlay(
            Rectangle().strokeBorder(t.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // Live ping + label, or idle dot, mirroring the BLOCKS session card.
    @ViewBuilder
    private var statusCluster: some View {
        let (label, tone) = statusLabelTone
        HStack(spacing: 6) {
            if summary.isLive && summary.unreadCount == 0 && summary.agentState != .error {
                DSStatusDot(tone: .ok, pulse: summary.agentState != .done, size: 7)
            } else {
                Rectangle()
                    .fill(tone == t.text3 ? Color.clear : tone)
                    .frame(width: 6, height: 6)
                    .overlay(tone == t.text3 ? Rectangle().strokeBorder(t.text3, lineWidth: 1) : nil)
            }
            Text(label)
                .font(.dsMonoPt(11))
                .foregroundStyle(tone)
        }
    }

    private var statusLabelTone: (String, Color) {
        if summary.unreadCount > 0 { return ("needs you", t.warn) }
        if !summary.isLive { return (summary.relativeTime == "–" ? "idle" : "idle \(summary.relativeTime)", t.text3) }
        switch summary.agentState {
        case .thinking:  return ("thinking", t.ok)
        case .streaming: return ("running", t.ok)
        case .done:      return ("connected", t.ok)
        case .approval:  return ("needs you", t.warn)
        case .error:     return ("error", t.danger)
        case .offline:   return ("idle", t.text3)
        }
    }
}

// Row press-scale button style
struct SessionRowButtonStyle: ButtonStyle {
    let t: ConduitTokens
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? t.surface2 : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.984 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
