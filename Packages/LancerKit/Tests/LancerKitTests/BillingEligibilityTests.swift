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

    @Test("Pro entitlement active when RevenueCat reports active")
    func proEntitlementActive() {
        #expect(BillingEligibility.isProEntitlementActive(true))
        #expect(!BillingEligibility.isProEntitlementActive(false))
    }

    @Test("free tier allows two hosts before paywall")
    func hostPaywallThreshold() {
        #expect(!BillingEligibility.requiresPaywallForAdditionalHost(existingHostCount: 1, isPro: false))
        #expect(BillingEligibility.requiresPaywallForAdditionalHost(existingHostCount: 2, isPro: false))
        #expect(!BillingEligibility.requiresPaywallForAdditionalHost(existingHostCount: 2, isPro: true))
        #expect(!BillingEligibility.requiresPaywallForProFeature(isPro: true))
        #expect(BillingEligibility.requiresPaywallForProFeature(isPro: false))
    }
}
