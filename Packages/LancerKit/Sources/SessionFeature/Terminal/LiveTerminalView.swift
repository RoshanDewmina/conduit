#if os(iOS)
import SwiftUI
import TerminalEngine

/// Interactive terminal surface for daemon-owned PTYs (Orca-style).
/// Direct keystroke input is the default (Orca mobile-terminal-direct-input).
public struct LiveTerminalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: RelayTerminalModel
    @State private var ctrlLatched = false

    public init(model: RelayTerminalModel) {
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
    }

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

            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

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
        .overlay(Rectangle().fill(theme.foreground.opacity(0.08)).frame(height: 0.5), alignment: .bottom)
    }

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
            case .connecting:
                statusOverlay(ProgressView().tint(theme.foreground), text: "Connecting…")
            case .failed(let message):
                statusOverlay(Image(systemName: "exclamationmark.triangle"), text: message)
            case .closed:
                statusOverlay(Image(systemName: "bolt.slash"), text: "Session closed")
            case .connected:
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

    /// Orca mobile accessory bar: Esc / Tab / Ctrl latch / arrows.
    private var accessoryRail: some View {
        HStack(spacing: 8) {
            key("Esc") { model.send([0x1b]) }
            key("Tab") { model.send([0x09]) }
            Button {
                ctrlLatched.toggle()
            } label: {
                Text("Ctrl")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ctrlLatched ? theme.background : theme.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ctrlLatched ? theme.foreground : theme.foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            key("↑") { model.send([0x1b, 0x5b, 0x41]) }
            key("↓") { model.send([0x1b, 0x5b, 0x42]) }
            key("←") { model.send([0x1b, 0x5b, 0x44]) }
            key("→") { model.send([0x1b, 0x5b, 0x43]) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.25))
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(theme.foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

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
        case .connected: return .green
        case .failed: return .red
        case .closed: return .gray
        }
    }

    private var statusLabel: String {
        switch model.status {
        case .connecting: return "connecting…"
        case .connected: return "connected"
        case .failed(let msg): return msg
        case .closed: return "closed"
        }
    }
}
#endif
