package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// stopLatchFile is the on-disk shape persisted at <home>/.lancer/emergency_stop.json
// (mode 0600) — the durable record that Emergency Stop was triggered.
type stopLatchFile struct {
	Active bool   `json:"active"`
	At     string `json:"at,omitempty"`
}

// emergencyStopLatch is the durable mirror of dispatcher.emergencyStopped.
// The in-memory bool stays the hot-path source of truth (checked on every
// dispatch/continue/hook call); this file exists solely so that bool can be
// reconstructed at startup — otherwise a daemon restart after a stop would
// silently un-stop everything, and a PreToolUse hook process that was still
// polling when the daemon restarted would get approved instead of denied.
//
// The latch clears only via an explicit agent.emergencyStop.clear RPC
// (server.clearEmergencyStop) — never implicitly on the next dispatch. An
// implicit clear would mean the very next automated dispatch call silently
// re-arms everything the stop was meant to interrupt, which defeats the
// "must pause, never silently resolve" fail-closed intent the rest of the
// approval path already follows (see handleHookWithNotify's doc comment).
type emergencyStopLatch struct {
	mu   sync.Mutex
	path string
}

func newEmergencyStopLatch(home string) *emergencyStopLatch {
	return &emergencyStopLatch{path: filepath.Join(home, ".lancer", "emergency_stop.json")}
}

// load reports whether the latch was left active by a prior process (or this
// one, earlier). Any read/parse failure (including "file does not exist", the
// common case) is treated as inactive — the latch is a fail-closed *addition*
// on top of the existing approval/policy fail-closed defaults, not itself a
// new single point of failure.
func (l *emergencyStopLatch) load() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	data, err := os.ReadFile(l.path)
	if err != nil {
		return false
	}
	var f stopLatchFile
	if err := json.Unmarshal(data, &f); err != nil {
		return false
	}
	return f.Active
}

// set persists the latch state. Called with true from applyEmergencyStop
// (before anything else, so the fail-closed record lands even if the process
// dies mid-stop) and with false from clearEmergencyStop.
func (l *emergencyStopLatch) set(active bool) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(l.path), 0700); err != nil {
		return err
	}
	f := stopLatchFile{Active: active}
	if active {
		f.At = time.Now().UTC().Format(time.RFC3339)
	}
	data, err := json.Marshal(f)
	if err != nil {
		return err
	}
	return os.WriteFile(l.path, data, 0600)
}
