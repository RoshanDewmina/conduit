import Testing
import Foundation
@testable import LancerCore
@testable import SecurityKit
#if os(iOS)
@testable import SessionFeature

/// Thread-safe capture of the last `Authorization` header `URLSession.shared` sent.
private final class AuthHeaderCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ v: String?) { lock.lock(); _value = v; lock.unlock() }
}

private let capturedAuth = AuthHeaderCapture()

/// Intercepts `URLSession.shared`, records the request's Authorization header, and
/// returns 200 so the backend POST path completes without a network.
final class CapturingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        capturedAuth.set(request.value(forHTTPHeaderField: "Authorization"))
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// SEC-2 regression: on a cold launch the relay must hydrate its per-session
/// `relayToken` from the Keychain *before* `postDecisionToBackend` reads it. The
/// old fire-and-forget hydration left the token empty at the `guard` that runs
/// before the URLSession suspension, so the POST never fired with auth.
@Suite @MainActor struct ApprovalRelayColdLaunchTests {
    @Test("cold-launch forward hydrates relayToken before the backend POST")
    func hydratesBeforePost() async throws {
        URLProtocol.registerClass(CapturingURLProtocol.self)
        defer { URLProtocol.unregisterClass(CapturingURLProtocol.self) }
        capturedAuth.set(nil)

        // Simulate a prior session that persisted relay credentials to the
        // Keychain, then a cold launch where the in-memory vars start empty.
        let kc = Keychain(service: "test.relayCreds", inMemory: true)
        try await kc.write(Data("https://relay.test".utf8), account: "backendURL")
        try await kc.write(Data("sess-1".utf8), account: "sessionID")
        try await kc.write(Data("tok-abc".utf8), account: "relayToken")

        let relay = ApprovalRelay()   // fresh instance: no channel, no e2e bridge
        relay.credentialKeychain = kc

        await relay.forwardDecisionOnly(approvalID: "appr-1", decision: .approved, editedToolInput: nil)

        #expect(capturedAuth.value == "Bearer tok-abc",
                "cold-launch POST must carry the hydrated token; nil/empty means the hydration race regressed")
    }
}
#endif
