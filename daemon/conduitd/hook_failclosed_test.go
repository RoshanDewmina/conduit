package main

import (
	"errors"
	"fmt"
	"testing"
)

// agentHookUnreachable mirrors the dial-failure branch in runAgentHook (fail-closed).
func agentHookUnreachable(normalizedKind string, dialErr error) error {
	if dialErr == nil {
		return nil
	}
	if hookShouldHold(normalizedKind) {
		return fmt.Errorf("conduitd resident not reachable (%v); mutating action held (fail-closed)", dialErr)
	}
	return nil
}

func TestHookMutatingDeniedWhenDaemonDown(t *testing.T) {
	t.Setenv("CONDUIT_HOOK_READONLY_FAIL_OPEN", "")
	dialErr := errors.New("connection refused")

	for _, kind := range []string{"patch", "fileWrite", "fileDelete", "network", "credential"} {
		nk := normalizeKind(kind)
		if err := agentHookUnreachable(nk, dialErr); err == nil {
			t.Fatalf("kind %q must not auto-approve when daemon is unreachable", kind)
		}
	}
}

func TestCommandHookFailOpenWhenDaemonDown(t *testing.T) {
	t.Setenv("CONDUIT_HOOK_READONLY_FAIL_OPEN", "")
	dialErr := errors.New("connection refused")
	nk := normalizeKind("command")
	if err := agentHookUnreachable(nk, dialErr); err != nil {
		t.Fatalf("command should fail-open when daemon down, got %v", err)
	}
}
