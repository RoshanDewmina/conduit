// Adapted from cmux (MIT) — CLI/CMUXCLI+AgentHookDefinitions.swift.
//
// cmux's full file ships per-format file renderers (Cursor flat JSON, Codex
// nested with timeouts, Antigravity grouped JSON, RovoDev YAML, Hermes YAML)
// and a `cmux hooks <agent>` invocation chain. Conduit only needs the schema
// + per-agent metadata so the iOS app can render an "Install hook on this
// host" flow that drops the right file at the right place; the actual hook
// invocation chains through `conduitd` (Conduit's remote daemon), so this
// file replaces cmux's `cmux hooks <agent>` marker with
// `conduitd hooks <agent>` and drops the cmux-only post-install actions.

import Foundation

// MARK: - Schema

/// Declarative description of one agent's hook integration: where to write
/// the hook config file on the remote host, what file format to use, and
/// which agent events to wire to which Conduit subcommands.
public struct AgentHookDef: Hashable, Sendable {
    public let name: String           // CLI key: "claude", "codex", "cursor", etc.
    public let displayName: String    // Human-readable: "Claude Code", "Codex"
    public let statusKey: String      // Diagnostic key
    public let configDir: String      // Relative to ~: ".claude", ".codex"
    public let configFile: String     // File name inside configDir
    public let configDirEnvOverride: String?         // e.g. CODEX_HOME overrides configDir
    public let configDirEnvOverrideSubpath: String?  // e.g. with GROK_HOME, append "hooks"
    public let createConfigDirIfMissing: Bool
    public let binaryName: String                    // Detection binary on PATH
    public let sessionStoreSuffix: String            // ~/.conduit/<suffix>-hook-sessions.json
    public let disableEnvVar: String                 // e.g. CONDUIT_CLAUDE_HOOKS_DISABLED
    public let hookMarker: String                    // Command marker: "conduitd hooks claude"
    public let format: Format
    public let events: [Event]
    public let aliases: Set<String>
    public let publishesStopNotification: Bool
    public let feedHookEvents: [String]              // Long-running events (PreToolUse, etc.)

    /// Hook-file rendering style. Each one corresponds to a different agent's
    /// expected config shape. Conduit doesn't render the files itself — the
    /// daemon (`conduitd`) on the remote host owns that — but the iOS app
    /// surfaces the right description per-agent.
    public enum Format: Hashable, Sendable {
        /// `{"hooks": {"<event>": [{"command": "..."}]}, "version": 1}` (Cursor)
        case flat
        /// `{"hooks": {"<event>": [{"hooks": [{"type":"command","command":"...","timeout":N}]}]}}` (Codex, Gemini, Claude Code)
        case nested(timeoutMs: Int)
        /// `~/.gemini/config/hooks.json` named-group format (Antigravity)
        case antigravityJSON(timeoutSeconds: Int)
        /// YAML body for RovoDev's hook config
        case rovoDevYAML
        /// YAML body for Hermes Agent's hook config
        case hermesAgentYAML
    }

    public struct Event: Hashable, Sendable {
        public let agentEvent: String       // Agent-side event name (e.g. "PreToolUse")
        public let conduitSubcommand: String // Subcommand the hook invokes (e.g. "prompt-submit")

        public init(agentEvent: String, conduitSubcommand: String) {
            self.agentEvent = agentEvent
            self.conduitSubcommand = conduitSubcommand
        }
    }

    public init(
        name: String,
        displayName: String,
        statusKey: String,
        configDir: String,
        configFile: String,
        configDirEnvOverride: String? = nil,
        configDirEnvOverrideSubpath: String? = nil,
        createConfigDirIfMissing: Bool = false,
        binaryName: String? = nil,
        sessionStoreSuffix: String,
        disableEnvVar: String,
        hookMarker: String,
        format: Format,
        events: [Event],
        aliases: Set<String> = [],
        publishesStopNotification: Bool = true,
        feedHookEvents: [String] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.statusKey = statusKey
        self.configDir = configDir
        self.configFile = configFile
        self.configDirEnvOverride = configDirEnvOverride
        self.configDirEnvOverrideSubpath = configDirEnvOverrideSubpath
        self.createConfigDirIfMissing = createConfigDirIfMissing
        self.binaryName = binaryName ?? name
        self.sessionStoreSuffix = sessionStoreSuffix
        self.disableEnvVar = disableEnvVar
        self.hookMarker = hookMarker
        self.format = format
        self.events = events
        self.aliases = Set(aliases.compactMap { alias in
            let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        })
        self.publishesStopNotification = publishesStopNotification
        self.feedHookEvents = feedHookEvents
    }

