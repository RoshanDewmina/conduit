import Foundation

public struct CIEvent: Sendable, Codable, Identifiable {
    public let id: String
    public let repo: String
    public let type: EventType
    public let action: String
    public let prNumber: Int?
    public let prTitle: String?
    public let prURL: String?
    public let status: CheckStatus
    public let context: String?
    public let message: String?
    public let timestamp: Date

    public enum EventType: String, Codable, Sendable {
        case pullRequest
        case checkRun
        case status
    }

    public enum CheckStatus: String, Codable, Sendable {
        case success
        case failure
        case pending
        case error
    }

    public init(
        id: String = UUID().uuidString,
        repo: String,
        type: EventType,
        action: String,
        prNumber: Int? = nil,
        prTitle: String? = nil,
        prURL: String? = nil,
        status: CheckStatus = .pending,
        context: String? = nil,
        message: String? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.repo = repo
        self.type = type
        self.action = action
        self.prNumber = prNumber
        self.prTitle = prTitle
        self.prURL = prURL
        self.status = status
        self.context = context
        self.message = message
        self.timestamp = timestamp
    }
}

extension CIEvent {
    public var statusIcon: String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    public var statusLabel: String {
        switch status {
        case .success: return "Passed"
        case .failure: return "Failed"
        case .pending: return "Pending"
        case .error:   return "Error"
        }
    }
}
