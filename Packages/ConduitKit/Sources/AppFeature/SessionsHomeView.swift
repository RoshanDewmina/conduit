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
    let pendingApprovals: Int
}

// MARK: - Sessions Home View

/// Root view for the "Sessions" tab. Lists the live session (if any) + recent
/// sessions derived from persisted blocks + known hosts. Tap → Agent Chat.
struct SessionsHomeView: View {
    let liveSession: SessionViewModel?
    let liveInboxVM: InboxViewModel?
    let hostRepo: HostRepository
    let blockRepo: BlockRepository
    let onTapLiveSession: () -> Void
    let onAddSession: () -> Void

    @State private var searchText = ""
    @State private var recentHosts: [Host] = []
    @State private var navigatingToLive = false

    @Environment(\.conduitTokens) private var t

    var body: some View {
        NavigationStack {
            Group {
                if filteredSummaries.isEmpty && searchText.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(t.surf0)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddSession) {
                        Image(systemName: "plus")
                    }
                }
            }
            // Navigate to the live Agent Chat session
            .navigationDestination(isPresented: $navigatingToLive) {
                if let vm = liveSession {
                    SessionView(viewModel: vm)
                        .navigationBarBackButtonHidden(false)
                }
            }
        }
        .task { await loadRecentHosts() }
    }

    // MARK: - Data

    private var liveSummary: SessionSummary? {
        guard let vm = liveSession else { return nil }
        let pending = liveInboxVM?.approvals.filter { $0.isPending }.count ?? 0
        return SessionSummary(
            id: vm.sessionID.raw,
            hostName: vm.host.name,
            hostname: vm.host.displayAddress,
            cwd: vm.cwd,
            lastUsedAt: .now,
            isLive: true,
            agentState: agentState(for: vm),
            pendingApprovals: pending
        )
    }

    private var recentSummaries: [SessionSummary] {
        recentHosts.map { host in
            SessionSummary(
                id: host.id.raw,
                hostName: host.name,
                hostname: host.displayAddress,
                cwd: "~",
                lastUsedAt: .distantPast,
                isLive: false,
                agentState: .offline,
                pendingApprovals: 0
            )
        }
    }

    private var filteredSummaries: [SessionSummary] {
        let all = [liveSummary].compactMap { $0 } + recentSummaries.filter { $0.id != liveSummary?.id }
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.hostName.lowercased().contains(q) || $0.hostname.lowercased().contains(q)
        }
    }

    private var liveSummaries: [SessionSummary]  { filteredSummaries.filter { $0.isLive } }
    private var recentVisible: [SessionSummary]  { filteredSummaries.filter { !$0.isLive } }

    // MARK: - Views

    private var sessionList: some View {
        List {
            if !liveSummaries.isEmpty {
                Section("Active") {
                    ForEach(liveSummaries) { s in sessionRow(s) }
                }
            }
            if !recentVisible.isEmpty {
                Section("Recent") {
                    ForEach(recentVisible) { s in sessionRow(s) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func sessionRow(_ s: SessionSummary) -> some View {
        Button(action: {
            if s.isLive {
                navigatingToLive = true
                onTapLiveSession()
            } else {
                onAddSession()
            }
        }) {
            SessionRowView(summary: s)
        }
        .buttonStyle(.plain)
        .listRowBackground(t.surf1)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(t.text4)
            Text("No sessions yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(t.text1)
            Text("Connect to a host from the Hosts tab to begin.")
                .font(.body)
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
            DSButton("Add host", systemImage: "plus", action: onAddSession)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load

    private func loadRecentHosts() async {
        if let hosts = try? await hostRepo.all() {
            recentHosts = Array(hosts.prefix(20))
        }
    }

    private func agentState(for vm: SessionViewModel) -> AgentState {
        switch vm.status {
        case .connecting:  return .thinking
        case .connected:   return vm.isExecutingUnified ? .streaming : .done
        case .suspended:   return .offline
        case .disconnected: return .offline
        case .reconnecting: return .thinking
        case .failed:      return .error
        }
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let summary: SessionSummary
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            PixelAvatar(seed: summary.hostName, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.hostName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(t.text1)
                    if summary.isLive {
                        StatusIcon(summary.agentState, size: 7)
                    }
                }
                Text(summary.hostname)
                    .font(.caption.monospaced())
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                AgentBadge(summary.agentState)
                if summary.pendingApprovals > 0 {
                    DSChip("\(summary.pendingApprovals)", systemImage: "exclamationmark", tone: .warn, style: .soft)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(t.text4)
        }
        .padding(.vertical, 4)
    }
}

#endif
