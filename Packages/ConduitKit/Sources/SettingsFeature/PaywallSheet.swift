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
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 16)

                        // Icon
                        ZStack {
                            Circle()
                                .fill(t.accentSoft)
                                .frame(width: 80, height: 80)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(t.accent)
                        }

                        // Headline
                        VStack(spacing: 8) {
                            Text("Conduit Pro")
                                .font(.dsDisplayPt(22, weight: .bold))
                                .foregroundStyle(t.text)
                            Text("\(featureName) requires Conduit Pro.")
                                .font(.dsSansPt(15))
                                .foregroundStyle(t.text3)
                                .multilineTextAlignment(.center)
                        }

                        // Feature list
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Self.proFeatures, id: \.self) { feature in
                                HStack(spacing: 10) {
                                    DSIconView(.check, size: 14, color: t.ok)
                                    Text(feature)
                                        .font(.dsSansPt(14))
                                        .foregroundStyle(t.text)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 4)

                        // Price
                        Group {
                            if let product = pm.product {
                                Text("\(product.displayPrice) · one-time purchase")
                            } else {
                                Text("$14.99 · one-time purchase")
                            }
                        }
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)

                        // Actions
                        VStack(spacing: 12) {
                            Button {
                                Task { await pm.purchase() }
                            } label: {
                                Group {
                                    switch pm.purchaseState {
                                    case .purchasing:
                                        HStack(spacing: 8) {
                                            ProgressView().tint(t.accentFg)
                                            Text("Processing…")
                                        }
                                    case .purchased:
                                        HStack(spacing: 6) {
                                            DSIconView(.check, size: 16, color: t.accentFg)
                                            Text("Purchased")
                                        }
                                    default:
                                        Text("Buy Conduit Pro")
                                    }
                                }
                                .font(.dsSansPt(16, weight: .semibold))
                                .foregroundStyle(t.accentFg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(t.accent, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled({
                                switch pm.purchaseState {
                                case .purchasing, .purchased: return true
                                default: return false
                                }
                            }())

                            Button("Restore Purchase") {
                                Task { await pm.restore() }
                            }
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.accent)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(t.accent)
                }
            }
        }
        .task { await pm.load() }
        .onChange(of: pm.purchaseState) { _, new in
            if case .purchased = new { dismiss() }
        }
    }

    static let proFeatures = [
        "Unlimited SSH hosts",
        "AI agent approval inbox",
        "Dev server preview (port forwarding)",
        "Diff review with partial-hunk approval",
        "SFTP file browser",
        "CloudKit sync across devices",
    ]
}
#endif
