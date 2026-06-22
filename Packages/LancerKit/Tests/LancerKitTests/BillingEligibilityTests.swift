import Testing
@testable import SettingsFeature

@Suite("Billing eligibility")
struct BillingEligibilityTests {
    @Test("US storefront codes are eligible for external Stripe CTA")
    func usStorefrontEligible() {
        #expect(BillingEligibility.isExternalStripeEligible(storefrontCountryCode: "US"))
        #expect(BillingEligibility.isExternalStripeEligible(storefrontCountryCode: "USA"))
    }

    @Test("non-US and unknown storefronts hide external Stripe CTA")
    func nonUSStorefrontUnavailable() {
        #expect(!BillingEligibility.isExternalStripeEligible(storefrontCountryCode: "MYS"))
        #expect(!BillingEligibility.isExternalStripeEligible(storefrontCountryCode: "CA"))
        #expect(!BillingEligibility.isExternalStripeEligible(storefrontCountryCode: nil))
    }
}
