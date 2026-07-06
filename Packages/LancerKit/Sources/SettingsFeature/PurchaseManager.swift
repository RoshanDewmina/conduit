#if os(iOS)
import Foundation
import StoreKit
import Observation
import RevenueCat
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

/// RevenueCat-backed manager for the Lancer one-time Pro purchase.
/// Product ID matches `Lancer.storekit` / App Store Connect; entitlement ID
/// must match the RevenueCat dashboard (`BillingEligibility.proEntitlementID`).
@MainActor @Observable
public final class PurchaseManager: NSObject {
    public static let shared = PurchaseManager()

    public static let proProductID = BillingEligibility.proProductID
    public static let stripeCustomerIDKey = "dev.lancer.stripeCustomerId"
    public static let appAccountTokenKey = "dev.lancer.appAccountToken"
    public static let clientTokenKey = "dev.lancer.clientToken"

    // TODO(owner): replace with real RevenueCat API key from https://app.revenuecat.com
    private static let revenueCatAPIKey = "REVENUECAT_API_KEY_PLACEHOLDER"

    public var purchaseState: PurchaseState = .unknown
    /// Localized price for the Pro package when offerings load successfully.
    public var displayPrice: String?
    public var storefrontCountryCode: String?
    public var cloudEntitlement: CloudEntitlement?
    public var cloudEntitlementState: CloudEntitlementLoadState = .unknown

    public var externalStripeEligible: Bool {
        BillingEligibility.isExternalStripeEligible(storefrontCountryCode: storefrontCountryCode)
    }

    /// Apple IAP one-time purchase — unlocks core Pro features.
    public var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANCER_FORCE_PRO"] == "1" { return true }
        if UserDefaults.standard.bool(forKey: "lancerDebugProBypass") { return true }
        #endif
        return purchaseState == .purchased
    }

    /// Stripe "Lancer Cloud" subscription — unlocks hosted agents + managed AI.
    public var hasCloudEntitlement: Bool {
        #if DEBUG
        let debugBypass = UserDefaults.standard.bool(forKey: "lancerDebugCloudEntitlement")
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
        get { UserDefaults.standard.bool(forKey: "lancerDebugProBypass") }
        set { UserDefaults.standard.set(newValue, forKey: "lancerDebugProBypass") }
    }

    public var debugCloudEntitlement: Bool {
        get { UserDefaults.standard.bool(forKey: "lancerDebugCloudEntitlement") }
        set { UserDefaults.standard.set(newValue, forKey: "lancerDebugCloudEntitlement") }
    }
#endif

    @ObservationIgnored private var proPackage: Package?
    @ObservationIgnored private static var isConfigured = false
    @ObservationIgnored private var cachedBackendURL: String?
    @ObservationIgnored private var accountAccessToken: String?

    private override init() {
        super.init()
    }

    public func configure(backendURL: String, accountAccessToken: String? = nil) {
        cachedBackendURL = backendURL
        self.accountAccessToken = accountAccessToken
    }

    public func load() async {
        ensureConfigured()
        storefrontCountryCode = await Storefront.current?.countryCode
        do {
            let offerings = try await Purchases.shared.offerings()
            proPackage = Self.resolveProPackage(from: offerings)
            displayPrice = proPackage?.storeProduct.localizedPriceString
            if proPackage == nil {
                #if DEBUG
                purchaseState = .error("Pro package not found. Check RevenueCat offerings and that Lancer.storekit is selected in the Run scheme.")
                #else
                purchaseState = .error("Couldn't load purchase options. Please check your connection and try again.")
                #endif
            }
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
        ensureConfigured()
        guard let proPackage else {
            #if DEBUG
            purchaseState = .error("Pro package not loaded")
            #else
            purchaseState = .error("Couldn't start the purchase. Please try again.")
            #endif
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await Purchases.shared.purchase(package: proPackage)
            if result.userCancelled {
                purchaseState = .notPurchased
            } else {
                applyCustomerInfo(result.customerInfo)
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    public func restore() async {
        ensureConfigured()
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(customerInfo)
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
                checkoutSessionId: checkoutSessionId,
                accessToken: accountAccessToken
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

    private func ensureConfigured() {
        guard !Self.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: Self.revenueCatAPIKey)
                .with(storeKitVersion: .storeKit2)
                .build()
        )
        Purchases.shared.delegate = self
        Self.isConfigured = true
    }

    private static func resolveProPackage(from offerings: Offerings) -> Package? {
        let allPackages = offerings.all.values.flatMap(\.availablePackages)
        if let match = allPackages.first(where: { $0.storeProduct.productIdentifier == proProductID }) {
            return match
        }
        return offerings.current?.lifetime
            ?? offerings.current?.availablePackages.first
    }

    private func checkoutSessionIdFromBillingReturn() -> String? {
        guard let urlString = UserDefaults.standard.string(forKey: "dev.lancer.lastBillingReturnURL"),
              let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == "checkoutSessionId" })?.value
            ?? components.queryItems?.first(where: { $0.name == "session_id" })?.value
    }

    private func applyCustomerInfo(_ customerInfo: CustomerInfo) {
        let isActive = BillingEligibility.isProEntitlementActive(
            customerInfo.entitlements[BillingEligibility.proEntitlementID]?.isActive == true
        )
        purchaseState = isActive ? .purchased : .notPurchased
    }

    private func refreshPurchaseState() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            applyCustomerInfo(customerInfo)
        } catch {
            if case .unknown = purchaseState {
                purchaseState = .notPurchased
            }
        }
    }
}

extension PurchaseManager: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.applyCustomerInfo(customerInfo)
        }
    }
}
#endif
