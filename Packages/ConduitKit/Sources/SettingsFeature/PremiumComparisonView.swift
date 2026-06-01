#if os(iOS)
import SwiftUI
import DesignSystem
import StoreKit

public struct PremiumComparisonView: View {
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var pm = PurchaseManager.shared

    public init() {}

    private struct ComparisonRow {
        let feature: String
        let freeTier: Bool
    }

    private static let rows: [ComparisonRow] = [
        ComparisonRow(feature: "Unlimited BYO hosts",           freeTier: true),
        ComparisonRow(feature: "Block terminal + raw PTY",      freeTier: true),
        ComparisonRow(feature: "Agent inbox & approvals",        freeTier: true),
        ComparisonRow(feature: "tmux survival + reconnect",      freeTier: true),
        ComparisonRow(feature: "Dev-server preview",             freeTier: false),
        ComparisonRow(feature: "SFTP file browser",              freeTier: false),
        ComparisonRow(feature: "Partial-hunk diff",              freeTier: false),
        ComparisonRow(feature: "CloudKit sync",                  freeTier: false),
        ComparisonRow(feature: "Multi-agent",                    freeTier: false),
    ]

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader("upgrade", breadcrumb: "free vs pro")

                ScrollView {
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("free")
                                .font(.dsMonoPt(10, weight: .medium))
                                .tracking(10 * 0.10)
                                .textCase(.uppercase)
                                .foregroundStyle(t.text3)
                                .frame(width: 52, alignment: .center)
                            Text("pro")
                                .font(.dsMonoPt(10, weight: .medium))
                                .tracking(10 * 0.10)
                                .textCase(.uppercase)
                                .foregroundStyle(t.accent)
                                .frame(width: 52, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(t.surface)

                        DSDivider(.line)

                        ForEach(Array(Self.rows.enumerated()), id: \.offset) { idx, row in
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.feature)
                                        .font(.dsMonoPt(12))
                                        .foregroundStyle(t.text)
                                    if row.freeTier && idx == 2 {
                                        Text("(free)")
                                            .font(.dsMonoPt(10))
                                            .foregroundStyle(t.text3)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Free column
                                Group {
                                    if row.freeTier {
                                        DSIconView(.check, size: 14, color: t.text3)
                                    } else {
                                        Text("·")
                                            .font(.dsMonoPt(14))
                                            .foregroundStyle(t.text4)
                                    }
                                }
                                .frame(width: 52, alignment: .center)

                                // Pro column — always check
                                DSIconView(.check, size: 14, color: t.ok)
                                    .frame(width: 52, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(idx % 2 == 0 ? t.surface : t.bg)

                            if idx < Self.rows.count - 1 {
                                DSDivider(.soft, leadingInset: 16)
                            }
                        }
                    }
                    .background(t.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                // Sticky footer
                VStack(spacing: 8) {
                    DSDivider(.line)
                    VStack(spacing: 8) {
                        DSButton(
                            "unlock pro · \(pm.product?.displayPrice ?? "$14.99") once",
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
                            default: return false
                            }
                        }())

                        Text("one-time · yours forever · no subscription")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(t.bg)
            }
        }
        .task { await pm.load() }
    }
}
#endif
