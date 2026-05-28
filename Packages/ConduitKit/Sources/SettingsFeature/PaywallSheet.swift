#if os(iOS)
import SwiftUI
import StoreKit
import DesignSystem

/// Reusable paywall modal. Present when a user accesses a Pro-gated surface.
/// Automatically dismisses on successful purchase.
public struct PaywallSheet: View {
    public let featureName: String
    @Environment(\.dismiss) private var dismiss
    @State private var pm = PurchaseManager.shared

    public init(featureName: String) {
        self.featureName = featureName
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 16)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)

                    VStack(spacing: 8) {
                        Text("Conduit Pro")
                            .font(.title2.weight(.bold))
                        Text("\(featureName) requires Conduit Pro.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.proFeatures, id: \.self) { feature in
                            Label(feature, systemImage: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .conduitGlassChrome(cornerRadius: 12)

                    Group {
                        if let product = pm.product {
                            Text("\(product.displayPrice) · one-time purchase")
                        } else {
                            Text("$14.99 · one-time purchase")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        Button {
                            Task { await pm.purchase() }
                        } label: {
                            Group {
                                switch pm.purchaseState {
                                case .purchasing:
                                    ProgressView()
                                case .purchased:
                                    Label("Purchased", systemImage: "checkmark")
                                default:
                                    Text("Buy Conduit Pro")
                                }
                            }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled({
                            switch pm.purchaseState {
                            case .purchasing, .purchased: return true
                            default: return false
                            }
                        }())

                        Button("Restore Purchase") {
                            Task { await pm.restore() }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
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
