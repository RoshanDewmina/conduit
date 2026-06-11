import Foundation

/// Prepaid / overage credit balance returned by the hosted-agent control plane.
public struct CreditBalance: Codable, Sendable, Equatable {
    public let customerId: String?
    public var prepaidUSD: Double
    public var overageUSD: Double
    public var allowOverage: Bool
    public var updatedAt: String?

    public init(
        customerId: String? = nil,
        prepaidUSD: Double = 0,
        overageUSD: Double = 0,
        allowOverage: Bool = true,
        updatedAt: String? = nil
    ) {
        self.customerId = customerId
        self.prepaidUSD = prepaidUSD
        self.overageUSD = overageUSD
        self.allowOverage = allowOverage
        self.updatedAt = updatedAt
    }

    public var creditsRemainingLabel: String {
        String(format: "$%.2f", max(0, prepaidUSD))
    }
}
