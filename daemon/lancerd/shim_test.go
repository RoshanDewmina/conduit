package main

import "testing"

func TestHandleShimSpawnLaunchesTmux(t *testing.T) {
	writeFakeTmux(t)
	s := newServer(t.TempDir())
	reply := s.handleShimSpawn(ShimSpawnEvent{
		Kind: "shim.spawn", Agent: "claude", CWD: "/tmp", Argv: []string{"claude"},
	})
	if reply.Action != "attached" {
		t.Fatalf("action = %q, want attached", reply.Action)
	}
	if reply.TmuxName == "" || s.sessions.count() != 1 {
		t.Fatalf("expected one registered session, got %d (tmux=%q)", s.sessions.count(), reply.TmuxName)
	}
}

func TestEmitShimStatusCountsSessions(t *testing.T) {
	s := newServer(t.TempDir())
	s.sessions.register(ShimSession{ID: "a", Agent: "claudeCode", Status: "running"})
	s.sessions.register(ShimSession{ID: "b", Agent: "claudeCode", Status: "running"})
	got := s.shimStatusData("claudeCode")
	if got.SessionCount != 2 {
		t.Fatalf("sessionCount = %d, want 2", got.SessionCount)
	}
}
