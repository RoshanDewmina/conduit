import Foundation

public struct AuditEvent: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let hostID: HostID
    public let type: EventType
    public let metadata: [String: String]
    public let createdAt: Date

    public enum EventType: String, Sendable, Hashable, Codable {
        case connect
        case disconnect
        case authFailure
        case hostKeyChanged
        case approval
    }

    public init(
        id: UUID = UUID(),
        hostID: HostID,
        type: EventType,
        metadata: [String: String] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.hostID = hostID
        self.type = type
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
