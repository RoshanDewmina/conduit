public enum BillingEligibility {
    /// RevenueCat entitlement identifier — must match the RevenueCat dashboard.
    public static let proEntitlementID = "pro"

    /// App Store / StoreKit product identifier for the one-time Pro unlock.
    public static let proProductID = "dev.lancer.mobile.pro"

    /// Free tier allows this many paired hosts before Pro is required.
    public static let freeHostLimit = 2

    public static func isExternalStripeEligible(storefrontCountryCode: String?) -> Bool {
        guard let code = storefrontCountryCode?.uppercased() else { return false }
        return code == "US" || code == "USA"
    }

    /// Whether the RevenueCat `pro` entitlement is active for this user.
    public static func isProEntitlementActive(_ isActive: Bool) -> Bool {
        isActive
    }

    /// Returns true when pairing another host should show the paywall.
    public static func requiresPaywallForAdditionalHost(existingHostCount: Int, isPro: Bool) -> Bool {
        !isPro && existingHostCount >= freeHostLimit
    }

    /// Returns true when a Pro-only feature was tapped without an active entitlement.
    public static func requiresPaywallForProFeature(isPro: Bool) -> Bool {
        !isPro
    }
}
