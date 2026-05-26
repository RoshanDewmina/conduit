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
}

public struct WorkspacesView: View {
    @State private var vm: WorkspacesViewModel
    @State private var searchText = ""
    public var onSelect: (Host) -> Void
    public var onEdit: (Host) -> Void
    public var onAddHost: () -> Void

    public init(
        viewModel: WorkspacesViewModel,
        onSelect: @escaping (Host) -> Void,
        onEdit: @escaping (Host) -> Void,
        onAddHost: @escaping () -> Void
    ) {
        _vm = State(initialValue: viewModel)
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onAddHost = onAddHost
    }

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
                ForEach(filteredHosts) { host in
                    Button { onSelect(host) } label: {
                        HostRow(host: host, isConnected: vm.connectedHostIDs.contains(host.id))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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
            }
        }
        .searchable(text: $searchText, prompt: "Search or \"ssh user@host -p port\"")
        .navigationTitle("Workspaces")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { onAddHost() } label: {
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
                Image(systemName: "terminal")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                if isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: 2)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(host.displayAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label(authLabel, systemImage: authImage)
                    if let tmuxSessionName = host.tmuxSessionName {
                        Label(tmuxSessionName, systemImage: "rectangle.connected.to.line.below")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let last = host.lastConnectedAt {
                    Text(last.formatted(.relative(presentation: .numeric)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
                Text(host.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(host.displayAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.tertiary)
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
