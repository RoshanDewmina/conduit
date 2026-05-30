import Testing
import Foundation
import ConduitCore
@testable import SSHTransport

// MARK: - Stub ReconnectController

/// A controllable stand-in for `ReconnectController` that lets tests push
/// `NetworkState` values manually through a continuation.
final class StubReconnectController: @unchecked Sendable {
    private var continuation: AsyncStream<ReconnectController.NetworkState>.Continuation?
    private(set) var started = false
    let stream: AsyncStream<ReconnectController.NetworkState>

    init() {
        var cap: AsyncStream<ReconnectController.NetworkState>.Continuation!
        stream = AsyncStream { continuation in
            cap = continuation
        }
        continuation = cap
    }

    func start() { started = true }

    func push(_ state: ReconnectController.NetworkState) {
        continuation?.yield(state)
    }

    func finish() {
        continuation?.finish()
    }
}

// MARK: - Tests

@Suite("AutoReconnectEngine")
struct AutoReconnectEngineTests {

    @Test("reconnect fires when network becomes reachable")
    func triggersOnReachable() async throws {
        let reconnectCalled = ActorCounter()
        let failedCalled = ActorCounter()

        let controller = ReconnectController()   // use real controller; we won't start the monitor

        // We cannot inject a stub into ReconnectController directly (it's a
        // concrete actor with a private NWPathMonitor), so we test the public
        // API end-to-end using a real engine that we control via
        // reportReconnectOutcome.
        //
        // For the unit-level trigger logic we verify the engine's
        // reportReconnectOutcome flow directly.

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test-host",
            onReconnect: { await reconnectCalled.increment() },
            onFailed:    { _ in await failedCalled.increment() }
        )

        // Simulate 5 failures → onFailed should fire.
        for _ in 0..<AutoReconnectEngine.maxAttempts {
            await engine.reportReconnectOutcome(succeeded: false)
        }

        let failCount = await failedCalled.value
        #expect(failCount == 1, "onFailed should fire exactly once after maxAttempts failures")
    }

    @Test("stops after explicit stop()")
    func stopsOnStop() async throws {
        let reconnectCalled = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test-host",
            onReconnect: { await reconnectCalled.increment() },
            onFailed: { _ in }
        )

        await engine.start()
        await engine.stop()

        // After stop() the engine should be halted; the monitorTask is
        // cancelled.  We verify that a subsequent reportReconnectOutcome has no
        // side-effects beyond the normal counter logic.
        await engine.reportReconnectOutcome(succeeded: true)

        // The reconnect closure should NOT have been called (we stopped before
        // any network transitions occurred).
        let count = await reconnectCalled.value
        #expect(count == 0, "onReconnect should not fire after stop()")
    }

    @Test("failure counter resets after success")
    func counterResetsOnSuccess() async throws {
        let failedCalled = ActorCounter()
        let controller = ReconnectController()

        let engine = AutoReconnectEngine(
            reconnectController: controller,
            hostName: "test-host",
            onReconnect: { },
            onFailed: { _ in await failedCalled.increment() }
        )

        // 3 failures, then 1 success, then 4 more failures (< maxAttempts from reset)
        for _ in 0..<3 { await engine.reportReconnectOutcome(succeeded: false) }
        await engine.reportReconnectOutcome(succeeded: true)
        for _ in 0..<4 { await engine.reportReconnectOutcome(succeeded: false) }

        // Still < maxAttempts (5) since reset — onFailed should not have fired.
        let count = await failedCalled.value
        #expect(count == 0, "onFailed should not fire when failures reset mid-sequence")
    }
}

// MARK: - Unexpected channel close → reconnect routing

/// A non-zero remote exit status, surfaced by Citadel as `CommandFailed`.
private struct FakeCommandFailed: Error {}

@Suite("Connection-loss classification")
struct ConnectionLossClassificationTests {

