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
    /// Absolute path to the repository/working directory on the ssh-host that
    /// workspace git operations (status/diff/commit/PR) target. nil ⇒ no workspace.
    public var workspacePath: String?
    /// Cloud-execution region hint (e.g. "us-east"). Cloud runtimes only; the
    /// backend selects the concrete provider (Fly vs GCP) from runtime + region.
    public var region: String?
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
        workspacePath: String? = nil,
        region: String? = nil,
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
        self.workspacePath = workspacePath
        self.region = region
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum HostedRuntimeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case sshHost
    case fly
    case gcpCloudRun
    case lightsail

    public var displayName: String {
        switch self {
        case .sshHost: "SSH host"
        case .fly: "Fly.io"
        case .gcpCloudRun: "GCP Cloud Run"
        case .lightsail: "AWS Lightsail"
        }
    }

    /// Requires a saved host id for SSH-backed execution on device.
    public var requiresHostID: Bool {
        switch self {
        case .sshHost, .fly: true
        case .gcpCloudRun, .lightsail: false
        }
    }

    /// True for runtimes orchestrated server-side in a cloud sandbox (no device SSH).
    public var isCloud: Bool {
        switch self {
        case .sshHost: false
        case .fly, .gcpCloudRun, .lightsail: true
        }
    }
}

/// The simplified user-facing execution choice. The UI offers only Cloud vs SSH
/// host; the backend picks the concrete cloud provider (Fly/GCP) from the run's
/// `runtime=cloud` + optional region (per the design spec §3.1 / §6).
public enum HostedRuntimeChoice: String, CaseIterable, Sendable, Hashable {
    case sshHost
    case cloud

    public var displayName: String {
        switch self {
        case .sshHost: "SSH host"
        case .cloud:   "Cloud"
        }
    }

    public var subtitle: String {
        switch self {
        case .sshHost: "Run on your own machine over SSH."
        case .cloud:   "Run in a managed cloud sandbox."
        }
    }

    /// Canonical backend runtime kind for this choice. Cloud maps to the
    /// region-driven Cloud Run kind; the backend may re-route to Fly.
    public var runtimeKind: HostedRuntimeKind {
        switch self {
        case .sshHost: .sshHost
        case .cloud:   .gcpCloudRun
        }
    }

    /// Derives the user-facing choice from a stored runtime kind.
    public init(runtimeKind: HostedRuntimeKind) {
        self = runtimeKind.isCloud ? .cloud : .sshHost
    }
}

/// A curated cloud region the user can pick for cloud agents. The slug is sent
/// to the backend; the backend resolves it to a concrete provider region.
public struct CloudRegion: Identifiable, Sendable, Hashable {
    public let slug: String
    public let displayName: String
    public var id: String { slug }

    public init(slug: String, displayName: String) {
        self.slug = slug
        self.displayName = displayName
    }

    /// Curated default region list surfaced in the create flow.
    public static let catalog: [CloudRegion] = [
        CloudRegion(slug: "us-east",  displayName: "US East"),
        CloudRegion(slug: "us-west",  displayName: "US West"),
        CloudRegion(slug: "eu-west",  displayName: "EU West"),
        CloudRegion(slug: "eu-central", displayName: "EU Central"),
        CloudRegion(slug: "ap-south", displayName: "Asia Pacific (South)"),
        CloudRegion(slug: "ap-northeast", displayName: "Asia Pacific (Northeast)"),
    ]

    public static let `default` = catalog[0]
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
    /// Process exit code reported by the control plane when the run completes.
    public var exitCode: Int?
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
        exitCode: Int? = nil,
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
        self.exitCode = exitCode
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

/// One page of an incremental run-log tail (GET /runs/{id}/logs?since=N).
public struct RunLogsPage: Sendable {
    public let lines: [RunLogLine]
    public let nextSince: Int

    public init(lines: [RunLogLine], nextSince: Int) {
        self.lines = lines
        self.nextSince = nextSince
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

// MARK: - Artifacts

public struct AgentArtifact: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let runID: String
    public var name: String
    public var contentType: String?
    public var sizeBytes: Int64?
    /// Opaque storage key or HTTPS download URL from the control plane.
    public var storageRef: String
    public var gcsURI: String?
    public var createdAt: Date?

    public init(
        id: String,
        runID: String,
        name: String,
        contentType: String? = nil,
        sizeBytes: Int64? = nil,
        storageRef: String,
        gcsURI: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.name = name
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.storageRef = storageRef
        self.gcsURI = gcsURI
        self.createdAt = createdAt
    }

    public var downloadURL: URL? {
        if let gcsURI, let url = URL(string: gcsURI) { return url }
        if storageRef.hasPrefix("http://") || storageRef.hasPrefix("https://") {
            return URL(string: storageRef)
        }
        return nil
    }
}

// MARK: - Schedules

public struct AgentSchedule: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let agentID: String
    public var cronExpr: String
    public var command: String?
    public var enabled: Bool
    public var nextRunAt: Date?
    public var lastRunAt: Date?

