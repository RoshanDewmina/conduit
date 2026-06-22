import Foundation

public struct FleetSummary: Sendable, Equatable {
    public let loggedInVendors: Int
    public let activeSessions: Int
    public let totalSpendUSD: Double

    public init(snapshots: [AgentStatusSnapshot]) {
        var loggedIn = Set<String>()
        var sessions = 0
        var spend = 0.0
        for snap in snapshots {
            for a in snap.agents {
                if a.loggedIn == true { loggedIn.insert(a.agent) }
                sessions += a.sessionCount
                spend += a.usageUSD ?? 0
            }
        }
        self.loggedInVendors = loggedIn.count
        self.activeSessions = sessions
        self.totalSpendUSD = spend
    }
}
