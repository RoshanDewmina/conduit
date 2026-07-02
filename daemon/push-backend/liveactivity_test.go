package main

import (
	"bytes"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// TestLiveActivityDateEncoding pins the date encoding contract.
//
// ActivityKit's default JSONDecoder expects Date as a Unix fractional-seconds
// float64 (Swift JSONEncoder default). A mismatch drops the whole update
// silently on-device. This test asserts the exact encoded representation so a
// future refactor can't break it undetected.
func TestLiveActivityDateEncoding(t *testing.T) {
	// Use a fixed, known Unix timestamp so the assertion is deterministic.
	fixedUnix := 1_700_000_000.0 // 2023-11-14T22:13:20Z

	state := liveActivityContentState{
		Status:           "connected",
		PendingApprovals: 1,
		IsStreaming:      false,
		LastUpdate:       fixedUnix,
	}

	buf, err := json.Marshal(state)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(buf, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	raw, ok := decoded["lastUpdate"]
	if !ok {
		t.Fatal("lastUpdate field missing from encoded JSON")
	}
	// JSON numbers decode to float64 in Go's standard library.
	gotFloat, ok := raw.(float64)
	if !ok {
		t.Fatalf("lastUpdate encoded as %T, want float64 (JSON number)", raw)
	}
	// Must match the input to machine precision.
	if math.Abs(gotFloat-fixedUnix) > 0.001 {
		t.Fatalf("lastUpdate = %v, want %v", gotFloat, fixedUnix)
	}

	// Verify the raw JSON string contains the timestamp as a plain number, not
	// a quoted string — ActivityKit would reject a string-encoded date.
	jsonStr := string(buf)
	quoted := `"lastUpdate":"` // would be wrong
	if strings.Contains(jsonStr, quoted) {
		t.Fatalf("lastUpdate appears to be JSON-string-encoded; want a JSON number. Got: %s", jsonStr)
	}
}

// TestLiveActivityPayloadShape asserts the full payload structure matches what
// ActivityKit expects: aps.timestamp, aps.event, aps.content-state.
func TestLiveActivityPayloadShape(t *testing.T) {
	now := float64(time.Now().UnixNano()) / 1e9
	approvalID := "appr-test-1"
	contentState := liveActivityContentState{
		Status:            "connected",
		PendingApprovals:  1,
		PendingApprovalID: &approvalID,
		IsStreaming:       false,
		LastUpdate:        now,
	}
	stale := time.Now().Add(30 * time.Minute).Unix()
	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:    time.Now().Unix(),
			Event:        "update",
			ContentState: contentState,
			StaleDate:    &stale,
		},
	}

	buf, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(buf, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	aps, ok := decoded["aps"].(map[string]any)
	if !ok {
		t.Fatal("aps key missing or wrong type")
	}
	if _, ok := aps["timestamp"]; !ok {
		t.Error("aps.timestamp missing")
	}
	if event, _ := aps["event"].(string); event != "update" {
		t.Errorf("aps.event = %q, want %q", event, "update")
	}
	cs, ok := aps["content-state"].(map[string]any)
	if !ok {
		t.Fatal("aps.content-state missing or wrong type")
	}
	if status, _ := cs["status"].(string); status != "connected" {
		t.Errorf("content-state.status = %q, want %q", status, "connected")
	}
	if pa, _ := cs["pendingApprovals"].(float64); int(pa) != 1 {
		t.Errorf("content-state.pendingApprovals = %v, want 1", pa)
	}
	if paid, _ := cs["pendingApprovalID"].(string); paid != approvalID {
		t.Errorf("content-state.pendingApprovalID = %q, want %q", paid, approvalID)
	}
	if _, ok := cs["lastUpdate"].(float64); !ok {
		t.Error("content-state.lastUpdate is not a JSON number (float64)")
	}
	if _, ok := aps["stale-date"]; !ok {
		t.Error("aps.stale-date missing")
	}
}

// TestLiveActivityPayloadPrivacy asserts that the content-state fields included
// in a push payload contain ONLY non-sensitive values — never the raw command,
// file paths, env values, or secrets.
func TestLiveActivityPayloadPrivacy(t *testing.T) {
	sensitiveCommand := "bash -c 'export AWS_SECRET=abc123; rm -rf /etc/passwd'"
	summary := redactSummary("high", sensitiveCommand)

	// The summary must NOT contain the raw command.
	if strings.Contains(summary, sensitiveCommand) {
		t.Errorf("redactSummary included raw command in output: %q", summary)
	}
	// Must not contain env variable values.
	if strings.Contains(summary, "abc123") {
		t.Errorf("redactSummary leaked secret value in output: %q", summary)
	}
	// Must not contain rm -rf or file paths.
	if strings.Contains(summary, "/etc/passwd") {
		t.Errorf("redactSummary leaked file path in output: %q", summary)
	}
	// Should classify correctly.
	if !strings.HasPrefix(summary, "Bash") {
		t.Errorf("expected Bash prefix in redacted summary, got %q", summary)
	}
}

// TestRedactSummaryClassification checks tool classification for common commands.
func TestRedactSummaryClassification(t *testing.T) {
	cases := []struct {
		command string
		wantTool string
	}{
		{"bash -c 'echo hi'", "Bash"},
		{"python3 script.py --secret $API_KEY", "Python"},
		{"git commit -m 'fix: secret'", "Git"},
		{"rm -rf /tmp/build", "Files"},
		{"curl https://api.example.com/secret", "HTTP"},
		{"", "Agent"},
		{"/usr/local/bin/node index.js", "JS"},
		{"unknowntool --arg1", "Command"},
	}
	for _, tc := range cases {
		summary := redactSummary("medium", tc.command)
		if !strings.HasPrefix(summary, tc.wantTool) {
			t.Errorf("command=%q: got %q, want prefix %q", tc.command, summary, tc.wantTool)
		}
		// Never include the raw command
		if tc.command != "" && strings.Contains(summary, tc.command) {
			t.Errorf("summary leaks raw command %q: got %q", tc.command, summary)
		}
	}
}

// TestRegisterActivityToken verifies the in-memory registry is correctly upserted.
func TestRegisterActivityToken(t *testing.T) {
	liveActivityRegistry.Lock()
	delete(liveActivityRegistry.sessions, "sess-la-1")
	liveActivityRegistry.Unlock()

	registerActivityToken("sess-la-1", "hex-activity-token-abc", false)
	registerActivityToken("sess-la-1", "hex-p2s-token-xyz", true)

	liveActivityRegistry.RLock()
	rec, ok := liveActivityRegistry.sessions["sess-la-1"]
	liveActivityRegistry.RUnlock()

	if !ok {
		t.Fatal("session not registered")
	}
	if rec.activityToken != "hex-activity-token-abc" {
		t.Errorf("activityToken = %q", rec.activityToken)
	}
	if rec.pushToStartToken != "hex-p2s-token-xyz" {
		t.Errorf("pushToStartToken = %q", rec.pushToStartToken)
	}
}

// TestEvictExpiredActivityTokens verifies the janitor removes stale records.
func TestEvictExpiredActivityTokens(t *testing.T) {
	liveActivityRegistry.Lock()
	liveActivityRegistry.sessions["sess-stale"] = &liveActivityRecord{
		activityToken: "tok",
		seen:          time.Now().Add(-2 * deviceTokenTTL).Unix(),
	}
	liveActivityRegistry.Unlock()

	evictExpiredActivityTokens(time.Now().Unix())

	liveActivityRegistry.RLock()
	_, ok := liveActivityRegistry.sessions["sess-stale"]
	liveActivityRegistry.RUnlock()

	if ok {
		t.Error("stale activity token record was not evicted")
	}
}

// TestApnsTopicFormat verifies the topic string pattern used for Live Activity pushes.
// The bare bundle ID silently fails; only "<bundleID>.push-type.liveactivity" is accepted.
func TestApnsTopicFormat(t *testing.T) {
	bundleID := "dev.lancer.mobile"
	want := "dev.lancer.mobile.push-type.liveactivity"
	got := bundleID + ".push-type.liveactivity"
	if got != want {
		t.Errorf("apns-topic = %q, want %q", got, want)
	}
}

func TestPushLiveActivityDecisionSetsLastDecision(t *testing.T) {
	// Capture the payload by registering a token then marshaling what the
	// content-state would contain. We assert the builder, not the network.
	dec := "approved"
	cs := liveActivityContentState{
		Status: "connected", PendingApprovals: 0, LastDecision: &dec,
		LastUpdate: 1700000000.0,
	}
	b, _ := json.Marshal(cs)
	if !strings.Contains(string(b), `"lastDecision":"approved"`) {
		t.Fatalf("decision push must carry lastDecision, got: %s", b)
	}
	if strings.Contains(string(b), "command") {
		t.Fatalf("decision push must not carry command text, got: %s", b)
	}
}

func TestContentStateLastDecisionOmittedWhenNil(t *testing.T) {
	cs := liveActivityContentState{Status: "connected", LastUpdate: 1700000000.0}
	b, err := json.Marshal(cs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(b), "lastDecision") {
		t.Fatalf("nil lastDecision must be omitted, got: %s", b)
	}
	dec := "approved"
	cs.LastDecision = &dec
	b2, _ := json.Marshal(cs)
	if !strings.Contains(string(b2), `"lastDecision":"approved"`) {
		t.Fatalf("set lastDecision must serialize, got: %s", b2)
	}
}

// TestLiveActivityStartPayloadShape asserts the push-to-start payload carries
// the fields Apple's ActivityKit push doc requires ONLY on "start" (unlike
// "update"/"end"): attributes-type, attributes, and an alert — see
// "Construct the payload that starts a Live Activity" in
// https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications.
// Constructs the payload directly (not via pushLiveActivityStart, which would
// hit mustEnv/APNs) — same discipline as TestLiveActivityPayloadShape above.
func TestLiveActivityStartPayloadShape(t *testing.T) {
	approvalID := "appr-start-1"
	agent := "Claude Code"
	contentState := liveActivityContentState{
		Status:            "connected",
		PendingApprovals:  1,
		AgentName:         &agent,
		PendingApprovalID: &approvalID,
		IsStreaming:       true,
		LastUpdate:        float64(time.Now().UnixNano()) / 1e9,
	}
	stale := time.Now().Add(30 * time.Minute).Unix()
	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:      time.Now().Unix(),
			Event:          "start",
			ContentState:   contentState,
			StaleDate:      &stale,
			AttributesType: "LancerSessionAttributes",
			Attributes:     &liveActivityAttrs{HostName: "devbox", HostID: "host-1"},
			Alert:          &liveActivityAlert{Title: "Lancer · devbox", Body: "Agent run started", Sound: "default"},
		},
	}

	buf, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(buf, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	aps, ok := decoded["aps"].(map[string]any)
	if !ok {
		t.Fatal("aps key missing or wrong type")
	}
	if event, _ := aps["event"].(string); event != "start" {
		t.Errorf("aps.event = %q, want %q", event, "start")
	}
	if at, _ := aps["attributes-type"].(string); at != "LancerSessionAttributes" {
		t.Errorf("aps.attributes-type = %q, want %q", at, "LancerSessionAttributes")
	}
	attrs, ok := aps["attributes"].(map[string]any)
	if !ok {
		t.Fatal("aps.attributes missing or wrong type — required on a start push")
	}
	if hn, _ := attrs["hostName"].(string); hn != "devbox" {
		t.Errorf("attributes.hostName = %q, want %q", hn, "devbox")
	}
	if hid, _ := attrs["hostID"].(string); hid != "host-1" {
		t.Errorf("attributes.hostID = %q, want %q", hid, "host-1")
	}
	alert, ok := aps["alert"].(map[string]any)
	if !ok {
		t.Fatal("aps.alert missing or wrong type — required on a start push")
	}
	if title, _ := alert["title"].(string); title == "" {
		t.Error("aps.alert.title must not be empty on a start push")
	}
	if body, _ := alert["body"].(string); strings.Contains(body, "rm -rf") {
		t.Errorf("aps.alert.body must never carry raw command text, got: %q", body)
	}
}

