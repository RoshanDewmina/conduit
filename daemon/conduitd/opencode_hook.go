package main

import (
	"encoding/json"
	"os"
	"strings"
)

// opencodePreToolUsePayload is the stdin JSON OpenCode sends for PreToolUse hooks
// (Claude-compatible shape; see anomalyco/opencode#12472).
type opencodePreToolUsePayload struct {
	SessionID     string          `json:"session_id"`
	CWD           string          `json:"cwd"`
	HookEventName string          `json:"hook_event_name"`
	ToolName      string          `json:"tool_name"`
	ToolUseID     string          `json:"tool_use_id"`
	ToolInput     json.RawMessage `json:"tool_input"`
}

// approvalEventFromOpencodeFixture maps a captured OpenCode hook payload to the
// ApprovalEvent conduitd forwards to the iOS inbox (same path as agent-hook).
func approvalEventFromOpencodeFixture(payload opencodePreToolUsePayload) ApprovalEvent {
	command := opencodeCommandFromPayload(payload)
	kind := normalizeKind(opencodeKindForTool(payload.ToolName))
	patch := ""
	if kind == "patch" {
		patch = command
	}
	cwd := strings.TrimSpace(payload.CWD)
	if cwd == "" {
		cwd = "/"
	}
	toolInput := strings.TrimSpace(string(payload.ToolInput))
	return ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      "opencode",
		Kind:       kind,
		Command:    command,
		Patch:      patch,
		CWD:        cwd,
		Risk:       opencodeRiskForTool(payload.ToolName, command),
		Timestamp:  "2026-01-01T00:00:00Z",
		ToolName:   payload.ToolName,
		ToolUseID:  payload.ToolUseID,
		SessionID:  payload.SessionID,
		ToolInput:  toolInput,
	}
}

func opencodeCommandFromPayload(payload opencodePreToolUsePayload) string {
	var input map[string]interface{}
	if len(payload.ToolInput) > 0 {
		_ = json.Unmarshal(payload.ToolInput, &input)
	}
	if cmd, ok := input["command"].(string); ok && cmd != "" {
		return cmd
	}
	if path, ok := input["file_path"].(string); ok && path != "" {
		return path
	}
	if path, ok := input["path"].(string); ok && path != "" {
		return path
	}
	if payload.ToolName != "" {
		return payload.ToolName
	}
	return "unknown"
}

func opencodeKindForTool(tool string) string {
	switch strings.ToLower(strings.TrimSpace(tool)) {
	case "bash":
		return "command"
	case "edit", "write", "multiedit", "apply_patch", "patch":
		return "patch"
	default:
		return "command"
	}
}

func opencodeRiskForTool(tool, command string) int {
	switch strings.ToLower(strings.TrimSpace(tool)) {
	case "bash":
		return riskToInt("high")
	}
	if strings.Contains(strings.ToLower(command), "rm -rf") {
		return riskToInt("critical")
	}
	return riskToInt("low")
}

func loadOpencodeFixture(path string) (opencodePreToolUsePayload, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return opencodePreToolUsePayload{}, err
	}
	var payload opencodePreToolUsePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return opencodePreToolUsePayload{}, err
	}
	return payload, nil
}
