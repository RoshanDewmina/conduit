package main

import "strings"

// normalizeAgentSource maps incoming hook agent values to canonical IDs used
// across conduitd and the iOS app protocol.
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
	case "cursor", "cursor-agent", "cursor-cli":
		// Placeholder for upcoming Cursor hook integration.
		return "cursor"
	case "gemini", "google-gemini":
		return "gemini"
	case "opencode", "open-code", "sst-opencode":
		return "opencode"
	default:
		return strings.TrimSpace(agent)
	}
}
