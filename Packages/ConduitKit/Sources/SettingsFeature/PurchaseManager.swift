#if os(iOS)
import Foundation
import StoreKit
import Observation

public enum PurchaseState: Sendable {
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

    @ObservationIgnored nonisolated(unsafe) private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
    }

    public func load() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
            await refreshPurchaseState()
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    public func purchase() async {
        guard let product else {
            purchaseState = .error("Product not loaded")
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
