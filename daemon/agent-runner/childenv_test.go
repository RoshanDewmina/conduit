package main

import (
	"os"
	"strings"
	"testing"
)

// envMap collapses an env slice to a map, honoring last-wins semantics like the OS.
func envMap(pairs []string) map[string]string {
	m := map[string]string{}
	for _, p := range pairs {
		if i := strings.IndexByte(p, '='); i >= 0 {
			m[p[:i]] = p[i+1:]
		}
	}
	return m
}

// With an OpenRouter key, the agent child env must route the Claude Code CLI through
// OpenRouter's Anthropic skin: ANTHROPIC_BASE_URL (no /v1), ANTHROPIC_AUTH_TOKEN=key,
// and ANTHROPIC_API_KEY explicitly empty.
func TestAgentChildEnv_OpenRouterWiring(t *testing.T) {
	t.Setenv("LANCER_MODEL", "anthropic/claude-3.5-sonnet")
	t.Setenv("LANCER_OPENROUTER_KEY", "sk-or-test123")
	t.Setenv("LANCER_OPENROUTER_BASE_URL", "")

	m := envMap(agentChildEnv())

	if m["ANTHROPIC_BASE_URL"] != "https://openrouter.ai/api" {
		t.Errorf("ANTHROPIC_BASE_URL = %q, want https://openrouter.ai/api (no /v1)", m["ANTHROPIC_BASE_URL"])
	}
	if strings.HasSuffix(m["ANTHROPIC_BASE_URL"], "/v1") {
		t.Error("ANTHROPIC_BASE_URL must NOT end in /v1 for the OpenRouter Anthropic skin")
	}
	if m["ANTHROPIC_AUTH_TOKEN"] != "sk-or-test123" {
		t.Errorf("ANTHROPIC_AUTH_TOKEN = %q, want the OpenRouter key", m["ANTHROPIC_AUTH_TOKEN"])
	}
	if v, ok := m["ANTHROPIC_API_KEY"]; !ok || v != "" {
		t.Errorf("ANTHROPIC_API_KEY must be present and empty, got ok=%v val=%q", ok, v)
	}
	if m["OPENROUTER_API_KEY"] != "sk-or-test123" {
		t.Errorf("OPENROUTER_API_KEY = %q, want the key", m["OPENROUTER_API_KEY"])
	}
	if m["ANTHROPIC_MODEL"] != "anthropic/claude-3.5-sonnet" {
		t.Errorf("ANTHROPIC_MODEL = %q, want the configured model", m["ANTHROPIC_MODEL"])
	}
}

// A custom base URL override is honored.
func TestAgentChildEnv_BaseURLOverride(t *testing.T) {
	t.Setenv("LANCER_OPENROUTER_KEY", "sk-or-x")
	t.Setenv("LANCER_OPENROUTER_BASE_URL", "https://proxy.internal/api")
	m := envMap(agentChildEnv())
	if m["ANTHROPIC_BASE_URL"] != "https://proxy.internal/api" {
		t.Errorf("ANTHROPIC_BASE_URL = %q, want the override", m["ANTHROPIC_BASE_URL"])
	}
}

// With no OpenRouter key, no Anthropic auth vars are emitted (nothing to route).
func TestAgentChildEnv_NoKey(t *testing.T) {
	os.Unsetenv("LANCER_OPENROUTER_KEY")
	t.Setenv("LANCER_MODEL", "")
	m := envMap(agentChildEnv())
	for _, k := range []string{"ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "OPENROUTER_API_KEY"} {
		if _, ok := m[k]; ok {
			t.Errorf("%s must not be set when no OpenRouter key is provided", k)
		}
	}
}
