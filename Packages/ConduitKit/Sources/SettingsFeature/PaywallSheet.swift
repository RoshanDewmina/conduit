#if os(iOS)
import SwiftUI
import StoreKit
import DesignSystem

public struct PaywallSheet: View {
    public let featureName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t
    @State private var pm = PurchaseManager.shared

    public init(featureName: String) {
        self.featureName = featureName
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Spectrum bar — aligned to the same 16pt gutter as the
                    // content below so it doesn't full-bleed past the layout.
                    SpectrumBar(mode: .idle, height: 8)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 20) {

                        // "no subscriptions, ever" chip
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(t.danger)
                                .frame(width: 5, height: 5)
                            Text("no subscriptions, ever")
                                .font(.dsMonoPt(11, weight: .medium))
                                .tracking(11 * 0.08)
                                .textCase(.uppercase)
                                .foregroundStyle(t.danger)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.danger.opacity(0.5), lineWidth: 1)
                        )

                        // Two-line big title
                        VStack(alignment: .leading, spacing: 2) {
                            Text("pay once.")
                                .font(.dsDisplayPt(34, weight: .bold))
                                .foregroundStyle(t.text)
                            Text("yours forever.")
                                .font(.dsDisplayPt(34, weight: .bold))
                                .foregroundStyle(t.accent)
                        }

                        // Body text
                        Text("Unlock every Pro power-tool with a single purchase. No recurring fee to use your own hardware — that's a promise.")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        // Feature context note
                        Text("\(featureName) — part of Pro.")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)

                        // Price display
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Group {
                                if let product = pm.product {
                                    Text(product.displayPrice)
                                } else {
                                    Text("$14.99")
                                }
                            }
                            .font(.dsDisplayPt(38, weight: .bold))
                            .foregroundStyle(t.text)

                            Text("once")
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.text3)
                        }

                        // CTA
                        VStack(spacing: 12) {
                            DSButton(
                                "unlock conduit pro",
                                variant: .primary,
                                mono: true,
                                isLoading: {
                                    if case .purchasing = pm.purchaseState { return true }
                                    return false
                                }(),
                                fullWidth: true,
                                action: { Task { await pm.purchase() } }
                            )
                            .disabled({
                                switch pm.purchaseState {
                                case .purchasing, .purchased: return true
                                default: return pm.product == nil
                                }
                            }())

                            if pm.product == nil, case .unknown = pm.purchaseState {
                                Text("loading price…")
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text3)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button("restore purchase") {
                                Task { await pm.restore() }
                            }
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.accent)
                            .frame(maxWidth: .infinity, alignment: .center)

                            if case .error(let msg) = pm.purchaseState {
                                VStack(spacing: 6) {
                                    Text(msg)
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.danger)
                                        .multilineTextAlignment(.center)
                                    Button("try again") { Task { await pm.load() } }
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.accent)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                }
            }

            // Dismiss button
            DSIconButton(.close) { dismiss() }
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .task { await pm.load() }
        .onChange(of: pm.purchaseState) { _, new in
            if case .purchased = new { dismiss() }
        }
    }
}
#endif
