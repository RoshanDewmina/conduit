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

    /// When true, this view is pushed inside a parent `NavigationStack` and must
    /// not wrap another stack or add a sheet Close button.
    private let embedsInParentNavigation: Bool

    public init(embedsInParentNavigation: Bool = false) {
        self.embedsInParentNavigation = embedsInParentNavigation
    }

    public var body: some View {
        Group {
            if embedsInParentNavigation {
                machinesList
                    .navigationTitle("Trusted Machines")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    machinesList
                        .navigationTitle("Trusted Machines")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
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
        #if DEBUG
        // Same rationale as the other LANCER_DEBUG_* seams in this build: the
        // Remove button is tap-gated and Simulator HID taps are unreliable on
        // this iOS build. Drives the exact same `store.remove(id)` the button
        // calls — no bypass. Bounded poll (not onChange) because connection
        // transitions reassign elements in place; the array's identity list
        // alone doesn't reliably signal that.
        .task {
            guard ProcessInfo.processInfo.environment["LANCER_DEBUG_REMOVE_CONNECTED_MACHINE"] == "1" else { return }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let machine = store.machines.first(where: { store.isConnected($0.id) }) {
                    store.remove(machine.id)
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        // Same rationale, for freeing fleet-cap slots blocked by stale
        // "host offline" pairings (not `.pairingInvalid`, so "Clear all dead
        // pairings" doesn't touch them) left over from a prior daemon
        // session — drives the exact same `store.remove(id)` the per-row
        // Remove button calls, for every currently listed machine. Bounded
        // poll for the FULL window (never breaks early on an empty read)
        // because this view's `.task` can start before `AppRoot`'s
        // `RelayFleetHydration.hydrate` has populated `store.machines` —
        // breaking out on an empty FIRST read raced ahead of hydration and
        // was a silent no-op (found live 2026-07-10, same class of ordering
        // bug ShellLiveBridge.waitForConnectedMachine already documents).
        .task {
            guard ProcessInfo.processInfo.environment["LANCER_DEBUG_REMOVE_ALL_MACHINES"] == "1" else { return }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                for machine in store.machines {
                    store.remove(machine.id)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        #endif
    }

    private var machinesList: some View {
        List {
            if store.pairedMachines.isEmpty {
                Section {
                    Text("No machines paired")
                    Text("Pair a machine to approve agent actions from this phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Paired") {
                    ForEach(store.pairedMachines) { machine in
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
                .accessibilityIdentifier("trusted-machines.pair")

                if store.isFull {
                    Text("You've reached the maximum of \(relayFleetMaxMachines) paired machines. Remove one to pair another.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func machineRow(_ machine: RelayFleetStore.Machine) -> some View {
        HStack {
            NavigationLink {
                MachineDetailView(machine: machine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.record.displayName)
                    Text(String(machine.id.uuidString.prefix(8)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.connectionState(for: machine.id)?.description ?? "Connecting…")
                        .font(.caption)
                        .foregroundStyle(store.isConnected(machine.id) ? .green : .secondary)
                }
            }
            Spacer()
            Button("Remove", role: .destructive) {
                machinePendingRemoval = machine
            }
        }
    }
}
#endif
