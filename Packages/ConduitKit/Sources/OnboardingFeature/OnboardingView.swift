#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingView: View {
    public var onContinue: () -> Void
    public var onSetupWorkspace: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(onContinue: @escaping () -> Void, onSetupWorkspace: @escaping () -> Void = {}) {
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
    }

    public var body: some View {
        ZStack {
            t.surf0.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    PixelBox(color: t.accent, size: 64)
                        .padding(.top, 56)
                    VStack(spacing: 6) {
                        Text("Conduit")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(t.text1)
                        Text("A phone-native cockpit for remote AI coding.")
                            .font(.callout)
                            .foregroundStyle(t.text3)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        featureRow("Attach", "Connect to your remote workspace in seconds.", icon: "bolt")
                        featureRow("Survive", "Sessions stay alive across Wi-Fi / cellular.", icon: "antenna.radiowaves.left.and.right")
                        featureRow("Approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
                        featureRow("Review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
                    }
                    Text("BYO host. BYO API key. No subscription required.")
                        .font(.caption)
                        .foregroundStyle(t.text4)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 130)
                .frame(maxWidth: .infinity)
            }
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
                .tint(t.accent)

                Button(action: onSetupWorkspace) {
                    Label("Set up a workspace for me", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(t.surf0)
            .overlay(Rectangle().fill(t.surf3.opacity(0.5)).frame(height: 0.5), alignment: .top)
        }
    }

    private func featureRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(t.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(t.text1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(t.text3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
