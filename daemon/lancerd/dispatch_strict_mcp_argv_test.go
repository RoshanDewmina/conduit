package main

import (
	"slices"
	"testing"
)

// Regression: a claudeCode conversation turn must launch with
// --strict-mcp-config + an empty --mcp-config so it doesn't pay for loading
// this project's dev-tooling MCP servers (or the operator's personal/global
// remote connectors) on every phone-dispatched chat turn. Measured
// 2026-07-14: those MCP tool schemas were the largest controllable component
// of the system prompt driving a cold-cache first-token latency of ~10s for
// a plain "Hi" (see claudeStrictMCPArgs's doc comment in dispatch.go for the
// full before/after numbers). This must hold for the fresh (agentArgv),
// continue (continueArgv), and exact-resume (resumeArgv) launch shapes alike,
// and must NEVER disturb the trailing "-p", prompt pair that
// claudeStdinPromptArgv depends on (see dispatch_model_argv_test.go).
func TestClaudeArgvUsesStrictMCPConfig(t *testing.T) {
	assertStrictMCP := func(t *testing.T, label string, argv []string, ok bool) {
		t.Helper()
		if !ok {
			t.Fatalf("%s: expected ok=true", label)
		}
		i := slices.Index(argv, "--strict-mcp-config")
		if i < 0 {
			t.Fatalf("%s: missing --strict-mcp-config in %v", label, argv)
		}
		j := slices.Index(argv, "--mcp-config")
		if j < 0 || j+1 >= len(argv) {
			t.Fatalf("%s: missing --mcp-config value in %v", label, argv)
		}
		if got := argv[j+1]; got != `{"mcpServers":{}}` {
			t.Fatalf("%s: --mcp-config = %q, want empty mcpServers object", label, got)
		}
		// The strict-MCP flags must never displace the trailing "-p", prompt
		// pair claudeStdinPromptArgv depends on.
		if argv[len(argv)-2] != "-p" {
			t.Fatalf("%s: -p not trailing after strict-MCP flags: %v", label, argv)
		}
	}

	fresh, ok := agentArgv("claudeCode", "Hi", "haiku", false)
	assertStrictMCP(t, "agentArgv", fresh, ok)

	cont, ok := continueArgv("claudeCode", "next", "haiku", false)
	assertStrictMCP(t, "continueArgv", cont, ok)

	res, ok := resumeArgv("claudeCode", "sess-123", "next", "haiku", false)
	assertStrictMCP(t, "resumeArgv", res, ok)

	// Non-claudeCode vendors must be untouched: no strict-mcp-config flag was
	// ever requested or verified for their CLIs, and the fix is explicitly
	// scoped to claudeCode only.
	for _, agent := range []string{"codex", "kimi", "opencode"} {
		argv, ok := agentArgv(agent, "hi", "", false)
		if !ok {
			t.Fatalf("agentArgv(%q) should be supported", agent)
		}
		if slices.Contains(argv, "--strict-mcp-config") {
			t.Fatalf("agent %q must not gain --strict-mcp-config: %v", agent, argv)
		}
	}
}

// Regression: fullTools=true (the phone composer's per-dispatch "Full tools"
// opt-in) must OMIT claudeStrictMCPArgs entirely for all three launch shapes
// — the whole point of the toggle is to let a real coding dispatch keep
// XcodeBuildMCP/apple-docs/context7 for that one turn — while still never
// disturbing the trailing "-p", prompt pair claudeStdinPromptArgv depends on,
// and never leaking onto non-claudeCode vendors (which ignore the flag).
func TestClaudeArgvFullToolsOmitsStrictMCPConfig(t *testing.T) {
	assertNoStrictMCP := func(t *testing.T, label string, argv []string, ok bool) {
		t.Helper()
		if !ok {
			t.Fatalf("%s: expected ok=true", label)
		}
		if slices.Contains(argv, "--strict-mcp-config") {
			t.Fatalf("%s: fullTools=true must omit --strict-mcp-config: %v", label, argv)
		}
		if slices.Contains(argv, "--mcp-config") {
			t.Fatalf("%s: fullTools=true must omit --mcp-config: %v", label, argv)
		}
		if argv[len(argv)-2] != "-p" {
			t.Fatalf("%s: -p not trailing with fullTools=true: %v", label, argv)
		}
	}

	fresh, ok := agentArgv("claudeCode", "Hi", "haiku", true)
	assertNoStrictMCP(t, "agentArgv", fresh, ok)

	cont, ok := continueArgv("claudeCode", "next", "haiku", true)
	assertNoStrictMCP(t, "continueArgv", cont, ok)

	res, ok := resumeArgv("claudeCode", "sess-123", "next", "haiku", true)
	assertNoStrictMCP(t, "resumeArgv", res, ok)

	// A non-claudeCode vendor must never gain --strict-mcp-config regardless
	// of fullTools — it's a claudeCode-only concept, ignored elsewhere.
	for _, agent := range []string{"codex", "kimi", "opencode"} {
		argv, ok := agentArgv(agent, "hi", "", true)
		if !ok {
			t.Fatalf("agentArgv(%q) should be supported", agent)
		}
		if slices.Contains(argv, "--strict-mcp-config") {
			t.Fatalf("agent %q must not gain --strict-mcp-config: %v", agent, argv)
		}
	}
}