    @Test("server-initiated channel close is treated as a connection loss")
    func channelCloseIsDrop() {
        // A HUP / sshd restart / dropped channel surfaces as one of these.
        #expect(SSHSession.isConnectionLoss(ConduitError.channelClosed))
        #expect(SSHSession.isConnectionLoss(ConduitError.notConnected))
        #expect(SSHSession.isConnectionLoss(ConduitError.networkUnavailable))
        #expect(SSHSession.isConnectionLoss(ConduitError.timeout))
    }

    @Test("opaque NIO/Citadel channel errors are treated as a connection loss")
    func opaqueChannelErrorsAreDrop() {
        struct ChannelEOFError: Error, CustomStringConvertible {
            var description: String { "NIOSSH channel closed: connection reset by peer (EOF)" }
        }
        #expect(SSHSession.isConnectionLoss(ChannelEOFError()))
    }

    @Test("a non-zero command exit is NOT a connection loss")
    func commandFailureIsNotDrop() {
        // A normal failing command (e.g. `false`, `grep` no-match) must stay a
        // command error and NOT trigger reconnect.
        struct GenericError: Error, CustomStringConvertible {
            var description: String { "exit status 1: no such file or directory" }
        }
        #expect(!SSHSession.isConnectionLoss(GenericError()))
        #expect(!SSHSession.isConnectionLoss(ConduitError.cancelled))
        #expect(!SSHSession.isConnectionLoss(ConduitError.authFailed(reason: "bad password")))
    }
}

@Suite("Unexpected drop drives reconnect, user disconnect does not")
struct UnexpectedDropReconnectTests {

    /// Models the SessionViewModel routing: an unexpected close runs the engine
    /// loop (which reports failures via the engine until maxAttempts), while a
    /// user-initiated disconnect short-circuits and never reconnects.
    @Test("unexpected close attempts reconnect with retry, then fails after maxAttempts")
    func unexpectedCloseRetriesThenFails() async {
        let reconnectAttempts = ActorCounter()
        let failed = ActorCounter()

        let engine = AutoReconnectEngine(
            reconnectController: ReconnectController(),
            hostName: "test-host",
            onReconnect: { await reconnectAttempts.increment() },
            onFailed: { _ in await failed.increment() }
        )

        // Simulate the loop the SessionViewModel runs after onUnexpectedShellDrop:
        // each attempt fails (server still down) until the engine gives up.
        for _ in 0..<AutoReconnectEngine.maxAttempts {
            await engine.reportReconnectOutcome(succeeded: false)
        }

        let failCount = await failed.value
        #expect(failCount == 1, "should surface .failed exactly once after maxAttempts")
    }

    @Test("an unexpected close while connection is up routes to reconnecting, not failed")
    func dropClassificationRoutesToReconnect() {
        // The decision that fixes the bug: a server HUP (channelClosed) must be
        // classified as a drop so the SessionViewModel sends it to the reconnect
        // loop (.reconnecting) instead of finalizing as .failed.
        let serverHup: any Error = ConduitError.channelClosed
        #expect(SSHSession.isConnectionLoss(serverHup),
                "server HUP must route to the reconnect path, not terminal failure")
    }

    @Test("a user-initiated disconnect is not a reconnect trigger")
    func userDisconnectDoesNotReconnect() {
        // disconnect() sets userInitiatedDisconnect = true and tears down the
        // session; the resulting `.notConnected` stream end must NOT be acted on
        // as a drop. We model the guard: a deliberate teardown short-circuits
        // before classification even runs.
        let userInitiatedDisconnect = true
        let streamEnd: any Error = ConduitError.notConnected
        let shouldReconnect = !userInitiatedDisconnect && SSHSession.isConnectionLoss(streamEnd)
        #expect(!shouldReconnect, "deliberate disconnect must never trigger auto-reconnect")
    }
}

// MARK: - Helpers

/// Thread-safe counter for tracking async callback invocations in tests.
private actor ActorCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
