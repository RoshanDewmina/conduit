#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import PersistenceKit
import SSHTransport
import DesignSystem

@MainActor @Observable
public final class WorkspacesViewModel {
    public private(set) var hosts: [Host] = []
    public private(set) var connectedHostIDs: Set<HostID> = []
    public var loadError: String?

    public private(set) var attentionCounters: [HostID: Int] = [:]
    public private(set) var attentionReasons: [HostID: AttentionFlashReason] = [:]

    private let repo: HostRepository

    public init(repository: HostRepository) {
        self.repo = repository
    }

    public func load() async {
        do { hosts = try await repo.all() }
        catch { loadError = error.localizedDescription }
        connectedHostIDs = await SessionPool.shared.connectedHostIDs()
    }

    public func remove(_ host: Host) async {
        do {
            try await repo.delete(id: host.id)
            await SessionPool.shared.disconnect(hostID: host.id)
            await load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func flashAttention(hostID: HostID, reason: AttentionFlashReason = .generic) {
        attentionCounters[hostID, default: 0] += 1
        attentionReasons[hostID] = reason
    }
}

public struct WorkspacesView: View {
    @State private var vm: WorkspacesViewModel
    @State private var searchText = ""
    public var onSelect: (Host) -> Void
    public var onEdit: (Host) -> Void
    public var onAddHost: () -> Void
    public var onAddHostGated: (() -> Void)?
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}

    #if DEBUG
    private static let freeHostLimit = Int.max // DEV: Pro unlocked for UX eval — restore before release
    #else
    private static let freeHostLimit = 2
    #endif

    @Environment(\.conduitTokens) private var t

    public init(
        viewModel: WorkspacesViewModel,
        onSelect: @escaping (Host) -> Void,
        onEdit: @escaping (Host) -> Void,
        onAddHost: @escaping () -> Void,
        onAddHostGated: (() -> Void)? = nil,
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {}
    ) {
        _vm = State(initialValue: viewModel)
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onAddHost = onAddHost
        self.onAddHostGated = onAddHostGated
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Title row
                HStack(alignment: .center) {
                    Text("Hosts")
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: handleAdd) {
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

                if !statusHeaderAgents.isEmpty {
                    AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                        .padding(.top, 10)
                }

                DSSearchField(text: $searchText, placeholder: "Search or \"ssh user@host\"")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if vm.hosts.isEmpty && searchText.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Quick connect row
                            if let qc = quickConnectHost {
                                quickConnectRow(qc)
                                Rectangle().fill(t.border).frame(height: 1)
                            }

                            if filteredHosts.isEmpty {
                                noResultsState
                            } else {
                                ForEach(hostGroups, id: \.title) { group in
                                    if !group.title.isEmpty {
                                        DSListSectionHead(group.title.uppercased())
                                    }
                                    ForEach(group.hosts) { host in
                                        hostRow(host)
                                        if host.id != group.hosts.last?.id {
                                            Rectangle().fill(t.divider).frame(height: 1)
                                                .padding(.leading, 70)
                                        }
                                    }
                                    Rectangle().fill(t.border).frame(height: 1)
                                }
                            }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
        }
        .task { await vm.load() }
        .alert("Error", isPresented: .constant(vm.loadError != nil), actions: {
            Button("OK") { vm.loadError = nil }
        }, message: {
            Text(vm.loadError ?? "")
        })
    }

    // MARK: - Computed data

    private var filteredHosts: [Host] {
        guard !searchText.isEmpty else { return vm.hosts }
        let q = searchText.lowercased()
        return vm.hosts.filter {
            $0.name.lowercased().contains(q) ||
            $0.hostname.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    private var quickConnectHost: Host? { parseSSHCommand(searchText) }

    private var hostGroups: [(title: String, hosts: [Host])] {
        var untagged: [Host] = []
        var byTag: [String: [Host]] = [:]
        for host in filteredHosts {
            if let tag = host.tags.first, !tag.isEmpty {
                byTag[tag, default: []].append(host)
            } else {
                untagged.append(host)
            }
        }
        var result: [(String, [Host])] = []
        if !untagged.isEmpty {
            result.append(("", untagged.sorted { $0.name < $1.name }))
        }
        for tag in byTag.keys.sorted() {
            result.append((tag, (byTag[tag] ?? []).sorted { $0.name < $1.name }))
        }
        return result
    }

    // MARK: - Rows

    @ViewBuilder
    private func hostRow(_ host: Host) -> some View {
        let isConnected = vm.connectedHostIDs.contains(host.id)
        let attention   = vm.attentionCounters[host.id] ?? 0
        DSHostRow(
            name: host.name,
            address: host.displayAddress,
            initials: hostInitials(host),
            status: isConnected ? .connected : .disconnected,
            pendingApprovals: attention,
            lastConnected: host.lastConnectedAt.map { relativeTime($0) },
            onTap: { onSelect(host) }
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await vm.remove(host) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { onEdit(host) } label: { Label("Edit", systemImage: "pencil") }
                .tint(.blue)
        }
    }

    @ViewBuilder
    private func quickConnectRow(_ host: Host) -> some View {
        Button { onSelect(host) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            DSEmptyState(
                icon: .server,
                title: "No hosts yet",
                subtitle: "Add any SSH-accessible server — a VPS, cloud VM, or local machine. You'll need a hostname, username, and a password or Ed25519 key.",
                action: ("Add host", handleAdd)
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
                subtitle: "No hosts match \"\(searchText)\".",
                action: nil
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private func handleAdd() {
        if let gated = onAddHostGated, vm.hosts.count >= Self.freeHostLimit {
            gated()
        } else {
            onAddHost()
        }
    }

    private func hostInitials(_ host: Host) -> String {
        let words = host.name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return String((words[0].prefix(1) + words[1].prefix(1)).uppercased())
        }
        return String(host.name.prefix(2).uppercased())
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

// MARK: - SSH quick-connect parser

private func parseSSHCommand(_ text: String) -> Host? {
    let pattern = #"^(?:ssh\s+)?([a-zA-Z0-9_.-]+)@([\w.-]+)(?:\s+-p\s*(\d+))?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let t = text.trimmingCharacters(in: .whitespaces)
    guard let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }

    func group(_ i: Int) -> String? {
        guard let r = Range(match.range(at: i), in: t) else { return nil }
        return String(t[r])
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
