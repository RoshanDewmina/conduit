import Foundation

public struct Session: Identifiable, Sendable, Hashable {
    public let id: SessionID
    public var hostID: HostID
    public var tmuxName: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: Status

    public enum Status: Sendable, Hashable, Codable {
        case disconnected
        case connecting
        case connected
        case suspended       // network gone; tmux still alive remotely
        case reconnecting(attempt: Int)
        case failed(reason: String)
    }

    public enum RelayState: String, Sendable, Codable {
        case none
        case connecting
        case paired
        case degraded
        case error
    }

    /// The single, honest connection state surfaced consistently across the top
    /// status bar and the Fleet header. It unifies the authoritative SSH session
    /// `Status` with the relay pairing `RelayState` so the two never disagree:
    /// the app must never claim "connected" until an SSH session or relay pairing
    /// is actually established (not merely attempting). Both `PersistentStatusBar`
    /// and `DSStatusHeader` derive their label from one value of this type.
    public enum ConnectionState: String, Sendable, Codable, Hashable {
        case offline       // nothing live — no session, no pairing
        case connecting    // SSH dialing OR relay handshaking — NOT yet usable
        case relayPaired   // E2E relay paired (no direct SSH, but a live path exists)
        case connected     // SSH session established (the bridge is truly up)
        case failed        // last attempt failed / unreachable

        /// True only when a usable path to the host is actually established.
        /// Used everywhere a "bridge connected" affordance is gated.
        public var isLive: Bool {
            self == .connected || self == .relayPaired
        }

        /// Derive the one honest state from the authoritative SSH session status
        /// and the relay pairing state. SSH-connected always wins; otherwise an
        /// established relay pairing counts as live; a failure is failure; an
        /// in-flight attempt (SSH connecting/reconnecting or relay connecting)
        /// reads as `.connecting`; everything else is `.offline`.
        public static func derive(session: Status, relay: RelayState) -> ConnectionState {
            switch session {
            case .connected:
                return .connected
            case .failed:
                // A failed SSH attempt may still have a live relay path.
                return relay == .paired ? .relayPaired : .failed
            case .connecting, .reconnecting:
                return .connecting
            case .suspended, .disconnected:
                switch relay {
                case .paired:               return .relayPaired
                case .connecting:           return .connecting
                case .error:                return .failed
                case .degraded:             return .connected
                case .none:                 return .offline
                }
            }
        }
    }

    public init(
        id: SessionID = .init(),
        hostID: HostID,
        tmuxName: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        status: Status = .disconnected
    ) {
        self.id = id
        self.hostID = hostID
        self.tmuxName = tmuxName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }
}
