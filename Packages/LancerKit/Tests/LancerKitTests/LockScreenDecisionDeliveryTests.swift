import Testing
import Foundation
@testable import LancerCore
@testable import SecurityKit
@testable import PersistenceKit
@testable import SSHTransport
#if os(iOS)
@testable import SessionFeature

/// Thread-safe capture of the last decision POST body/URL sent through
/// `URLSession.shared`.
private final class DecisionPostCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _body: [String: Any]?
    var body: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _body }
    func set(_ b: [String: Any]?) { lock.lock(); _body = b; lock.unlock() }
}

private let capturedDecisionPost = DecisionPostCapture()

/// Intercepts `URLSession.shared`, records the decision POST body, and returns
/// 200 so `postDecisionToBackend` reports delivered without a real network call.
final class DecisionCapturingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let data = request.httpBodyStreamedData() ?? request.httpBody,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            capturedDecisionPost.set(obj)
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension URLRequest {
    /// `httpBody` is nil for requests routed through `URLProtocol` in some
    /// URLSession configurations; fall back to the stream if present.
    func httpBodyStreamedData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data.isEmpty ? nil : data
    }
}

/// Regression coverage for checkpoint 5c (2026-07-08 device proof): a lock-screen
/// Approve/Reject tapped while the app is force-quit must reach the backend
/// WITHOUT `AppRoot`'s SwiftUI view graph ever running. `LancerNotificationDelegate`
/// (app target, not unit-testable directly) now calls exactly the path exercised
/// here — `ApprovalRelay.enqueue` against a fresh `AppDatabase` with no local
/// approval row (the push-only, cold-launch case) — so this proves the engine-level
/// half of the fix: enqueue on a row-less approval still hydrates credentials and
/// posts the decision to the backend relay.
///
/// `.serialized`: like `ApprovalRelayColdLaunchTests`, this registers a global
/// `URLProtocol` and reads a module-level capture var around `URLSession.shared`
/// — shared mutable state that races against any other suite doing the same
/// thing concurrently (Swift Testing parallelizes across suites by default).
/// Serializing only fixes multiple tests within *this* suite; running this file
/// together with another suite that also swaps in a global `URLProtocol`
/// (e.g. `ApprovalRelayColdLaunchTests`) can still cross-contaminate when both
/// run in the same process at once — a pre-existing limitation of this test
/// pattern (see `LiveActivityContentStateTests.swift:151`'s identical caveat),
/// not something this fix introduced. Verified in isolation via
/// `-only-testing:LancerKitTests/LockScreenDecisionDeliveryTests`.
@Suite(.serialized) @MainActor struct LockScreenDecisionDeliveryTests {
    @Test("enqueue on a cold-launch, row-less approval still posts the decision to the backend")
    func enqueueWithoutLocalRowPostsDecision() async throws {
        URLProtocol.registerClass(DecisionCapturingURLProtocol.self)
        defer { URLProtocol.unregisterClass(DecisionCapturingURLProtocol.self) }
        capturedDecisionPost.set(nil)

        // Simulate credentials persisted by a prior warm session (configureBackend),
        // exactly as ApprovalRelay.persistCredentials already does in production.
        let kc = Keychain(service: "test.lockscreen.relayCreds", inMemory: true)
        try await kc.write(Data("https://relay.test".utf8), account: "backendURL")
        try await kc.write(Data("sess-cold".utf8), account: "sessionID")
        try await kc.write(Data("tok-cold".utf8), account: "relayToken")

        let relay = ApprovalRelay()   // fresh instance: no channel, no e2e bridge, no in-memory creds
        relay.credentialKeychain = kc

        // No local DB row for this approval — the force-quit/push-only case:
        // the phone never had a chance to persist the approval before the
        // decision arrived.
        let db = try AppDatabase.inMemory()
        let approvalID = UUID().uuidString

        await relay.enqueue(approvalID: approvalID, decision: .approved, db: db, hostID: "")

        let posted = capturedDecisionPost.body
        #expect(posted != nil, "a row-less cold-launch decision must still be forwarded to the backend relay")
        #expect(posted?["approvalId"] as? String == approvalID)
        #expect(posted?["decision"] as? String == DaemonChannel.decisionWireValue(for: .approved))
        #expect(posted?["sessionId"] as? String == "sess-cold")
        #expect(posted?["contentHash"] == nil, "without a local row or caller-supplied hash, contentHash is omitted")
    }

    @Test("enqueue with a caller-supplied contentHash (APNs userInfo) posts that hash even with no local row")
    func enqueueWithCallerContentHashPostsHash() async throws {
        URLProtocol.registerClass(DecisionCapturingURLProtocol.self)
        defer { URLProtocol.unregisterClass(DecisionCapturingURLProtocol.self) }
        capturedDecisionPost.set(nil)

        let kc = Keychain(service: "test.lockscreen.relayCreds.hash", inMemory: true)
        try await kc.write(Data("https://relay.test".utf8), account: "backendURL")
        try await kc.write(Data("sess-cold".utf8), account: "sessionID")
        try await kc.write(Data("tok-cold".utf8), account: "relayToken")

        let relay = ApprovalRelay()
        relay.credentialKeychain = kc

        let db = try AppDatabase.inMemory()
        let approvalID = UUID().uuidString
        let hash = "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"

        await relay.enqueue(
            approvalID: approvalID,
            decision: .rejected,
            db: db,
            hostID: "",
            contentHash: hash
        )

        let posted = capturedDecisionPost.body
        #expect(posted != nil, "a row-less cold-launch decision with APNs contentHash must still be forwarded")
        #expect(posted?["approvalId"] as? String == approvalID)
        #expect(posted?["decision"] as? String == DaemonChannel.decisionWireValue(for: .rejected))
        #expect(posted?["contentHash"] as? String == hash)
    }

    // NOTE: the "already-resolved local approval is a no-op" branch of `enqueue`
    // (approvalRepo.exists == true) calls `Notifications.shared.clearDeliveredApproval`,
    // which calls `UNUserNotificationCenter.current()`. That crashes this bare
    // `LancerKitTests` xctest bundle (`bundleProxyForCurrentProcess is nil` —
    // no host app bundle), independent of this fix, so it is not exercised here.
    // The row-less path above (the actual force-quit / checkpoint-5c scenario)
    // never reaches that branch.
}
#endif
