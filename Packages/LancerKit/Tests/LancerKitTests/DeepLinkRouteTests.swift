import Testing
import Foundation
@testable import LancerCore

@Suite("DeepLinkRoute")
struct DeepLinkRouteTests {

    struct ParseCase: Sendable {
        let name: String
        let urlString: String
        let expected: DeepLinkRoute?
    }

    private static let parseCases: [ParseCase] = [
        ParseCase(
            name: "auth callback with query",
            urlString: "lancer://auth/callback?token=x",
            expected: .authCallback(URL(string: "lancer://auth/callback?token=x")!)
        ),
        ParseCase(
            name: "auth root",
            urlString: "lancer://auth",
            expected: .authCallback(URL(string: "lancer://auth")!)
        ),
        ParseCase(
            name: "auth root slash",
            urlString: "lancer://auth/",
            expected: .authCallback(URL(string: "lancer://auth/")!)
        ),
        ParseCase(
            name: "auth smuggled path",
            urlString: "lancer://auth/evil",
            expected: nil
        ),
        ParseCase(
            name: "billing root",
            urlString: "lancer://billing",
            expected: .billing(returnURL: URL(string: "lancer://billing")!)
        ),
        ParseCase(
            name: "billing complete",
            urlString: "lancer://billing/complete?checkoutSessionId=cs_123",
            expected: .billing(returnURL: URL(string: "lancer://billing/complete?checkoutSessionId=cs_123")!)
        ),
        ParseCase(
            name: "billing smuggled path",
            urlString: "lancer://billing/evil",
            expected: nil
        ),
        ParseCase(
            name: "wrong scheme",
            urlString: "https://auth/callback",
            expected: nil
        ),
        ParseCase(
            name: "unknown host",
            urlString: "lancer://unknown",
            expected: nil
        ),
    ]

    @Test("parse routes known deep links and rejects everything else", arguments: parseCases)
    func parse(case parseCase: ParseCase) {
        let url = URL(string: parseCase.urlString)!
        let route = DeepLinkRoute.parse(url)
        #expect(route == parseCase.expected, "case: \(parseCase.name)")
    }
}
