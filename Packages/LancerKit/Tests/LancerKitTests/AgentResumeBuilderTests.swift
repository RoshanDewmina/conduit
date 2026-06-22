import Foundation
import Testing
@testable import AgentKit

@Suite("AgentResumeBuilder")
struct AgentResumeBuilderTests {

    @Test("Claude resume command substitutes sessionId and cd's into cwd")
    func claudeResume() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInClaude,
            sessionId: "abc123",
            workingDirectory: "/home/me/proj"
        )
        #expect(cmd == "cd '/home/me/proj' && claude --resume abc123")
    }

    @Test("Codex resume uses 'resume' subcommand")
    func codexResume() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInCodex,
            sessionId: "sess-42",
            workingDirectory: nil
        )
        #expect(cmd == "codex resume sess-42")
    }

    @Test("Grok resume uses -r flag")
    func grokResume() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInGrok,
            sessionId: "xyz",
            workingDirectory: nil
        )
        #expect(cmd == "grok -r xyz")
    }

    @Test("workingDirectory with spaces gets shell-quoted")
    func cwdWithSpacesQuoted() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInClaude,
            sessionId: "id",
            workingDirectory: "/home/me/my project"
        )
        #expect(cmd == "cd '/home/me/my project' && claude --resume id")
    }

    @Test("sessionId with quotes gets safely escaped")
    func sessionIdWithSingleQuotes() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInClaude,
            sessionId: "weird'id",
            workingDirectory: nil
        )
        // The single quote must be escaped using the '\'' idiom
        #expect(cmd?.contains("'weird'\\''id'") == true)
    }

    @Test("empty sessionId returns nil")
    func emptySessionIdRejected() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: .builtInClaude,
            sessionId: "   ",
            workingDirectory: nil
        )
        #expect(cmd == nil)
    }

    @Test("cwd: .ignore drops the cd prefix")
    func cwdIgnoreDropsPrefix() {
        let agent = AgentRegistration(
            id: "test",
            name: "Test",
            detect: AgentDetectRule(processName: "test"),
            sessionIdSource: .argvOption("--id"),
            resumeCommand: "{{executable}} --id {{sessionId}}",
            cwd: .ignore
        )
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: agent,
            sessionId: "x",
            workingDirectory: "/should/be/ignored"
        )
        #expect(cmd == "test --id x")
    }

    @Test("environment vars produce env-prefix sorted by key")
    func environmentPrefix() {
        let cmd = AgentResumeBuilder.resumeShellCommand(
            AgentResumeContext(
                agent: .builtInClaude,
                sessionId: "id",
                workingDirectory: nil,
                environment: ["ANTHROPIC_API_KEY": "sk-xxx", "FOO": "bar"]
            )
        )
        // Keys sorted alphabetically, values single-quoted
        #expect(cmd == "env ANTHROPIC_API_KEY='sk-xxx' FOO='bar' claude --resume id")
    }

    @Test("sessionPath placeholder resolves from sessionDirectory + sessionId")
    func sessionPathResolves() {
        let agent = AgentRegistration(
            id: "test",
            name: "Test",
            detect: AgentDetectRule(processName: "test"),
            sessionIdSource: .argvOption("--id"),
            resumeCommand: "{{executable}} --file {{sessionPath}}",
            cwd: .ignore,
            sessionDirectory: "~/.test/sessions"
        )
        let cmd = AgentResumeBuilder.resumeShellCommand(
            agent: agent,
            sessionId: "abc"
        )
        #expect(cmd == "test --file '~/.test/sessions/abc'")
    }

    @Test("ShellQuoting handles non-ASCII via printf substitution")
    func nonASCIIQuoting() {
        let quoted = ShellQuoting.singleQuoted("café")
        #expect(quoted.hasPrefix("\"$(printf '"))
        #expect(quoted.hasSuffix("')\""))
    }
}
