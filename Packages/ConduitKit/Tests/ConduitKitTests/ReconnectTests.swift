import Testing
import Foundation
@testable import SSHTransport

// MARK: - B4: Reconnect coverage

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
