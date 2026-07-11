package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const claudeReceiptFixture = `{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_1","name":"Bash"}}}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"command\":\"go test ./...\"}"}}}
{"type":"stream_event","event":{"type":"content_block_stop"}}
{"type":"system","subtype":"init","session_id":"sess-claude-1"}
`

const opencodeReceiptFixture = `{"type":"tool_use","sessionID":"sess-oc-1","part":{"tool":"bash","callID":"call-1","state":{"input":{"command":"npm test"}}}}
`

func TestReceiptClaudeConfidenceComplete(t *testing.T) {
	d := newDispatcher()
	repo := initReceiptGitRepo(t)
	d.receiptGit = realGitRunner

	var captured *runReceipt
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		go func() {
			seq := int64(0)
			var wg sync.WaitGroup
			wg.Add(1)
			streamJSONOutput(emit, runID, strings.NewReader(claudeReceiptFixture), &seq, &wg)
			wg.Wait()
			emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
		}()
		return &procHandle{kill: func() {}}, nil
	}

	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: repo, Prompt: "hi", Model: "sonnet"}, allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("dispatch status = %q", res.Status)
	}
	deadline := time.After(2 * time.Second)
	for captured == nil {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for receipt")
		default:
			captured = d.getReceipt(res.RunID)
			if captured == nil {
				time.Sleep(10 * time.Millisecond)
			}
		}
	}
	if captured.Confidence.Commands != "complete" {
		t.Fatalf("commands confidence = %q, want complete", captured.Confidence.Commands)
	}
	if len(captured.Commands) != 1 || captured.Commands[0].Command != "go test ./..." {
		t.Fatalf("commands = %+v", captured.Commands)
	}
	if captured.Commands[0].Kind != "test" {
		t.Fatalf("command kind = %q, want test", captured.Commands[0].Kind)
	}
	if captured.Resume == nil || captured.Resume.VendorSessionID != "sess-claude-1" {
		t.Fatalf("resume = %+v", captured.Resume)
	}
}

func TestReceiptOpencodeConfidenceBestEffort(t *testing.T) {
	d := newDispatcher()
	repo := initReceiptGitRepo(t)
	d.receiptGit = realGitRunner

	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		go func() {
			seq := int64(0)
			var wg sync.WaitGroup
			wg.Add(1)
			streamJSONOutput(emit, runID, strings.NewReader(opencodeReceiptFixture), &seq, &wg)
			wg.Wait()
			emit("agent.run.status", map[string]any{"runId": runID, "status": "exited", "exitCode": 0})
		}()
		return &procHandle{kill: func() {}}, nil
	}

	res := d.dispatch(dispatchParams{Agent: "opencode", CWD: repo, Prompt: "hi"}, allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("dispatch status = %q", res.Status)
	}
	var receipt *runReceipt
	deadline := time.After(2 * time.Second)
	for receipt == nil {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for receipt")
		default:
			receipt = d.getReceipt(res.RunID)
			if receipt == nil {
				time.Sleep(10 * time.Millisecond)
			}
		}
	}
	if receipt.Confidence.Commands != "bestEffort" {
		t.Fatalf("commands confidence = %q, want bestEffort", receipt.Confidence.Commands)
	}
	if len(receipt.Commands) != 1 || receipt.Commands[0].Command != "npm test" {
		t.Fatalf("commands = %+v", receipt.Commands)
	}
}

// TestNewReceiptAccumulatorDoesNotBlockOnHungGit: start-snapshot must not
// run on the caller's goroutine — a forever-blocking gitRunner must not delay
// construction (relay messageLoop must stay free).
func TestNewReceiptAccumulatorDoesNotBlockOnHungGit(t *testing.T) {
	blocking := func(workdir, tool string, args ...string) (string, error) {
		select {} // hang forever
	}
	start := time.Now()
	acc := newReceiptAccumulator("run-hang", receiptStartParams{
		agent: "claudeCode",
		cwd:   t.TempDir(),
	}, blocking)
	elapsed := time.Since(start)
	if elapsed >= time.Second {
		t.Fatalf("newReceiptAccumulator blocked for %v; want <1s", elapsed)
	}
	if acc == nil {
		t.Fatal("expected accumulator")
	}
	// Honest unknown start state until (if ever) the async snapshot lands.
	acc.mu.Lock()
	ref, dirty, ok := acc.gitStartRef, acc.gitDirtyAtStart, acc.gitAvailable
	acc.mu.Unlock()
	if ref != "" || dirty || ok {
		t.Fatalf("initial snapshot = ref=%q dirty=%v ok=%v, want unknown", ref, dirty, ok)
	}
}

