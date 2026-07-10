#if os(iOS)
import SwiftUI
import LancerCore
import SSHTransport
import SessionFeature

/// Settings → Trusted Machines: list paired hosts, pair a new one, remove an
/// existing one. Real (non-mocked) relay state, sourced from `RelayFleetStore`
/// / `ConnectionStateStore` via the environment. Apple-native `List` only —
/// behavior reference: `git show 3789aa5f:…/CursorTrustedMachinesView.swift`
/// (structure only; that file's `cursorShellLiveBridge` / pending-approval-count
/// dependencies are out of scope for this milestone).
public struct TrustedMachinesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var store

    @State private var isPairingPresented = false
    @State private var machinePendingRemoval: RelayFleetStore.Machine?
    @State private var isClearDeadPairingsConfirming = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if store.machines.isEmpty {
                    Section {
                        Text("No machines paired")
                        Text("Pair a machine to approve agent actions from this phone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Paired") {
                        ForEach(store.machines) { machine in
                            machineRow(machine)
                        }
                    }
                }

                if !store.invalidMachines.isEmpty {
                    Section("Dead pairings") {
                        ForEach(store.invalidMachines) { machine in
                            machineRow(machine)
                        }
                        Button("Clear all dead pairings", role: .destructive) {
                            isClearDeadPairingsConfirming = true
                        }
                    }
                }

                Section {
                    Button {
                        isPairingPresented = true
                    } label: {
                        Text("Pair a machine")
                    }
                    .disabled(store.isFull)

                    if store.isFull {
                        Text("You've reached the maximum of \(relayFleetMaxMachines) paired machines. Remove one to pair another.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Trusted Machines")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isPairingPresented) {
            RelayPairingSheet(existingMachineCount: store.usableMachineCount) { client, record in
                RelayFleetHydration.addMachine(client: client, record: record, to: store)
                isPairingPresented = false
            }
        }
        .alert(
            "Remove \(machinePendingRemoval?.record.displayName ?? "machine")?",
            isPresented: Binding(
                get: { machinePendingRemoval != nil },
                set: { if !$0 { machinePendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let id = machinePendingRemoval?.id {
                    store.remove(id)
                }
                machinePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { machinePendingRemoval = nil }
        } message: {
            Text("This phone will no longer be able to connect to or approve actions on this machine.")
        }
        .alert("Clear dead pairings?", isPresented: $isClearDeadPairingsConfirming) {
            Button("Clear", role: .destructive) { store.removeAllInvalid() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = store.invalidMachines.count
            Text("Removes \(count) pairing\(count == 1 ? "" : "s") that failed to restore.")
        }
    }

    @ViewBuilder
    private func machineRow(_ machine: RelayFleetStore.Machine) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.record.displayName)
                Text(String(machine.id.uuidString.prefix(8)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.connectionState(for: machine.id)?.description ?? "Connecting…")
                    .font(.caption)
                    .foregroundStyle(store.isConnected(machine.id) ? .green : .secondary)
            }
            Spacer()
            Button("Remove", role: .destructive) {
                machinePendingRemoval = machine
            }
        }
    }
}
#endif
