// Adapted from cmux (MIT) — Sources/RestorableAgentSession.swift
// (specifically AgentResumeCommandBuilder + TerminalStartupShellQuoting).
//
// cmux's full builder handles many launcher-fork variants (claude-teams,
// codex-teams, omo, omx, omc) that are internal to cmux's macOS shipping
// — Conduit doesn't ship those forks, so this is a leaner adaptation:
// take an `AgentRegistration`, substitute `{{sessionId}}`,
// `{{sessionPath}}`, `{{executable}}`, `{{cwd}}` placeholders in its
// resumeCommand template, shell-quote inputs, and optionally `cd` into
// the recorded working directory first. The shell-quoting helper is a
// near-verbatim port (the algorithm is correct and well-tested).

import Foundation

// MARK: - Shell quoting (verbatim port from cmux)

/// POSIX-shell-safe quoting helpers used when building remote command strings.
/// Single-quoting handles every byte except embedded single quotes (which we
/// escape via the `'\''` idiom). Non-ASCII bytes go through `printf '\xxx'`
/// to avoid locale ambiguity over SSH.
public enum ShellQuoting {
    /// Always wraps `value` in single quotes; safe for any input.
    public static func singleQuoted(_ value: String) -> String {
        if value.utf8.contains(where: { $0 >= 0x80 }) {
            return asciiPrintfCommandSubstitution(for: value)
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Returns `value` bare if it only contains shell-safe ASCII; otherwise
    /// wraps with single quotes. Useful for readable command strings where
    /// most tokens don't need quoting.
    public static func shellToken(_ value: String, allowingBareASCII: Bool = true) -> String {
        if value.utf8.contains(where: { $0 >= 0x80 }) {
            return asciiPrintfCommandSubstitution(for: value)
        }
        if allowingBareASCII,
           value.range(of: "[^A-Za-z0-9_./:=+-]", options: .regularExpression) == nil {
            return value
        }
        return singleQuoted(value)
    }

    private static func asciiPrintfCommandSubstitution(for value: String) -> String {
        let octalBytes = value.utf8
            .map { String(format: #"\%03o"#, Int($0)) }
            .joined()
        return #""$(printf '"# + octalBytes + #"')""#
    }
}

// MARK: - Resume builder

/// Inputs to a resume-command build. `sessionId` is required; the rest are
/// optional and consumed only if the template references them.
public struct AgentResumeContext: Hashable, Sendable {
    public let agent: AgentRegistration
    public let sessionId: String
    public let sessionPath: String?
    public let workingDirectory: String?
    public let environment: [String: String]

    public init(
        agent: AgentRegistration,
        sessionId: String,
        sessionPath: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.sessionPath = sessionPath
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// Builds the shell command string used to resume an agent session on a remote
/// host. Returns `nil` when the context is invalid (e.g. empty session id,
/// template missing required placeholder).
///
/// **Template placeholders supported:**
/// - `{{sessionId}}` — required by `AgentRegistration` decoder; the live session ID
/// - `{{sessionPath}}` — full path to the session file/directory (e.g.
///   `~/.claude/projects/<id>.jsonl`); resolved from `sessionDirectory + sessionId` when not provided
/// - `{{executable}}` — the agent's launcher binary (`agent.defaultExecutable`)
/// - `{{cwd}}` — the recorded working directory; empty when `cwd == .ignore`
///
/// **Working-directory prefix:** when `agent.cwd == .preserve` and a
/// `workingDirectory` is supplied, the result is prefixed with
/// `cd '<dir>' && `. Disable per call via `includeWorkingDirectoryPrefix: false`.
///
/// **Environment:** when `environment` is non-empty, the result is prefixed
/// with `env KEY1='VAL1' KEY2='VAL2' …` (keys sorted for determinism).
public enum AgentResumeBuilder {

    public static func resumeShellCommand(
        _ context: AgentResumeContext,
        includeWorkingDirectoryPrefix: Bool = true
    ) -> String? {
        let trimmedSessionID = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionID.isEmpty else { return nil }

        let executable = context.agent.defaultExecutable
        let resolvedSessionPath = context.sessionPath ?? defaultSessionPath(
            agent: context.agent,
            sessionId: trimmedSessionID
        )
        let resolvedCWD: String? = {
            switch context.agent.cwd {
            case .preserve: return context.workingDirectory
            case .ignore: return nil
            }
        }()

        // Template substitution. Quote each value as a shell token so the
        // template author doesn't have to think about escaping.
        var rendered = context.agent.resumeCommand
        rendered = rendered.replacingOccurrences(
            of: "{{sessionId}}",
            with: ShellQuoting.shellToken(trimmedSessionID)
        )
        if rendered.contains("{{sessionPath}}") {
            guard let resolvedSessionPath else { return nil }
            rendered = rendered.replacingOccurrences(
                of: "{{sessionPath}}",
                with: ShellQuoting.shellToken(resolvedSessionPath)
            )
        }
        rendered = rendered.replacingOccurrences(
            of: "{{executable}}",
            with: ShellQuoting.shellToken(executable)
        )
        rendered = rendered.replacingOccurrences(
            of: "{{cwd}}",
            with: resolvedCWD.map { ShellQuoting.shellToken($0) } ?? ""
        )

        // Environment prefix.
        var commandPrefix = ""
        if !context.environment.isEmpty {
            let envParts = context.environment.keys.sorted().map { key -> String in
                let value = context.environment[key] ?? ""
                return "\(key)=\(ShellQuoting.singleQuoted(value))"
            }
            commandPrefix = "env " + envParts.joined(separator: " ") + " "
        }

        var final = commandPrefix + rendered

        // Working-directory prefix.
        if includeWorkingDirectoryPrefix,
           let cwd = resolvedCWD,
           !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            final = "cd \(ShellQuoting.singleQuoted(cwd)) && \(final)"
        }

        return final
    }

    /// Convenience overload used widely in the codebase.
    public static func resumeShellCommand(
        agent: AgentRegistration,
        sessionId: String,
        workingDirectory: String? = nil
    ) -> String? {
        resumeShellCommand(
            AgentResumeContext(
                agent: agent,
                sessionId: sessionId,
                workingDirectory: workingDirectory
            )
        )
    }

    // MARK: - Helpers

    private static func defaultSessionPath(agent: AgentRegistration, sessionId: String) -> String? {
        guard let directory = agent.sessionDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !directory.isEmpty else { return nil }
        let normalizedDir = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return "\(normalizedDir)/\(sessionId)"
    }
}