func TestReceiptNonGitCWDFilesUnavailable(t *testing.T) {
	acc := newReceiptAccumulator("run-1", receiptStartParams{
		agent: "claudeCode",
		cwd:   t.TempDir(),
	}, func(workdir, tool string, args ...string) (string, error) {
		return "", &gitCmdError{exitCode: 128, output: "not a git repository"}
	})
	receipt := acc.build("", "exited", 0, func(workdir, tool string, args ...string) (string, error) {
		return "", &gitCmdError{exitCode: 128, output: "not a git repository"}
	})
	if receipt.Confidence.Files != "unavailable" {
		t.Fatalf("files confidence = %q, want unavailable", receipt.Confidence.Files)
	}
	if len(receipt.FilesTouched) != 0 {
		t.Fatalf("filesTouched = %+v, want empty", receipt.FilesTouched)
	}
}

func TestReceiptValidationExitZeroMet(t *testing.T) {
	zero := 0
	commands := []receiptCommand{{
		Command:  "go test ./...",
		ExitCode: &zero,
		Kind:     "test",
	}}
	contract := &receiptContract{
		DoneCriteria:       []string{"tests pass"},
		ValidationCommands: []string{"go test ./..."},
	}
	criteria := evaluateReceiptCriteria(contract, commands)
	if len(criteria) != 1 {
		t.Fatalf("criteria len = %d", len(criteria))
	}
	if criteria[0].Status != "met" {
		t.Fatalf("status = %q, want met", criteria[0].Status)
	}
}

func TestReceiptNoValidationUnknown(t *testing.T) {
	contract := &receiptContract{
		DoneCriteria: []string{"feature implemented"},
	}
	criteria := evaluateReceiptCriteria(contract, nil)
	if len(criteria) != 1 || criteria[0].Status != "unknown" {
		t.Fatalf("criteria = %+v, want unknown", criteria)
	}
}

func TestReceiptTruncatedAtFiftyOneCommands(t *testing.T) {
	acc := newReceiptAccumulator("run-trunc", receiptStartParams{agent: "claudeCode", cwd: t.TempDir()}, nil)
	acc.mu.Lock()
	for i := 0; i < 51; i++ {
		acc.commands = append(acc.commands, receiptCommand{
			Command:   "echo hi",
			Kind:      "shell",
			StartedAt: "2026-07-07T00:00:00Z",
		})
	}
	acc.mu.Unlock()

	receipt := acc.build("", "exited", 0, func(string, string, ...string) (string, error) { return "", nil })
	if !receipt.Truncated {
		t.Fatal("expected truncated=true")
	}
	if len(receipt.Commands) != receiptMaxCommands {
		t.Fatalf("commands len = %d, want %d", len(receipt.Commands), receiptMaxCommands)
	}
}

func TestClassifyCommandKind(t *testing.T) {
	cases := map[string]string{
		"go test ./...":   "test",
		"swift test":      "test",
		"pytest -q":       "test",
		"npm test":        "test",
		"yarn test":       "test",
		"cargo test":      "test",
		"xcodebuild test": "test",
		"echo hello":      "shell",
		"go build ./...":  "shell",
	}
	for cmd, want := range cases {
		if got := classifyCommandKind(cmd); got != want {
			t.Errorf("classifyCommandKind(%q) = %q, want %q", cmd, got, want)
		}
	}
}

func TestParseGitNumstat(t *testing.T) {
	files := parseGitNumstat("12\t3\tpkg/a.go\n-\t-\tbinary.dat\n")
	if len(files) != 2 {
		t.Fatalf("len = %d", len(files))
	}
	if files[0].Path != "pkg/a.go" || files[0].Additions != 12 || files[0].Deletions != 3 {
		t.Errorf("first file = %+v", files[0])
	}
	if files[1].Additions != 0 || files[1].Deletions != 0 {
		t.Errorf("binary file = %+v", files[1])
	}
}

func TestReceiptObserveToolStart(t *testing.T) {
	d := newDispatcher()
	d.startReceiptAccum("r1", receiptStartParams{agent: "claudeCode", cwd: "/tmp"})
	d.observeReceiptEmit("r1", "agent.tool.start", map[string]any{
		"inputJSON": `{"command":"swift test"}`,
	})
	receipt := d.finalizeReceipt("r1", "exited", 0)
	if receipt == nil || len(receipt.Commands) != 1 {
		t.Fatalf("receipt = %+v", receipt)
	}
}

func initReceiptGitRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	runGit := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		var buf bytes.Buffer
		cmd.Stdout = &buf
		cmd.Stderr = &buf
		if err := cmd.Run(); err != nil {
			t.Fatalf("git %v: %v (%s)", args, err, buf.String())
		}
	}
	runGit("init")
	runGit("config", "user.email", "test@example.com")
	runGit("config", "user.name", "Test")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit("add", "README.md")
	runGit("commit", "-m", "init")
	return dir
}