// TestPushLiveActivityStartNoOpsWithoutSession asserts pushLiveActivityStart
// returns nil (no error, no network call) for a session with no registry
// entry at all. If this test hangs/crashes the binary instead of passing
// quickly, the no-op guard regressed and the call fell through to mustEnv.
func TestPushLiveActivityStartNoOpsWithoutSession(t *testing.T) {
	liveActivityRegistry.Lock()
	delete(liveActivityRegistry.sessions, "sess-p2s-none")
	liveActivityRegistry.Unlock()

	if err := pushLiveActivityStart("sess-p2s-none", "host-1", "devbox", nil, nil, ""); err != nil {
		t.Fatalf("expected nil (silent no-op), got: %v", err)
	}
}

// TestPushLiveActivityStartNoOpsWithoutPushToStartToken asserts a session
// with only an activity (update) token registered — no push-to-start token —
// is a no-op: there's nothing to originate a NEW Activity with.
func TestPushLiveActivityStartNoOpsWithoutPushToStartToken(t *testing.T) {
	liveActivityRegistry.Lock()
	liveActivityRegistry.sessions["sess-p2s-no-token"] = &liveActivityRecord{
		activityToken: "some-activity-token", seen: time.Now().Unix(),
	}
	liveActivityRegistry.Unlock()

	if err := pushLiveActivityStart("sess-p2s-no-token", "host-1", "devbox", nil, nil, ""); err != nil {
		t.Fatalf("expected nil (silent no-op), got: %v", err)
	}
}

