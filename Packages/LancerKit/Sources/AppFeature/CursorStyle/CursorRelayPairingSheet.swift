#if os(iOS)
import SwiftUI
import DesignSystem
import SSHTransport
import LancerCore
import SecurityKit

/// Cursor-styled relay pairing sheet. Replaces the legacy `E2ERelayPairingView`
/// chrome (DesignSystem / "relay pairing" header) for all user-facing paths.
public struct CursorRelayPairingSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
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

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private var isAtCap: Bool {
        existingMachineCount >= relayFleetMaxMachines
    }

    private var isPairingFailed: Bool {
        if case .pairingFailed = client.pairingState { return true }
        return false
    }

    private var pairingFailureReason: String? {
        guard case .pairingFailed(let reason) = client.pairingState else { return nil }
        return humanizePairingFailure(reason)
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Pair machine",
            leadingButton: (systemImageName: "xmark", action: { dismiss() })
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connect your phone to a host through an end-to-end encrypted relay.")
                        .font(CursorType.bodyText)
                        .foregroundColor(colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    sectionLabel("Relay server")
                    readOnlyField(RelaySettings.urlString())

                    if isAtCap {
                        capReached
                    } else {
                        sectionLabel("Pairing code")
                        codeField
                        helperText("Run `lancerd pair` on your machine, then enter the 6-digit code.")
                        if client.connectionState != .disconnected || isPairingFailed {
                            statusCard
                        }
                        if let failure = pairingFailureReason {
                            failureBanner(failure)
                        }
                        CursorPillButton(title: "Connect", style: .primary) {
                            connect()
                        }
                        .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 6)
                        .frame(maxWidth: .infinity)

                        if client.pairingState == .paired {
                            CursorPillButton(
                                segments: [CursorPillButton.Segment("Disconnect", color: colors.dangerRed)],
                                style: .secondary
                            ) {
                                client.disconnect()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
            }
        }
        .accessibilityIdentifier("cursor.relay.pairing")
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CursorType.sectionHeader)
            .foregroundColor(colors.mutedText)
    }

    private func readOnlyField(_ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.mutedText)
            Text(value)
                .font(CursorType.inlineCode)
                .foregroundColor(colors.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var codeField: some View {
        TextField("000000", text: $pairingCode)
            .font(.system(size: 36, weight: .bold, design: .monospaced))
            .foregroundColor(colors.primaryText)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .padding(.vertical, 16)
            .background(colors.composerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("relay.pairing.code")
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(CursorType.rowSecondary)
            .foregroundColor(colors.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            statusRow("Relay", state: "\(client.connectionState)")
            Rectangle().fill(colors.hairline).frame(height: 1)
            statusRow("Pairing", state: "\(client.pairingState)")
        }
        .background(colors.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusRow(_ label: String, state: String) -> some View {
        HStack {
            Text(label)
                .font(CursorType.rowTitle)
                .foregroundColor(colors.secondaryText)
            Spacer()
            Text(formattedState(state))
                .font(CursorType.statusPill)
                .foregroundColor(colors.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func formattedState(_ raw: String) -> String {
        raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    private var capReached: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You've paired \(relayFleetMaxMachines) machines — the maximum (often ghost simulator pairings). Remove one from Trusted machines, then try again.")
                .font(CursorType.bodyText)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            CursorPillButton(title: "Close and manage machines", style: .primary) {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("cursor.relay.pairing.manage-machines")
        }
    }

    private func failureBanner(_ message: String) -> some View {
        Text(message)
            .font(CursorType.bodyText)
            .foregroundColor(colors.dangerRed)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.dangerRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("cursor.relay.pairing.failure")
    }

    /// Maps relay/daemon failure strings into an actionable sentence.
    private func humanizePairingFailure(_ reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("key mismatch") {
            return "This code is already pinned to another device (often a simulator auto-pair). On the Mac run `lancerd pair` for a fresh code, then enter that new code here — don't reuse an old one."
        }
        if lower.contains("expired") {
            return "That pairing code expired. Run `lancerd pair` on the Mac for a new code."
        }
        if lower.contains("too many") {
            return "Too many pairing attempts from this network. Wait a minute, then try again with a fresh `lancerd pair` code."
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
