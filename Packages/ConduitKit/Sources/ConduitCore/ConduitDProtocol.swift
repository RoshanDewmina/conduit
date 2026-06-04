import Foundation

// Framing helper: 4-byte big-endian length prefix
public enum DaemonFraming {
    public static func frame(_ json: Data) -> Data {
        var out = Data(capacity: 4 + json.count)
        let len = UInt32(json.count)
        out.append(UInt8((len >> 24) & 0xFF))
        out.append(UInt8((len >> 16) & 0xFF))
        out.append(UInt8((len >> 8) & 0xFF))
        out.append(UInt8(len & 0xFF))
        out.append(json)
        return out
    }

    public static func unframe(_ data: Data) -> (Data, Data)? {
        guard data.count >= 4 else { return nil }
        let b = data
        let len = (UInt32(b[b.startIndex]) << 24)
                | (UInt32(b[b.startIndex+1]) << 16)
                | (UInt32(b[b.startIndex+2]) << 8)
                | UInt32(b[b.startIndex+3])
        let needed = 4 + Int(len)
        guard data.count >= needed else { return nil }
        return (data.subdata(in: 4..<needed), data.subdata(in: needed..<data.count))
    }
}

/// Blast-radius metadata from conduitd policy escalation (WS-B).
public struct ApprovalBlastRadius: Codable, Sendable, Hashable {
    public let files: [String]?
    public let touchesGit: Bool?
    public let touchesNetwork: Bool?
    public let matchedRule: String?

    public init(
        files: [String]? = nil,
        touchesGit: Bool? = nil,
        touchesNetwork: Bool? = nil,
        matchedRule: String? = nil
    ) {
        self.files = files
        self.touchesGit = touchesGit
        self.touchesNetwork = touchesNetwork
        self.matchedRule = matchedRule
    }
}

public struct ApprovalPendingParams: Codable, Sendable {
    public let id: String
    public let sessionId: String?
    public let agent: String
    public let kind: String
    public let command: String?
    public let patch: String?
    public let cwd: String
    public let risk: Int

    public let toolName: String?
    public let toolUseID: String?
    public let agentSessionID: String?
    public let toolInput: String?

    public let files: [String]?
    public let touchesGit: Bool?
    public let touchesNetwork: Bool?
    public let matchedRule: String?

    enum CodingKeys: String, CodingKey {
        case id, sessionId, agent, kind, command, patch, cwd, risk
        case toolName, toolUseID, toolInput
        case agentSessionID = "agentSessionID"
        case files, touchesGit, touchesNetwork, matchedRule
    }

    public var approvalRisk: Approval.Risk {
        Approval.Risk(rawValue: min(risk, 3)) ?? .high
    }
    public var approvalKind: Approval.Kind {
        Approval.Kind(rawValue: kind) ?? .command
    }
    public var approvalAgent: Approval.AgentSource {
        Approval.AgentSource(rawValue: agent) ?? .unknown
    }
    public var approvalToolName: String? { toolName }
    public var approvalToolUseID: String? { toolUseID }
    public var approvalAgentSessionID: String? { agentSessionID }
    public var approvalToolInput: String? { toolInput }
    public var blastRadius: ApprovalBlastRadius {
        ApprovalBlastRadius(
            files: files,
            touchesGit: touchesGit,
            touchesNetwork: touchesNetwork,
            matchedRule: matchedRule
        )
    }
}

public struct AuditLogEntry: Codable, Sendable, Identifiable, Hashable {
    public let timestamp: String
    public let action: String
    public let agent: String?
    public let kind: String?
    public let command: String?
    public let effect: String?
    public let rule: String?
    public let approvalId: String?

    public var id: String { "\(timestamp)-\(action)-\(approvalId ?? command ?? "")" }

    enum CodingKeys: String, CodingKey {
        case timestamp, action, agent, kind, command, effect, rule
        case approvalId
    }
}

public struct AuditTailResult: Codable, Sendable {
    public let entries: [AuditLogEntry]
}

/// Legacy single-YAML response (older conduitd); prefer PolicyGetResult.
public struct PolicyYAMLResult: Codable, Sendable {
    public let yaml: String
}

public struct PolicyGetResult: Codable, Sendable {
    public let documents: [PolicyDocument]?
    public let `default`: String?
}

public struct PolicyDocument: Codable, Sendable {
    public var `default`: String?
    public var rules: [PolicyRule]?
}

public struct PolicyRule: Codable, Sendable, Hashable {
    public var ruleID: String?
    public var effect: String
    public var agent: String?
    public var tool: String?
    public var kind: String?
    public var match: String?
    public var cwd: String?
    public var minRisk: String?
    public var maxRisk: String?

    enum CodingKeys: String, CodingKey {
        case ruleID = "id"
        case effect, agent, tool, kind, match, cwd, minRisk, maxRisk
    }
}

public enum DaemonEvent: Sendable {
    case approvalPending(ApprovalPendingParams)
    case agentStatus(AgentStatusSnapshot)
    case pong
    case unknown(method: String)
}

extension DaemonEvent {
    public static func decode(from data: Data) -> DaemonEvent? {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let method = dict["method"] as? String else { return nil }
        switch method {
        case "agent.approval.pending":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let pending = try? JSONDecoder().decode(ApprovalPendingParams.self, from: paramsData)
            else { return .unknown(method: method) }
            return .approvalPending(pending)
        case "agent.status":
            guard let params = dict["params"] as? [String: Any],
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let snapshot = try? JSONDecoder().decode(AgentStatusSnapshot.self, from: paramsData)
            else { return .unknown(method: method) }
            return .agentStatus(snapshot)
        case "pong":
            return .pong
        default:
            return .unknown(method: method)
        }
    }
}

public enum DaemonRPCResponse: Sendable {
    case agentStatus(AgentStatusSnapshot)
    case auditTail(AuditTailResult)
    case policyGet(PolicyGetResult)
    case policyYAML(PolicyYAMLResult)
    case pong
    case ok
    case error(code: Int, message: String)
    case unknown

    public static func decode(from data: Data) -> DaemonRPCResponse? {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let err = dict["error"] as? [String: Any], let message = err["message"] as? String {
            return .error(code: err["code"] as? Int ?? -1, message: message)
        }
        guard let result = dict["result"] else { return .unknown }
        if let s = result as? String {
            if s == "pong" { return .pong }
            if s == "ok" { return .ok }
        }
        guard JSONSerialization.isValidJSONObject(result),
              let rd = try? JSONSerialization.data(withJSONObject: result) else { return .unknown }
        let dec = JSONDecoder()
        if let snap = try? dec.decode(AgentStatusSnapshot.self, from: rd) { return .agentStatus(snap) }
        if let t = try? dec.decode(AuditTailResult.self, from: rd) { return .auditTail(t) }
        if let pol = try? dec.decode(PolicyGetResult.self, from: rd) { return .policyGet(pol) }
        if let yaml = try? dec.decode(PolicyYAMLResult.self, from: rd) { return .policyYAML(yaml) }
        return .unknown
    }
}
