#if os(iOS)
import SwiftUI
import DesignSystem

public struct TrustView: View {
    public let relayEncrypted: Bool
    public let relayHost: String?
    public let onOpenDevices: () -> Void
    public let onOpenRelay: () -> Void
    public let embedded: Bool

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(
        relayEncrypted: Bool,
        relayHost: String?,
        embedded: Bool = false,
        onOpenDevices: @escaping () -> Void,
        onOpenRelay: @escaping () -> Void
    ) {
        self.relayEncrypted = relayEncrypted
        self.relayHost = relayHost
        self.embedded = embedded
        self.onOpenDevices = onOpenDevices
        self.onOpenRelay = onOpenRelay
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    guaranteesSection
                    relayStatusSection
                    navSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .navigationBarHidden(!embedded)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            if !embedded {
                DSDetailHeader("privacy & trust", onBack: { dismiss() })
            }

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(t.ok)
                .padding(.top, 8)

            Text("Code never leaves your machine")
                .font(.dsSansPt(20, weight: .bold))
                .foregroundStyle(t.text)
                .multilineTextAlignment(.center)

            Text("The relay forwards ciphertext it can't read. Your agent sessions and approval decisions travel end-to-end encrypted between your phone and your host — no third party has the keys.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    // MARK: - Guarantees

    private var guaranteesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("GUARANTEES")
            VStack(spacing: 0) {
                guaranteeRow(
                    icon: "lock.rotation",
                    title: "Blind E2E relay",
                    detail: "The hosted relay routes encrypted frames. It never holds a session key."
                )
                DSDivider(.soft, leadingInset: 48)
                guaranteeRow(
                    icon: "key.horizontal",
                    title: "X25519 + ChaCha20-Poly1305",
                    detail: "Ephemeral Curve25519 key agreement derives per-session keys. Frames are sealed with ChaCha20-Poly1305 AEAD."
                )
                DSDivider(.soft, leadingInset: 48)
                guaranteeRow(
                    icon: "faceid",
                    title: "Keys in Keychain, behind biometrics",
                    detail: "Private keys are stored with whenUnlockedThisDeviceOnly. Sensitive actions require biometric confirmation."
                )
                DSDivider(.soft, leadingInset: 48)
                guaranteeRow(
                    icon: "eye.slash",
                    title: "No plaintext logging",
                    detail: "Session content and credentials are never written to logs. Approval decisions stay on-device."
                )
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func guaranteeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(t.ok)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Live relay indicator

    private var relayStatusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("RELAY STATUS")
            HStack(spacing: 10) {
                DSStatusDot(
                    tone: relayEncrypted ? .ok : .off,
                    pulse: relayEncrypted,
                    size: 10
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(relayEncrypted ? "Encrypted" : "Not connected")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.text)
                    if let host = relayHost {
                        Text(host)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                PrivacyBadge(relayEncrypted ? .e2eRelay : .local)
            }
            .padding(14)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Navigation

    private var navSection: some View {
        VStack(spacing: 10) {
            DSButton(
                "Paired devices",
                systemImage: "iphone.and.arrow.forward",
                variant: .secondary,
                size: .lg,
                fullWidth: true,
                action: onOpenDevices
            )
            DSButton(
                "Relay status",
                systemImage: "lock.rotation",
                variant: .secondary,
                size: .lg,
                fullWidth: true,
                action: onOpenRelay
            )
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.dsMonoPt(10, weight: .medium))
            .tracking(10 * 0.12)
            .foregroundStyle(t.text3)
            .padding(.bottom, 6)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TrustView(
            relayEncrypted: true,
            relayHost: "conduit-push-y4wpy6zeva-ts.a.run.app",
            onOpenDevices: {},
            onOpenRelay: {}
        )
        .lancerTokens()
    }
}
#endif
