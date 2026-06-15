#if os(iOS)
import SwiftUI
import SSHTransport
import SecurityKit
import DesignSystem

public struct E2ERelayPairingView: View {
    @ObservedObject private var client: E2ERelayClient
    @State private var ownedClient: E2ERelayClient?
    @State private var relayURL: String = ""
    @State private var pairingCode: String = ""
    @State private var showGeneratedCode = false
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    /// Pair against an app-wide `E2ERelayClient` so the connection drives the
    /// live `ApprovalRelay.e2eBridge`. When `client` is nil this falls back to a
    /// self-owned client (no live bridge) — kept for standalone/preview use.
    public init(client: E2ERelayClient? = nil) {
        let resolved = client ?? E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        _client = ObservedObject(initialValue: resolved)
        _ownedClient = State(initialValue: client == nil ? resolved : nil)
        _relayURL = State(initialValue: RelaySettings.urlString())
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    relayURLSection
                    pairingCodeSection
                    statusSection
                    connectButton
                    if client.pairingState == .paired {
                        disconnectButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .navigationTitle("Relay Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if client.pairingState == .paired {
                        Button("Done") { dismiss() }
                            .font(.dsSansPt(15, weight: .medium))
                            .foregroundStyle(t.accent)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
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

    private var relayURLSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RELAY SERVER")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(t.text2)
                TextField("wss://relay.conduit.dev", text: $relayURL)
                    .font(.dsMonoPt(14))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundStyle(t.text)
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

    // MARK: - Pairing Code

    private var pairingCodeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAIRING CODE")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            if showGeneratedCode {
                Text(pairingCode)
                    .font(.dsMonoPt(40, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(t.text)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(t.surfaceSunk)
                    .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )

                Text("Enter this code on your phone")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            } else {
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
            }

            Toggle(isOn: $showGeneratedCode) {
                Text("I'm on the host (daemon)")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text)
            }
            .tint(t.accent)
            .onChange(of: showGeneratedCode) { _, show in
                if show, pairingCode.isEmpty {
                    pairingCode = generateCode()
                }
            }
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
        .disabled(relayURL.isEmpty || pairingCode.isEmpty)
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
        let normalized = RelaySettings.setURLString(relayURL)
        relayURL = normalized
        guard let url = URL(string: normalized) else { return }
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else { return }

        client.disconnect()
        client.relayURL = url
        client.pairingCode = code
        client.connect()
    }

    private func generateCode() -> String {
        String(format: "%06d", Int.random(in: 0...999999))
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let state: CustomStringConvertible
    @Environment(\.conduitTokens) private var t

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
