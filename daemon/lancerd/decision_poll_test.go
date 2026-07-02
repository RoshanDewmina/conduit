package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestDecisionPollerResolves(t *testing.T) {
	served := int32(0)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if atomic.AddInt32(&served, 1) == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"decisions": []map[string]string{
					{"approvalId": "a-1", "decision": "approve", "editedToolInput": ""},
				},
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"decisions": []any{}})
	}))
	defer srv.Close()

	got := make(chan [3]string, 1)
	resolve := func(id, decision, edited, contentHash string) (ApprovalEvent, bool) {
		got <- [3]string{id, decision, edited}
		return ApprovalEvent{}, true
	}

	p := newDecisionPoller(resolve)
	p.pollIntervalForTest = 20 * time.Millisecond
	p.ensureRunning(srv.URL, "sess-A", "tok-A")
	defer p.stopForTest()

	select {
	case v := <-got:
		if v[0] != "a-1" || v[1] != "approve" {
			t.Fatalf("resolved with %+v", v)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("poller did not resolve the decision in time")
	}
}

// The poll must carry the per-session relayToken as `Authorization: Bearer …`
// so the backend can authorize lancerd's GET /decisions.
func TestDecisionPollerSendsBearerToken(t *testing.T) {
	gotAuth := make(chan string, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case gotAuth <- r.Header.Get("Authorization"):
		default:
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"decisions": []any{}})
	}))
	defer srv.Close()

	p := newDecisionPoller(func(id, decision, edited, contentHash string) (ApprovalEvent, bool) {
		return ApprovalEvent{}, false
	})
	p.pollIntervalForTest = 20 * time.Millisecond
	p.ensureRunning(srv.URL, "sess-A", "tok-123")
	defer p.stopForTest()

	select {
	case auth := <-gotAuth:
		if auth != "Bearer tok-123" {
			t.Fatalf("Authorization = %q, want %q", auth, "Bearer tok-123")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("poller did not poll in time")
	}
}

// TestDecisionPollerThreadsContentHash is the item-1 REST-fallback regression:
// the poller must carry a poll-delivered decision's contentHash through to
// apply() unmodified, so the push-backend path is verified identically to the
// live-SSH/relay paths (approvalStore.resolve) rather than a weaker path that
// skips the check.
func TestDecisionPollerThreadsContentHash(t *testing.T) {
	served := int32(0)
	const wantHash = "deadbeefcafe"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if atomic.AddInt32(&served, 1) == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"decisions": []map[string]string{
					{"approvalId": "a-2", "decision": "approve", "contentHash": wantHash},
				},
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"decisions": []any{}})
	}))
	defer srv.Close()

	got := make(chan string, 1)
	p := newDecisionPoller(func(id, decision, edited, contentHash string) (ApprovalEvent, bool) {
		got <- contentHash
		return ApprovalEvent{}, true
	})
	p.pollIntervalForTest = 20 * time.Millisecond
	p.ensureRunning(srv.URL, "sess-B", "tok-B")
	defer p.stopForTest()

	select {
	case h := <-got:
		if h != wantHash {
			t.Fatalf("contentHash = %q, want %q", h, wantHash)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("poller did not resolve the decision in time")
	}
}
