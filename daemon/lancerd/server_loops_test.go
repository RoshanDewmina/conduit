package main

import (
	"testing"
)

// A loop upserted into one server must survive a fresh load from the same home:
// the on-disk mirror (~/.lancer/loops.json) is the durability proof.
func TestLoopsPersistAcrossLoad(t *testing.T) {
	home := t.TempDir()

	s := newServer(home)
	if !s.upsertLoop(map[string]interface{}{"id": "loop-1", "status": "running", "note": "first"}) {
		t.Fatal("upsertLoop returned false for a valid payload")
	}

	reloaded := newServer(home)
	loops := reloaded.listLoops()
	if len(loops) != 1 {
		t.Fatalf("after reload: got %d loops, want 1", len(loops))
	}
	if loops[0].ID != "loop-1" || loops[0].Status != "running" {
		t.Fatalf("after reload: got %+v, want id=loop-1 status=running", loops[0])
	}
	if note, _ := loops[0].Payload["note"].(string); note != "first" {
		t.Fatalf("after reload: payload note = %q, want \"first\"", note)
	}
}

// Upserting the same id again updates in place — it must not create a duplicate.
func TestLoopsUpsertUpdatesInPlace(t *testing.T) {
	home := t.TempDir()

	s := newServer(home)
	s.upsertLoop(map[string]interface{}{"id": "loop-1", "status": "running"})
	s.upsertLoop(map[string]interface{}{"id": "loop-1", "status": "done"})

	reloaded := newServer(home)
	loops := reloaded.listLoops()
	if len(loops) != 1 {
		t.Fatalf("after reload: got %d loops, want 1 (no duplicates)", len(loops))
	}
	if loops[0].Status != "done" {
		t.Fatalf("after reload: status = %q, want \"done\" (latest upsert)", loops[0].Status)
	}
}

// An empty id is rejected and nothing is written under the "" key.
func TestLoopsRejectEmptyID(t *testing.T) {
	home := t.TempDir()

	s := newServer(home)
	if s.upsertLoop(map[string]interface{}{"status": "running"}) {
		t.Fatal("upsertLoop accepted a payload with no id")
	}
	if s.upsertLoop(map[string]interface{}{"id": "", "status": "running"}) {
		t.Fatal("upsertLoop accepted a payload with an empty id")
	}

	reloaded := newServer(home)
	if got := len(reloaded.listLoops()); got != 0 {
		t.Fatalf("after reload: got %d loops, want 0", got)
	}
}
