#if os(iOS)
import SwiftUI
import DesignSystem

public enum SSHConnectPhase: Equatable {
    case connecting    // pixel grid cycles through "working" animations
    case connected     // grid settles to the green "done" state
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

            VStack(spacing: 30) {
                Spacer()

                // The grid. `.id` + transition gives a soft crossfade each time
                // the state switches, so the loading loop never pops.
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
                    Text("Tap anywhere to continue")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                }

                Spacer()
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
        case .connected:
            withAnimation(.easeInOut(duration: 0.6)) { displayState = .done }
            labelText = "Connected"
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation { showDismissHint = true }
        }
    }
}

#endif
