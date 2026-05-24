import Foundation
import ConduitCore

/// A declarative description of a workspace to provision.
public struct ProvisioningPlan: Codable, Sendable {
    public var name: String
    public var provider: Provider
    public var region: String
    public var size: MachineSize
    public var agentCLI: AgentCLI
    public var dotfilesURL: URL?

    public enum Provider: String, CaseIterable, Codable, Sendable {
        case fly         = "fly"
        case lightsail   = "lightsail"
        case orbstack    = "orbstack"

        public var displayName: String {
            switch self {
            case .fly:       "Fly.io"
            case .lightsail: "AWS Lightsail"
            case .orbstack:  "OrbStack (local)"
            }
        }
    }

    public enum MachineSize: String, CaseIterable, Codable, Sendable {
        case shared1x    = "shared-cpu-1x"
        case shared2x    = "shared-cpu-2x"
        case performance = "performance-1x"

        public var displayName: String {
            switch self {
            case .shared1x:    "1 CPU / 256 MB (Free tier)"
            case .shared2x:    "1 CPU / 512 MB"
            case .performance: "1 CPU / 2 GB (Recommended)"
            }
        }
    }

    public enum AgentCLI: String, CaseIterable, Codable, Sendable {
        case claudeCode = "claude-code"
        case codex      = "codex"
        case none       = "none"

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex:      "OpenAI Codex"
            case .none:       "None (shell only)"
            }
        }

        public var installCommand: String {
            switch self {
            case .claudeCode: "npm install -g @anthropic-ai/claude-code"
            case .codex:      "npm install -g @openai/codex"
            case .none:       "echo 'No agent CLI requested'"
            }
        }
    }

    public init(
        name: String,
        provider: Provider,
        region: String,
        size: MachineSize = .performance,
        agentCLI: AgentCLI = .claudeCode,
        dotfilesURL: URL? = nil
    ) {
        self.name = name
        self.provider = provider
        self.region = region
        self.size = size
        self.agentCLI = agentCLI
        self.dotfilesURL = dotfilesURL
    }
}

/// A provisioner creates a Host from a plan.
public protocol Provisioner: Actor {
    /// Creates the compute instance and returns a ready-to-connect Host.
    /// Progress is reported via the log stream.
    func create(plan: ProvisioningPlan, log: @escaping @Sendable (String) async -> Void) async throws -> ConduitCore.Host
}
