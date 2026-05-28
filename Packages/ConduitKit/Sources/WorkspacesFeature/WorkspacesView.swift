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

    /// Per-host attention counters. Each value bumps when the host receives a
    /// new approval / reconnect / debug event; SwiftUI's `.onChange` then
    /// fires `AttentionFlashRing.pulse()` over that host's card.
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

    /// Bump the attention counter for a host — drives one `AttentionFlashRing`
    /// pulse on that host's card. Called from approval-arrival,
    /// reconnect-success, and debug-event paths.
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
    /// Called instead of `onAddHost` when the free-tier host limit (2) is hit.
    /// Pass `nil` to allow unlimited hosts (Pro users).
    public var onAddHostGated: (() -> Void)?

    public init(
        viewModel: WorkspacesViewModel,
        onSelect: @escaping (Host) -> Void,
        onEdit: @escaping (Host) -> Void,
        onAddHost: @escaping () -> Void,
        onAddHostGated: (() -> Void)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onAddHost = onAddHost
        self.onAddHostGated = onAddHostGated
    }

    private static let freeHostLimit = 2

    // MARK: - Filtered list

    private var filteredHosts: [Host] {
        guard !searchText.isEmpty else { return vm.hosts }
        let q = searchText.lowercased()
        return vm.hosts.filter {
            $0.name.lowercased().contains(q) ||
            $0.hostname.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
        }
    }

    /// Parse `ssh user@host` or `ssh user@host -p port` from search text.
    private var quickConnectHost: Host? {
        parseSSHCommand(searchText)
    }

    /// Hosts split into groups by their first tag, with an "Untagged" group
    /// (title `""`) at the top. Within each group, sort by name.
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
            result.append(("", untagged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }))
        }
        for tag in byTag.keys.sorted() {
            let group = byTag[tag] ?? []
            result.append((tag, group.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }))
        }
        return result
    }

    /// Single host row with attention flash overlay + swipe actions. Hoisted
    /// out so the tag-grouped + flat code paths can share it.
    @ViewBuilder
    private func hostRow(_ host: Host) -> some View {
        Button { onSelect(host) } label: {
            HostRow(host: host, isConnected: vm.connectedHostIDs.contains(host.id))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .overlay(
            AttentionFlashRing(
                trigger: vm.attentionCounters[host.id] ?? 0,
                reason: vm.attentionReasons[host.id] ?? .generic,
                cornerRadius: 12
            )
        )
        .swipeActions {
            Button(role: .destructive) {
                Task { await vm.remove(host) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                onEdit(host)
            } label: { Label("Edit", systemImage: "pencil") }
            .tint(.blue)
        }
    }

    public var body: some View {
        List {
            // Quick-connect row when search matches ssh syntax
            if let qc = quickConnectHost {
                Section {
                    Button {
                        onSelect(qc)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect to \(qc.username)@\(qc.hostname)")
                                    .font(.body.weight(.medium))
                                Text("Port \(qc.port) · one-time")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Quick Connect")
                }
            }

            // Saved hosts
            if filteredHosts.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "No hosts yet",
                    systemImage: "server.rack",
                    description: Text("Add your first remote host to begin.")
                )
                .listRowBackground(Color.clear)
            } else if filteredHosts.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(hostGroups, id: \.title) { group in
                    if group.title.isEmpty {
                        // Untagged hosts shown without a header.
                        ForEach(group.hosts) { host in hostRow(host) }
                    } else {
                        Section(group.title) {
                            ForEach(group.hosts) { host in hostRow(host) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search or \"ssh user@host -p port\"")
        .navigationTitle("Hosts")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let gated = onAddHostGated, vm.hosts.count >= Self.freeHostLimit {
                        gated()
                    } else {
                        onAddHost()
                    }
                } label: {
                    Label("Add Host", systemImage: "plus")
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.loadError != nil), actions: {
            Button("OK") { vm.loadError = nil }
        }, message: {
            Text(vm.loadError ?? "")
        })
    }
}

// MARK: - SSH quick-connect parser

private func parseSSHCommand(_ text: String) -> Host? {
    // Matches: ssh user@host, ssh user@host -p 2222, user@host
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

private struct HostRow: View {
    let host: Host
    var isConnected: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.conduitTokens) private var t

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityLayout
        } else {
            standardLayout
        }
    }

    private var standardLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PixelAvatar(seed: host.name, size: 36)
                if isConnected {
                    Circle()
                        .fill(t.ok)
                        .frame(width: 9, height: 9)
                        .offset(x: 2, y: 2)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(host.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(t.text1)
                    .lineLimit(1)
                Text(host.displayAddress)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label(authLabel, systemImage: authImage)
                    if let tmuxSessionName = host.tmuxSessionName {
                        Label(tmuxSessionName, systemImage: "rectangle.connected.to.line.below")
                    }
                }
                .font(.caption2)
                .foregroundStyle(t.text4)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let last = host.lastConnectedAt {
                    Text(last.formatted(.relative(presentation: .numeric)))
                        .font(.caption2)
                        .foregroundStyle(t.text4)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.vertical, 6)
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PixelAvatar(seed: host.name, size: 24)
                Text(host.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(t.text1)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(t.text4)
            }

            Text(host.displayAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(t.text3)
                .lineLimit(1)
                .truncationMode(.middle)

            VStack(alignment: .leading, spacing: 4) {
                Text(authLabel)
                if let tmuxSessionName = host.tmuxSessionName {
                    Text(tmuxSessionName)
                }
                if let last = host.lastConnectedAt {
                    Text(last.formatted(.relative(presentation: .numeric)))
                        .lineLimit(2)
                }
            }
            .font(.caption2)
            .foregroundStyle(t.text4)
        }
        .padding(.vertical, 8)
    }

    private var authLabel: String {
        switch host.authMethod {
        case .password: "password"
        case .ed25519: "key"
        case .agent: "agent"
        }
    }

    private var authImage: String {
        switch host.authMethod {
        case .password: "lock"
        case .ed25519: "key"
        case .agent: "person.badge.key"
        }
    }
}

#endif
