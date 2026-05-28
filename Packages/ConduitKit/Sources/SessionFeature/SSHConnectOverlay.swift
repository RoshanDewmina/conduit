#if os(iOS)
import SwiftUI
import DesignSystem

public enum SSHConnectPhase: Equatable {
    case connecting    // orb pulsing, spinner visible
    case connected     // orb expands, spinner → checkmark
}

// Full-screen 4-phase SSH connect orb overlay.
// Phases: connecting → orb pulses → expanding → done (dismiss).
// Uses phaseAnimator for the orb and keyframeAnimator for the expand/burst.
public struct SSHConnectOverlay: View {
    let phase: SSHConnectPhase

    @State private var orbScale: CGFloat = 1
    @State private var orbOpacity: Double = 0.7
    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0
    @State private var checkVisible = false
    @State private var labelText = "Connecting…"
    @State private var subText: String? = nil
    @State private var showDismissHint = false

    @Environment(\.conduitTokens) private var t

    public init(phase: SSHConnectPhase) {
        self.phase = phase
    }

    public var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Orb cluster
                ZStack {
                    // Outer ring pulse (connecting state)
                    Circle()
                        .strokeBorder(t.accent.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    Circle()
                        .strokeBorder(t.accent.opacity(0.15), lineWidth: 1)
                        .frame(width: 170, height: 170)
                        .scaleEffect(ringScale * 1.2)
                        .opacity(ringOpacity * 0.6)

                    // Gradient blob (the orb)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    t.accent.opacity(0.9),
                                    t.accent.opacity(0.4),
                                    t.accent.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 55
                            )
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(orbScale)
                        .opacity(orbOpacity)

                    // Core: spinner or checkmark
                    ZStack {
                        if !checkVisible {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.3)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4), value: checkVisible)
                }

                // Labels
                VStack(spacing: 8) {
                    Text(labelText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .animation(.easeInOut(duration: 0.3), value: labelText)

                    if let sub = subText {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .transition(.opacity)
                    }
                }

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
        .onAppear { startConnectingAnimation() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .connected { playConnectedBurst() }
        }
    }

    // MARK: - Animations

    private func startConnectingAnimation() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            orbScale = 1.08
            orbOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            ringScale = 1.3
            ringOpacity = 0.0
        }
        labelText = "Connecting…"
    }

    private func playConnectedBurst() {
        // Expand orb
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            orbScale = 1.3
        }
        // Swap spinner → checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            checkVisible = true
            labelText = "Connected"
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                orbScale = 1.0
            }
        }
        // Show dismiss hint after a beat
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showDismissHint = true }
        }
    }
}

#endif
