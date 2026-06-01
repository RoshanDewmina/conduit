#if os(iOS)
import Foundation
import StoreKit
import Observation

public enum PurchaseState: Sendable, Equatable {
    case unknown
    case notPurchased
    case purchased
    case purchasing
    case error(String)
}

/// StoreKit 2 manager for the Conduit one-time purchase.
/// Product ID matches the entry in App Store Connect.
@MainActor @Observable
public final class PurchaseManager {
    public static let shared = PurchaseManager()

    public static let proProductID = "dev.conduit.mobile.pro"

    public var purchaseState: PurchaseState = .unknown
    public var product: Product?
    public var storefrontCountryCode: String?
    public var externalStripeEligible: Bool {
        BillingEligibility.isExternalStripeEligible(storefrontCountryCode: storefrontCountryCode)
    }

    /// DEBUG ONLY — all Pro features are unlocked in debug builds so the
    /// paywall never blocks simulator/device testing. The `conduitDebugProBypass`
    /// flag is honoured as a kill-switch (set it to `false` in UserDefaults to
    /// re-engage the paywall during debug). Production builds (#if !DEBUG)
    /// always require a real purchase.
    public var isPro: Bool {
        #if DEBUG
        // Default: unlocked. Explicit `false` overrides back to paywall.
        if UserDefaults.standard.object(forKey: "conduitDebugProBypass") == nil { return true }
        if UserDefaults.standard.bool(forKey: "conduitDebugProBypass") { return true }
        #endif
        return purchaseState == .purchased
    }

#if DEBUG
    /// Toggle the debug pro-bypass flag from the Settings UI.
    public var debugProBypass: Bool {
        get { UserDefaults.standard.bool(forKey: "conduitDebugProBypass") }
        set { UserDefaults.standard.set(newValue, forKey: "conduitDebugProBypass") }
    }
#endif

    @ObservationIgnored nonisolated(unsafe) private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
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

    // MARK: - Private

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
