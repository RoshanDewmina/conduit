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
}
