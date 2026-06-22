import Foundation

// MARK: - Transfer types

/// Lightweight Codable snapshot of an `Approval`, used as the WatchConnectivity wire type.
public struct WatchApprovalTransfer: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let sessionID: String
    public let agent: String
    public let kind: String
    public let command: String?
    public let cwd: String
    public let risk: Int
    public let createdAt: TimeInterval

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

/// Session connection status pushed from iPhone to Watch.
public struct WatchSessionStatus: Codable, Sendable {
    public let hostName: String
    public let hostname: String
    public let isConnected: Bool
    public let agentActive: Bool
    public let pendingCount: Int
    public let connectedAt: TimeInterval?

    public init(
        hostName: String, hostname: String, isConnected: Bool,
        agentActive: Bool, pendingCount: Int, connectedAt: TimeInterval?
    ) {
        self.hostName = hostName; self.hostname = hostname
        self.isConnected = isConnected; self.agentActive = agentActive
        self.pendingCount = pendingCount; self.connectedAt = connectedAt
    }
}

/// A completed (or in-progress) terminal block, pushed from iPhone to Watch.
public struct WatchActivityBlock: Codable, Identifiable, Sendable {
    public let id: String
    public let command: String
    public let outputPreview: String   // truncated stdout
    public let exitCode: Int?          // nil = still running
    public let isSuccess: Bool?
    public let startedAt: TimeInterval
    public let duration: TimeInterval? // nil = still running

    public init(
        id: String, command: String, outputPreview: String,
        exitCode: Int?, isSuccess: Bool?, startedAt: TimeInterval, duration: TimeInterval?
    ) {
        self.id = id; self.command = command; self.outputPreview = outputPreview
        self.exitCode = exitCode; self.isSuccess = isSuccess
        self.startedAt = startedAt; self.duration = duration
    }
}

/// A snippet entry pushed from iPhone to Watch for quick remote execution.
public struct WatchSnippet: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let body: String

    public init(id: String, name: String, body: String) {
        self.id = id; self.name = name; self.body = body
    }
}

// MARK: - Wire protocol

/// All message types over WatchConnectivity. Both sides use this to encode/decode.
public enum WatchSyncMessage: Sendable {
    // iPhone → Watch
    case approvalSync([WatchApprovalTransfer])
    case sessionSync(WatchSessionStatus)
    case activitySync([WatchActivityBlock])
    case snippetSync([WatchSnippet])

    // Watch → iPhone
    case decision(approvalID: String, result: String)   // "approved" | "rejected"
    case emergencyStop
    case runSnippet(body: String)

    public static func decode(_ dict: [String: Any]) -> WatchSyncMessage? {
        guard let type = dict["type"] as? String else { return nil }
        switch type {
        case "approvals.sync":
            guard let payload = dict["payload"] as? String,
                  let data = payload.data(using: .utf8),
                  let items = try? JSONDecoder().decode([WatchApprovalTransfer].self, from: data)
            else { return nil }
            return .approvalSync(items)

        case "session.sync":
            guard let payload = dict["payload"] as? String,
                  let data = payload.data(using: .utf8),
                  let status = try? JSONDecoder().decode(WatchSessionStatus.self, from: data)
            else { return nil }
            return .sessionSync(status)

        case "activity.sync":
            guard let payload = dict["payload"] as? String,
                  let data = payload.data(using: .utf8),
                  let blocks = try? JSONDecoder().decode([WatchActivityBlock].self, from: data)
            else { return nil }
            return .activitySync(blocks)

        case "snippet.sync":
            guard let payload = dict["payload"] as? String,
                  let data = payload.data(using: .utf8),
                  let snippets = try? JSONDecoder().decode([WatchSnippet].self, from: data)
            else { return nil }
            return .snippetSync(snippets)

        case "decision":
            guard let id = dict["id"] as? String, let result = dict["decision"] as? String
            else { return nil }
            return .decision(approvalID: id, result: result)

        case "emergency.stop":
            return .emergencyStop

        case "run.snippet":
            guard let body = dict["body"] as? String else { return nil }
            return .runSnippet(body: body)

        default:
            return nil
        }
    }

    public func encode() -> [String: Any] {
        switch self {
        case .approvalSync(let items):
            return jsonPayload("approvals.sync", items)
        case .sessionSync(let status):
            return jsonPayload("session.sync", status)
        case .activitySync(let blocks):
            return jsonPayload("activity.sync", blocks)
        case .snippetSync(let snippets):
            return jsonPayload("snippet.sync", snippets)
        case .decision(let id, let result):
            return ["type": "decision", "id": id, "decision": result]
        case .emergencyStop:
            return ["type": "emergency.stop"]
        case .runSnippet(let body):
            return ["type": "run.snippet", "body": body]
        }
    }

    private func jsonPayload<T: Encodable>(_ type: String, _ value: T) -> [String: Any] {
        let payload = (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return ["type": type, "payload": payload]
    }
}
