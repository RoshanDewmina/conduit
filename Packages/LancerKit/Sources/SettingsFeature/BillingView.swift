#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem
import AgentKit

public struct BillingView: View {
    @State private var pm = PurchaseManager.shared
    @State private var creditBalance: CreditBalance?
    @State private var usageTodayUSD: Double = 0
    @State private var billingLoadError: String?
    @State private var isRestoring = false

    /// Surfaces a StoreKit failure from `purchaseState` so nothing fails silently.
    private var purchaseError: String? {
        if case .error(let message) = pm.purchaseState { return message }
        return nil
    }
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private let backendURL: String

    public init(backendURL: String = "") {
        self.backendURL = backendURL
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSDetailHeader("billing", onBack: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                    // ── Section 1: LANCER PRO
                    DSListSectionHead("Lancer Pro")

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
                                    Text("unlock at \(pm.displayPrice ?? "$14.99") once")
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSButton(
                                    "unlock lancer pro · \(pm.displayPrice ?? "$14.99") once",
                                    variant: .primary,
                                    size: .sm,
                                    mono: true,
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

                        // Visible failure surface — App Store review requires no silent errors.
                        if let purchaseError {
                            cardDivider
                            DSQuoteBlock(title: "purchase failed", message: purchaseError, tone: .danger)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .accessibilityIdentifier("billing.purchaseError")
                        }

                        cardDivider

                        // Restore row — App Store review requires a restore path.
                        Button {
                            Task {
                                isRestoring = true
                                await pm.restore()
                                isRestoring = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if isRestoring {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(t.accent)
                                }
                                Text(isRestoring ? "restoring…" : "restore purchase")
                                    .font(.dsMonoPt(12))
                                    .foregroundStyle(t.accent)
                                Spacer()
                                DSIconView(.arrowRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoring)
                        .accessibilityIdentifier("billing.restore")
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
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await pm.load()
            await loadCloudBilling()
        }
    }

    private var cloudBillingSection: some View {
        Group {
            HStack(spacing: 0) {
                DSListSectionHead("Lancer Cloud")
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

                // Spend hero — mirrors the board's billing glance (big mono spend value).
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "$%.2f", usageTodayUSD))
                            .font(.dsMonoPt(30, weight: .bold))
                            .foregroundStyle(t.text)
                        Text("today")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                        Spacer()
                    }
                    Rectangle()
                        .fill(t.divider)
                        .frame(height: 1)
                    Text("AI usage today · metered across vendors")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

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
        Bundle.main.infoDictionary?["LANCER_PUSH_BACKEND_URL"] as? String ?? ""
    }

    // MARK: - Layout helpers

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 1).padding(.horizontal, 16)
    }
}
#endif
