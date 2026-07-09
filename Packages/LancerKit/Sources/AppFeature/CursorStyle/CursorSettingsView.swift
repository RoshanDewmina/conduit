#if os(iOS)
import SwiftUI
import SSHTransport
import LancerCore

/// Settings root — machines/pairing, notifications summary, reset.
public struct CursorSettingsView: View {
    @State private var showingTrustedMachines = false
    @State private var showingResetConfirmation = false
    @State private var showingClearInvalidConfirmation = false

    private let relayMachineCount: Int
    private let invalidMachineCount: Int
    private let trustedMachines: [CursorTrustedMachineRow]
    private let invalidTrustedMachines: [CursorTrustedMachineRow]
    private let onRequestPairing: (() -> Void)?
    private let onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?
    private let onRemoveMachine: ((String) -> Void)?
    private let onClearInvalid: (() -> Void)?
    private let onReset: (() async -> Void)?

    public init(
        relayMachineCount: Int = 0,
        invalidMachineCount: Int = 0,
        trustedMachines: [CursorTrustedMachineRow] = [],
        invalidTrustedMachines: [CursorTrustedMachineRow] = [],
        onRequestPairing: (() -> Void)? = nil,
        onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)? = nil,
        onRemoveMachine: ((String) -> Void)? = nil,
        onClearInvalid: (() -> Void)? = nil,
        onReset: (() async -> Void)? = nil
    ) {
        self.relayMachineCount = relayMachineCount
        self.invalidMachineCount = invalidMachineCount
        self.trustedMachines = trustedMachines
        self.invalidTrustedMachines = invalidTrustedMachines
        self.onRequestPairing = onRequestPairing
        self.onPaired = onPaired
        self.onRemoveMachine = onRemoveMachine
        self.onClearInvalid = onClearInvalid
        self.onReset = onReset
    }

    public var body: some View {
        Form {
            Section("Machines & Pairing") {
                Button {
                    showingTrustedMachines = true
                } label: {
                    LabeledContent(
                        "Trusted machines",
                        value: relayMachineCount == 1
                            ? "1 machine paired"
                            : (relayMachineCount > 0 ? "\(relayMachineCount)" : "")
                    )
                }
                .accessibilityIdentifier("cursor.settings.row.trusted-machines")

                if invalidMachineCount > 0 {
                    Button("Clear dead pairings", role: .destructive) {
                        showingClearInvalidConfirmation = true
                    }
                    .accessibilityIdentifier("cursor.settings.row.clear-dead-pairings")
                }
            }

            Section("Notifications") {
                LabeledContent("Notifications", value: "Critical and high risk")
                    .accessibilityIdentifier("cursor.settings.row.notifications")
            }

            Section("Legal & Reset") {
                Button("Reset app data", role: .destructive) {
                    if onReset != nil { showingResetConfirmation = true }
                }
                .accessibilityIdentifier("cursor.settings.row.reset")
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("cursor.settings")
        .sheet(isPresented: $showingTrustedMachines) {
            CursorTrustedMachinesView(
                trustedMachines: trustedMachines,
                invalidMachines: invalidTrustedMachines,
                onRequestPairing: onRequestPairing,
                onRemoveMachine: onRemoveMachine,
                onClearInvalid: onClearInvalid,
                onPaired: onPaired
            )
        }
        .alert("Reset app data?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                guard let onReset else { return }
                Task { await onReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local pairing, threads, and cached settings from this device. Your hosts and audit history on paired machines are not affected.")
        }
        .alert("Clear dead pairings?", isPresented: $showingClearInvalidConfirmation) {
            Button("Clear", role: .destructive) { onClearInvalid?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(invalidMachineCount) pairing\(invalidMachineCount == 1 ? "" : "s") that failed to restore. Re-pair from the machine to reconnect.")
        }
    }
}
#endif
