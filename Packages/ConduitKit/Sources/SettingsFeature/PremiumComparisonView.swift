#if os(iOS)
import SwiftUI
import DesignSystem
import StoreKit

public struct PremiumComparisonView: View {
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var pm = PurchaseManager.shared
    @State private var showPaywall = false

    public init() {}

    private let freeFeatures = [
        "Core SSH terminal",
        "1 host connection",
        "Block-based command history",
        "Shell integration (OSC 133)",
    ]

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 8)

                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(t.accentSoft)
                                .frame(width: 64, height: 64)
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(t.accent)
                        }
                        Text("Free vs Pro")
                            .font(.dsDisplayPt(22, weight: .bold))
                            .foregroundStyle(t.text)
                        Text("One-time purchase · no subscription")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                    }
                    .padding(.top, 8)

                    // Comparison table
                    VStack(spacing: 0) {
                        // Header row
                        HStack {
                            Text("Feature")
                                .font(.dsSansPt(12, weight: .semibold))
                                .foregroundStyle(t.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Free")
                                .font(.dsSansPt(12, weight: .semibold))
                                .foregroundStyle(t.text3)
                                .frame(width: 52, alignment: .center)
                            Text("Pro")
                                .font(.dsSansPt(12, weight: .semibold))
                                .foregroundStyle(t.accent)
                                .frame(width: 52, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(t.surface)

                        Divider().foregroundStyle(t.border)

                        ForEach(Array(comparisonRows.enumerated()), id: \.offset) { idx, row in
                            HStack {
                                Text(row.feature)
                                    .font(.dsSansPt(14))
                                    .foregroundStyle(t.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: row.free ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(row.free ? t.ok : t.text3.opacity(0.4))
                                    .frame(width: 52, alignment: .center)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(t.accent)
                                    .frame(width: 52, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(idx % 2 == 0 ? t.surface : t.bg)

                            if idx < comparisonRows.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                                    .foregroundStyle(t.border)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 4)

                    // Price callout
                    if let product = pm.product {
                        Text("\(product.displayPrice) · one-time, yours forever")
                            .font(.dsSansPt(14, weight: .semibold))
                            .foregroundStyle(t.text)
                    } else {
                        Text("$14.99 · one-time, yours forever")
                            .font(.dsSansPt(14, weight: .semibold))
                            .foregroundStyle(t.text)
                    }

                    // CTA
                    VStack(spacing: 12) {
                        switch pm.purchaseState {
                        case .purchased:
                            HStack(spacing: 8) {
                                DSIconView(.check, size: 16, color: t.ok)
                                Text("You're on Pro")
                                    .font(.dsSansPt(16, weight: .semibold))
                                    .foregroundStyle(t.ok)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(t.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                        case .unknown:
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.85)
                                Text("Loading…")
                                    .font(.dsSansPt(14))
                                    .foregroundStyle(t.text3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        default:
                            Button {
                                Task { await pm.purchase() }
                            } label: {
                                Group {
                                    if case .purchasing = pm.purchaseState {
                                        HStack(spacing: 8) {
                                            ProgressView().tint(t.accentFg)
                                            Text("Processing…")
                                        }
                                    } else {
                                        Text("Upgrade to Pro")
                                    }
                                }
                                .font(.dsSansPt(16, weight: .semibold))
                                .foregroundStyle(t.accentFg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(t.accent, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled({ if case .purchasing = pm.purchaseState { return true }; return false }())

                            Button("Restore Purchase") {
                                Task { await pm.restore() }
                            }
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.accent)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Upgrade to Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await pm.load() }
    }

    private struct ComparisonRow {
        let feature: String
        let free: Bool
    }

    private var comparisonRows: [ComparisonRow] {
        let freeSet = Set(freeFeatures)
        let allFeatures = freeFeatures + PaywallSheet.proFeatures
        return allFeatures.map { ComparisonRow(feature: $0, free: freeSet.contains($0)) }
    }
}
#endif
