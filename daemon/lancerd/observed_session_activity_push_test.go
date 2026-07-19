package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

func TestObservedActivityPush_NewActiveTriggersOnceThenRetriggersAfterStale(t *testing.T) {
	var (
		mu       sync.Mutex
		payloads []map[string]interface{}
	)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/run-start" || r.Method != http.MethodPost {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		var payload map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("decode body: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		mu.Lock()
		payloads = append(payloads, payload)
		mu.Unlock()
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	s := newServer(t.TempDir())
	s.deviceMu.Lock()
	s.device = &registeredDevice{
		PushBackendURL: srv.URL,
		SessionID:      "phone-device-session",
	}
	s.deviceMu.Unlock()

	var (
		listMu sync.Mutex
		listed []SessionInfo
	)
	s.listObservedSessions = func(home string) ([]SessionInfo, error) {
		listMu.Lock()
		defer listMu.Unlock()
		out := make([]SessionInfo, len(listed))
		copy(out, listed)
		return out, nil
	}

	setListed := func(sessions ...SessionInfo) {
		listMu.Lock()
		listed = append([]SessionInfo(nil), sessions...)
		listMu.Unlock()
	}
	gotCount := func() int {
		mu.Lock()
		defer mu.Unlock()
		return len(payloads)
	}

	active := SessionInfo{
		SessionID: "vendor-cli-session-abc",
		Provider:  "claudeCode",
		State:     "recentlyActive",
	}

	// (a) Newly-active observed session → exactly one postRunStartPush-shaped call.
	setListed(active)
	s.pollObservedSessionsForActivityPush()
	if n := gotCount(); n != 1 {
		t.Fatalf("after first active poll: got %d /run-start POSTs, want 1", n)
	}
	mu.Lock()
	first := payloads[0]
	mu.Unlock()
	if first["sessionId"] != "phone-device-session" {
		t.Fatalf("sessionId = %v, want phone-device-session (device identity, not vendor session id)", first["sessionId"])
	}
	if first["agent"] != "claudeCode" {
		t.Fatalf("agent = %v, want claudeCode", first["agent"])
	}

	// (b) Still active → no second call.
	s.pollObservedSessionsForActivityPush()
	s.pollObservedSessionsForActivityPush()
	if n := gotCount(); n != 1 {
		t.Fatalf("while still active: got %d /run-start POSTs, want 1", n)
	}

	// Goes stale → set drops the vendor session id.
	setListed(SessionInfo{
		SessionID: "vendor-cli-session-abc",
		Provider:  "claudeCode",
		State:     "historical",
	})
	s.pollObservedSessionsForActivityPush()
	if n := gotCount(); n != 1 {
		t.Fatalf("after stale poll: got %d /run-start POSTs, want 1", n)
	}

	// (c) Active again → triggers again (through real postRunStartPush).
	setListed(active)
	s.pollObservedSessionsForActivityPush()
	if n := gotCount(); n != 2 {
		t.Fatalf("after re-active poll: got %d /run-start POSTs, want 2", n)
	}
	mu.Lock()
	second := payloads[1]
	mu.Unlock()
	if second["sessionId"] != "phone-device-session" {
		t.Fatalf("re-trigger sessionId = %v, want phone-device-session", second["sessionId"])
	}
}

func TestObservedActivityPush_SkipsWhenNoDevice(t *testing.T) {
	s := newServer(t.TempDir())
	s.listObservedSessions = func(home string) ([]SessionInfo, error) {
		return []SessionInfo{{
			SessionID: "vendor-1",
			Provider:  "codex",
			State:     "recentlyActive",
		}}, nil
	}
	// No device registered — must not panic and must not mark as pushed
	// (so a later device registration can still fire).
	s.pollObservedSessionsForActivityPush()

	s.observedPushMu.Lock()
	n := len(s.observedPushed)
	s.observedPushMu.Unlock()
	if n != 0 {
		t.Fatalf("observedPushed size = %d, want 0 when device is nil", n)
	}
}

func TestIsObservedSessionActive(t *testing.T) {
	cases := []struct {
		state string
		want  bool
	}{
		{"recentlyActive", true},
		{"working", true},
		{"waitingForInput", true},
		{"historical", false},
		{"completed", false},
		{"idle", false},
		{"unknown", false},
		{"", false},
	}
	for _, tc := range cases {
		got := isObservedSessionActive(SessionInfo{State: tc.state})
		if got != tc.want {
			t.Errorf("state %q: got %v, want %v", tc.state, got, tc.want)
		}
	}
}
