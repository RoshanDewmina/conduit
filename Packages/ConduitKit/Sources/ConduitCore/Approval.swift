import Foundation

public struct Approval: Identifiable, Sendable, Hashable {
    public let id: ApprovalID
    public let sessionID: SessionID
    public let agent: AgentSource
    public let kind: Kind
    public let command: String?
    public let patch: String?
    public let cwd: String
    public let risk: Risk
    public let createdAt: Date
    public var decidedAt: Date?
    public var decision: Decision?
    public let question: String?
    public let choices: [String]?
    public var answeredChoice: Int?
    public var toolName: String?
    public var toolUseID: String?
    public var agentSessionID: String?
    public var toolInput: String?
    public let blastRadius: ApprovalBlastRadius?

    public enum AgentSource: String, Sendable, Hashable, Codable {
        case claudeCode, codex, opencode, cursor, devin, unknown
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        case command, patch, fileWrite, fileDelete, network, credential, browser, callMCP, askQuestion
    }

    public enum Risk: Int, Sendable, Hashable, Codable, Comparable {
        case low = 0, medium = 1, high = 2, critical = 3
        public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Decision: String, Sendable, Hashable, Codable {
        case approved, approvedAlways, rejected, expired
    }

    public init(
        id: ApprovalID = .init(),
        sessionID: SessionID,
        agent: AgentSource,
        kind: Kind,
        command: String? = nil,
        patch: String? = nil,
        cwd: String,
        risk: Risk,
        createdAt: Date = .now,
        decidedAt: Date? = nil,
        decision: Decision? = nil,
        question: String? = nil,
        choices: [String]? = nil,
        answeredChoice: Int? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        agentSessionID: String? = nil,
        toolInput: String? = nil,
        blastRadius: ApprovalBlastRadius? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agent = agent
        self.kind = kind
        self.command = command
        self.patch = patch
        self.cwd = cwd
        self.risk = risk
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.decision = decision
        self.question = question
        self.choices = choices
        self.answeredChoice = answeredChoice
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.agentSessionID = agentSessionID
        self.toolInput = toolInput
        self.blastRadius = blastRadius
    }

    public var isPending: Bool { decision == nil }
}
