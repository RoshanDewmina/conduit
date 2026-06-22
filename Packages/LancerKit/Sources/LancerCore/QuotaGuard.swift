import Foundation

/// Per-provider quota and spend guardrails
public struct QuotaGuard: Sendable, Codable {
    public var providers: [ProviderQuota]
    public var alerts: [SpendAlert]

    public init(providers: [ProviderQuota] = [], alerts: [SpendAlert] = []) {
        self.providers = providers
        self.alerts = alerts
    }

    public struct ProviderQuota: Sendable, Codable, Identifiable {
        public let id: String
        public var dailyCapUSD: Double?
        public var monthlyCapUSD: Double?
        public var spentTodayUSD: Double
        public var spentThisMonthUSD: Double
        public var burnRateUSDPerHour: Double
        public var projectedDailyTotal: Double
        public var quotaRemainingUSD: Double?
        public var lastUpdated: Date

        public init(
            id: String,
            dailyCapUSD: Double? = nil,
            monthlyCapUSD: Double? = nil,
            spentTodayUSD: Double = 0,
            spentThisMonthUSD: Double = 0,
            burnRateUSDPerHour: Double = 0,
            projectedDailyTotal: Double = 0,
            quotaRemainingUSD: Double? = nil,
            lastUpdated: Date = .now
        ) {
            self.id = id
            self.dailyCapUSD = dailyCapUSD
            self.monthlyCapUSD = monthlyCapUSD
            self.spentTodayUSD = spentTodayUSD
            self.spentThisMonthUSD = spentThisMonthUSD
            self.burnRateUSDPerHour = burnRateUSDPerHour
            self.projectedDailyTotal = projectedDailyTotal
            self.quotaRemainingUSD = quotaRemainingUSD
            self.lastUpdated = lastUpdated
        }

        public var percentUsed: Double? {
            guard let cap = dailyCapUSD, cap > 0 else { return nil }
            return spentTodayUSD / cap
        }

        public var isNearLimit: Bool {
            guard let pct = percentUsed else { return false }
            return pct >= 0.8
        }

        public var isOverLimit: Bool {
            guard let pct = percentUsed else { return false }
            return pct >= 1.0
        }

        public var displayName: String {
            switch id {
            case "claudeCode": return "Claude Code"
            case "codex": return "Codex"
            case "opencode": return "OpenCode"
            default: return id
            }
        }
    }

    public struct SpendAlert: Sendable, Codable, Identifiable {
        public let id: UUID
        public let provider: String
        public let type: AlertType
        public let message: String
        public let threshold: Double
        public let actual: Double
        public let createdAt: Date

        public init(
            id: UUID = UUID(),
            provider: String,
            type: AlertType,
            message: String,
            threshold: Double,
            actual: Double,
            createdAt: Date = .now
        ) {
            self.id = id
            self.provider = provider
            self.type = type
            self.message = message
            self.threshold = threshold
            self.actual = actual
            self.createdAt = createdAt
        }

        public enum AlertType: String, Codable, Sendable {
            case burnRateHigh
            case nearLimit
            case overLimit
            case projectedExceed
        }
    }
}
