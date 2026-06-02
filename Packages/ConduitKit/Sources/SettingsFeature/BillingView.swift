#if os(iOS)
import SwiftUI
import StoreKit
import DesignSystem
import AgentKit

public struct BillingView: View {
    @State private var pm = PurchaseManager.shared
    @State private var creditBalance: CreditBalance?
    @State private var usageTodayUSD: Double = 0
    @State private var billingLoadError: String?
    @Environment(\.conduitTokens) private var t

    private let backendURL: String

    public init(backendURL: String = "") {
        self.backendURL = backendURL
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Section 1: CONDUIT PRO
                    DSListSectionHead("Conduit Pro")

                    settingsCard {
                        if pm.isPro {
                            // Purchased state
                            HStack(spacing: 12) {
                                DSIconView(.sparkles, size: 16, color: t.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pro unlocked")
                                        .font(.dsSansPt(15, weight: .semibold))
                                        .foregroundStyle(t.text)
                                    Text("one-time · verified")
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSIconView(.check, size: 16, color: t.ok)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        } else {
                            // Not purchased state
                            HStack(spacing: 12) {
                                DSIconView(.sparkles, size: 16, color: t.text3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pro not purchased")
                                        .font(.dsSansPt(15, weight: .semibold))
                                        .foregroundStyle(t.text)
                                    Text("unlock at \(pm.product?.displayPrice ?? "$14.99") once")
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSButton(
                                    "unlock conduit pro · \(pm.product?.displayPrice ?? "$14.99") once",
                                    variant: .primary,
                                    size: .sm,
                                    isLoading: {
                                        if case .purchasing = pm.purchaseState { return true }
                                        return false
                                    }(),
                                    action: { Task { await pm.purchase() } }
                                )
                                .disabled({
                                    switch pm.purchaseState {
                                    case .purchasing: return true
                                    default: return false
                                    }
                                }())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        cardDivider

                        // Restore row
                        Button {
                            Task { await pm.restore() }
                        } label: {
                            HStack {
                                Text("restore purchase")
                                    .font(.dsMonoPt(12))
                                    .foregroundStyle(t.accent)
                                Spacer()
                                DSIconView(.arrowRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)

                    // ── Section 2: MANAGED COMPUTE (gated by externalStripeEligible)
                    if pm.externalStripeEligible {
                        cloudBillingSection
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await pm.load()
            await loadCloudBilling()
        }
    }

    private var cloudBillingSection: some View {
        Group {
            HStack(spacing: 0) {
                DSListSectionHead("Conduit Cloud")
                Spacer()
                Text(creditBalance?.creditsRemainingLabel ?? "$—")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            settingsCard {
                HStack(spacing: 12) {
                    DSIconView(.sparkles, size: 16, color: pm.hasCloudEntitlement ? t.accent : t.text3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pm.hasCloudEntitlement ? "Cloud active" : "Cloud inactive")
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text)
                        Text("status: \(pm.cloudEntitlement?.status ?? "unknown")")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                cardDivider

                HStack(spacing: 12) {
                    DSIconView(.list, size: 16, color: t.text3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI usage today")
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text)
                        Text(String(format: "$%.2f", usageTodayUSD))
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if let creditBalance {
                    cardDivider
                    HStack(spacing: 12) {
                        DSIconView(.key, size: 16, color: t.text3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prepaid credits")
                                .font(.dsSansPt(14))
                                .foregroundStyle(t.text)
                            Text(creditBalance.creditsRemainingLabel)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                            if creditBalance.overageUSD > 0 {
                                Text(String(format: "Overage $%.2f", creditBalance.overageUSD))
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(t.warn)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .padding(.bottom, 8)

            if let billingLoadError {
                Text(billingLoadError)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 20)
            }

            Text("Managed AI is metered via OpenRouter. SSH hosts you own remain free.")
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
    }

    private func loadCloudBilling() async {
        guard pm.hasCloudEntitlement else { return }
        let urlString = backendURL.isEmpty ? (pm.cloudEntitlement != nil ? resolvedBackendURL() : "") : backendURL
        guard !urlString.isEmpty, let baseURL = URL(string: urlString) else { return }

        let auth = ControlPlaneAuth(
            customerId: UserDefaults.standard.string(forKey: PurchaseManager.stripeCustomerIDKey),
            appAccountToken: UserDefaults.standard.string(forKey: PurchaseManager.appAccountTokenKey),
            clientToken: UserDefaults.standard.string(forKey: PurchaseManager.clientTokenKey)
        )
        let client = HostedAgentAPIClient(baseURL: baseURL, auth: auth)
        billingLoadError = nil
        do {
            creditBalance = try await client.fetchCredits()
        } catch {
            billingLoadError = "Credits unavailable"
        }
        usageTodayUSD = 0
    }

    private func resolvedBackendURL() -> String {
        Bundle.main.infoDictionary?["CONDUIT_PUSH_BACKEND_URL"] as? String ?? ""
    }

    // MARK: - Layout helpers

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 0.5).padding(.horizontal, 16)
    }
}
#endif
