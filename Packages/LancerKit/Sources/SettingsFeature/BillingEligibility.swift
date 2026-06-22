public enum BillingEligibility {
    public static func isExternalStripeEligible(storefrontCountryCode: String?) -> Bool {
        guard let code = storefrontCountryCode?.uppercased() else { return false }
        return code == "US" || code == "USA"
    }
}
