#if os(iOS)
import Foundation
import StoreKit
import Observation
import AgentKit

public enum PurchaseState: Sendable, Equatable {
    case unknown
    case notPurchased
    case purchased
    case purchasing
    case error(String)
}

public enum CloudEntitlementLoadState: Sendable, Equatable {
    case unknown
    case loading
    case loaded
    case error(String)
}

/// StoreKit 2 manager for the Conduit one-time purchase.
/// Product ID matches the entry in App Store Connect.
@MainActor @Observable
public final class PurchaseManager {
    public static let shared = PurchaseManager()

    public static let proProductID = "dev.conduit.mobile.pro"
    public static let stripeCustomerIDKey = "dev.conduit.stripeCustomerId"
    public static let appAccountTokenKey = "dev.conduit.appAccountToken"
    public static let clientTokenKey = "dev.conduit.clientToken"

    public var purchaseState: PurchaseState = .unknown
    public var product: Product?
    public var storefrontCountryCode: String?
    public var cloudEntitlement: CloudEntitlement?
    public var cloudEntitlementState: CloudEntitlementLoadState = .unknown

    public var externalStripeEligible: Bool {
        BillingEligibility.isExternalStripeEligible(storefrontCountryCode: storefrontCountryCode)
    }

    /// Apple IAP one-time purchase — unlocks core Pro features.
    public var isPro: Bool {
        #if DEBUG
        // Default: unlocked. Explicit `false` overrides back to paywall.
        if UserDefaults.standard.object(forKey: "conduitDebugProBypass") == nil { return true }
        if UserDefaults.standard.bool(forKey: "conduitDebugProBypass") { return true }
        #endif
        return purchaseState == .purchased
    }

    /// Stripe "Conduit Cloud" subscription — unlocks hosted agents + managed AI.
    public var hasCloudEntitlement: Bool {
        #if DEBUG
        let debugBypass = UserDefaults.standard.bool(forKey: "conduitDebugCloudEntitlement")
        #else
        let debugBypass = false
        #endif
        return CloudEntitlementPolicy.hasCloudEntitlement(
            cloudEntitlement,
            backendURLConfigured: cachedBackendURL?.isEmpty == false,
            debugBypass: debugBypass
        )
    }

    /// Managed OpenRouter sub-key provisioned by push-backend (premium tier).
    public var managedOpenRouterKey: String? {
        cloudEntitlement?.openRouterAPIKey
    }

#if DEBUG
    /// Toggle the debug pro-bypass flag from the Settings UI.
    public var debugProBypass: Bool {
        get { UserDefaults.standard.bool(forKey: "conduitDebugProBypass") }
        set { UserDefaults.standard.set(newValue, forKey: "conduitDebugProBypass") }
    }

    public var debugCloudEntitlement: Bool {
        get { UserDefaults.standard.bool(forKey: "conduitDebugCloudEntitlement") }
        set { UserDefaults.standard.set(newValue, forKey: "conduitDebugCloudEntitlement") }
    }
#endif

    @ObservationIgnored nonisolated(unsafe) private var transactionListener: Task<Void, Never>?
    @ObservationIgnored private var cachedBackendURL: String?

    private init() {
        transactionListener = listenForTransactions()
    }

    public func configure(backendURL: String) {
        cachedBackendURL = backendURL
    }

    public func load() async {
        do {
            storefrontCountryCode = await Storefront.current?.countryCode
            let products = try await Product.products(for: [Self.proProductID])
            guard let loadedProduct = products.first else {
                product = nil
                #if DEBUG
                purchaseState = .error("Product not found. Check that Conduit.storekit is selected in the Run scheme for StoreKit testing.")
                #else
                purchaseState = .error("Couldn't load purchase options. Please check your connection and try again.")
                #endif
                return
            }
            product = loadedProduct
            await refreshPurchaseState()
        } catch {
            #if DEBUG
            purchaseState = .error(error.localizedDescription)
            #else
            purchaseState = .error("Couldn't load purchase options. Please check your connection and try again.")
            #endif
        }
    }

    public func purchase() async {
        guard let product else {
            #if DEBUG
            purchaseState = .error("Product not loaded")
            #else
            purchaseState = .error("Couldn't start the purchase. Please try again.")
            #endif
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                purchaseState = .purchased
            case .userCancelled:
                purchaseState = .notPurchased
            case .pending:
                purchaseState = .notPurchased
            @unknown default:
                purchaseState = .notPurchased
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    public func restore() async {
        do {
            try await AppStore.sync()
            await refreshPurchaseState()
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    /// Poll push-backend for Stripe subscription entitlement.
    public func refreshCloudEntitlement(backendURL: String? = nil) async {
        let urlString = backendURL ?? cachedBackendURL ?? ""
        cachedBackendURL = urlString

        guard !urlString.isEmpty, let baseURL = URL(string: urlString) else {
            #if DEBUG
            cloudEntitlement = CloudEntitlement(status: "debug_stub", active: false)
            cloudEntitlementState = .loaded
            #else
            cloudEntitlement = nil
            cloudEntitlementState = .error("Cloud backend not configured")
            #endif
            return
        }

        cloudEntitlementState = .loading
        let client = CloudEntitlementClient(baseURL: baseURL)
        let customerId = UserDefaults.standard.string(forKey: Self.stripeCustomerIDKey)
        let appToken = UserDefaults.standard.string(forKey: Self.appAccountTokenKey)
        let checkoutSessionId = checkoutSessionIdFromBillingReturn()

        do {
            let entitlement = try await client.fetch(
                customerId: customerId,
                appAccountToken: appToken,
                checkoutSessionId: checkoutSessionId
            )
            cloudEntitlement = entitlement
            cloudEntitlementState = .loaded
            if let customerId = entitlement.customerId, !customerId.isEmpty {
                UserDefaults.standard.set(customerId, forKey: Self.stripeCustomerIDKey)
            }
            if let clientToken = entitlement.clientToken, !clientToken.isEmpty {
                UserDefaults.standard.set(clientToken, forKey: Self.clientTokenKey)
            }
        } catch {
            cloudEntitlementState = .error(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func checkoutSessionIdFromBillingReturn() -> String? {
        guard let urlString = UserDefaults.standard.string(forKey: "dev.conduit.lastBillingReturnURL"),
              let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == "checkoutSessionId" })?.value
            ?? components.queryItems?.first(where: { $0.name == "session_id" })?.value
    }

    private func refreshPurchaseState() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                purchaseState = .purchased
                return
            }
        }
        purchaseState = .notPurchased
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshPurchaseState()
                }
            }
        }
    }
}
#endif
