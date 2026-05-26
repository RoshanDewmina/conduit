import Foundation

/// A port forward rule attached to a specific host.
public struct PortForward: Identifiable, Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable, CaseIterable {
        case local   // forward localhost:localPort → remoteHost:remotePort via SSH
        case remote  // forward remoteHost:remotePort → localhost:localPort via SSH
    }

    public var id: UUID
    public var hostID: HostID
    public var direction: Direction
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var label: String

    public init(
        id: UUID = UUID(),
        hostID: HostID,
        direction: Direction = .local,
        localPort: Int,
        remoteHost: String = "localhost",
        remotePort: Int,
        label: String = ""
    ) {
        self.id = id
        self.hostID = hostID
        self.direction = direction
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.label = label
    }

    public var displayTitle: String {
        label.isEmpty ? "\(direction == .local ? "L" : "R"):\(localPort) → \(remoteHost):\(remotePort)" : label
    }
}