    public init(
        id: String,
        agentID: String,
        cronExpr: String,
        command: String? = nil,
        enabled: Bool = true,
        nextRunAt: Date? = nil,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.cronExpr = cronExpr
        self.command = command
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
    }
}

/// Presets understood by push-backend schedule ticker.
public enum SchedulePreset: String, CaseIterable, Sendable {
    case hourly = "@hourly"
    case daily = "@daily"
    case weekly = "@weekly"

    public var label: String {
        switch self {
        case .hourly: "Every hour"
        case .daily: "Every day"
        case .weekly: "Every week"
        }
    }

    public static func every(seconds: Int) -> String {
        "every:\(seconds)"
    }
}

// MARK: - Billing / quota

public struct HostedQuotaSnapshot: Codable, Sendable, Equatable {
    public var agentsUsed: Int
    public var agentsLimit: Int
    public var runsToday: Int
    public var concurrentRuns: Int
    public var concurrentRunsLimit: Int
    public var usageTodayUSD: Double
    public var dailyUsageLimitUSD: Double
    public var creditsRemainingUSD: Double?

    public init(
        agentsUsed: Int = 0,
        agentsLimit: Int = HostedQuotaPolicy.defaultMaxAgents,
        runsToday: Int = 0,
        concurrentRuns: Int = 0,
        concurrentRunsLimit: Int = HostedQuotaPolicy.defaultMaxConcurrentRuns,
        usageTodayUSD: Double = 0,
        dailyUsageLimitUSD: Double = HostedQuotaPolicy.defaultDailyUsageUSD,
        creditsRemainingUSD: Double? = nil
    ) {
        self.agentsUsed = agentsUsed
        self.agentsLimit = agentsLimit
        self.runsToday = runsToday
        self.concurrentRuns = concurrentRuns
        self.concurrentRunsLimit = concurrentRunsLimit
        self.usageTodayUSD = usageTodayUSD
        self.dailyUsageLimitUSD = dailyUsageLimitUSD
        self.creditsRemainingUSD = creditsRemainingUSD
    }
}

public enum HostedQuotaPolicy {
    public static let defaultMaxAgents = 20
    public static let defaultMaxConcurrentRuns = 5
    public static let defaultDailyUsageUSD = 100.0
}

public struct TeamOrgInfo: Sendable, Equatable {
    public let orgId: String
    public let displayName: String

    public init(orgId: String, displayName: String) {
        self.orgId = orgId
        self.displayName = displayName
    }
}

// MARK: - Org members

/// A member of a team org (push-backend `/orgs/{id}/members`).
public struct OrgMember: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var orgId: String
    public var email: String
    public var role: String
    public var invitedAt: Date?
    /// "invited" | "accepted".
    public var status: String

    public init(
        id: String,
        orgId: String,
        email: String,
        role: String = "member",
        invitedAt: Date? = nil,
        status: String = "invited"
    ) {
        self.id = id
        self.orgId = orgId
        self.email = email
        self.role = role
        self.invitedAt = invitedAt
        self.status = status
    }
}

// MARK: - Managed model catalog

/// Curated OpenRouter model identifiers offered in the create-agent picker.
/// A "custom" escape hatch lets advanced users type any OpenRouter slug.
public enum ManagedModel: String, CaseIterable, Sendable, Hashable {
    case claudeSonnet = "anthropic/claude-sonnet-4"
    case claudeOpus = "anthropic/claude-opus-4"
    case claudeHaiku = "anthropic/claude-haiku-4"
    case gptCodex = "openai/gpt-5-codex"
    case gpt = "openai/gpt-5"
    case geminiPro = "google/gemini-2.5-pro"

    public var label: String {
        switch self {
        case .claudeSonnet: "Claude Sonnet 4"
        case .claudeOpus: "Claude Opus 4"
        case .claudeHaiku: "Claude Haiku 4"
        case .gptCodex: "GPT-5 Codex"
        case .gpt: "GPT-5"
        case .geminiPro: "Gemini 2.5 Pro"
        }
    }

    public static let `default`: ManagedModel = .claudeSonnet

    /// True when the slug isn't one of the curated presets (→ show custom field).
    public static func isCustom(_ slug: String) -> Bool {
        ManagedModel(rawValue: slug) == nil
    }
}
