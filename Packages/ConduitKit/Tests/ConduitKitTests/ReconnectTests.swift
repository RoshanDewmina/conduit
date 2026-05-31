import Testing
import Foundation
@testable import SSHTransport
@testable import ConduitCore

// MARK: - B4: Reconnect coverage

// MARK: - Backoff schedule

@Suite("ReconnectController — backoff schedule")
struct BackoffScheduleTests {

    @Test("first attempt is 250 ms ± 20%")
    func firstAttempt() {
        let d = ReconnectController.backoff(attempt: 0)
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        #expect(ms >= 200 && ms <= 300, "attempt 0 should be ~250 ms, got \(ms) ms")
    }

    @Test("attempt 1 is 500 ms ± 20%")
    func secondAttempt() {
        let d = ReconnectController.backoff(attempt: 1)
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        #expect(ms >= 400 && ms <= 600, "attempt 1 should be ~500 ms, got \(ms) ms")
    }

    @Test("attempt 5+ caps at 10 s ± 20%")
    func capAtTen() {
        for attempt in 5...8 {
            let d = ReconnectController.backoff(attempt: attempt)
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            #expect(ms >= 8000 && ms <= 12000,
                    "attempt \(attempt) should be ~10 s, got \(ms) ms")
        }
    }

    @Test("backoff is always positive (jitter never produces zero)")
    func alwaysPositive() {
        for i in 0..<20 {
            let d = ReconnectController.backoff(attempt: i)
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            #expect(ms > 0, "backoff for attempt \(i) must be positive")
        }
    }
}

// MARK: - Error mapping: authentication pass-through

@Suite("SSHSession — auth-failure credential clear")
struct AuthCredentialTests {

    @Test("map(error:) returns .authFailed for ConduitError.authFailed pass-through")
    func authFailedPassthrough() {
        let err = ConduitError.authFailed(reason: "bad password")
        let mapped = SSHSession.map(error: err, host: "h")
        if case .authFailed(let reason) = mapped {
            #expect(reason == "bad password")
        } else {
            Issue.record("Expected .authFailed passthrough, got \(mapped)")
        }
    }

    @Test("map(error:) returns .timeout for ConduitError.timeout pass-through")
    func timeoutPassthrough() {
        let mapped = SSHSession.map(error: ConduitError.timeout, host: "h")
        #expect(mapped == .timeout)
    }
}

// MARK: - AutoReconnectEngine — trigger and retry

@Suite("AutoReconnectEngine — trigger and retry")
struct ReconnectRetryTests {

    @Test("trigger() fires onReconnect once")
    func singleShotTrigger() async throws {
        let callCount = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test",
            onReconnect: { await callCount.increment() },
            onFailed: { _ in }
        )

        await engine.trigger()
        await engine.reportReconnectOutcome(succeeded: true)

        let count = await callCount.value
        #expect(count == 1, "trigger() fires onReconnect exactly once")
    }

    @Test("triggerWithRetry stops when reportReconnectOutcome(succeeded:true) is called")
    func triggerWithRetryStopsOnSuccess() async throws {
        let callCount = ActorCounter()
        let failedCalled = ActorCounter()
        let controller = ReconnectController()

        // Use a shared state: after 2 calls report success.
        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test",
            onReconnect: { await callCount.increment() },
            onFailed: { _ in await failedCalled.increment() }
        )

        // Run triggerWithRetry in background; drive outcomes externally.
        let task = Task { await engine.triggerWithRetry() }
        // First attempt: fail
        try? await Task.sleep(for: .milliseconds(20))
        await engine.reportReconnectOutcome(succeeded: false)
        // Second attempt: succeed — loop should exit
        try? await Task.sleep(for: .milliseconds(20))
        await engine.reportReconnectOutcome(succeeded: true)
        await task.value

        let count = await callCount.value
        // At least 1 call (we can't guarantee exactly 2 due to scheduling), but
        // the loop must stop and onFailed must not have fired.
        #expect(count >= 1)
        let failed = await failedCalled.value
        #expect(failed == 0, "onFailed must not fire when reconnect eventually succeeds")
    }

    @Test("failure counter resets on success — subsequent failures stay below maxAttempts")
    func counterResetsOnSuccess() async throws {
        let failedCalled = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test",
            onReconnect: { },
            onFailed: { _ in await failedCalled.increment() }
        )

        for _ in 0..<4 { await engine.reportReconnectOutcome(succeeded: false) }
        await engine.reportReconnectOutcome(succeeded: true)        // reset
        for _ in 0..<4 { await engine.reportReconnectOutcome(succeeded: false) }

        let failed = await failedCalled.value
        #expect(failed == 0, "4+4 failures straddling a success should not reach maxAttempts=5")
    }

    @Test("onFailed fires exactly once after maxAttempts consecutive failures")
    func onFailedAfterMaxAttempts() async throws {
        let failedCalled = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "dead-host",
            onReconnect: { },
            onFailed: { _ in await failedCalled.increment() }
        )

        for _ in 0..<AutoReconnectEngine.maxAttempts {
            await engine.reportReconnectOutcome(succeeded: false)
        }

        let count = await failedCalled.value
        #expect(count == 1, "onFailed fires exactly once after maxAttempts failures")
    }

    @Test("stop() halts the engine before any reconnect fires")
    func stopPreventsReconnect() async throws {
        let callCount = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test",
            onReconnect: { await callCount.increment() },
            onFailed: { _ in }
        )

        await engine.start()
        await engine.stop()
        await engine.trigger()

        let count = await callCount.value
        #expect(count == 0, "onReconnect must not fire after stop()")
    }
}

// MARK: - Helpers

private actor ActorCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
