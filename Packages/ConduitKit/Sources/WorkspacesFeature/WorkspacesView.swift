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
    public var onAddHost: () -> Void

    public init(
        viewModel: WorkspacesViewModel,
        onSelect: @escaping (Host) -> Void,
        onAddHost: @escaping () -> Void
    ) {
        _vm = State(initialValue: viewModel)
        self.onSelect = onSelect
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
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.remove(host) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("Workspaces")
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
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "terminal").font(.body).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).font(.body.weight(.medium))
                Text(host.displayAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let last = host.lastConnectedAt {
                Text(last.formatted(.relative(presentation: .numeric)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
