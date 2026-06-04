import Foundation

public struct AgentVendorStatus: Codable, Sendable, Equatable, Identifiable {
    public var id: String { agent }
    public let agent: String
    public let loggedIn: Bool?
    public let model: String?
    public let sessionCount: Int
    public let runningCount: Int?
    public let usageUSD: Double?
    public let usagePeriod: String?

    public init(
        agent: String,
        loggedIn: Bool? = nil,
        model: String? = nil,
        sessionCount: Int = 0,
        runningCount: Int? = nil,
        usageUSD: Double? = nil,
        usagePeriod: String? = nil
    ) {
        self.agent = agent
        self.loggedIn = loggedIn
        self.model = model
        self.sessionCount = sessionCount
        self.runningCount = runningCount
        self.usageUSD = usageUSD
        self.usagePeriod = usagePeriod
    }

    public var displayName: String {
        switch agent {
        case "claudeCode": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        default: return agent
        }
    }
}

public struct AgentStatusSnapshot: Codable, Sendable, Equatable {
    public let agents: [AgentVendorStatus]
    public let collectedAt: String?

    public init(agents: [AgentVendorStatus], collectedAt: String? = nil) {
        self.agents = agents
        self.collectedAt = collectedAt
    }

    public var totalUsageUSD: Double? {
        let values = agents.compactMap(\.usageUSD)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}
