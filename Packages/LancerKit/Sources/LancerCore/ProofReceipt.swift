import Foundation

/// Portable run proof emitted once per terminal agent run (`lancer.proof/v0`).
/// Wire: JSON-RPC `agent.run.receipt` params and E2E relay `runReceipt` payload.
public struct ProofReceipt: Codable, Sendable, Hashable {
    public let schema: String
    public let runId: String
    public let conversationId: String
    public let agent: String
    public let model: String?
    public let startedAt: String?
    public let endedAt: String?
    public let status: String
    public let exitCode: Int?
    public let contract: Contract?
    public let commands: [Command]?
    public let filesTouched: [FileTouched]?
    public let tests: TestsSummary?
    public let criteria: [Criterion]?
    public let git: GitSnapshot?
    public let confidence: Confidence?
    public let resume: Resume?
    /// Reserved for a future question-ladder answers block; decoded but unused in v0.
    public let answersReserved: [String: String]?
    public let truncated: Bool?

    public struct Contract: Codable, Sendable, Hashable {
        public let goal: String
        public let doneCriteria: [String]
        public let validationCommands: [String]

        public init(goal: String, doneCriteria: [String], validationCommands: [String]) {
            self.goal = goal
            self.doneCriteria = doneCriteria
            self.validationCommands = validationCommands
        }
    }

    public struct Command: Codable, Sendable, Hashable {
        public let command: String
        public let exitCode: Int?
        public let kind: String?
        public let startedAt: String?

        public init(command: String, exitCode: Int? = nil, kind: String? = nil, startedAt: String? = nil) {
            self.command = command
            self.exitCode = exitCode
            self.kind = kind
            self.startedAt = startedAt
        }
    }

    public struct FileTouched: Codable, Sendable, Hashable {
        public let path: String
        public let additions: Int
        public let deletions: Int

        public init(path: String, additions: Int, deletions: Int) {
            self.path = path
            self.additions = additions
            self.deletions = deletions
        }
    }

    public struct TestsSummary: Codable, Sendable, Hashable {
        public let ran: Bool
        public let passed: Int
        public let failed: Int

        public init(ran: Bool, passed: Int, failed: Int) {
            self.ran = ran
            self.passed = passed
            self.failed = failed
        }
    }

    public struct Criterion: Codable, Sendable, Hashable {
        public enum Status: String, Codable, Sendable {
            case met
            case unmet
            case unknown
        }

        public let text: String
        public let status: Status
        public let evidence: String?

        public init(text: String, status: Status, evidence: String? = nil) {
            self.text = text
            self.status = status
            self.evidence = evidence
        }
    }

    public struct GitSnapshot: Codable, Sendable, Hashable {
        public let startRef: String?
        public let endRef: String?
        public let dirtyAtStart: Bool?
        public let worktreePath: String?

        public init(
            startRef: String? = nil,
            endRef: String? = nil,
            dirtyAtStart: Bool? = nil,
            worktreePath: String? = nil
        ) {
            self.startRef = startRef
            self.endRef = endRef
            self.dirtyAtStart = dirtyAtStart
            self.worktreePath = worktreePath
        }
    }

    public struct Confidence: Codable, Sendable, Hashable {
        public let commands: String
        public let files: String
        public let tests: String

        public init(commands: String, files: String, tests: String) {
            self.commands = commands
            self.files = files
            self.tests = tests
        }
    }

    public struct Resume: Codable, Sendable, Hashable {
        public let agent: String
        public let vendorSessionId: String?

        public init(agent: String, vendorSessionId: String? = nil) {
            self.agent = agent
            self.vendorSessionId = vendorSessionId
        }
    }

    public init(
        schema: String = "lancer.proof/v0",
        runId: String,
        conversationId: String,
        agent: String,
        model: String? = nil,
        startedAt: String? = nil,
        endedAt: String? = nil,
        status: String,
        exitCode: Int? = nil,
        contract: Contract? = nil,
        commands: [Command]? = nil,
        filesTouched: [FileTouched]? = nil,
        tests: TestsSummary? = nil,
        criteria: [Criterion]? = nil,
        git: GitSnapshot? = nil,
        confidence: Confidence? = nil,
        resume: Resume? = nil,
        answersReserved: [String: String]? = nil,
        truncated: Bool? = nil
    ) {
        self.schema = schema
        self.runId = runId
        self.conversationId = conversationId
        self.agent = agent
        self.model = model
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.exitCode = exitCode
        self.contract = contract
        self.commands = commands
        self.filesTouched = filesTouched
        self.tests = tests
        self.criteria = criteria
        self.git = git
        self.confidence = confidence
        self.resume = resume
        self.answersReserved = answersReserved
        self.truncated = truncated
    }
}
