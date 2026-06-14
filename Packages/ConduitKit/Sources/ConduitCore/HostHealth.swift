import Foundation

public struct HostHealth: Sendable, Codable {
    public let hostname: String
    public let status: Status
    public let isAsleep: Bool?
    public let isOnBattery: Bool?
    public let batteryPercent: Int?
    public let isPluggedIn: Bool?
    public let lidClosed: Bool?
    public let networkReachable: Bool
    public let interfaceType: String?
    public let daemonVersion: String?
    public let uptime: TimeInterval?
    public let lastPhoneContact: Date?
    public let apnsTokenFresh: Bool?
    public let hooksInstalled: Bool?
    public let localModelEndpoints: [ModelEndpoint]

    public enum Status: String, Codable, Sendable {
        case healthy, degraded, unreachable, sleeping
    }

    public struct ModelEndpoint: Sendable, Codable {
        public let name: String
        public let url: String
        public let reachable: Bool
    }

    public var summary: String {
        switch status {
        case .healthy: return "Host healthy"
        case .degraded: return "Host degraded"
        case .unreachable: return "Host unreachable"
        case .sleeping: return "Host sleeping"
        }
    }
}
