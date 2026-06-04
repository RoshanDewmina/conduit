package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"
)

// runAgentHook is called by `conduitd agent-hook` from an agent pre-tool hook.
// It sends an approval event to the running conduitd serve process and waits for
// the user's decision on their phone.
//
// Exit codes (agent hook convention):
//
//	0 = approved — the tool call may proceed
//	1 = denied / error — the tool call must be blocked
func runAgentHook(args []string) error {
	fs := flag.NewFlagSet("agent-hook", flag.ContinueOnError)
	agent := fs.String("agent", "", "agent name (e.g. claudeCode|codex)")
	kind := fs.String("kind", "command", "tool kind (command|patch|fileWrite|...)")
	command := fs.String("command", "", "command or path being executed")
	cwd := fs.String("cwd", "", "current working directory")
	risk := fs.String("risk", "low", "risk band: low|medium|high")
	timeout := fs.Duration("timeout", 120*time.Second, "max wait for decision")
	// Structured tool-use fields from Claude Code / Codex PreToolUse hooks.
	toolName := fs.String("tool-name", "", "structured tool name from tool_use (e.g. bash, write_file)")
	toolUseID := fs.String("tool-use-id", "", "tool_use_id from the agent session")
	sessionID := fs.String("session-id", "", "agent session ID")
	toolInput := fs.String("tool-input", "", "raw JSON tool_input from tool_use")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *command == "" {
		return errors.New("--command is required")
	}
	if *cwd == "" {
		if wd, err := os.Getwd(); err == nil {
			*cwd = wd
		}
	}

	normalizedKind := normalizeKind(*kind)
	patch := ""
	if normalizedKind == "patch" {
		patch = *command
	}

	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(*agent),
		Kind:       normalizedKind,
		Command:    *command,
		Patch:      patch,
		CWD:        *cwd,
		Risk:       riskToInt(*risk),
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		ToolName:   *toolName,
		ToolUseID:  *toolUseID,
		SessionID:  *sessionID,
		ToolInput:  *toolInput,
	}

	sockPath, err := socketPath()
	if err != nil {
		return fmt.Errorf("socket path: %w", err)
	}

	conn, err := net.DialTimeout("unix", sockPath, 5*time.Second)
	if err != nil {
		if hookShouldHold(normalizedKind, event.Risk) {
			return fmt.Errorf("conduitd resident not reachable (%v); mutating action held (fail-closed)", err)
		}
		fmt.Fprintf(os.Stderr, "conduitd not running (%v); read-only fail-open (CONDUIT_HOOK_READONLY_FAIL_OPEN=1)\n", err)
		return nil
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(*timeout + 10*time.Second))

	if err := json.NewEncoder(conn).Encode(event); err != nil {
		return fmt.Errorf("send event: %w", err)
	}

	var decision ApprovalDecision
	if err := json.NewDecoder(conn).Decode(&decision); err != nil {
		return fmt.Errorf("read decision: %w", err)
	}

	if decision.Decision != "approve" && decision.Decision != "approveAlways" {
		return fmt.Errorf("denied by user")
	}
	return nil
}

// newUUID returns a random UUID v4 string using crypto/rand.
func newUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return hex.EncodeToString(b[0:4]) + "-" +
		hex.EncodeToString(b[4:6]) + "-" +
		hex.EncodeToString(b[6:8]) + "-" +
		hex.EncodeToString(b[8:10]) + "-" +
		hex.EncodeToString(b[10:])
}

func riskToInt(r string) int {
	switch r {
	case "medium", "1":
		return 1
	case "high", "2":
		return 2
	case "critical", "3":
		return 3
	default:
		return 0
	}
}

func normalizeKind(kind string) string {
	switch kind {
	case "bash", "Bash", "shell", "command":
		return "command"
	case "edit", "multiedit":
		return "patch"
	case "apply_patch", "Patch", "patch", "Edit", "Write", "MultiEdit", "write":
		return "patch"
	case "file-write", "file_write", "fileWrite":
		return "fileWrite"
	case "delete", "file-delete", "file_delete", "fileDelete":
		return "fileDelete"
	case "network":
		return "network"
	case "credential":
		return "credential"
	case "browser":
		return "browser"
	default:
		return kind
	}
}

// hookShouldHold returns true when the hook must block (exit 1) because the resident daemon is down.
// Mutating tool kinds (including command/bash) always hold. Read-only kinds fail-open only when
// CONDUIT_HOOK_READONLY_FAIL_OPEN=1. Critical risk always holds regardless of kind.
func hookShouldHold(kind string, risk int) bool {
	if risk >= 3 {
		return true
	}
	if isReadOnlyKind(kind) && os.Getenv("CONDUIT_HOOK_READONLY_FAIL_OPEN") == "1" {
		return false
	}
	return isMutatingKind(kind)
}

func isMutatingKind(kind string) bool {
	switch kind {
	case "read", "grep", "list", "search":
		return false
	default:
		return true
	}
}

func isReadOnlyKind(kind string) bool {
	switch kind {
	case "read", "grep", "list", "search":
		return true
	default:
		return false
	}
}

func init() {
	home, _ := os.UserHomeDir()
	_ = os.MkdirAll(filepath.Join(home, ".conduit"), 0700)
}
