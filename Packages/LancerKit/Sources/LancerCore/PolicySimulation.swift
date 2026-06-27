import Foundation

/// Result of simulating a proposed policy against historical actions
public struct PolicySimulation: Sendable, Codable {
    public let generatedAt: String
    public let periodDays: Int
    public let totalActions: Int
    public let autoApproved: Int
    public let asked: Int
    public let denied: Int
    public let ruleHits: [RuleHit]
    public let riskDistribution: [String: Int]

    public struct RuleHit: Sendable, Codable {
        public let ruleID: String
        public let effect: String
        public let count: Int
        public let sampleCommands: [String]
    }

    public init(
        generatedAt: String = "",
        periodDays: Int = 7,
        totalActions: Int = 0,
        autoApproved: Int = 0,
        asked: Int = 0,
        denied: Int = 0,
        ruleHits: [RuleHit] = [],
        riskDistribution: [String: Int] = [:]
    ) {
        self.generatedAt = generatedAt
        self.periodDays = periodDays
        self.totalActions = totalActions
        self.autoApproved = autoApproved
        self.asked = asked
        self.denied = denied
        self.ruleHits = ruleHits
        self.riskDistribution = riskDistribution
    }

    /// Human-readable summary
    public var summary: String {
        "Last \(periodDays) days: \(autoApproved) auto-approved, \(asked) asked, \(denied) denied"
    }
}
