package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestZeroOutputExit1SurfacesStderrInErrorMessage is the A3 regression:
// a vendor CLI that prints a real error to stderr and exits 1 with no stdout
// must leave that stderr text on the turn's error_message — not the bare
// "Run failed with exit code 1". Drives realLauncher → emitNotification →
// conversation ledger, the same path launchConversationTurn uses in production.
//
// streamOutputHold forces readers to start after cmd.Wait returns — the exact
// race where StdoutPipe/StderrPipe used to discard unread stderr (Wait closes
// those readers) and status persisted the generic exit-code fallback.
func TestZeroOutputExit1SurfacesStderrInErrorMessage(t *testing.T) {
	stateDir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", stateDir)

	binDir := t.TempDir()
	fakeClaude := filepath.Join(binDir, "claude")
	// Absolute-path fake vendor binary: stderr-only failure, no stream-JSON.
	script := "#!/bin/sh\nprintf '%s\\n' 'Invalid API key' >&2\nexit 1\n"
	if err := os.WriteFile(fakeClaude, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake claude: %v", err)
	}

	hold := make(chan struct{})
	streamOutputHold = hold
	t.Cleanup(func() {
		streamOutputHold = nil
		select {
		case <-hold:
		default:
			close(hold)
		}
	})

	s, conversationID, runID := newLedgerBackedTestServer(t)

	if _, err := realLauncher([]string{fakeClaude}, t.TempDir(), runID, s.emitNotification); err != nil {
		t.Fatalf("launch: %v", err)
	}

	// Release readers shortly after the process exits so a correct
	// drain-before-status + non-Wait-closed pipes implementation can still
	// surface stderr. The broken StdoutPipe+status-before-drain path recorded
	// the generic exit-code message with zero output events.
	time.AfterFunc(100*time.Millisecond, func() {
		select {
		case <-hold:
		default:
			close(hold)
		}
	})

	deadline := time.Now().Add(5 * time.Second)
	var errMsg string
	for {
		fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
		if err != nil {
			t.Fatalf("fetch: %v", err)
		}
		if len(fetchRes.Turns) == 1 && fetchRes.Turns[0].Status == "failed" {
			errMsg = fetchRes.Turns[0].ErrorMessage
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for failed turn; turns=%+v", fetchRes.Turns)
		}
		time.Sleep(10 * time.Millisecond)
	}

	if errMsg == "" {
		t.Fatal("error_message is empty; want stderr text")
	}
	if errMsg == "Run failed with exit code 1" {
		t.Fatalf("error_message is the generic exit-code fallback %q; want stderr text", errMsg)
	}
	if !strings.Contains(errMsg, "Invalid API key") {
		t.Fatalf("error_message = %q, want it to contain %q", errMsg, "Invalid API key")
	}
}
