#if os(iOS)
import SwiftUI
import DesignSystem

extension DSConnectError {
    // Heuristic classification from raw SSH error strings.
    static func classify(_ message: String) -> DSConnectError {
        let m = message.lowercased()
        if m.contains("auth") || m.contains("password") || m.contains("refused") || m.contains("key") && m.contains("fail") {
            return .authRejected
        } else if m.contains("resolve") || m.contains("dns") || m.contains("hostname") || m.contains("find host") {
            return .dnsFailed
        } else if m.contains("mismatch") || m.contains("fingerprint") || m.contains("host key") || m.contains("mitm") {
            return .hostKeyMismatch
        } else if m.contains("timeout") || m.contains("refused") || m.contains("unreachable") || m.contains("connect") {
            return .hostUnreachable
        } else {
            return .other(message)
        }
    }
}

public enum SSHConnectPhase: Equatable {
    case connecting             // pixel grid cycles through "working" animations
    case slow(message: String)  // still trying, but taking a while
    case connected              // grid settles to the green "done" state
    case disconnected           // connect ended without success (cancelled / host-key rejected) — dismissible
    case failed(message: String) // terminal failure, show error
}

// Full-screen SSH connect overlay built around the nested PixelBox.
// While connecting it crossfades between "working" grid animations (thinking ↔
// streaming) to convey loading; on connect it settles to the green "done" grid.
// No orb / ring / spinner — just the living pixel grid + a label.
public struct SSHConnectOverlay: View {
    let phase: SSHConnectPhase

    @State private var displayState: AgentState = .thinking
    @State private var labelText = "Connecting…"
    @State private var showDismissHint = false

    @Environment(\.conduitTokens) private var t

    public init(phase: SSHConnectPhase) {
        self.phase = phase
    }

    // States cycled while connecting — the two "busy" grid animations.
    private let loadingCycle: [AgentState] = [.thinking, .streaming]

    public var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            if case .failed(let message) = phase {
                // Typed error card replaces the raw string message
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 60)
                        DSTypedErrorCard(
                            error: .classify(message),
                            onPrimary: nil,
                            onSecondary: nil
                        )
                        .padding(.horizontal, 24)
                        if showDismissHint {
                            Text("Tap anywhere to dismiss")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, 20)
                                .transition(.opacity)
                        }
                        Spacer(minLength: 40)
                    }
                }
            } else {
                VStack(spacing: 30) {
                    Spacer()

                    ZStack {
                        PixelBox(state: displayState, size: 22, gap: 3, subdivisions: 3)
                            .id(displayState)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                    .frame(width: 92, height: 92)
                    .animation(.easeInOut(duration: 0.45), value: displayState)
                    .shadow(color: PixelBox.stateColor(displayState).opacity(0.35), radius: 24)

                    Text(labelText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: labelText)

                    if showDismissHint {
                        Text(phase == .connected ? "Tap anywhere to continue" : "Tap anywhere to dismiss")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .transition(.opacity)
                    }

                    Spacer()
                }
            }
        }
        .transition(.opacity)
        .task(id: phase) { await runPhase() }
    }

    private func runPhase() async {
        switch phase {
        case .connecting:
            labelText = "Connecting…"
            showDismissHint = false
            var i = 0
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.45)) {
                    displayState = loadingCycle[i % loadingCycle.count]
                }
                i += 1
                try? await Task.sleep(for: .seconds(2.0))
            }
        case .slow(let message):
            labelText = message
            // Keep cycling the loading animation (don't change displayState)
        case .connected:
            withAnimation(.easeInOut(duration: 0.6)) { displayState = .done }
            labelText = "Connected"
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation { showDismissHint = true }
        case .disconnected:
            withAnimation(.easeInOut(duration: 0.4)) { displayState = .offline }
            labelText = "Disconnected"
            withAnimation { showDismissHint = true }
        case .failed(let message):
            withAnimation(.easeInOut(duration: 0.3)) { displayState = .error }
            labelText = message
            withAnimation { showDismissHint = true }
        }
    }
}

#endif
