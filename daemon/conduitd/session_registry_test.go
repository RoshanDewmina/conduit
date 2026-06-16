package main

import "testing"

func TestSessionRegistryLifecycle(t *testing.T) {
	r := newSessionRegistry()
	r.register(ShimSession{ID: "abc123", Agent: "claudeCode", TmuxName: "conduit-abc123", Status: "running"})
	if r.count() != 1 {
		t.Fatalf("count = %d, want 1", r.count())
	}
	got, ok := r.get("abc123")
	if !ok || got.TmuxName != "conduit-abc123" {
		t.Fatalf("get = %+v ok=%v", got, ok)
	}
	r.unregister("abc123")
	if r.count() != 0 {
		t.Fatalf("count after unregister = %d, want 0", r.count())
	}
}
