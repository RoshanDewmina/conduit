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
                VStack(spacing: 24) {
                    PixelBox(color: t.accent, size: 56, gap: 6, subdivisions: 3)
                        .padding(.top, 44)
                    VStack(spacing: 6) {
                        Text("Conduit")
                            .font(.dsDisplayPt(34, weight: .bold))
                            .foregroundStyle(t.text1)
                        Text("A phone-native cockpit for remote AI coding.")
                            .font(.dsSansPt(15))
                            .foregroundStyle(t.text3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    modelCallout
                    VStack(alignment: .leading, spacing: 14) {
                        featureRow("Attach", "Connect to your remote workspace in seconds.", icon: "bolt")
                        featureRow("Survive", "Sessions stay alive across Wi-Fi / cellular.", icon: "antenna.radiowaves.left.and.right")
                        featureRow("Approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
                        featureRow("Review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 130)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                DSButton("Add your first host", icon: .plus,
                         variant: .accent, size: .lg, fullWidth: true,
                         action: onContinue)

                VStack(spacing: 4) {
                    DSButton("Set up a workspace for me", systemImage: "wand.and.stars",
                             variant: .secondary, size: .lg, fullWidth: true,
                             action: onSetupWorkspace)
                    Text("Provision a new Fly.io VM · Beta")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(t.surf0)
            .overlay(Rectangle().fill(t.surf3.opacity(0.5)).frame(height: 0.5), alignment: .top)
        }
    }

    private var modelCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How Conduit works", systemImage: "info.circle.fill")
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.text2)
            VStack(alignment: .leading, spacing: 7) {
                modelPoint(icon: "server.rack", title: "Your server",
                           detail: "Any SSH host — a VPS, cloud VM, or local machine.")
                modelPoint(icon: "key.fill", title: "Your API key",
                           detail: "Paste your Anthropic or OpenAI key. It goes directly to the provider, never to Conduit.")
                modelPoint(icon: "person.badge.minus", title: "No account needed",
                           detail: "No Conduit login. No subscription. Data stays on your device.")
            }
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }

    private func modelPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(t.accent)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            (Text(title).fontWeight(.semibold) + Text(" \(detail)"))
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(t.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(16, weight: .semibold))
                    .foregroundStyle(t.text1)
                Text(subtitle)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
