// Adapted from cmux (MIT) — Sources/VaultAgentRegistry.swift + RestorableAgentTypes.swift.
// Lancer drops the on-disk JSON config discovery (cmux loads ~/.config/cmux/cmux.json
// and project-local .cmux/cmux.json — those don't apply on iOS) and the local
// process detection (cmux uses pgrep against running processes; Lancer instead
// detects agents remotely over SSH). The schema, default agent set, and validation
// rules are ported essentially verbatim so registered agents stay compatible with
// cmux's project config format if anyone ever wants to import one.

import Foundation
import OSLog

// MARK: - Reserved agent kinds

/// Stable identifiers for agents whose resume command shape lives in Lancer
/// natively (see `AgentResumeBuilder`). Custom registry entries cannot collide
/// with these IDs.
public enum AgentKind: String, Codable, Hashable, Sendable, CaseIterable {
    case claude        // Claude Code
    case codex         // Codex (OpenAI)
    case cursor        // Cursor CLI
    case grok          // Grok
    case pi            // Pi (Inflection)
    case gemini        // Gemini CLI / Antigravity
    case opencode      // OpenCode
    case copilot       // GitHub Copilot CLI
    case kimi          // Kimi Code (Moonshot AI)
}

// MARK: - Registration

/// A registered agent (built-in or user-defined) with everything needed to
/// detect a running session and rebuild its resume command.
public struct AgentRegistration: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var iconAssetName: String?
    public var detect: AgentDetectRule
    public var sessionIdSource: AgentSessionIDSource
    public var resumeCommand: String
    public var cwd: AgentCWDPolicy
    public var sessionDirectory: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, iconAssetName, detect, sessionIdSource, resumeCommand, cwd, sessionDirectory
    }

    public init(
        id: String,
        name: String,
        iconAssetName: String? = nil,
        detect: AgentDetectRule,
        sessionIdSource: AgentSessionIDSource,
        resumeCommand: String,
        cwd: AgentCWDPolicy = .preserve,
        sessionDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconAssetName = Self.normalizedOptional(iconAssetName)
        self.detect = detect
        self.sessionIdSource = sessionIdSource
        self.resumeCommand = resumeCommand
        self.cwd = cwd
        self.sessionDirectory = sessionDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidID(id), !Self.isReservedID(id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "Agent id must contain only letters, numbers, dots, underscores, and hyphens, and must not collide with a reserved AgentKind"
            )
        }

        let name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: container,
                debugDescription: "Agent name must not be blank"
            )
        }

        let resumeCommand = try container.decode(String.self, forKey: .resumeCommand)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resumeCommand.isEmpty,
              resumeCommand.contains("{{sessionId}}") || resumeCommand.contains("{{sessionPath}}") else {
            throw DecodingError.dataCorruptedError(
                forKey: .resumeCommand, in: container,
                debugDescription: "Agent resumeCommand must include {{sessionId}} or {{sessionPath}}"
            )
        }

        self.id = id
        self.name = name
        self.iconAssetName = Self.normalizedOptional(try container.decodeIfPresent(String.self, forKey: .iconAssetName))
        self.detect = try container.decodeIfPresent(AgentDetectRule.self, forKey: .detect) ?? .init()
        self.sessionIdSource = try container.decode(AgentSessionIDSource.self, forKey: .sessionIdSource)
        self.resumeCommand = resumeCommand
        self.cwd = try container.decodeIfPresent(AgentCWDPolicy.self, forKey: .cwd) ?? .preserve
        let directory = try container.decodeIfPresent(String.self, forKey: .sessionDirectory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionDirectory = (directory?.isEmpty == true) ? nil : directory
    }

    /// The executable name to call when launching this agent — falls back from
    /// detect rules to the agent id.
    public var defaultExecutable: String {
        if let name = detect.processName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let name = detect.processNames.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return id
    }

    // MARK: - Validation helpers

    public static func isValidID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func isReservedID(_ value: String) -> Bool {
        AgentKind.allCases.contains { $0.rawValue == value }
    }

    // MARK: - Built-in agents
    //
    // Lancer ships these as defaults. They cover the agents Lancer users
    // are most likely to drive remotely over SSH. cmux's project config
    // format remains importable through the Codable surface above for power
    // users who already maintain `.cmux/cmux.json` files on their hosts.

    public static var builtInClaude: AgentRegistration {
        AgentRegistration(
            id: AgentKind.claude.rawValue,
            name: "Claude Code",
            iconAssetName: "AgentIcons/Claude",
            detect: AgentDetectRule(processName: "claude", argvContains: ["claude"]),
            sessionIdSource: .argvOption("--resume"),
            resumeCommand: "{{executable}} --resume {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.claude/projects"
        )
    }

    public static var builtInCodex: AgentRegistration {
        AgentRegistration(
            id: AgentKind.codex.rawValue,
            name: "Codex",
            iconAssetName: "AgentIcons/Codex",
            detect: AgentDetectRule(processName: "codex", argvContains: ["codex"]),
            sessionIdSource: .argvOption("resume"),
            resumeCommand: "{{executable}} resume {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.codex/sessions"
        )
    }

    public static var builtInCursor: AgentRegistration {
        AgentRegistration(
            id: AgentKind.cursor.rawValue,
            name: "Cursor",
            iconAssetName: "AgentIcons/Cursor",
            detect: AgentDetectRule(processNames: ["agent", "cursor-agent"], argvContains: ["agent", "cursor-agent"]),
            sessionIdSource: .argvOption("--resume"),
            resumeCommand: "{{executable}} -p --resume {{sessionId}} --output-format stream-json --trust",
            cwd: .preserve,
            sessionDirectory: "~/.cursor/sessions"
        )
    }

    public static var builtInGrok: AgentRegistration {
        AgentRegistration(
            id: AgentKind.grok.rawValue,
            name: "Grok",
            iconAssetName: "AgentIcons/Grok",
            detect: AgentDetectRule(processNames: ["grok", "grok-macos-aarch64", "grok-macos-aarch"]),
            sessionIdSource: .grokSessionDirectory,
            resumeCommand: "{{executable}} -r {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.grok/sessions"
        )
    }

    public static var builtInPi: AgentRegistration {
        AgentRegistration(
            id: AgentKind.pi.rawValue,
            name: "Pi",
            iconAssetName: "AgentIcons/Pi",
            detect: AgentDetectRule(processName: "pi", argvContains: ["pi"]),
            sessionIdSource: .piSessionFile,
            resumeCommand: "{{executable}} --session {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.pi/agent/sessions"
        )
    }

    public static var builtInGemini: AgentRegistration {
        AgentRegistration(
            id: AgentKind.gemini.rawValue,
            name: "Gemini",
            iconAssetName: "AgentIcons/Gemini",
            detect: AgentDetectRule(processNames: ["agy", "antigravity", "gemini"]),
            sessionIdSource: .argvOption("--conversation"),
            resumeCommand: "{{executable}} --conversation {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.gemini/antigravity-cli"
        )
    }

    public static var builtInOpencode: AgentRegistration {
        AgentRegistration(
            id: AgentKind.opencode.rawValue,
            name: "OpenCode",
            detect: AgentDetectRule(processName: "opencode", argvContains: ["opencode"]),
            sessionIdSource: .argvOption("--session"),
            resumeCommand: "{{executable}} --session {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.local/share/opencode"
        )
    }

    public static var builtInKimi: AgentRegistration {
        AgentRegistration(
            id: AgentKind.kimi.rawValue,
            name: "Kimi Code",
            iconAssetName: "AgentIcons/Kimi",
            detect: AgentDetectRule(processName: "kimi", argvContains: ["kimi"]),
            sessionIdSource: .argvOption("--session"),
            resumeCommand: "{{executable}} --session {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.kimi-code"
        )
    }

    public static var builtInCopilot: AgentRegistration {
        AgentRegistration(
            id: AgentKind.copilot.rawValue,
            name: "GitHub Copilot",
            iconAssetName: "AgentIcons/Copilot",
            detect: AgentDetectRule(processName: "copilot", argvContains: ["copilot"]),
            sessionIdSource: .argvOption("--resume"),
            resumeCommand: "{{executable}} --resume {{sessionId}}",
            cwd: .preserve,
            sessionDirectory: "~/.copilot/sessions"
        )
    }
}

