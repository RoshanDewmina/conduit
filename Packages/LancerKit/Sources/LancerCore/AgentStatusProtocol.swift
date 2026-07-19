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
    public let local: Bool
    public let isLocalModel: Bool?
    public let dataLeavesHost: Bool?

    public init(
        agent: String,
        loggedIn: Bool? = nil,
        model: String? = nil,
        sessionCount: Int = 0,
        runningCount: Int? = nil,
        usageUSD: Double? = nil,
        usagePeriod: String? = nil,
        local: Bool = false,
        isLocalModel: Bool? = nil,
        dataLeavesHost: Bool? = nil
    ) {
        self.agent = agent
        self.loggedIn = loggedIn
        self.model = model
        self.sessionCount = sessionCount
        self.runningCount = runningCount
        self.usageUSD = usageUSD
        self.usagePeriod = usagePeriod
        self.local = local
        self.isLocalModel = isLocalModel
        self.dataLeavesHost = dataLeavesHost
    }

    enum CodingKeys: String, CodingKey {
        case agent, loggedIn, model, sessionCount, runningCount
        case usageUSD, usagePeriod, local, isLocalModel, dataLeavesHost
    }

    // Custom decode so daemons that omit the newer/optional-with-default fields
    // (local, sessionCount) still decode — synthesized Decodable ignores the
    // memberwise-init defaults and would throw keyNotFound on a missing "local".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decode(String.self, forKey: .agent)
        loggedIn = try c.decodeIfPresent(Bool.self, forKey: .loggedIn)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        runningCount = try c.decodeIfPresent(Int.self, forKey: .runningCount)
        usageUSD = try c.decodeIfPresent(Double.self, forKey: .usageUSD)
        usagePeriod = try c.decodeIfPresent(String.self, forKey: .usagePeriod)
        local = try c.decodeIfPresent(Bool.self, forKey: .local) ?? false
        isLocalModel = try c.decodeIfPresent(Bool.self, forKey: .isLocalModel)
        dataLeavesHost = try c.decodeIfPresent(Bool.self, forKey: .dataLeavesHost)
    }

    public var displayName: String {
        switch agent {
        case "claudeCode": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "kimi": return "Kimi"
        case "pi": return "Pi"
        case "cursor": return "Cursor"
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
