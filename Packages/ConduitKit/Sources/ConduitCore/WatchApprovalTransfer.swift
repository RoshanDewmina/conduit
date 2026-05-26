import Foundation

/// Lightweight Codable snapshot of an `Approval`, used as the WatchConnectivity wire type.
/// Sent iOS → Watch whenever pending approvals change; decoded on Watch to drive the inbox UI.
public struct WatchApprovalTransfer: Codable, Identifiable, Hashable, Sendable {
    public let id: String           // ApprovalID.uuidString
    public let sessionID: String    // SessionID.uuidString
    public let agent: String        // Approval.AgentSource.rawValue
    public let kind: String         // Approval.Kind.rawValue
    public let command: String?
    public let cwd: String
    public let risk: Int            // Approval.Risk.rawValue (0–3)
    public let createdAt: TimeInterval  // Date.timeIntervalSinceReferenceDate

    public init(
        id: String, sessionID: String, agent: String, kind: String,
        command: String?, cwd: String, risk: Int, createdAt: TimeInterval
    ) {
        self.id = id; self.sessionID = sessionID; self.agent = agent; self.kind = kind
        self.command = command; self.cwd = cwd; self.risk = risk; self.createdAt = createdAt
    }

    public init(approval: Approval) {
        self.init(
            id: approval.id.uuidString,
            sessionID: approval.sessionID.uuidString,
            agent: approval.agent.rawValue,
            kind: approval.kind.rawValue,
            command: approval.command,
            cwd: approval.cwd,
            risk: approval.risk.rawValue,
            createdAt: approval.createdAt.timeIntervalSinceReferenceDate
        )
    }

    public var riskLevel: Approval.Risk { Approval.Risk(rawValue: risk) ?? .low }
    public var agentSource: Approval.AgentSource { Approval.AgentSource(rawValue: agent) ?? .unknown }
    public var approvalKind: Approval.Kind { Approval.Kind(rawValue: kind) ?? .command }
    public var createdDate: Date { Date(timeIntervalSinceReferenceDate: createdAt) }
}

/// WatchConnectivity message envelope shared by both iOS and watchOS targets.
public enum WatchSyncMessage: Sendable {
    /// iPhone → Watch: full list of pending approvals
    case approvalSync([WatchApprovalTransfer])
    /// Watch → iPhone: user decision ("approved" | "rejected")
    case decision(approvalID: String, result: String)

    public static func decode(_ dict: [String: Any]) -> WatchSyncMessage? {
        guard let type = dict["type"] as? String else { return nil }
        switch type {
        case "approvals.sync":
            guard let payload = dict["payload"] as? String,
                  let data = payload.data(using: .utf8),
                  let items = try? JSONDecoder().decode([WatchApprovalTransfer].self, from: data)
            else { return nil }
            return .approvalSync(items)
        case "decision":
            guard let id = dict["id"] as? String, let result = dict["decision"] as? String
            else { return nil }
            return .decision(approvalID: id, result: result)
        default:
            return nil
        }
    }

    public func encode() -> [String: Any] {
        switch self {
        case .approvalSync(let items):
            let payload = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            return ["type": "approvals.sync", "payload": payload]
        case .decision(let id, let result):
            return ["type": "decision", "id": id, "decision": result]
        }
    }
}
