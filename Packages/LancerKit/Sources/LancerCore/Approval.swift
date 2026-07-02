import CryptoKit
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
    public let lastStateChangeAt: Date?
    /// SHA-256 over (command, patch, cwd, toolInput) as computed by the daemon
    /// when this approval was created (`computeContentHash` in
    /// `daemon/lancerd/approval.go`) — echoed back verbatim in the decision
    /// payload so lancerd can verify the phone decided on the exact content it
    /// is holding pending, not a stale or substituted copy. `nil` only for
    /// approvals synthesized entirely on-device before ever reaching the wire.
    public let contentHash: String?

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
        blastRadius: ApprovalBlastRadius? = nil,
        lastStateChangeAt: Date? = nil,
        contentHash: String? = nil
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
        self.lastStateChangeAt = lastStateChangeAt
        self.contentHash = contentHash
    }

    public var isPending: Bool { decision == nil }

    /// Canonicalizes (command, patch, cwd, toolInput) into the same SHA-256
    /// digest `computeContentHash` produces in `daemon/lancerd/approval.go` —
    /// fields joined with \u{1F} (ASCII unit separator), which cannot occur in
    /// any of them, so concatenation stays unambiguous across a field boundary
    /// without a length-prefixed encoding. The two implementations are kept in
    /// sync by shared test vectors, not by sharing code across languages.
    public static func computeContentHash(command: String?, patch: String?, cwd: String, toolInput: String?) -> String {
        let joined = [command ?? "", patch ?? "", cwd, toolInput ?? ""].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
