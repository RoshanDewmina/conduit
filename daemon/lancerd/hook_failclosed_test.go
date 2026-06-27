package main

import (
	"errors"
	"fmt"
	"testing"
)

// agentHookUnreachable mirrors the dial-failure branch in runAgentHook (fail-closed).
func agentHookUnreachable(normalizedKind string, risk int, dialErr error) error {
	if dialErr == nil {
		return nil
	}
	if hookShouldHold(normalizedKind, risk) {
		return fmt.Errorf("lancerd resident not reachable (%v); mutating action held (fail-closed)", dialErr)
	}
	return nil
}

func TestHookMutatingDeniedWhenDaemonDown(t *testing.T) {
	t.Setenv("LANCER_HOOK_READONLY_FAIL_OPEN", "")
	dialErr := errors.New("connection refused")

	for _, kind := range []string{"patch", "fileWrite", "fileDelete", "network", "credential"} {
		nk := normalizeKind(kind)
		if err := agentHookUnreachable(nk, 0, dialErr); err == nil {
			t.Fatalf("kind %q must not auto-approve when daemon is unreachable", kind)
		}
	}
}

func TestCommandHookHeldWhenDaemonDown(t *testing.T) {
	t.Setenv("LANCER_HOOK_READONLY_FAIL_OPEN", "")
	dialErr := errors.New("connection refused")
	nk := normalizeKind("command")
	if err := agentHookUnreachable(nk, 0, dialErr); err == nil {
		t.Fatal("command must not auto-approve when daemon is unreachable")
	}
	if err := agentHookUnreachable(nk, 3, dialErr); err == nil {
		t.Fatal("critical command must not auto-approve when daemon is unreachable")
	}
}
