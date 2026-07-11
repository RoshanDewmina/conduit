package main

import (
	"errors"
	"testing"
	"time"

	"lancer/lancerd/policy"
)

// Seam cases for the permission matrix that live outside policy.Evaluate:
// timeout → deny (waitWithTimeout) and daemon-unreachable → mutating blocked
// (hookShouldHold). Vendors are listed so the matrix shape stays per-vendor ×
// outcome even though these helpers are agent-agnostic.

var matrixSeamVendors = []string{"claudeCode", "codex", "opencode", "kimi"}

func TestPermissionMatrixTimeoutDenies(t *testing.T) {
	for _, vendor := range matrixSeamVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			ch := make(chan hookDecision)
			got, ok := waitWithTimeout(ch, 5*time.Millisecond)
			if ok {
				t.Fatalf("%s: timeout must report !ok (no decision received)", vendor)
			}
			if got.decision != "deny" {
				t.Fatalf("%s: timeout must synthesize deny, got %q", vendor, got.decision)
			}
		})
	}
}

func TestPermissionMatrixUnreachableMutatingBlocked(t *testing.T) {
	t.Setenv("LANCER_HOOK_READONLY_FAIL_OPEN", "")
	dialErr := errors.New("connection refused")
	mutating := []string{"command", "patch", "fileWrite", "fileDelete", "network", "credential"}

	for _, vendor := range matrixSeamVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			for _, kind := range mutating {
				nk := normalizeKind(kind)
				if err := agentHookUnreachable(nk, 0, dialErr); err == nil {
					t.Fatalf("%s/%s: mutating action must block when daemon unreachable", vendor, kind)
				}
				if !hookShouldHold(nk, 0) {
					t.Fatalf("%s/%s: hookShouldHold must be true for mutating kind", vendor, kind)
				}
			}
		})
	}
}

func TestPermissionMatrixUnreachableHighRiskNoGrace(t *testing.T) {
	// Cross-check: high/critical risk must not be eligible for the no-client
	// auto-approve grace — unreachable stays held for those bands.
	for _, vendor := range matrixSeamVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			if policy.PermitsNoClientGrace(2) {
				t.Fatalf("%s: high risk must not permit no-client grace", vendor)
			}
			if policy.PermitsNoClientGrace(3) {
				t.Fatalf("%s: critical risk must not permit no-client grace", vendor)
			}
		})
	}
}