// Regression: buildConversationArgv (the conversation-append dispatch path,
// which is what a phone chat turn actually calls) must carry the same
// strict-MCP flags through all three resume-mode branches (new/exact/
// latestInCwdFallback) since it delegates to agentArgv/resumeArgv/
// continueArgv respectively.
func TestBuildConversationArgvUsesStrictMCPConfig(t *testing.T) {
	newArgv, _, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "Hi", Model: "haiku", IsNew: true,
	})
	if !ok || !slices.Contains(newArgv, "--strict-mcp-config") {
		t.Fatalf("new-conversation argv missing --strict-mcp-config: %v (ok=%v)", newArgv, ok)
	}

	exactArgv, _, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", Model: "haiku", VendorSessionID: "sess-abc",
	})
	if !ok || !slices.Contains(exactArgv, "--strict-mcp-config") {
		t.Fatalf("exact-resume argv missing --strict-mcp-config: %v (ok=%v)", exactArgv, ok)
	}

	fallbackArgv, _, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", Model: "haiku",
	})
	if !ok || !slices.Contains(fallbackArgv, "--strict-mcp-config") {
		t.Fatalf("continue-fallback argv missing --strict-mcp-config: %v (ok=%v)", fallbackArgv, ok)
	}
}

// Regression: buildConversationArgv with FullTools:true must OMIT
// --strict-mcp-config for all three resume-mode branches — the per-dispatch
// toggle threaded straight from conversationAppendRequest.FullTools
// (conversation_store.go) through conversationLaunchParams, never re-derived.
func TestBuildConversationArgvFullToolsOmitsStrictMCPConfig(t *testing.T) {
	newArgv, mode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "Hi", Model: "haiku", IsNew: true, FullTools: true,
	})
	if !ok || mode != "new" || slices.Contains(newArgv, "--strict-mcp-config") {
		t.Fatalf("new-conversation argv should omit --strict-mcp-config with FullTools:true: %v (ok=%v mode=%s)", newArgv, ok, mode)
	}

	exactArgv, mode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", Model: "haiku", VendorSessionID: "sess-abc", FullTools: true,
	})
	if !ok || mode != "exact" || slices.Contains(exactArgv, "--strict-mcp-config") {
		t.Fatalf("exact-resume argv should omit --strict-mcp-config with FullTools:true: %v (ok=%v mode=%s)", exactArgv, ok, mode)
	}

	fallbackArgv, mode, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "next", Model: "haiku", FullTools: true,
	})
	if !ok || mode != "latestInCwdFallback" || slices.Contains(fallbackArgv, "--strict-mcp-config") {
		t.Fatalf("continue-fallback argv should omit --strict-mcp-config with FullTools:true: %v (ok=%v mode=%s)", fallbackArgv, ok, mode)
	}

	// FullTools:false (the default zero value, matching an omitted wire field)
	// must still be strict — no regression to the existing default behavior.
	defaultArgv, _, ok := buildConversationArgv(conversationLaunchParams{
		Agent: "claudeCode", Prompt: "Hi", Model: "haiku", IsNew: true,
	})
	if !ok || !slices.Contains(defaultArgv, "--strict-mcp-config") {
		t.Fatalf("FullTools omitted (zero value) should default to strict: %v (ok=%v)", defaultArgv, ok)
	}
}
