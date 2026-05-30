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
                // ── Title row
                HStack(alignment: .center) {
                    Text("Sessions")
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                    Spacer()
                    Button(action: onAddSession) {
                        ZStack {
                            Circle()
                                .fill(t.text)
                                .frame(width: 32, height: 32)
                            DSIconView(.plus, size: 16, color: t.bg)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // ── Agent status header (only while a live session exists)
                if !statusHeaderAgents.isEmpty {
                    AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                        .padding(.top, 10)
                }

                // ── Search pill
                DSSearchField(text: $searchText, placeholder: "Search sessions")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // ── Session list
                if filteredSummaries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !liveSummaries.isEmpty {
                                DSListSectionHead("ACTIVE", count: liveSummaries.count)
                                ForEach(liveSummaries) { s in
                                    sessionRow(s)
                                    if s.id != liveSummaries.last?.id {
                                        Rectangle().fill(t.divider).frame(height: 1)
                                            .padding(.leading, 74)
                                    }
                                }
                                Rectangle().fill(t.border).frame(height: 1)
                            }
                            if !recentVisible.isEmpty {
                                DSListSectionHead("RECENT")
                                ForEach(recentVisible) { s in
                                    sessionRow(s)
                                    if s.id != recentVisible.last?.id {
                                        Rectangle().fill(t.divider).frame(height: 1)
                                            .padding(.leading, 74)
                                    }
                                }
                            }
                        }
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            DSEmptyState(
                icon: .terminal,
                title: "No sessions yet",
                subtitle: "Connect to a host from the Hosts tab to begin.",
                action: ("Add host", onAddSession)
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

private struct SessionRowView: View {
    let summary: SessionSummary
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            // Avatar + status dot overlay
            ZStack(alignment: .bottomTrailing) {
                PixelAvatar(seed: summary.hostName, size: 46)
                DSStatusDot(
                    tone: statusDotTone,
                    pulse: summary.isLive && summary.agentState != .done,
                    size: 12
                )
                .background(
                    Circle().fill(t.bg).frame(width: 16, height: 16)
                )
                .offset(x: 2, y: 2)
            }

            // Body
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(summary.hostName)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(t.text)
                    if summary.isLive && summary.agentKey != .unknown {
                        AgentIdentityBadge(agent: summary.agentKey, label: nil)
                    }
                }
                Text(summary.subtitle)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }

            Spacer()

            // Right column: time / PixelBox / unread — fixed geometry so PixelBox never shifts
            VStack(alignment: .trailing, spacing: 4) {
                Text(summary.relativeTime)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                HStack(spacing: 6) {
                    PixelBox(state: summary.agentState, size: 5, gap: 1)
                    ZStack(alignment: .trailing) {
                        if summary.unreadCount > 0 {
                            Text("\(summary.unreadCount)")
                                .font(.dsMonoPt(11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(t.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(width: 20, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var statusDotTone: DSStatusDotTone {
        switch summary.agentState {
        case .thinking, .streaming: return .accent
        case .done:                 return .ok
        case .approval:             return .warn
        case .error:                return .danger
        case .offline:              return .off
        }
    }
}

// Row press-scale button style
private struct SessionRowButtonStyle: ButtonStyle {
    let t: ConduitTokens
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? t.surface2 : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.984 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