// MARK: - Detection rule

/// How to detect a running instance of this agent on the remote host. cmux
/// matches against local processes via pgrep; Lancer uses the same rule
/// shape but runs the matching over SSH (`pgrep -f`) so the same project
/// config files round-trip cleanly.
public struct AgentDetectRule: Codable, Hashable, Sendable {
    public var processName: String?
    public var processNames: [String]
    public var argvContains: [String]

    private enum CodingKeys: String, CodingKey {
        case processName, processNames, argvContains
    }

    public init(processName: String? = nil, processNames: [String] = [], argvContains: [String] = []) {
        let name = processName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.processName = (name?.isEmpty == true) ? nil : name
        self.processNames = processNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.argvContains = argvContains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .processName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        processName = (name?.isEmpty == true) ? nil : name
        processNames = try Self.decodeOneOrManyStrings(forKey: .processNames, in: container)
        argvContains = try Self.decodeOneOrManyStrings(forKey: .argvContains, in: container)
    }

    private static func decodeOneOrManyStrings(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        if let values = try? container.decode([String].self, forKey: key) {
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let value = try container.decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return [value]
        }
        return []
    }
}

// MARK: - Session-ID source

/// Where to read the live session ID from for this agent.
/// - `argvOption(flag)`: read from a command-line option already in the
///   process's argv (e.g. `--resume <id>`).
/// - `piSessionFile`: agent writes its session ID to a known file in
///   `~/.pi/agent/sessions/`.
/// - `grokSessionDirectory`: agent stores per-session subdirectories in
///   `~/.grok/sessions/` named after the session ID.
public enum AgentSessionIDSource: Codable, Hashable, Sendable {
    case argvOption(String)
    case piSessionFile
    case grokSessionDirectory

