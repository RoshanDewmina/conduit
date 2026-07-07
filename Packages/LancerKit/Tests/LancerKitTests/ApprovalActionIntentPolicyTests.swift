#if os(iOS)
import Testing
import AppIntents
import LancerCore
@testable import SessionFeature

@Suite("ApprovalActionIntentPolicy")
@available(iOS 17.0, *)
struct ApprovalActionIntentPolicyTests {

    @Test("reject never requires authentication")
    func rejectStaysUnauthenticated() {
        for risk in [Approval.Risk?.none, .some(.low), .some(.critical)] {
            #expect(!ApprovalActionIntentPolicy.requiresAuthentication(decision: .reject, risk: risk))
            #expect(
                ApprovalActionIntentPolicy.authenticationPolicy(decision: .reject, risk: risk)
                    == .alwaysAllowed
            )
        }
    }

    @Test("approve requires authentication for high/critical and unknown risk")
    func approveGatesElevatedAndUnknown() {
        #expect(ApprovalActionIntentPolicy.requiresAuthentication(decision: .approve, risk: nil))
        #expect(ApprovalActionIntentPolicy.requiresAuthentication(decision: .approve, risk: .high))
        #expect(ApprovalActionIntentPolicy.requiresAuthentication(decision: .approve, risk: .critical))
        #expect(
            ApprovalActionIntentPolicy.authenticationPolicy(decision: .approve, risk: .high)
                == .requiresAuthentication
        )
    }

    @Test("approve allows fast path for low/medium risk")
    func approvePassesLowMedium() {
        #expect(!ApprovalActionIntentPolicy.requiresAuthentication(decision: .approve, risk: .low))
        #expect(!ApprovalActionIntentPolicy.requiresAuthentication(decision: .approve, risk: .medium))
        #expect(
            ApprovalActionIntentPolicy.authenticationPolicy(decision: .approve, risk: .low)
                == .alwaysAllowed
        )
    }

    @Test("intent declares system authentication policy for lock-screen approve baseline")
    func intentStaticPolicyRequiresAuthentication() {
        #expect(ApprovalActionIntent.authenticationPolicy == .requiresAuthentication)
    }
}
#endif
