#if os(iOS)
import SwiftUI
import StoreKit

public struct BillingView: View {
    @State private var pm = PurchaseManager.shared

    public init() {}

    public var body: some View {
        List {
            purchaseSection
            subscriptionSection
            providerSection
            legalSection
        }
        .navigationTitle("Billing")
        .task { await pm.load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var purchaseSection: some View {
        Section {
            switch pm.purchaseState {
            case .purchased:
                HStack {
                    Label("Conduit Pro", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("Purchased").foregroundStyle(.secondary)
                }

            case .notPurchased:
                VStack(alignment: .leading, spacing: 8) {
                    if let product = pm.product {
                        Text("Conduit Pro — \(product.displayPrice)")
                            .font(.headline)
                    } else {
                        Text("Conduit Pro — $14.99")
                            .font(.headline)
                    }
                    Text("One-time purchase. No subscription required.")
                        .font(.caption).foregroundStyle(.secondary)
                    featureBullets
                    Button("Buy Conduit Pro") {
                        Task { await pm.purchase() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)

            case .purchasing:
                HStack {
                    ProgressView()
                    Text("Processing…").foregroundStyle(.secondary)
                }

            case .unknown:
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…").foregroundStyle(.secondary)
                }

            case .error(let msg):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchase unavailable").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                    Button("Try again") { Task { await pm.load() } }
                        .font(.caption)
                }
            }
        } header: {
            Text("App Purchase")
        }

        Section {
            Button("Restore Purchase") { Task { await pm.restore() } }
        }
    }

    private var featureBullets: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([
                "Unlimited SSH hosts",
                "AI agent approval inbox",
                "Dev server preview (port forwarding)",
                "Diff review with partial-hunk approval",
                "SFTP file browser",
                "CloudKit sync across devices",
            ], id: \.self) { feature in
                Label(feature, systemImage: "checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            if pm.externalStripeEligible {
                Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                    HStack {
                        Label("Manage Pro subscription", systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Cloud subscription management unavailable", systemImage: "globe")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("App access remains available through App Store purchase and restore.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section("Compute Providers") {
            Link("Fly.io Dashboard", destination: URL(string: "https://fly.io/dashboard")!)
            Link("AWS Lightsail Console", destination: URL(string: "https://lightsail.aws.amazon.com/ls/webapp/home")!)
        }
    }

    private var legalSection: some View {
        Section {
            Link("Privacy Policy", destination: URL(string: "https://conduit.dev/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://conduit.dev/terms")!)
            Text("Purchases are processed by Apple. Conduit does not store payment information.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
#endif
