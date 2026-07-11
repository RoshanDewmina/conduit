#if os(iOS)
import SwiftUI
import LancerCore
import SSHTransport

/// Settings → Trusted machines — list, unpair, re-pair, dead-pairing cleanup.
public struct CursorTrustedMachinesView: View {
    @Environment(\.dismiss) private var dismiss

    private let trustedMachines: [CursorTrustedMachineRow]
    private let invalidMachines: [CursorTrustedMachineRow]
    private let onRequestPairing: (() -> Void)?
    private let onRemoveMachine: ((String) -> Void)?
    private let onClearInvalid: (() -> Void)?
    private let onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?

    @State private var showingPairing = false
    @State private var machinePendingRemoval: CursorTrustedMachineRow?
    @State private var showingClearInvalidConfirmation = false

    public init(
        trustedMachines: [CursorTrustedMachineRow] = [],
        invalidMachines: [CursorTrustedMachineRow] = [],
        onRequestPairing: (() -> Void)? = nil,
        onRemoveMachine: ((String) -> Void)? = nil,
        onClearInvalid: (() -> Void)? = nil,
        onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)? = nil
    ) {
        self.trustedMachines = trustedMachines
        self.invalidMachines = invalidMachines
        self.onRequestPairing = onRequestPairing
        self.onRemoveMachine = onRemoveMachine
        self.onClearInvalid = onClearInvalid
        self.onPaired = onPaired
    }

    public var body: some View {
        NavigationStack {
            List {
                if trustedMachines.isEmpty {
                    Section {
                        Text("No machines paired")
                        Text("Pair a machine to approve agent actions from this phone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("cursor.trusted-machines.empty")
                } else {
                    Section("Paired") {
                        ForEach(trustedMachines) { machine in
                            machineRow(machine)
                        }
                    }
                }

                if !invalidMachines.isEmpty {
                    Section("Dead pairings") {
                        ForEach(invalidMachines) { machine in
                            machineRow(machine)
                        }
                        if onClearInvalid != nil {
                            Button("Clear all dead pairings", role: .destructive) {
                                showingClearInvalidConfirmation = true
                            }
                            .accessibilityIdentifier("cursor.trusted-machines.clear-dead-pairings")
                        }
                    }
                }

                if onRequestPairing != nil || onPaired != nil {
                    Section {
                        Button("Pair a machine") { requestPairing() }
                            .accessibilityIdentifier("cursor.trusted-machines.pair-cta")
                    }
                }
            }
            .navigationTitle("Trusted machines")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .accessibilityIdentifier("cursor.trusted-machines")
        }
        .sheet(isPresented: $showingPairing) {
            if let onPaired {
                CursorRelayPairingSheet(
                    existingMachineCount: trustedMachines.filter { !$0.isInvalid }.count,
                    onPaired: onPaired
                )
            }
        }
        .alert(
            "Remove \(machinePendingRemoval?.displayName ?? "machine")?",
            isPresented: Binding(
                get: { machinePendingRemoval != nil },
                set: { if !$0 { machinePendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let id = machinePendingRemoval?.id {
                    onRemoveMachine?(id)
                }
                machinePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { machinePendingRemoval = nil }
        } message: {
            if let machine = machinePendingRemoval {
                Text(
                    CursorTrustedMachineFormatting.removeConfirmationMessage(
                        displayName: machine.displayName,
                        pendingApprovalCount: machine.pendingApprovalCount
                    )
                )
            }
        }
        .alert("Clear dead pairings?", isPresented: $showingClearInvalidConfirmation) {
            Button("Clear", role: .destructive) { onClearInvalid?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = invalidMachines.count
            Text("Removes \(count) pairing\(count == 1 ? "" : "s") that failed to restore.")
        }
    }

    private func requestPairing() {
        if onPaired != nil {
            showingPairing = true
        } else {
            onRequestPairing?()
            dismiss()
        }
    }

    @ViewBuilder
    private func machineRow(_ machine: CursorTrustedMachineRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.displayName)
                Text(machine.shortMachineID).font(.caption).foregroundStyle(.secondary)
                Text(CursorTrustedMachineFormatting.connectionStatusLabel(isConnected: machine.isConnected))
                    .font(.caption)
                    .foregroundStyle(machine.isConnected ? .green : .secondary)
                if machine.pendingApprovalCount > 0 {
                    Text("\(machine.pendingApprovalCount) pending")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if onRemoveMachine != nil {
                Button("Remove", role: .destructive) { machinePendingRemoval = machine }
                    .accessibilityIdentifier("cursor.trusted-machines.remove.\(machine.shortMachineID)")
            }
        }
        .accessibilityIdentifier("cursor.trusted-machines.row.\(machine.shortMachineID)")
    }
}
#endif
