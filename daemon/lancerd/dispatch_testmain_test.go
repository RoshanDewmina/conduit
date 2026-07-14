package main

import (
	"context"
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	// Avoid shelling out to live `claude auth status` from dispatch/status unit
	// tests. Tests that exercise the probe set claudeAuthRunnerForPkg / 
	// d.claudeAuthPreflight explicitly.
	claudeAuthPreflightDisabledForTest = true
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":true}`), nil
	}
	os.Exit(m.Run())
}