    /// Resolve the absolute hook-config directory on a host, honouring the
    /// per-agent env override when present. `home` is the remote user's
    /// home directory (Conduit reads this via `$HOME` or `pwd` over SSH).
    public func resolvedConfigDir(home: String, environment: [String: String] = [:]) -> String {
        let normalizedHome = home.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseHome = normalizedHome.isEmpty ? "~" : normalizedHome

        if let envKey = configDirEnvOverride,
           let rawEnvValue = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawEnvValue.isEmpty {
            let expanded = rawEnvValue.hasPrefix("~")
                ? rawEnvValue.replacingOccurrences(of: "~", with: baseHome)
                : rawEnvValue
            if let subpath = configDirEnvOverrideSubpath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !subpath.isEmpty {
                return joinPath(expanded, subpath)
            }
            return expanded
        }
        return joinPath(baseHome, configDir)
    }

    /// Absolute path to the hook-config file the daemon should write/update.
    public func resolvedConfigPath(home: String, environment: [String: String] = [:]) -> String {
        joinPath(
            resolvedConfigDir(home: home, environment: environment),
            configFile
        )
    }

    // MARK: - Internal

    private func joinPath(_ base: String, _ component: String) -> String {
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let trimmedComp = component.hasPrefix("/") ? String(component.dropFirst()) : component
        return "\(trimmedBase)/\(trimmedComp)"
    }
}

// MARK: - Hook action vocabulary

/// Canonical action set the daemon expects on the wire. Each agent maps its
/// own event names (e.g. Claude's `UserPromptSubmit`) onto one of these.
public enum AgentHookAction: String, Hashable, Sendable {
    case sessionStart   = "session-start"
    case promptSubmit   = "prompt-submit"
    case stop           = "stop"
    case notification   = "notification"
    case sessionEnd     = "session-end"
    case noop           = "noop"
}

/// Round-trip subcommand strings → canonical actions, mirroring cmux's
/// subcommandActions map.
public enum AgentHookActions {
    public static let map: [String: AgentHookAction] = [
        "session-start": .sessionStart,
        "prompt-submit": .promptSubmit,
        "stop": .stop,
        "notification": .notification,
        "notify": .notification,
        "agent-response": .stop,
        "shell-exec": .promptSubmit,
        "shell-done": .noop,
        "session-end": .sessionEnd,
    ]

    public static func action(for subcommand: String) -> AgentHookAction? {
        map[subcommand]
    }
}

// MARK: - Built-in agent hook definitions

extension AgentHookDef {

    /// Claude Code (`~/.claude/settings.json`). Nested format with 5s timeout,
    /// plus 120s feed hooks for `PreToolUse` and `PermissionRequest` so
    /// long-running mobile approvals don't trip the agent's default timeout.
    public static var claude: AgentHookDef {
        AgentHookDef(
            name: "claude",
            displayName: "Claude Code",
            statusKey: "claude",
            configDir: ".claude",
            configFile: "settings.json",
            sessionStoreSuffix: "claude",
            disableEnvVar: "CONDUIT_CLAUDE_HOOKS_DISABLED",
            hookMarker: "conduitd hooks claude",
            format: .nested(timeoutMs: 5000),
            events: [
                .init(agentEvent: "SessionStart", conduitSubcommand: "session-start"),
                .init(agentEvent: "UserPromptSubmit", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "Stop", conduitSubcommand: "stop"),
                .init(agentEvent: "Notification", conduitSubcommand: "notification"),
                .init(agentEvent: "SessionEnd", conduitSubcommand: "session-end"),
            ],
            feedHookEvents: ["PreToolUse", "PermissionRequest"]
        )
    }

