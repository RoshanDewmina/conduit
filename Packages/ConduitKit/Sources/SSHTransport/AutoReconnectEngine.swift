import Foundation
import ConduitCore

/// Watches network reachability via `ReconnectController` and fires a
/// reconnect callback whenever the network transitions from `.unreachable`
/// to a reachable state.  After `maxAttempts` consecutive failures it calls
/// `onFailed` (which typically posts a local notification) and stops.
///
/// Call `reportReconnectOutcome(succeeded:)` from your reconnect closure so
/// the engine can track consecutive failures and call `onFailed` when the
/// limit is reached.
public actor AutoReconnectEngine {

    // MARK: - Configuration

    /// Number of consecutive reconnect attempts before giving up.
    public static let maxAttempts = 5

    // MARK: - State

    private let reconnectController: ReconnectController
    private let hostName: String
    private let onReconnect: @Sendable () async -> Void
    private let onFailed: @Sendable (String) async -> Void  // receives hostName

    private var monitorTask: Task<Void, Never>?
    private var stopped = false
    private var failureCount = 0

    // MARK: - Init

    /// - Parameters:
    ///   - reconnectController: Shared network state monitor.
    ///   - hostName: Name of the host, forwarded to `onFailed`.
    ///   - onReconnect: Called each time a reconnect should be attempted. The
    ///     caller must call `reportReconnectOutcome(succeeded:)` afterwards.
    ///   - onFailed: Called once when `maxAttempts` consecutive failures occur.
    public init(
        reconnectController: ReconnectController = .shared,
        hostName: String = "remote host",
        onReconnect: @escaping @Sendable () async -> Void,
        onFailed: @escaping @Sendable (String) async -> Void
    ) {
        self.reconnectController = reconnectController
        self.hostName = hostName
        self.onReconnect = onReconnect
        self.onFailed = onFailed
    }

    // MARK: - Lifecycle

    /// Begin watching network state.  Safe to call multiple times; subsequent
    /// calls are no-ops if already running.
    public func start() async {
        guard monitorTask == nil, !stopped else { return }
        await reconnectController.start()

        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// Permanently stops the engine.  After `stop()` the engine cannot be
    /// restarted.
    public func stop() {
        stopped = true
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Call this after each reconnect attempt to inform the engine whether it
    /// succeeded.  On success the failure counter resets; on failure it
    /// increments.  When the count reaches `maxAttempts` the engine calls
    /// `onFailed` and stops.
    public func reportReconnectOutcome(succeeded: Bool) async {
        if succeeded {
            failureCount = 0
        } else {
            failureCount += 1
            if failureCount >= Self.maxAttempts {
                stop()
                let name = hostName
                let cb = onFailed
                await cb(name)
            }
        }
    }

    // MARK: - Private

    private func runLoop() async {
        let stream = await reconnectController.states()
        var wasUnreachable = false

        for await state in stream {
            guard !stopped else { break }

            switch state {
            case .unreachable:
                wasUnreachable = true

            case .reachableWifi, .reachableCellular, .reachableOther:
                guard wasUnreachable else { break }
                wasUnreachable = false
                await triggerReconnect()

            case .unknown:
                break
            }
        }
    }

    private func triggerReconnect() async {
        guard !stopped else { return }
        let backoff = ReconnectController.backoff(attempt: failureCount)
        if failureCount > 0 {
            try? await Task.sleep(for: backoff)
        }
        guard !stopped else { return }
        await onReconnect()
    }
}
