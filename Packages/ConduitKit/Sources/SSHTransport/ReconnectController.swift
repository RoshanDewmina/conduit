import Foundation
import Network
import ConduitCore

/// Watches `NWPathMonitor` and tells observers when reachability changes,
/// emitting a stream of `NetworkState` values the SessionViewModel can act
/// on. This is intentionally tiny — actual SSH reconnect orchestration
/// happens in feature-layer view models that own credentials and UX.
public actor ReconnectController {
    public enum NetworkState: Sendable, Equatable {
        case unknown
        case unreachable
        case reachableWifi
        case reachableCellular
        case reachableOther
    }

    public static let shared = ReconnectController()

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "dev.conduit.reconnect.monitor")
    private(set) public var state: NetworkState = .unknown

    private var continuations: [UUID: AsyncStream<NetworkState>.Continuation] = [:]
    private var started = false

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.update(path: path) }
        }
        monitor.start(queue: queue)
    }

    private func update(path: NWPath) {
        let newState: NetworkState
        if path.status != .satisfied {
            newState = .unreachable
        } else if path.usesInterfaceType(.wifi) {
            newState = .reachableWifi
        } else if path.usesInterfaceType(.cellular) {
            newState = .reachableCellular
        } else {
            newState = .reachableOther
        }
        guard newState != state else { return }
        state = newState
        for cont in continuations.values { cont.yield(newState) }
    }

    public func states() -> AsyncStream<NetworkState> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id: id) }
            }
            continuation.yield(state)
        }
    }

    private func remove(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Exponential backoff schedule used by reconnect loops.
    /// 250 ms, 500 ms, 1 s, 2 s, 5 s, 10 s, 10 s... capped, with ±20% jitter.
    public static func backoff(attempt: Int) -> Duration {
        let baseMs: Double = switch attempt {
        case 0: 250
        case 1: 500
        case 2: 1_000
        case 3: 2_000
        case 4: 5_000
        default: 10_000
        }
        let jitter = Double.random(in: 0.8...1.2)
        let ms = baseMs * jitter
        return .milliseconds(Int(ms))
    }
}
