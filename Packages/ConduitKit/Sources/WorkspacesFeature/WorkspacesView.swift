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
    public var loadError: String?

    private let repo: HostRepository

    public init(repository: HostRepository) {
        self.repo = repository
    }

    public func load() async {
        do { hosts = try await repo.all() }
        catch { loadError = error.localizedDescription }
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

    public var body: some View {
        List {
            if vm.hosts.isEmpty {
                ContentUnavailableView(
                    "No hosts yet",
                    systemImage: "server.rack",
                    description: Text("Add your first remote host to begin.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vm.hosts) { host in
                    Button { onSelect(host) } label: {
                        HostRow(host: host)
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

private struct HostRow: View {
    let host: Host
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
            Image(systemName: "terminal")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
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
