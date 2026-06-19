package main

import "testing"

func TestRunForCWDCorrelation(t *testing.T) {
	d := newDispatcher()
	d.runs["run-1"] = &dispatchRun{ID: "run-1", Agent: "claudeCode", CWD: "/tmp/x", Status: "running"}
	if got := d.runForCWD("/tmp/x", "claudeCode"); got != "run-1" {
		t.Fatalf("want run-1, got %q", got)
	}
	if got := d.runForCWD("/tmp/y", "claudeCode"); got != "" {
		t.Fatalf("cwd mismatch should be empty, got %q", got)
	}
	d.runs["run-1"].Status = "cancelled"
	if got := d.runForCWD("/tmp/x", "claudeCode"); got != "" {
		t.Fatalf("non-running run should not match, got %q", got)
	}
}