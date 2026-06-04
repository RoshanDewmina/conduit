package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestDeviceRegister verifies that conduit.device.register stores the device info.
func TestDeviceRegister(t *testing.T) {
	s := newServer(t.TempDir())

	params, _ := json.Marshal(map[string]string{
		"pushBackendURL": "https://example.com",
		"sessionID":      "test-session-id",
	})
	msg := &rpcMessage{
		JSONRPC: "2.0",
		ID:      1,
		Method:  "conduit.device.register",
		Params:  params,
	}

	// Capture stdout to prevent test noise; handleMessage writes to os.Stdout.
	// We only care about the stored device, not the RPC response.
	s.handleMessage(msg)

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()

	if dev == nil {
		t.Fatal("device not registered")
	}
	if dev.PushBackendURL != "https://example.com" {
		t.Errorf("pushBackendURL = %q, want %q", dev.PushBackendURL, "https://example.com")
	}
	if dev.SessionID != "test-session-id" {
		t.Errorf("sessionID = %q, want %q", dev.SessionID, "test-session-id")
	}
}

// TestPostApprovalPush verifies that postApprovalPush POSTs to /approval with the correct payload.
func TestPostApprovalPush(t *testing.T) {
	var received []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/approval" || r.Method != http.MethodPost {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		received = make([]byte, r.ContentLength)
		r.Body.Read(received)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	s := newServer(t.TempDir())
	dev := &registeredDevice{
		PushBackendURL: srv.URL,
		SessionID:      "device-session-123",
	}

	event := ApprovalEvent{
		ApprovalID: "approval-abc",
		Command:    "ls /tmp",
		Risk:       1, // medium
	}

	s.postApprovalPush(dev, event)

	var payload map[string]interface{}
	if err := json.Unmarshal(received, &payload); err != nil {
		t.Fatalf("could not decode payload: %v (raw: %s)", err, received)
	}
	if payload["sessionId"] != "device-session-123" {
		t.Errorf("sessionId = %v, want device-session-123", payload["sessionId"])
	}
	if payload["id"] != "approval-abc" {
		t.Errorf("id = %v, want approval-abc", payload["id"])
	}
	if payload["risk"] != "medium" {
		t.Errorf("risk = %v, want medium", payload["risk"])
	}
}
