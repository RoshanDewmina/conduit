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
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "terminal")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)
                VStack(spacing: 6) {
                    Text("Conduit").font(.largeTitle.weight(.semibold))
                    Text("A phone-native cockpit for remote AI coding.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 16) {
                    feature("Attach", "Connect to your remote workspace in seconds.", icon: "bolt")
                    feature("Survive", "Sessions stay alive across Wi-Fi / cellular.", icon: "antenna.radiowaves.left.and.right")
                    feature("Approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
                    feature("Review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
                }
                Text("BYO host. BYO API key. No subscription required.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Label("Add your first host", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onSetupWorkspace) {
                    Label("Set up a workspace for me", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .conduitGlassChrome(cornerRadius: 0)
        }
    }

    private func feature(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
