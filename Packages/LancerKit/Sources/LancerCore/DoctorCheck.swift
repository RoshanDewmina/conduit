import Foundation

/// A single health check result from lancerd
public struct DoctorCheckResult: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let passed: Bool
    public let message: String
    public let severity: Severity

    public enum Severity: String, Sendable, Codable {
        case info, warning, error
    }

    public init(id: String, name: String, passed: Bool, message: String, severity: Severity) {
        self.id = id
        self.name = name
        self.passed = passed
        self.message = message
        self.severity = severity
    }
}

/// Full doctor report from the daemon
public struct DoctorReport: Sendable, Codable {
    public let daemonVersion: String
    public let checks: [DoctorCheckResult]
    public let generatedAt: String

    public var allPassed: Bool { checks.allSatisfy(\.passed) }
    public var errors: [DoctorCheckResult] { checks.filter { $0.severity == .error && !$0.passed } }
    public var warnings: [DoctorCheckResult] { checks.filter { $0.severity == .warning && !$0.passed } }

    public init(daemonVersion: String, checks: [DoctorCheckResult], generatedAt: String) {
        self.daemonVersion = daemonVersion
        self.checks = checks
        self.generatedAt = generatedAt
    }
}
