import Foundation

public struct Snippet: Identifiable, Sendable, Hashable, Codable {
    public let id: SnippetID
    public var name: String
    public var body: String
    public var hostTags: [String]
    public var tags: [String]
    public var arguments: [SnippetArgument]    // Tier 2.1 — parameterized form
    public var useCount: Int                   // Tier 2.4 — palette ranking
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: SnippetID = .init(),
        name: String,
        body: String,
        hostTags: [String] = [],
        tags: [String] = [],
        arguments: [SnippetArgument] = [],
        useCount: Int = 0,
        createdAt: Date = .now,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.hostTags = hostTags
        self.tags = tags
        self.arguments = arguments
        self.useCount = useCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - Parameterized snippet arguments (Tier 2.1, adapted from Warp YAML)

/// A typed parameter that drives the `{{name}}` substitution performed by
/// `WorkflowEngine`. Schema mirrors Warp's `Argument` struct so workflows
/// authored in Warp's YAML format can round-trip through Conduit.
///
/// Source of design: `/Users/roshansilva/Downloads/warp-master/app/src/workflows/workflow.rs:24,34`
/// and `workflow_enum.rs:1-20` (`EnumVariants::Dynamic`).
public struct SnippetArgument: Sendable, Hashable, Codable {
    public var name: String              // matches `{{name}}` in body
    public var description: String?
    public var defaultValue: String?
    public var source: Source

    public enum Source: Sendable, Hashable, Codable {
        /// Plain text input.
        case literal
        /// Fixed list — user picks one from a dropdown.
        case enumValues([String])
        /// Dropdown values come from running a shell command on the remote
        /// host at invoke-time (e.g. `git branch --format='%(refname:short)'`).
        case dynamicShellCommand(String)
    }

    public init(
        name: String,
        description: String? = nil,
        defaultValue: String? = nil,
        source: Source = .literal
    ) {
        self.name = name
        self.description = description
        self.defaultValue = defaultValue
        self.source = source
    }
}
