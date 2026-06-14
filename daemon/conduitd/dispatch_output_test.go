package main

import (
	"sync"
	"testing"
	"time"
)

// realLauncher must stream both stdout and stderr as agent.run.output events
// (tagged with runID + ordered seq) and emit run.status running→failed with the
// real exit code. This is the wire contract the phone consumes to surface a
// dispatched run's live output and final state.
func TestRealLauncherStreamsOutputAndStatus(t *testing.T) {
	var mu sync.Mutex
	var outputs []map[string]any
	var statuses []map[string]any
	emit := func(method string, params any) {
		p := params.(map[string]any)
		mu.Lock()
		defer mu.Unlock()
		switch method {
		case "agent.run.output":
			outputs = append(outputs, p)
		case "agent.run.status":
			statuses = append(statuses, p)
		}
	}

	_, err := realLauncher([]string{"sh", "-c", "echo out; echo err 1>&2; exit 3"}, "", "run-1", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		done := len(statuses) >= 2
		mu.Unlock()
		if done || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	mu.Lock()
	defer mu.Unlock()

	var sawStdout, sawStderr bool
	for _, o := range outputs {
		if o["runId"] != "run-1" {
			t.Fatalf("output missing runId: %+v", o)
		}
		if _, ok := o["seq"].(int); !ok {
			t.Fatalf("output seq not int: %+v", o)
		}
		switch o["stream"] {
		case "stdout":
			sawStdout = true
		case "stderr":
			sawStderr = true
		}
	}
	if !sawStdout || !sawStderr {
		t.Fatalf("want both stdout+stderr chunks, got %+v", outputs)
	}

	if len(statuses) < 2 {
		t.Fatalf("want running+final status, got %+v", statuses)
	}
	if statuses[0]["status"] != "running" {
		t.Fatalf("first status must be running, got %+v", statuses[0])
	}
	last := statuses[len(statuses)-1]
	if last["status"] != "failed" {
		t.Fatalf("final status must be failed (exit 3), got %+v", last)
	}
	if last["exitCode"].(int) != 3 {
		t.Fatalf("want exitCode 3, got %+v", last["exitCode"])
	}
}

func TestRealLauncherCleanExit(t *testing.T) {
	var mu sync.Mutex
	var statuses []map[string]any
	emit := func(method string, params any) {
		if method != "agent.run.status" {
			return
		}
		mu.Lock()
		statuses = append(statuses, params.(map[string]any))
		mu.Unlock()
	}

	if _, err := realLauncher([]string{"sh", "-c", "exit 0"}, "", "run-2", emit); err != nil {
		t.Fatalf("launch: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for {
		mu.Lock()
		done := len(statuses) >= 2
		mu.Unlock()
		if done || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(statuses) < 2 {
		t.Fatalf("want running+exited, got %+v", statuses)
	}
	last := statuses[len(statuses)-1]
	if last["status"] != "exited" || last["exitCode"].(int) != 0 {
		t.Fatalf("want exited/0, got %+v", last)
	}
}
