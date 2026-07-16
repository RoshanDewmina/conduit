#if os(iOS)
import SwiftUI

/// Minimal first-run gate: two screens explaining what Lancer is, then a
/// non-mandatory "Pair a machine" CTA that reuses `RelayPairingSheet`.
public struct OnboardingGateView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore

    private let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var isPairingPresented = false

    private enum Step {
        case welcome
        case pair
    }

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            switch step {
            case .welcome:
                welcomeScreen
            case .pair:
                pairScreen
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $isPairingPresented) {
            RelayPairingSheet(existingMachineCount: relayFleetStore.usableMachineCount) { client, record in
                RelayFleetHydration.addMachine(client: client, record: record, to: relayFleetStore)
                isPairingPresented = false
                onFinished()
            }
        }
    }

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            VStack(spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 88, height: 88)
                    .background(
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                    )

                Text("Lancer")
                    .font(.largeTitle.bold())

                Text("Mission control for AI coding agents")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text("Steer and approve Claude Code, Codex, and other agents running on your own machines and servers. Your phone does not run the agents — it governs them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 28)

            Spacer()

            primaryButton(title: "Continue") {
                step = .pair
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private var pairScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            VStack(spacing: 20) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 88, height: 88)
                    .background(
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                    )

                Text("Pair a machine")
                    .font(.largeTitle.bold())

                Text("Connect this phone to a host that runs `lancerd`. Once paired, you can open workspaces, start agents, and approve actions from here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                primaryButton(title: "Pair a Machine") {
                    isPairingPresented = true
                }

                Button {
                    onFinished()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 17, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Skip for now"))
                .accessibilityHint(Text("Continue into the app without pairing"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Color(.systemBackground))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary)
                )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    OnboardingGateView(onFinished: {})
        .environment(RelayFleetStore())
}
#endif
#endif
