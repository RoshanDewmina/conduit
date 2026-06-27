import Foundation

/// A slash-command available to an agent in a workspace — a project/user custom
/// command, a skill, or a curated built-in. Returned by the daemon's
/// `agent.commands.list` RPC and merged with Lancer's own app-commands in the
/// composer's "/" autocomplete.
public struct AgentCommand: Codable, Identifiable, Sendable, Hashable {
    public let name: String        // "/review"
    public let description: String
    public let source: String      // "project" | "user" | "builtin"
    public let kind: String        // "command" | "skill" | "builtin"

    public var id: String { name }

    public init(name: String, description: String, source: String, kind: String) {
        self.name = name
        self.description = description
        self.source = source
        self.kind = kind
    }
}
