#if os(iOS)
import SwiftUI
import LancerCore
import TerminalEngine

public struct LiveTerminalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LiveTerminalModel
    @State private var ctrlLatched = false

    public init(model: LiveTerminalModel) {
        _model = State(initialValue: model)
    }

    private var theme: TerminalTheme { TerminalTheme.current }

    public var body: some View {
        VStack(spacing: 0) {
            header
            terminalSurface
        }
        .background(theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { accessoryRail }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: hostKeySheetPresented) {
            hostKeyTrustSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.foreground.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            statusDot

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                Text(statusLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.foreground.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.background)
        .background(Color.black.opacity(0.18))
        .overlay(Rectangle().fill(theme.foreground.opacity(0.08)).frame(height: 0.5), alignment: .bottom)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 9, height: 9)
            .opacity(model.status == .connecting ? 0.6 : 1)
            .animation(model.status == .connecting ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: model.status)
    }

    // MARK: - Terminal surface

    private var terminalSurface: some View {
        ZStack {
            theme.background
            RawTerminalView(
                feedHandle: model.feedHandle,
                onUserBytes: { bytes in
                    model.send(consumeCtrlLatch(Array(bytes)))
                },
                onResize: { cols, rows in
                    model.resize(cols: cols, rows: rows)
                }
            )

            switch model.status {
            case .connecting where model.pendingHostKeyFingerprint == nil:
                statusOverlay(ProgressView().tint(theme.foreground), text: "Connecting…")
            case .failed(let message):
                statusOverlay(Image(systemName: "exclamationmark.triangle"), text: message)
            case .closed:
                statusOverlay(Image(systemName: "bolt.slash"), text: "Session closed")
            case .connecting, .connected:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusOverlay(_ icon: some View, text: String) -> some View {
        VStack(spacing: 10) {
            icon.font(.title2).foregroundStyle(theme.foreground.opacity(0.8))
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.foreground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(40)
    }

    // MARK: - Keyboard accessory rail

    private var accessoryRail: some View {
        TerminalAccessoryRail(ctrlLatched: $ctrlLatched) { bytes in
            model.send(bytes)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.25))
    }

    // MARK: - Host key TOFU

    private var hostKeySheetPresented: Binding<Bool> {
        Binding(
            get: { model.pendingHostKeyFingerprint != nil },
            set: { if !$0 { model.rejectHostKey() } }
        )
    }

    private var hostKeyTrustSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unknown host key")
                    .font(.headline)
                Text("Verify this fingerprint before trusting:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.pendingHostKeyFingerprint ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(20)
            .navigationTitle("Trust host?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.rejectHostKey() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Trust") {
                        Task { await model.trustHostKey() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func consumeCtrlLatch(_ bytes: [UInt8]) -> [UInt8] {
        guard ctrlLatched, let first = bytes.first else { return bytes }
        ctrlLatched = false
        var outgoing = bytes
        if (0x41...0x5a).contains(first) || (0x61...0x7a).contains(first) {
            outgoing[0] = first & 0x1f
        }
        return outgoing
    }

    private var statusColor: Color {
        switch model.status {
        case .connecting: return .yellow
        case .connected:  return .green
        case .failed:     return .red
        case .closed:     return .gray
        }
    }

    private var statusLabel: String {
        if model.pendingHostKeyFingerprint != nil {
            return "verify host key…"
        }
        switch model.status {
        case .connecting:        return "connecting…"
        case .connected:         return "connected"
        case .failed(let msg):   return msg
        case .closed:            return "closed"
        }
    }
}

// MARK: - Minimal accessory rail (no DesignSystem)

private struct TerminalAccessoryRail: View {
    @Binding var ctrlLatched: Bool
    let onBytes: ([UInt8]) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                keyButton("Esc", bytes: [0x1b])
                keyButton("Tab", bytes: [0x09])
                ctrlButton
                keyButton("↑", bytes: [0x1b, 0x5b, 0x41])
                keyButton("↓", bytes: [0x1b, 0x5b, 0x42])
                keyButton("←", bytes: [0x1b, 0x5b, 0x44])
                keyButton("→", bytes: [0x1b, 0x5b, 0x43])
            }
            .padding(.horizontal, 4)
        }
    }

    private var ctrlButton: some View {
        Button {
            ctrlLatched.toggle()
        } label: {
            Text("Ctrl")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ctrlLatched ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func keyButton(_ title: String, bytes: [UInt8]) -> some View {
        Button {
            onBytes(bytes)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
#endif
