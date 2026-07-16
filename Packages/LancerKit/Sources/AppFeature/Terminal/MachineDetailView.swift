#if os(iOS)
import SwiftUI
import SessionFeature

/// Machine detail — connection state and Orca-style relay terminal entry.
public struct MachineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator

    public let machine: RelayFleetStore.Machine

    @State private var isRemoveConfirming = false

    public init(machine: RelayFleetStore.Machine) {
        self.machine = machine
    }

    private var isConnected: Bool {
        relayFleetStore.isConnected(machine.id)
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

            Section("Terminal") {
                Text("Opens a daemon-owned shell on this machine over the relay (Orca-style). No separate SSH host setup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Terminal") {
                    terminalCoordinator.openTerminal(on: machine)
                }
                .disabled(!isConnected)

                if !isConnected {
                    Text("Relay must be connected before opening a terminal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Remove Machine", role: .destructive) {
                    isRemoveConfirming = true
                }
                .accessibilityIdentifier("machine-detail.remove")
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
        .alert(
            "Remove \(machine.record.displayName)?",
            isPresented: $isRemoveConfirming
        ) {
            Button("Remove", role: .destructive) {
                relayFleetStore.remove(machine.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This phone will no longer be able to connect to or approve actions on this machine.")
        }
    }
}
#endif
