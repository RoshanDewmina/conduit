#if os(iOS)
import SwiftUI
import SSHTransport
import LancerCore
import SecurityKit
import DesignSystem

public struct E2ERelayPairingView: View {
    let existingMachineCount: Int
    let onPaired: (E2ERelayClient, RelayMachineRecord) -> Void

    @ObservedObject private var client: E2ERelayClient
    @State private var pairingCode: String = ""
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    /// Always constructs a fresh, self-contained `E2ERelayClient` for exactly
    /// one pairing attempt (a fresh random `machineID`, no ambient/app-wide
    /// client). The real flow is always one-directional: the daemon
    /// (`lancerd pair` on the host) generates the code, the phone types it in.
    public init(existingMachineCount: Int, onPaired: @escaping (E2ERelayClient, RelayMachineRecord) -> Void) {
        self.existingMachineCount = existingMachineCount
        self.onPaired = onPaired
        let fresh = E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        _client = ObservedObject(initialValue: fresh)
        _pairingCode = State(initialValue: "")
    }

    private var isAtCap: Bool {
        existingMachineCount >= relayFleetMaxMachines
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    relayURLSection
                    if isAtCap {
                        capReachedSection
                    } else {
                        pairingCodeSection
                        statusSection
                        connectButton
                        if client.pairingState == .paired {
                            disconnectButton
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .navigationBarHidden(true)
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            DSDetailHeader("relay pairing", onBack: { dismiss() })

            Image(systemName: "lock.rotation")
                .font(.system(size: 48))
                .foregroundStyle(t.accent)

            Text("E2E Relay")
                .font(.dsSansPt(20, weight: .bold))
                .foregroundStyle(t.text)

            Text("Connect your phone and host through an end-to-end encrypted relay. Your data is encrypted before it leaves either device.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    // MARK: - Relay URL

    // The relay endpoint is fixed to the hosted relay in V1 — shown read-only so
    // a user can't strand their device on the wrong server. Self-hosters set the
    // LANCER_RELAY_URL env override (see RelaySettings).
    private var relayURLSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RELAY SERVER")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(t.text3)
                Text(RelaySettings.urlString())
                    .font(.dsMonoPt(14))
                    .foregroundStyle(t.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Cap reached

    private var capReachedSection: some View {
        VStack(spacing: 12) {
            Text("You've paired \(relayFleetMaxMachines) machines — the maximum. Offline or unreachable machines still count toward this limit. Remove one from Paired Machines in Settings to pair another.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            DSButton(
                "Maximum machines paired",
                variant: .primary,
                size: .lg,
                mono: true,
                fullWidth: true
            ) {}
            .disabled(true)
        }
    }

    // MARK: - Pairing Code

    private var pairingCodeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAIRING CODE")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            TextField("000000", text: $pairingCode)
                .font(.dsMonoPt(40, weight: .bold))
                .tracking(8)
                .foregroundStyle(t.text)
                .multilineTextAlignment(.center)
                .padding(16)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .keyboardType(.numberPad)

            Text("Run `lancerd pair` on your machine, then enter the 6-digit code it prints.")
                .font(.dsSansPt(12))
                .foregroundStyle(t.text3)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        if client.connectionState != .disconnected {
            VStack(spacing: 0) {
                StatusRow(label: "Relay", state: client.connectionState)
                DSDivider(.soft, leadingInset: 16)
                StatusRow(label: "Pairing", state: client.pairingState)
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Buttons

    private var connectButton: some View {
        DSButton(
            "Connect",
            variant: .primary,
            size: .lg,
            mono: true,
            fullWidth: true
        ) {
            connect()
        }
        .disabled(pairingCode.isEmpty)
    }

    private var disconnectButton: some View {
        DSButton(
            "Disconnect",
            variant: .destructive,
            size: .lg,
            mono: true,
            fullWidth: true
        ) {
            client.disconnect()
        }
    }

    // MARK: - Actions

    private func connect() {
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else { return }

        // A fresh client with no prior state — no need to disconnect() first.
        client.pairingCode = code
        client.connect()
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let state: CustomStringConvertible
    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.dsSansPt(13, weight: .medium))
                .foregroundStyle(t.text2)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(formattedState)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var formattedState: String {
        let desc = "\(state)"
        return desc
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    private var stateColor: Color {
        let s = "\(state)".lowercased()
        if s.contains("connect") || s.contains("paired") { return t.risk(0) }
        if s.contains("wait") || s.contains("reconnect") { return .orange }
        if s.contains("fail") || s.contains("error") { return t.danger }
        return t.text4
    }
}

#endif
