package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestAppendLogs verifies that AppendLogs sends the correct POST request with
// the right auth header and body, and parses the nextSince cursor from the response.
func TestAppendLogs(t *testing.T) {
	const runID = "run_x"
	const token = "rt_testtoken"

	var gotMethod, gotPath, gotAuth string
	var gotBody appendLogsRequest

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")

		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &gotBody)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"nextSince":7}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL, runID, token)
	lines := []LogLine{
		{Stream: "stdout", Text: "hello"},
		{Stream: "stderr", Text: "world"},
	}

	nextSince, err := client.AppendLogs(context.Background(), lines)
	if err != nil {
		t.Fatalf("AppendLogs returned error: %v", err)
	}

	if gotMethod != http.MethodPost {
		t.Errorf("expected POST, got %s", gotMethod)
	}
	if gotPath != "/runs/run_x/logs" {
		t.Errorf("expected path /runs/run_x/logs, got %s", gotPath)
	}
	if gotAuth != "Bearer "+token {
		t.Errorf("expected Bearer auth, got %q", gotAuth)
	}
	if len(gotBody.Lines) != 2 {
		t.Errorf("expected 2 lines in body, got %d", len(gotBody.Lines))
	}
	if gotBody.Lines[0].Stream != "stdout" || gotBody.Lines[0].Text != "hello" {
		t.Errorf("unexpected first line: %+v", gotBody.Lines[0])
	}
	if gotBody.Lines[1].Stream != "stderr" || gotBody.Lines[1].Text != "world" {
		t.Errorf("unexpected second line: %+v", gotBody.Lines[1])
	}
	if nextSince != 7 {
		t.Errorf("expected nextSince=7, got %d", nextSince)
	}
}

// TestAppendLogs_ErrorStatus verifies that a non-2xx response is returned as an error.
func TestAppendLogs_ErrorStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "internal error", http.StatusInternalServerError)
	}))
	defer srv.Close()

	client := NewClient(srv.URL, "run_x", "rt_tok")
	_, err := client.AppendLogs(context.Background(), []LogLine{{Stream: "stdout", Text: "hi"}})
	if err == nil {
		t.Fatal("expected error for 500 response, got nil")
	}
	if !strings.Contains(err.Error(), "500") {
		t.Errorf("expected error to mention status 500, got: %v", err)
	}
}

// TestGetControl_Cancel verifies that GetControl returns true when the server
// responds with cancelRequested=true.
func TestGetControl_Cancel(t *testing.T) {
	const runID = "run_x"
	const token = "rt_testtoken"

	var gotMethod, gotPath, gotAuth string

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"cancelRequested":true}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL, runID, token)
	cancelled, err := client.GetControl(context.Background())
	if err != nil {
		t.Fatalf("GetControl returned error: %v", err)
	}
	if !cancelled {
		t.Error("expected cancelRequested=true, got false")
	}
	if gotMethod != http.MethodGet {
		t.Errorf("expected GET, got %s", gotMethod)
	}
	if gotPath != "/runs/run_x/control" {
		t.Errorf("expected path /runs/run_x/control, got %s", gotPath)
	}
	if gotAuth != "Bearer "+token {
		t.Errorf("expected Bearer auth, got %q", gotAuth)
	}
}

// TestGetControl_NoCanel verifies that GetControl returns false when not cancelled.
func TestGetControl_NoCancel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"cancelRequested":false}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL, "run_x", "rt_tok")
	cancelled, err := client.GetControl(context.Background())
	if err != nil {
		t.Fatalf("GetControl returned error: %v", err)
	}
	if cancelled {
		t.Error("expected cancelRequested=false, got true")
	}
}

// TestPatchRun verifies that PatchRun sends the correct PATCH request with the
// right auth header and body fields.
func TestPatchRun(t *testing.T) {
	const runID = "run_x"
	const token = "rt_testtoken"

	var gotMethod, gotPath, gotAuth string
	var gotBody patchRunRequest

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")

		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &gotBody)

		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	client := NewClient(srv.URL, runID, token)
	err := client.PatchRun(context.Background(), "failed", 1, "2026-06-03T12:00:00Z")
	if err != nil {
		t.Fatalf("PatchRun returned error: %v", err)
	}

	if gotMethod != http.MethodPatch {
		t.Errorf("expected PATCH, got %s", gotMethod)
	}
	if gotPath != "/runs/run_x" {
		t.Errorf("expected path /runs/run_x, got %s", gotPath)
	}
	if gotAuth != "Bearer "+token {
		t.Errorf("expected Bearer auth, got %q", gotAuth)
	}
	if gotBody.Status != "failed" {
		t.Errorf("expected status=failed, got %q", gotBody.Status)
	}
	if gotBody.ExitCode != 1 {
		t.Errorf("expected exitCode=1, got %d", gotBody.ExitCode)
	}
	if gotBody.CompletedAt != "2026-06-03T12:00:00Z" {
		t.Errorf("expected completedAt=2026-06-03T12:00:00Z, got %q", gotBody.CompletedAt)
	}
}

// TestPatchRun_Succeeded verifies the succeeded path sets exitCode=0.
func TestPatchRun_Succeeded(t *testing.T) {
	var gotBody patchRunRequest

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &gotBody)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	client := NewClient(srv.URL, "run_x", "rt_tok")
	err := client.PatchRun(context.Background(), "succeeded", 0, "2026-06-03T12:00:00Z")
	if err != nil {
		t.Fatalf("PatchRun returned error: %v", err)
	}
	if gotBody.Status != "succeeded" {
		t.Errorf("expected status=succeeded, got %q", gotBody.Status)
	}
	if gotBody.ExitCode != 0 {
		t.Errorf("expected exitCode=0, got %d", gotBody.ExitCode)
	}
}

// TestBatchFlushing verifies that the batching constants are sane and that
// building large batches of LogLines doesn't panic or corrupt data.
func TestBatchFlushing(t *testing.T) {
	const batchSize = 50
	lines := make([]LogLine, 0, batchSize*3)
	for i := 0; i < batchSize*3; i++ {
		stream := "stdout"
		if i%2 == 0 {
			stream = "stderr"
		}
		lines = append(lines, LogLine{Stream: stream, Text: "line"})
	}

	// Split into batches of batchSize and count them.
	var batches [][]LogLine
	for len(lines) > 0 {
		end := batchSize
		if end > len(lines) {
			end = len(lines)
		}
		batches = append(batches, lines[:end])
		lines = lines[end:]
	}

	if len(batches) != 3 {
		t.Errorf("expected 3 batches of %d, got %d", batchSize, len(batches))
	}
	for i, b := range batches {
		if len(b) != batchSize {
			t.Errorf("batch %d: expected %d lines, got %d", i, batchSize, len(b))
		}
	}

	// Verify that each batch can be marshalled without error (no panics, no nil).
	requestCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"nextSince":0}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL, "run_x", "rt_tok")
	for _, batch := range batches {
		if _, err := client.AppendLogs(context.Background(), batch); err != nil {
			t.Fatalf("AppendLogs failed for batch: %v", err)
		}
	}
	if requestCount != 3 {
		t.Errorf("expected 3 HTTP requests, got %d", requestCount)
	}
}
