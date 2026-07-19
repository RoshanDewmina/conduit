package main

import "strings"

// normalizeAgentSource maps incoming hook agent values to canonical IDs used
// across lancerd and the iOS app protocol.
func normalizeAgentSource(agent string) string {
	normalized := strings.ToLower(strings.TrimSpace(agent))
	normalized = strings.ReplaceAll(normalized, "_", "-")

	switch normalized {
	case "", "unknown":
		return "unknown"
	case "claude", "claude-code", "claudecode":
		return "claudeCode"
	case "codex", "openai-codex":
		return "codex"
	case "cursor", "cursor-agent", "cursor-cli", "agent":
		// Cursor Agent CLI (`agent` / `cursor-agent`); dispatch via agentArgv.
		return "cursor"
	case "gemini", "google-gemini":
		return "gemini"
	case "kimi", "kimi-code", "kimicode":
		return "kimi"
	case "opencode", "open-code", "sst-opencode":
		return "opencode"
	case "pi", "pi-coding-agent", "earendil-pi":
		return "pi"
	case "copilot", "github-copilot":
		return "copilot"
	default:
		return strings.TrimSpace(agent)
	}
}
