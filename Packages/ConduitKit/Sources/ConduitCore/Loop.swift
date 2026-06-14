import Foundation

/// A first-class record of an agent's work session.
/// Tracks goal, progress, approvals, spend, and final state.
public struct Loop: Codable, Sendable, Identifiable {
    public let id: String
    public var goal: String
    public var plan: String?
    public var currentStep: String?
    public var blockedReason: BlockedReason?

    // Identity
    public let agent: String
    public let vendor: String?
    public var model: String?
    public let hostID: String
    public var repo: String?
    public var branch: String?
    public var worktree: String?

    // Progress
    public var filesChanged: [String]
    public var commandsRun: [String]
    public var testsRun: [TestResult]
    public var approvalsAsked: Int
    public var approvalsDecided: Int
    public var policyExceptions: Int

    // Spend
    public var spendUSD: Double
    public var tokenCount: TokenUsage?

    // State
    public var status: Status
    public var startedAt: Date
    public var completedAt: Date?
    public var lastActivityAt: Date?

    // Final proof
    public var proof: Proof?

    public enum Status: String, Codable, Sendable {
        case running
        case blocked
        case paused
        case completed
        case failed
        case cancelled
    }

    public struct TestResult: Codable, Sendable, Equatable {
        public let name: String
        public let passed: Bool
        public let duration: TimeInterval?

        public init(name: String, passed: Bool, duration: TimeInterval? = nil) {
            self.name = name
            self.passed = passed
            self.duration = duration
        }
    }

    public struct TokenUsage: Codable, Sendable, Equatable {
        public let inputTokens: Int
        public let outputTokens: Int

        public init(inputTokens: Int, outputTokens: Int) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public struct Proof: Codable, Sendable, Equatable {
        public let summary: String
        public let testResults: [TestResult]
        public let diffSummary: String?
        public let prURL: String?
        public let filesChanged: [String]
        public let commandsRun: [String]
        public let totalSpend: Double
        public let policyExceptions: Int

        public init(
            summary: String,
            testResults: [TestResult],
            diffSummary: String? = nil,
            prURL: String? = nil,
            filesChanged: [String] = [],
            commandsRun: [String] = [],
            totalSpend: Double = 0,
            policyExceptions: Int = 0
        ) {
            self.summary = summary
            self.testResults = testResults
            self.diffSummary = diffSummary
            self.prURL = prURL
            self.filesChanged = filesChanged
            self.commandsRun = commandsRun
            self.totalSpend = totalSpend
            self.policyExceptions = policyExceptions
        }
    }

    public init(
        id: String = UUID().uuidString,
        goal: String,
        plan: String? = nil,
        currentStep: String? = nil,
        blockedReason: BlockedReason? = nil,
        agent: String,
        vendor: String? = nil,
        model: String? = nil,
        hostID: String,
        repo: String? = nil,
        branch: String? = nil,
        worktree: String? = nil,
        filesChanged: [String] = [],
        commandsRun: [String] = [],
        testsRun: [TestResult] = [],
        approvalsAsked: Int = 0,
        approvalsDecided: Int = 0,
        policyExceptions: Int = 0,
        spendUSD: Double = 0,
        tokenCount: TokenUsage? = nil,
        status: Status = .running,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        proof: Proof? = nil
    ) {
        self.id = id
        self.goal = goal
        self.plan = plan
        self.currentStep = currentStep
        self.blockedReason = blockedReason
        self.agent = agent
        self.vendor = vendor
        self.model = model
        self.hostID = hostID
        self.repo = repo
        self.branch = branch
        self.worktree = worktree
        self.filesChanged = filesChanged
        self.commandsRun = commandsRun
        self.testsRun = testsRun
        self.approvalsAsked = approvalsAsked
        self.approvalsDecided = approvalsDecided
        self.policyExceptions = policyExceptions
        self.spendUSD = spendUSD
        self.tokenCount = tokenCount
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastActivityAt = lastActivityAt
        self.proof = proof
    }
}

#if DEBUG
extension Loop {
    public static let sample = Loop(
        goal: "Add rate-limiting middleware to the API gateway",
        plan: "1. Audit existing middleware chain\n2. Implement token bucket\n3. Add tests\n4. Update config",
        currentStep: "Implement token bucket",
        agent: "claudeCode",
        vendor: "anthropic",
        model: "claude-sonnet-4-20250514",
        hostID: "dev-box",
        repo: "gateway",
        branch: "feat/rate-limit",
        filesChanged: ["src/middleware/ratelimit.ts", "src/config/gateway.yaml"],
        commandsRun: ["npm test", "npm run lint"],
        testsRun: [
            TestResult(name: "rate limit allows under threshold", passed: true, duration: 0.12),
            TestResult(name: "rate limit blocks over threshold", passed: true, duration: 0.08),
            TestResult(name: "rate limit resets after window", passed: false, duration: 0.15),
        ],
        approvalsAsked: 3,
        approvalsDecided: 3,
        spendUSD: 0.47,
        tokenCount: TokenUsage(inputTokens: 12400, outputTokens: 3200),
        status: .running,
        startedAt: Date().addingTimeInterval(-1800),
        lastActivityAt: Date().addingTimeInterval(-60)
    )
}
#endif
