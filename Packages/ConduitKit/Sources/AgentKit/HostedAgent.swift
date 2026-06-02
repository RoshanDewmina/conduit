import Foundation

// MARK: - Hosted agent

/// A user-configured agent definition stored in the control plane.
public struct HostedAgent: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var model: String
    public var runtimeKind: HostedRuntimeKind
    /// Host identifier for SSH-backed runtimes.
    public var hostID: String?
    /// Shell command invoked when a run starts (e.g. `claude`).
    public var command: String?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        model: String,
        runtimeKind: HostedRuntimeKind = .sshHost,
        hostID: String? = nil,
        command: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.runtimeKind = runtimeKind
        self.hostID = hostID
        self.command = command
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum HostedRuntimeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case sshHost
    case fly
}

// MARK: - Agent run

/// One execution of a hosted agent.
public struct AgentRun: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let agentID: String
    public var status: RunStatus
    public var prompt: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var logLines: [RunLogLine]
    public var approvals: [RunApproval]
    public var usageRecords: [UsageRecord]

    public init(
        id: String = UUID().uuidString,
        agentID: String,
        status: RunStatus = .pending,
        prompt: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        logLines: [RunLogLine] = [],
        approvals: [RunApproval] = [],
        usageRecords: [UsageRecord] = []
    ) {
        self.id = id
        self.agentID = agentID
        self.status = status
        self.prompt = prompt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.logLines = logLines
        self.approvals = approvals
        self.usageRecords = usageRecords
    }
}

public enum RunStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pending
    case running
    case awaitingApproval
    case succeeded
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        default: false
        }
    }
}

public struct RunLogLine: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let timestamp: Date
    public let text: String

    public init(id: String = UUID().uuidString, timestamp: Date = .now, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

public struct RunApproval: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var kind: String
    public var command: String?
    public var status: RunApprovalStatus
    public var createdAt: Date

    public init(
        id: String,
        kind: String,
        command: String? = nil,
        status: RunApprovalStatus = .pending,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.command = command
        self.status = status
        self.createdAt = createdAt
    }
}

public enum RunApprovalStatus: String, Codable, Sendable, Hashable {
    case pending
    case approved
    case rejected
}

// MARK: - Usage

/// Metered AI usage recorded for a run.
public struct UsageRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var inputTokens: Int
    public var outputTokens: Int
    /// USD cost from OpenRouter inline `usage.cost`.
    public var costUSD: Double?
    public var model: String?
    public var recordedAt: Date

    public init(
        id: String = UUID().uuidString,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double? = nil,
        model: String? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.model = model
        self.recordedAt = recordedAt
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}
