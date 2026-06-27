package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestActivityTokenRegister verifies that lancer.device.register.activity
// parses sessionId/activityToken/isPushToStart/pushBackendURL and forwards a
// POST to <pushBackendURL>/register-activity-token carrying the Tier-1
// APPROVAL_RELAY_SECRET bearer header — the app itself never sees that secret.
func TestActivityTokenRegister(t *testing.T) {
	t.Setenv("APPROVAL_RELAY_SECRET", "test-relay-secret")

	gotReg := make(chan map[string]interface{}, 1)
	gotAuth := make(chan string, 1)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/register-activity-token" {
			var body map[string]interface{}
			_ = json.NewDecoder(r.Body).Decode(&body)
			select {
			case gotReg <- body:
			default:
			}
			select {
			case gotAuth <- r.Header.Get("Authorization"):
			default:
			}
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer backend.Close()

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	resultCh := make(chan rpcMessage, 1)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		_ = json.Unmarshal(data, &m)
		select {
		case resultCh <- m:
		default:
		}
		return nil
	})

	params, _ := json.Marshal(map[string]interface{}{
		"pushBackendURL": backend.URL,
		"sessionId":      "test-session-id",
		"activityToken":  "deadbeef",
		"isPushToStart":  true,
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 1, Method: "lancer.device.register.activity", Params: params})

	select {
	case res := <-resultCh:
		if res.Error != nil {
			t.Fatalf("unexpected RPC error: %+v", res.Error)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no RPC result emitted")
	}

	select {
	case body := <-gotReg:
		if body["sessionId"] != "test-session-id" {
			t.Errorf("registration sessionId = %v, want %q", body["sessionId"], "test-session-id")
		}
		if body["activityToken"] != "deadbeef" {
			t.Errorf("registration activityToken = %v, want %q", body["activityToken"], "deadbeef")
		}
		if body["isPushToStart"] != true {
			t.Errorf("registration isPushToStart = %v, want true", body["isPushToStart"])
		}
	case <-time.After(2 * time.Second):
		t.Fatal("lancerd did not POST to /register-activity-token")
	}

	select {
	case auth := <-gotAuth:
		if auth != "Bearer test-relay-secret" {
			t.Errorf("Authorization header = %q, want %q", auth, "Bearer test-relay-secret")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("did not observe Authorization header")
	}
}

// TestActivityTokenRegisterInvalidParams verifies the RPC rejects missing
// required fields instead of silently dropping the request.
func TestActivityTokenRegisterInvalidParams(t *testing.T) {
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	resultCh := make(chan rpcMessage, 1)
	s.setEmitter(func(data []byte) error {
		var m rpcMessage
		_ = json.Unmarshal(data, &m)
		select {
		case resultCh <- m:
		default:
		}
		return nil
	})

	params, _ := json.Marshal(map[string]interface{}{
		"pushBackendURL": "https://example.invalid",
		"sessionId":      "",
		"activityToken":  "",
	})
	s.handleMessage(&rpcMessage{JSONRPC: "2.0", ID: 2, Method: "lancer.device.register.activity", Params: params})

	select {
	case res := <-resultCh:
		if res.Error == nil {
			t.Fatal("expected RPC error for missing sessionId/activityToken, got none")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no RPC result emitted")
	}
}
