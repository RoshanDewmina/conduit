import Foundation

public enum AttentionKind: Sendable {
    case approval(Approval)
    case blockedRun(hostID: HostID, hostName: String, runID: String, title: String)
    case offlineMachine(hostID: HostID, hostName: String)
}

public struct AttentionItem: Identifiable, Sendable {
    public let id: String
    public let kind: AttentionKind
    public let severity: Approval.Risk
    public let createdAt: Date
    public let isExpired: Bool

    public init(approval: Approval) {
        id = approval.id.uuidString
        kind = .approval(approval)
        severity = approval.risk
        createdAt = approval.createdAt
        isExpired = (approval.decision == .expired)
    }

    public init(blockedRunOn hostID: HostID, hostName: String, runID: String, title: String) {
        id = "run-\(runID)"
        kind = .blockedRun(hostID: hostID, hostName: hostName, runID: runID, title: title)
        severity = .medium
        createdAt = .now
        isExpired = false
    }

    public init(offlineHost hostID: HostID, hostName: String) {
        id = "offline-\(hostID)"
        kind = .offlineMachine(hostID: hostID, hostName: hostName)
        severity = .low
        createdAt = .now
        isExpired = false
    }
}
