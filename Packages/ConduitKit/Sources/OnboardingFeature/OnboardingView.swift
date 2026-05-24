#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingView: View {
    public var onContinue: () -> Void
    public var onSetupWorkspace: () -> Void

    public init(onContinue: @escaping () -> Void, onSetupWorkspace: @escaping () -> Void = {}) {
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
    }

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "terminal").font(.system(size: 64)).foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Conduit").font(.largeTitle.weight(.semibold))
                Text("A phone-native cockpit for remote AI coding.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("Attach", "Connect to your remote workspace in seconds.", icon: "bolt")
                feature("Survive", "Sessions stay alive across Wi-Fi / cellular.", icon: "antenna.radiowaves.left.and.right")
                feature("Approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
                feature("Review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
            }
            .padding(.horizontal, 32)
            Spacer()
            Button(action: onContinue) {
                Text("Add your first host")
                    .font(.body.weight(.semibold)).padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button(action: onSetupWorkspace) {
                Text("Set up a workspace for me")
                    .font(.body).padding(.horizontal, 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text("BYO host. BYO API key. No subscription required.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer().frame(height: 16)
        }
        .padding()
    }

    private func feature(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

#endif
