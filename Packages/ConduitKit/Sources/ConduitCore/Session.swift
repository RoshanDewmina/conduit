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