    /// Codex (`~/.codex/hooks.json`), honours `CODEX_HOME`.
    public static var codex: AgentHookDef {
        AgentHookDef(
            name: "codex",
            displayName: "Codex",
            statusKey: "codex",
            configDir: ".codex",
            configFile: "hooks.json",
            configDirEnvOverride: "CODEX_HOME",
            sessionStoreSuffix: "codex",
            disableEnvVar: "CONDUIT_CODEX_HOOKS_DISABLED",
            hookMarker: "conduitd hooks codex",
            format: .nested(timeoutMs: 5000),
            events: [
                .init(agentEvent: "SessionStart", conduitSubcommand: "session-start"),
                .init(agentEvent: "UserPromptSubmit", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "Stop", conduitSubcommand: "stop"),
            ],
            feedHookEvents: ["PreToolUse", "PermissionRequest"]
        )
    }

    /// Cursor (`~/.cursor/hooks.json`), flat format.
    public static var cursor: AgentHookDef {
        AgentHookDef(
            name: "cursor",
            displayName: "Cursor",
            statusKey: "cursor",
            configDir: ".cursor",
            configFile: "hooks.json",
            sessionStoreSuffix: "cursor",
            disableEnvVar: "CONDUIT_CURSOR_HOOKS_DISABLED",
            hookMarker: "conduitd hooks cursor",
            format: .flat,
            events: [
                .init(agentEvent: "afterFileEdit", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "beforeShellExecution", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "stop", conduitSubcommand: "stop"),
            ],
            feedHookEvents: ["beforeShellExecution"]
        )
    }

    /// Grok (`~/.grok/hooks/cmux-session.json`), honours `GROK_HOME/hooks`.
    public static var grok: AgentHookDef {
        AgentHookDef(
            name: "grok",
            displayName: "Grok",
            statusKey: "grok",
            configDir: ".grok/hooks",
            configFile: "conduit-session.json",
            configDirEnvOverride: "GROK_HOME",
            configDirEnvOverrideSubpath: "hooks",
            createConfigDirIfMissing: true,
            sessionStoreSuffix: "grok",
            disableEnvVar: "CONDUIT_GROK_HOOKS_DISABLED",
            hookMarker: "conduitd hooks grok",
            format: .nested(timeoutMs: 5000),
            events: [
                .init(agentEvent: "SessionStart", conduitSubcommand: "session-start"),
                .init(agentEvent: "UserPromptSubmit", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "Stop", conduitSubcommand: "stop"),
                .init(agentEvent: "Notification", conduitSubcommand: "notification"),
                .init(agentEvent: "SessionEnd", conduitSubcommand: "session-end"),
            ],
            publishesStopNotification: false
        )
    }

    /// Gemini / Antigravity (`~/.gemini/config/hooks.json`).
    public static var gemini: AgentHookDef {
        AgentHookDef(
            name: "gemini",
            displayName: "Gemini",
            statusKey: "gemini",
            configDir: ".gemini/config",
            configFile: "hooks.json",
            createConfigDirIfMissing: true,
            sessionStoreSuffix: "gemini",
            disableEnvVar: "CONDUIT_GEMINI_HOOKS_DISABLED",
            hookMarker: "conduitd hooks gemini",
            format: .antigravityJSON(timeoutSeconds: 5),
            events: [
                .init(agentEvent: "session.start", conduitSubcommand: "session-start"),
                .init(agentEvent: "prompt.submit", conduitSubcommand: "prompt-submit"),
                .init(agentEvent: "session.end", conduitSubcommand: "session-end"),
            ],
            aliases: ["antigravity", "agy"]
        )
    }

    /// All Conduit-supported agent hook definitions.
    public static let defaults: [AgentHookDef] = [
        .claude,
        .codex,
        .cursor,
        .grok,
        .gemini,
    ]
}
