#if os(iOS)
import SwiftUI
import LancerCore
import SessionFeature

/// Machine detail — connection state and entry to the interactive SSH terminal.
public struct MachineDetailView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator

    @State private var hosts: [Host] = []
    @State private var isHostSetupPresented = false
    @State private var loadError: String?

    public let machine: RelayFleetStore.Machine

    public init(machine: RelayFleetStore.Machine) {
        self.machine = machine
    }

    private var isConnected: Bool {
        relayFleetStore.isConnected(machine.id)
    }

    private var resolvedHost: Host? {
        Self.resolveHost(for: machine, from: hosts)
    }

    public var body: some View {
        List {
            Section("Machine") {
                LabeledContent("Name", value: machine.record.displayName)
                LabeledContent("ID", value: String(machine.id.uuidString.prefix(8)))
                LabeledContent("Status") {
                    Text(relayFleetStore.connectionState(for: machine.id)?.description ?? "Connecting…")
                        .foregroundStyle(isConnected ? .green : .secondary)
                }
            }

            Section("SSH Terminal") {
                if let host = resolvedHost {
                    LabeledContent("Host", value: host.displayAddress)
                    Button("Open Terminal") {
                        openTerminal(host: host)
                    }
                    .disabled(!isConnected)
                } else {
                    Text("No SSH host configured for this machine.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Add SSH Host") {
                        isHostSetupPresented = true
                    }
                    .disabled(!isConnected)
                }

                if !isConnected {
                    Text("Relay must be connected before opening a terminal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let message = terminalCoordinator.lastErrorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(machine.record.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHosts() }
        .sheet(isPresented: $isHostSetupPresented) {
            SSHHostSetupSheet(suggestedName: machine.record.displayName) { host, password in
                Task {
                    await terminalCoordinator.saveHostAndOpen(host, password: password, startupCommand: nil)
                    await loadHosts()
                }
            }
        }
    }

    private func openTerminal(host: Host) {
        terminalCoordinator.openTerminal(host: host, startupCommand: nil)
    }

    private func loadHosts() async {
        do {
            hosts = try await terminalCoordinator.allHosts()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Prefer a host whose name or tags match the relay machine display name.
    static func resolveHost(for machine: RelayFleetStore.Machine, from hosts: [Host]) -> Host? {
        let needle = machine.record.displayName.lowercased()
        if let match = hosts.first(where: {
            $0.name.lowercased() == needle
                || $0.tags.contains { $0.lowercased() == needle }
        }) {
            return match
        }
        return hosts.first
    }
}
#endif