    private enum CodingKeys: String, CodingKey {
        case type, argvOption
    }

    public init(from decoder: Decoder) throws {
        // Allow string-form for the simple cases.
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch trimmed {
            case "piSessionFile", "pi-session-file":
                self = .piSessionFile
            case "grokSessionDirectory", "grok-session-directory":
                self = .grokSessionDirectory
            default:
                guard !trimmed.isEmpty else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "sessionIdSource must not be blank"
                        )
                    )
                }
                self = .argvOption(trimmed)
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "piSessionFile", "pi-session-file":
            self = .piSessionFile
        case "grokSessionDirectory", "grok-session-directory":
            self = .grokSessionDirectory
        case "argvOption", "argv-option":
            let option = try container.decodeIfPresent(String.self, forKey: .argvOption)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let option, !option.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .argvOption, in: container,
                    debugDescription: "argvOption must not be blank"
                )
            }
            self = .argvOption(option)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown sessionIdSource type '\(type)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .argvOption(let option):
            try container.encode("argvOption", forKey: .type)
            try container.encode(option, forKey: .argvOption)
        case .piSessionFile:
            try container.encode("piSessionFile", forKey: .type)
        case .grokSessionDirectory:
            try container.encode("grokSessionDirectory", forKey: .type)
        }
    }
}

// MARK: - CWD policy

/// Whether to preserve the agent's recorded working directory when rebuilding
/// the resume command. `preserve` `cd`s into the directory first; `ignore`
/// drops the working-directory step entirely.
public enum AgentCWDPolicy: String, Codable, Hashable, Sendable {
    case preserve
    case ignore

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "preserve":
            self = .preserve
        case "ignore", "none":
            self = .ignore
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown agent cwd policy '\(value)'"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Registry

/// Ordered collection of `AgentRegistration` with deduplication-by-id and
/// lookup helpers. Built-in defaults are merged with any user/project
/// overrides; later registrations win on collision.
public struct AgentRegistry: Sendable {
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "AgentRegistry")

    public var registrations: [AgentRegistration]

    public init(registrations: [AgentRegistration]) {
        var ordered: [AgentRegistration] = []
        var indexesByID: [String: Int] = [:]
        for registration in registrations {
            if let existingIndex = indexesByID[registration.id] {
                ordered[existingIndex] = registration
            } else {
                indexesByID[registration.id] = ordered.count
                ordered.append(registration)
            }
        }
        self.registrations = ordered
    }

    public func registration(id: String) -> AgentRegistration? {
        registrations.first { $0.id == id }
    }

    /// Default registry covering all built-in agents Lancer ships with.
    public static var defaults: AgentRegistry {
        AgentRegistry(registrations: [
            .builtInClaude,
            .builtInCodex,
            .builtInOpencode,
            .builtInKimi,
            .builtInCopilot,
            .builtInCursor,
            .builtInGrok,
            .builtInPi,
            .builtInGemini,
        ])
    }
}
