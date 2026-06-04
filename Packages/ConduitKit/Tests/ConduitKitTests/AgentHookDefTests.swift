import Foundation
import Testing
@testable import AgentKit

@Suite("AgentHookDef")
struct AgentHookDefTests {

    @Test("defaults cover Claude, Codex, OpenCode, Cursor, Grok, Gemini")
    func defaultsCoverAllSupportedAgents() {
        let names = Set(AgentHookDef.defaults.map(\.name))
        #expect(names == ["claude", "codex", "opencode", "cursor", "grok", "gemini"])
    }

    @Test("OpenCode resolves to ~/.config/opencode/hooks.json")
    func opencodeConfigPath() {
        let path = AgentHookDef.opencode.resolvedConfigPath(home: "/Users/me")
        #expect(path == "/Users/me/.config/opencode/hooks.json")
    }

    @Test("OpenCode uses nested format with approval feed hooks")
    func opencodeFormatAndFeedHooks() {
        if case .nested(let timeout) = AgentHookDef.opencode.format {
            #expect(timeout == 5000)
        } else {
            Issue.record("expected .nested format")
        }
        #expect(AgentHookDef.opencode.feedHookEvents.contains("PreToolUse"))
    }

    @Test("Claude resolves to ~/.claude/settings.json")
    func claudeConfigPath() {
        let path = AgentHookDef.claude.resolvedConfigPath(home: "/Users/me")
        #expect(path == "/Users/me/.claude/settings.json")
    }

    @Test("Codex honours CODEX_HOME env override")
    func codexHonoursEnvOverride() {
        let path = AgentHookDef.codex.resolvedConfigPath(
            home: "/Users/me",
            environment: ["CODEX_HOME": "/opt/codex"]
        )
        #expect(path == "/opt/codex/hooks.json")
    }

    @Test("Grok honours GROK_HOME + hooks subpath")
    func grokHonoursSubpath() {
        let path = AgentHookDef.grok.resolvedConfigPath(
            home: "/Users/me",
            environment: ["GROK_HOME": "/opt/grok"]
        )
        #expect(path == "/opt/grok/hooks/conduit-session.json")
    }

    @Test("Env override with ~ expands to home")
    func envOverrideTildeExpands() {
        let path = AgentHookDef.codex.resolvedConfigPath(
            home: "/Users/me",
            environment: ["CODEX_HOME": "~/custom"]
        )
        #expect(path == "/Users/me/custom/hooks.json")
    }

    @Test("AgentHookActions map round-trips canonical actions")
    func actionMapping() {
        #expect(AgentHookActions.action(for: "session-start") == .sessionStart)
        #expect(AgentHookActions.action(for: "notify") == .notification)
        #expect(AgentHookActions.action(for: "agent-response") == .stop)
        #expect(AgentHookActions.action(for: "unknown") == nil)
    }

    @Test("Claude has nested format with 5000ms timeout")
    func claudeFormatNested() {
        if case .nested(let timeout) = AgentHookDef.claude.format {
            #expect(timeout == 5000)
        } else {
            Issue.record("expected .nested format")
        }
    }

    @Test("Cursor uses flat format")
    func cursorFormatFlat() {
        #expect(AgentHookDef.cursor.format == .flat)
    }

    @Test("Feed hook events flagged for long-running approvals")
    func feedHookEventsPresent() {
        #expect(AgentHookDef.claude.feedHookEvents.contains("PreToolUse"))
        #expect(AgentHookDef.claude.feedHookEvents.contains("PermissionRequest"))
    }
}
