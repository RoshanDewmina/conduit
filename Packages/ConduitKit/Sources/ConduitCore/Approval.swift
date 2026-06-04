import Foundation

/// An approval request raised by a remote agent (Claude Code, Codex, etc.)
/// and surfaced to the user in the Inbox.
public struct Approval: Identifiable, Sendable, Hashable {
    public let id: ApprovalID
    public let sessionID: SessionID
    public let agent: AgentSource
    public let kind: Kind
    public let command: String?           // present for `.command` / `.patch`
    public let patch: String?             // unified diff for `.patch`
    public let cwd: String
    public let risk: Risk
    public let createdAt: Date
    public var decidedAt: Date?
    public var decision: Decision?
    // askQuestion fields
    public let question: String?          // prompt text for .askQuestion
    public let choices: [String]?         // answer options for .askQuestion
    public var answeredChoice: Int?       // user-selected index (0-based)
    // Structured tool-use fields — nil when received from older conduitd
    public var toolName: String?
    public var toolUseID: String?
    public var agentSessionID: String?    // Claude Code / Codex session ID
    public var toolInput: String?

    public enum AgentSource: String, Sendable, Hashable, Codable {
        case claudeCode, codex, opencode, cursor, devin, unknown
    }

    public enum Kind: String, Sendable, Hashable, Codable {
        case command         // wants to run a shell command
        case patch           // wants to apply a code change
        case fileWrite       // wants to overwrite a file
        case fileDelete
        case network         // wants to make a network call
        case credential      // wants a secret / API key
        case browser         // wants to perform a browser action
        case callMCP         // wants to invoke an MCP tool
        case askQuestion     // agent needs user to pick from multiple choices
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
        toolInput: String? = nil
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
    }

    public var isPending: Bool { decision == nil }
}
