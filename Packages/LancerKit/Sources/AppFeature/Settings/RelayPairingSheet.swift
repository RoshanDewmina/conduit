#if os(iOS)
import SwiftUI
import LancerCore
import SecurityKit
import SSHTransport

/// Real (non-mocked) relay pairing sheet: enter the 6-digit code printed by
/// `lancerd pair` on the host, connect, and hand the paired client + record
/// back to the caller via `onPaired`. Rewritten fresh for the frontend
/// rebuild (Apple-native `Form`/`NavigationStack` only, no DesignSystem) —
/// behavior reference: `git show 3789aa5f:…/CursorRelayPairingSheet.swift`.
public struct RelayPairingSheet: View {
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
        _client = ObservedObject(initialValue: E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        ))
    }

    private var isAtCap: Bool { existingMachineCount >= relayFleetMaxMachines }

    private var pairingFailureReason: String? {
        guard case .pairingFailed(let reason) = client.pairingState else { return nil }
        return Self.humanizePairingFailure(reason)
    }

    private var isCodeExpired: Bool { client.pairingState == .codeExpired }

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
                        Text("You've paired \(relayFleetMaxMachines) machines — the maximum. Remove one from Trusted Machines, then try again.")
                        Button("Close") { dismiss() }
                    }
                } else {
                    Section("Pairing code") {
                        TextField("000000", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.system(.title, design: .monospaced))
                            .multilineTextAlignment(.center)
                        Text("Run `lancerd pair` on your machine, then enter the 6-digit code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if client.connectionState != .disconnected || pairingFailureReason != nil || isCodeExpired {
                        Section("Status") {
                            LabeledContent("Relay", value: "\(client.connectionState)")
                            LabeledContent("Pairing", value: "\(client.pairingState)")
                            if client.pairingState == .waitingForPeer, let expiresAt = client.pairingExpiresAt {
                                pairingCountdown(until: expiresAt)
                            }
                        }
                    }

                    if isCodeExpired {
                        Section {
                            Text("Pairing code expired — generate a new one on your machine, then enter it above.")
                                .foregroundStyle(.red)
                        }
                    } else if let pairingFailureReason {
                        Section {
                            Text(pairingFailureReason)
                                .foregroundStyle(.red)
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
            .navigationTitle("Pair a Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: client.pairingState) { _, newValue in
            guard newValue == .paired else { return }
            let record = RelayMachineRecord(id: client.machineID, displayName: "Relay host", pairedAt: .now)
            onPaired(client, record)
        }
        .onDisappear {
            if client.pairingState != .paired {
                client.disconnect()
            }
        }
    }

    /// Live TTL countdown for an unconfirmed pairing code, driven by
    /// `TimelineView` rather than a `Timer`/`Task.sleep` — no extra state to
    /// tear down when the sheet dismisses mid-wait.
    @ViewBuilder
    private func pairingCountdown(until expiresAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(expiresAt.timeIntervalSince(context.date).rounded(.up))
            if remaining > 0 {
                LabeledContent("Expires", value: "\(remaining / 60):\(String(format: "%02d", remaining % 60))")
            } else {
                LabeledContent("Expires", value: "any moment")
            }
        }
    }

    private func connect() {
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else { return }
        client.pairingCode = code
        client.connect()
    }

    private static func humanizePairingFailure(_ reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("key mismatch") {
            return "This code is already pinned to another device. On the host, run `lancerd pair` for a fresh code."
        }
        if lower.contains("expired") {
            return "That pairing code expired. Run `lancerd pair` on the host for a new code."
        }
        if lower.contains("too many") {
            return "Too many pairing attempts. Wait a minute, then try again with a fresh code."
        }
        return reason
    }
}
#endif
