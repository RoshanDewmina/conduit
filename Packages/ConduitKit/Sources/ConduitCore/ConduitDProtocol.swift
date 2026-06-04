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

    // Returns (message, remainder) or nil if not enough bytes
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

// Typed params for agent.approval.pending events from conduitd
public struct ApprovalPendingParams: Codable, Sendable {
    public let id: String        // UUID string for this approval
    public let sessionId: String?
    public let agent: String     // matches Approval.AgentSource raw values
    public let kind: String      // matches Approval.Kind raw values
    public let command: String?
    public let patch: String?
    public let cwd: String
    public let risk: Int         // 0=low 1=medium 2=high 3=critical

    // Structured tool-use fields — nil when sent by older conduitd (backwards compat)
    public let toolName: String?
    public let toolUseID: String?
    public let agentSessionID: String?  // Claude Code / Codex session ID (distinct from Conduit's sessionId)
    public let toolInput: String?

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
}

// Events delivered from conduitd to the iOS client
public enum DaemonEvent: Sendable {
    case approvalPending(ApprovalPendingParams)
    case pong                                     // keepalive
    case unknown(method: String)
}

extension DaemonEvent {
    // Decode a raw JSON frame into a DaemonEvent.
    // Uses JSONSerialization for the outer envelope, JSONDecoder for typed params.
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
        case "pong":
            return .pong
        default:
            return .unknown(method: method)
        }
    }
}
