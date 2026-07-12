package main

import (
	"testing"
)

// A daemon restart must never leave 'running' turns behind — phones poll them
// forever (live incident 2026-07-11).
func TestOrphanedRunningTurnsFailOnReopen(t *testing.T) {
	home := t.TempDir()
	s, err := openConversationStore(home)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "client-1",
		Agent:        "claudeCode",
		Prompt:       "do it",
	}, "/repo", "run-1"); err != nil {
		t.Fatal(err)
	}
	if err := s.db.Close(); err != nil {
		t.Fatal(err)
	}
	s2, err := openConversationStore(home)
	if err != nil {
		t.Fatal(err)
	}
	defer s2.db.Close()
	var status string
	if err := s2.db.QueryRow(`SELECT status FROM conversation_turns LIMIT 1`).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "failed" {
		t.Fatalf("orphaned running turn not reconciled: status=%q", status)
	}

	// list() must surface the reconciled status so the phone thread list can
	// drop a stale "Working" badge without opening the live thread.
	listRes, err := s2.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 1 {
		t.Fatalf("conversations = %d, want 1", len(listRes.Conversations))
	}
	if listRes.Conversations[0].LastTurnStatus != "failed" {
		t.Fatalf("lastTurnStatus = %q, want failed", listRes.Conversations[0].LastTurnStatus)
	}
	if listRes.Conversations[0].LastTurnID == "" {
		t.Fatal("expected non-empty lastTurnID after orphan reconciliation")
	}
}

// list() carries the latest turn's terminal status so a completed run does
// not leave the phone list stuck on "Working".
func TestListReportsCompletedLastTurnStatus(t *testing.T) {
	s := openTestConversationStore(t)
	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "client-done",
		Agent:        "claudeCode",
		Prompt:       "finish me",
	}, "/repo", "run-done")
	if err != nil {
		t.Fatal(err)
	}
	exitCode := 0
	if err := s.appendRunStatus("run-done", "completed", &exitCode, ""); err != nil {
		t.Fatalf("appendRunStatus: %v", err)
	}
	listRes, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 1 {
		t.Fatalf("conversations = %d, want 1", len(listRes.Conversations))
	}
	got := listRes.Conversations[0]
	if got.LastTurnStatus != "completed" {
		t.Fatalf("lastTurnStatus = %q, want completed", got.LastTurnStatus)
	}
	if got.LastTurnID != res.TurnID {
		t.Fatalf("lastTurnID = %q, want %q", got.LastTurnID, res.TurnID)
	}
}