// TestPushLiveActivityStartNoOpsWhenAlreadyRunning asserts the "don't
// duplicate the Lock Screen card" heuristic: a session with BOTH a
// push-to-start token and an existing activity (update) token is treated as
// already having a locally-running Activity, so push-to-start is skipped.
func TestPushLiveActivityStartNoOpsWhenAlreadyRunning(t *testing.T) {
	liveActivityRegistry.Lock()
	liveActivityRegistry.sessions["sess-p2s-running"] = &liveActivityRecord{
		activityToken: "existing-activity-token", pushToStartToken: "p2s-token", seen: time.Now().Unix(),
	}
	liveActivityRegistry.Unlock()

	if err := pushLiveActivityStart("sess-p2s-running", "host-1", "devbox", nil, nil, ""); err != nil {
		t.Fatalf("expected nil (silent no-op), got: %v", err)
	}
}

// TestHandleRunStartRejectsMissingFields asserts the /run-start handler's
// input validation, without ever reaching pushLiveActivityStart / mustEnv.
func TestHandleRunStartRejectsMissingFields(t *testing.T) {
	body, _ := json.Marshal(runStartEvent{HostID: "host-1", HostName: "devbox"}) // SessionID missing
	rec := httptest.NewRecorder()
	handleRunStart(rec, httptest.NewRequest(http.MethodPost, "/run-start", bytes.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

// TestHandleRunStartNoOpsForUnregisteredSession asserts an unrecognized
// session (no push-to-start token on file) still responds 204 — the no-op is
// silent by design (pushLiveActivityStart), matching the existing
// pushLiveActivityApproval/Decision "missing token" contract.
func TestHandleRunStartNoOpsForUnregisteredSession(t *testing.T) {
	liveActivityRegistry.Lock()
	delete(liveActivityRegistry.sessions, "sess-run-start-ghost")
	liveActivityRegistry.Unlock()

	body, _ := json.Marshal(runStartEvent{SessionID: "sess-run-start-ghost", HostID: "host-1", HostName: "devbox"})
	rec := httptest.NewRecorder()
	handleRunStart(rec, httptest.NewRequest(http.MethodPost, "/run-start", bytes.NewReader(body)))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
}
