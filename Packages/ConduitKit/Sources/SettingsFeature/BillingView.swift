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
                        HStack(spacing: 0) {
                            DSListSectionHead("Managed Compute")
                            Spacer()
                            Text("$— / mo")
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        settingsCard {
                            // GPU instance row (mock)
                            HStack(spacing: 12) {
                                DSIconView(.server, size: 16, color: t.text3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("gpu-box (fly.io)")
                                        .font(.dsSansPt(14))
                                        .foregroundStyle(t.text)
                                    Text("running · $0.06/hr") // TODO: wire live billing data
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSIconView(.chevronRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            cardDivider

                            // Payment method row (mock)
                            HStack(spacing: 12) {
                                DSIconView(.key, size: 16, color: t.text3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Payment method")
                                        .font(.dsSansPt(14))
                                        .foregroundStyle(t.text)
                                    Text("•••• 4242") // TODO: wire real payment method
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSIconView(.chevronRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            cardDivider

                            // Usage row (mock)
                            HStack(spacing: 12) {
                                DSIconView(.list, size: 16, color: t.text3)
                                Text("Usage & invoices") // TODO: wire billing portal
                                    .font(.dsSansPt(14))
                                    .foregroundStyle(t.text)
                                Spacer()
                                DSIconView(.chevronRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .padding(.bottom, 8)

                        Text("Metered compute is billed by the provider. Your own SSH hosts are always free.")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text3)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await pm.load() }
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
