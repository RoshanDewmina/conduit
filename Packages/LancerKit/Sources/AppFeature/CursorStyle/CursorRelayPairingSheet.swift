#if os(iOS)
import SwiftUI

/// Cursor-styled relay pairing sheet — pure UI, no SSHTransport dependency.
/// States: enter code → connecting (25 s timeout) → success / failed.
///
/// - `onSubmitCode`: called with the 6-digit code when the user taps Connect.
/// - `onCancel`:     called when the sheet is dismissed without completing pairing.
///
/// In demo mode the connecting phase simulates log lines and times out to
/// "failed" after 25 s, which lets the owner tap through the full UX locally
/// without a live relay running. The parent controls whether a real pairing
/// attempt proceeds by acting on `onSubmitCode`.
public struct CursorRelayPairingSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.dismiss) private var dismiss

    let onSubmitCode: (String) -> Void
    let onCancel: () -> Void

    @State private var pairingCode = ""
    @State private var state: PairingState = .enterCode
    @State private var logLines: [String] = []
    @State private var connectTask: Task<Void, Never>?

    public init(
        onSubmitCode: @escaping (String) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.onSubmitCode = onSubmitCode
        self.onCancel = onCancel
    }

    private enum PairingState: Equatable {
        case enterCode
        case connecting
        case success
        case failed
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Pair machine",
            leadingButton: (systemImageName: "xmark", action: handleCancel)
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch state {
                    case .enterCode:
                        enterCodeContent
                    case .connecting:
                        connectingContent
                    case .success:
                        successContent
                    case .failed:
                        failedContent
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state)
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
            }
        }
        .environment(\.cursorScheme, .light)
        .accessibilityIdentifier("relay-pairing-sheet")
        .onDisappear {
            connectTask?.cancel()
        }
    }

    // MARK: - State views

    private var enterCodeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter the 6-digit code shown by `lancerd pair` on your machine.")
                .font(CursorType.bodyText)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            sectionLabel("Pairing code")
            codeField

            CursorPillButton(title: "Connect", style: .primary, action: submitCode)
                .disabled(normalizedCode.count != 6)
                .frame(maxWidth: .infinity)
        }
    }

    private var connectingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(colors.secondaryText)
                Text("Connecting…")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            if !logLines.isEmpty {
                sectionLabel("Connection log")
                logCard
            }

            CursorPillButton(title: "Cancel", style: .secondary, action: handleCancel)
                .frame(maxWidth: .infinity)
        }
    }

    private var successContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colors.successGreen)
                    .font(.system(size: 20))
                Text("Machine paired successfully.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.primaryText)
            }
            CursorPillButton(title: "Done", style: .primary) { dismiss() }
                .frame(maxWidth: .infinity)
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(colors.dangerRed)
                    .font(.system(size: 20))
                Text("Connection timed out. Check that `lancerd` is running and try again.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !logLines.isEmpty {
                sectionLabel("Connection log")
                logCard
            }

            CursorPillButton(title: "Try again", style: .primary, action: resetToEnterCode)
                .frame(maxWidth: .infinity)
            CursorPillButton(title: "Cancel", style: .secondary, action: handleCancel)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sub-components

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
            .onChange(of: pairingCode) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue || digits.count > 6 {
                    pairingCode = String(digits.prefix(6))
                }
            }
    }

    private var logCard: some View {
        VStack(spacing: 0) {
            let visibleLines = logLines.suffix(3)
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                if index > 0 {
                    Rectangle().fill(colors.hairline).frame(height: 1)
                }
                Text(line)
                    .font(CursorType.inlineCode)
                    .foregroundColor(colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(colors.composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CursorType.sectionHeader)
            .foregroundColor(colors.mutedText)
    }

    // MARK: - Actions

    private var normalizedCode: String {
        pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitCode() {
        let code = normalizedCode
        guard code.count == 6 else { return }
        onSubmitCode(code)
        state = .connecting
        logLines = []
        connectTask?.cancel()
        connectTask = Task { await runConnectSequence() }
    }

    private func resetToEnterCode() {
        connectTask?.cancel()
        connectTask = nil
        pairingCode = ""
        logLines = []
        state = .enterCode
    }

    private func handleCancel() {
        connectTask?.cancel()
        onCancel()
        dismiss()
    }

    /// Simulates the connecting sequence: emits log lines over time and
    /// transitions to "failed" after the 25 s relay timeout.
    private func runConnectSequence() async {
        let steps: [(delayNs: UInt64, line: String)] = [
            (5_000_000_000, "→ relay.lancer.sh:443 TCP ok"),
            (7_000_000_000, "→ sending HELLO frame"),
            (6_000_000_000, "→ waiting for agent response…"),
            (7_000_000_000, "→ timeout: no ACK after 25 s"),
        ]
        for (delayNs, line) in steps {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            let isTimeout = line.contains("timeout")
            await MainActor.run {
                logLines.append(line)
                if isTimeout { state = .failed }
            }
        }
    }
}
#endif
