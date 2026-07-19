package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestPersistedActivityRoundTrip proves the push-to-start token survives a
// save/load cycle and that junk/missing/incomplete files fail closed to nil —
// mirrors TestPersistedDeviceRoundTrip (push_device_persist_test.go) for the
// new push-activity.json file.
func TestPersistedActivityRoundTrip(t *testing.T) {
	dir := t.TempDir()
	s := &server{home: dir}

	if got := s.loadPersistedActivity(); got != nil {
		t.Fatalf("missing file should load nil, got %+v", got)
	}

	s.savePersistedActivity(&registeredActivityPushToStart{
		PushBackendURL:   "https://conduit-push.fly.dev",
		SessionID:        "sess-abc",
		PushToStartToken: "p2s-token-1",
	})
	got := s.loadPersistedActivity()
	if got == nil || got.SessionID != "sess-abc" || got.PushToStartToken != "p2s-token-1" {
		t.Fatalf("round trip = %+v", got)
	}

	info, err := os.Stat(filepath.Join(dir, "push-activity.json"))
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("perm = %o, want 600", info.Mode().Perm())
	}

	if err := os.WriteFile(filepath.Join(dir, "push-activity.json"), []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := s.loadPersistedActivity(); got != nil {
		t.Fatalf("junk file should load nil, got %+v", got)
	}

	if err := os.WriteFile(filepath.Join(dir, "push-activity.json"), []byte(`{"sessionId":"","pushToStartToken":"x"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := s.loadPersistedActivity(); got != nil {
		t.Fatalf("empty sessionID should load nil (fail closed), got %+v", got)
	}

	if err := os.WriteFile(filepath.Join(dir, "push-activity.json"), []byte(`{"sessionId":"sess-abc","pushToStartToken":""}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := s.loadPersistedActivity(); got != nil {
		t.Fatalf("empty pushToStartToken should load nil (fail closed), got %+v", got)
	}
}

// TestActivityRegisterPersistsPushToStartOnly proves lancer.device.register.activity
// persists the push-to-start token to push-activity.json but NEVER the
// per-activity (isPushToStart=false) token — re-forwarding a stale per-activity
// token would recreate the "existingActivityToken != '' forever suppresses a
// future push-to-start" bug (push-backend's pushLiveActivityStart heuristic).
func TestActivityRegisterPersistsPushToStartOnly(t *testing.T) {
	dir := t.TempDir()
	s := newServer(dir)
	defer s.poller.stopForTest()
	s.setEmitter(func([]byte) error { return nil })

	// A per-activity (non-push-to-start) token registration must NOT persist.
	params, _ := json.Marshal(map[string]interface{}{
		"pushBackendURL": "https://example.invalid",
		"sessionId":      "sess-1",
		"activityToken":  "per-activity-token",
		"isPushToStart":  false,
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "lancer.device.register.activity", Params: params})
	if _, err := os.Stat(filepath.Join(dir, "push-activity.json")); err == nil {
		t.Fatal("per-activity token registration must not persist push-activity.json")
	}

	// A push-to-start registration MUST persist.
	params2, _ := json.Marshal(map[string]interface{}{
		"pushBackendURL": "https://example.invalid",
		"sessionId":      "sess-1",
		"activityToken":  "p2s-token",
		"isPushToStart":  true,
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 2, Method: "lancer.device.register.activity", Params: params2})
	got := s.loadPersistedActivity()
	if got == nil || got.PushToStartToken != "p2s-token" || got.SessionID != "sess-1" {
		t.Fatalf("push-to-start registration should have persisted, got %+v", got)
	}
}

// TestDaemonRestartReforwardsPushToStartToken proves that a fresh daemon
// process (newServer against a home dir with a pre-existing push-activity.json,
// simulating a restart) re-POSTs the persisted push-to-start token to
// push-backend WITHOUT waiting for the phone to re-register — closing the
// gap where a push-backend restart (which wipes its in-memory
// liveActivityRegistry, see push-backend/liveactivity.go) permanently broke
// app-closed push-to-start until some unrelated event caused the phone to
// resend. Without reforwardPersistedActivityToken's call inside newServer,
// this test fails: no POST is ever observed.
func TestDaemonRestartReforwardsPushToStartToken(t *testing.T) {
	gotReg := make(chan map[string]interface{}, 1)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/register-activity-token" {
			var body map[string]interface{}
			_ = json.NewDecoder(r.Body).Decode(&body)
			select {
			case gotReg <- body:
			default:
			}
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer backend.Close()

	dir := t.TempDir()
	pre := &server{home: dir}
	pre.savePersistedActivity(&registeredActivityPushToStart{
		PushBackendURL:   backend.URL,
		SessionID:        "sess-restart",
		PushToStartToken: "p2s-durable-token",
	})

	// Simulate the daemon restarting: a brand-new server constructed against
	// the same home directory should rehydrate and re-forward on its own,
	// with no RPC from the phone at all.
	s := newServer(dir)
	defer s.poller.stopForTest()

	select {
	case body := <-gotReg:
		if body["sessionId"] != "sess-restart" {
			t.Errorf("sessionId = %v, want %q", body["sessionId"], "sess-restart")
		}
		if body["activityToken"] != "p2s-durable-token" {
			t.Errorf("activityToken = %v, want %q", body["activityToken"], "p2s-durable-token")
		}
		if body["isPushToStart"] != true {
			t.Errorf("isPushToStart = %v, want true", body["isPushToStart"])
		}
	case <-time.After(2 * time.Second):
		t.Fatal("daemon restart did not re-forward the persisted push-to-start token")
	}
}
