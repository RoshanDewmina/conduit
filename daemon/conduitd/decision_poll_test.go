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
	resolve := func(id, decision, edited string) (ApprovalEvent, bool) {
		got <- [3]string{id, decision, edited}
		return ApprovalEvent{}, true
	}

	p := newDecisionPoller(resolve)
	p.pollIntervalForTest = 20 * time.Millisecond
	p.ensureRunning(srv.URL, "sess-A")
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
