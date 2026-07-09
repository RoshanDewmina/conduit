#if os(iOS)
import SwiftUI
import SSHTransport
import LancerCore
import SecurityKit

/// Relay pairing sheet — enter code, connect, call `onPaired`, dismiss.
/// Post-pair landing (root → Workspaces) is owned by `CursorAppShell`.
/// Ported from stablyai/orca (MIT) mobile/app/pair-confirm.tsx pair-once semantics.
public struct CursorRelayPairingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingMachineCount: Int
    let onPaired: (E2ERelayClient, RelayMachineRecord) -> Void

    @ObservedObject private var client: E2ERelayClient
    @State private var pairingCode: String = ""

    public init(
        existingMachineCount: Int,
        onPaired: @escaping (E2ERelayClient, RelayMachineRecord) -> Void
    ) {
        self.existingMachineCount = existingMachineCount
        self.onPaired = onPaired
        let fresh = E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        _client = ObservedObject(initialValue: fresh)
    }

    private var isAtCap: Bool { existingMachineCount >= relayFleetMaxMachines }

    private var pairingFailureReason: String? {
        guard case .pairingFailed(let reason) = client.pairingState else { return nil }
        return humanizePairingFailure(reason)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect your phone to a host through an end-to-end encrypted relay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Relay server") {
                    Text(RelaySettings.urlString())
                        .font(.system(.body, design: .monospaced))
                }

                if isAtCap {
                    Section {
                        Text("You've paired \(relayFleetMaxMachines) machines — the maximum. Remove one from Trusted machines, then try again.")
                        Button("Close and manage machines") { dismiss() }
                            .accessibilityIdentifier("cursor.relay.pairing.manage-machines")
                    }
                } else {
                    Section("Pairing code") {
                        TextField("000000", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.system(.title, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("relay.pairing.code")
                        Text("Run `lancerd pair` on your machine, then enter the 6-digit code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if client.connectionState != .disconnected || pairingFailureReason != nil {
                        Section("Status") {
                            LabeledContent("Relay", value: "\(client.connectionState)")
                            LabeledContent("Pairing", value: "\(client.pairingState)")
                        }
                    }

                    if let failure = pairingFailureReason {
                        Section {
                            Text(failure)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("cursor.relay.pairing.failure")
                        }
                    }

                    Section {
                        Button("Connect") { connect() }
                            .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 6)
                        if client.pairingState == .paired {
                            Button("Disconnect", role: .destructive) { client.disconnect() }
                        }
                    }
                }
            }
            .navigationTitle("Pair machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .accessibilityIdentifier("cursor.relay.pairing")
        }
        .onChange(of: client.pairingState) { _, newValue in
            guard newValue == .paired else { return }
            let record = RelayMachineRecord(id: client.machineID, displayName: "Relay host", pairedAt: .now)
            onPaired(client, record)
            dismiss()
        }
        .onDisappear {
            if client.pairingState != .paired {
                client.disconnect()
            }
        }
    }

    private func humanizePairingFailure(_ reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("key mismatch") {
            return "This code is already pinned to another device. On the Mac run `lancerd pair` for a fresh code."
        }
        if lower.contains("expired") {
            return "That pairing code expired. Run `lancerd pair` on the Mac for a new code."
        }
        if lower.contains("too many") {
            return "Too many pairing attempts. Wait a minute, then try again with a fresh code."
        }
        return reason
    }

    private func connect() {
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else { return }
        client.pairingCode = code
        client.connect()
    }
}
#endif
