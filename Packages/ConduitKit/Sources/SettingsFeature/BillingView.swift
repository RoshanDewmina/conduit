#if os(iOS)
import SwiftUI
import StoreKit
import DesignSystem

public struct BillingView: View {
    @State private var pm = PurchaseManager.shared
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── App Purchase
                    sectionHead("App Purchase")
                    settingsCard {
                        purchaseContent
                    }
                    .padding(.bottom, 8)

                    HStack {
                        Spacer()
                        Button("Restore Purchase") {
                            Task { await pm.restore() }
                        }
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.accent)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 8)

                    // ── Subscription
                    sectionHead("Subscription")
                    settingsCard {
                        if pm.externalStripeEligible {
                            Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                                HStack {
                                    DSIconView(.globe, size: 16, color: t.accent)
                                    Text("Manage Pro subscription")
                                        .font(.dsSansPt(15))
                                        .foregroundStyle(t.text)
                                    Spacer()
                                    DSIconView(.arrowRight, size: 14, color: t.text3)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        } else {
                            HStack(spacing: 8) {
                                DSIconView(.globe, size: 16, color: t.text3)
                                Text("Cloud subscription management unavailable")
                                    .font(.dsSansPt(14))
                                    .foregroundStyle(t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, 4)
                    Text("App access remains available through App Store purchase and restore.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // ── Compute Providers
                    sectionHead("Compute Providers")
                    settingsCard {
                        providerLink("Fly.io Dashboard", url: "https://fly.io/dashboard")
                        cardDivider
                        providerLink("AWS Lightsail Console", url: "https://lightsail.aws.amazon.com/ls/webapp/home")
                    }
                    .padding(.bottom, 16)

                    // ── Legal
                    sectionHead("Legal")
                    settingsCard {
                        providerLink("Privacy Policy", url: "https://conduit.dev/privacy")
                        cardDivider
                        providerLink("Terms of Service", url: "https://conduit.dev/terms")
                        cardDivider
                        Text("Purchases are processed by Apple. Conduit does not store payment information.")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await pm.load() }
    }

    // MARK: - Purchase content

    @ViewBuilder
    private var purchaseContent: some View {
        switch pm.purchaseState {
        case .purchased:
            HStack(spacing: 10) {
                DSIconView(.check, size: 16, color: t.ok)
                Text("Conduit Pro")
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                DSChip("Purchased", tone: .ok, variant: .soft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

        case .notPurchased:
            VStack(alignment: .leading, spacing: 12) {
                Text(pm.product.map { "Conduit Pro — \($0.displayPrice)" } ?? "Conduit Pro — $14.99")
                    .font(.dsSansPt(17, weight: .bold))
                    .foregroundStyle(t.text)
                Text("One-time purchase. No subscription required.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                featureBullets
                DSButton("Buy Conduit Pro", variant: .primary, action: {
                    Task { await pm.purchase() }
                })
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

        case .purchasing:
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.85)
                Text("Processing…")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

        case .unknown:
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.75)
                Text("Loading…")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    DSIconView(.alert, size: 14, color: t.danger)
                    Text("Purchase unavailable")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.danger)
                }
                Text(msg)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                Button("Try again") { Task { await pm.load() } }
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var featureBullets: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([
                "Unlimited SSH hosts",
                "AI agent approval inbox",
                "Dev server preview (port forwarding)",
                "Diff review with partial-hunk approval",
                "SFTP file browser",
                "CloudKit sync across devices",
            ], id: \.self) { feature in
                HStack(spacing: 8) {
                    DSIconView(.check, size: 12, color: t.ok)
                    Text(feature)
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text2)
                }
            }
        }
    }

    // MARK: - Layout helpers

    private func providerLink(_ label: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(label)
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
                Spacer()
                DSIconView(.arrowRight, size: 14, color: t.text3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sectionHead(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 0.5).padding(.horizontal, 16)
    }
}
#endif
