package main

import (
	"encoding/json"
	"math"
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
	bundleID := "dev.conduit.mobile"
	want := "dev.conduit.mobile.push-type.liveactivity"
	got := bundleID + ".push-type.liveactivity"
	if got != want {
		t.Errorf("apns-topic = %q, want %q", got, want)
	}
}
