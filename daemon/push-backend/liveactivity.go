package main

// ActivityKit APNs sender for Conduit Live Activities.
//
// Strict contract — updates fail SILENTLY at the iOS side if any of these are wrong:
//   - apns-topic MUST be "<bundleID>.push-type.liveactivity" (NOT the bare bundle id).
//   - apns-push-type: liveactivity
//   - apns-priority: 10 for user-visible changes (budgeted by iOS); 5 for background updates.
//   - Payload: aps.timestamp (unix secs), aps.event ("update"|"end"), aps.content-state.
//   - aps.content-state MUST decode exactly into ConduitSessionAttributes.ContentState.
//   - Date fields: ActivityKit decodes dates using the default JSONDecoder strategy, which
//     expects Unix time as a JSON number (secondsSince1970 fractional float). This matches
//     Swift's JSONEncoder default for Date (which emits a double). We pin this with a test.
//
// Payload privacy: content-state carries ONLY non-sensitive summary fields. The full command
// text, file contents, env values, and secrets are NEVER included — see redactSummary().

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

// liveActivityRecord holds a per-session Live Activity push token.
// Keyed by sessionID, separate from the device (alert) token.
type liveActivityRecord struct {
	activityToken  string // per-activity update token; changes on every new Activity
	pushToStartToken string // push-to-start token; stable per install
	seen           int64
}

// liveActivityRegistry stores Live Activity tokens keyed by sessionID.
// In production, back this with Redis or DynamoDB (same as deviceTokens).
var liveActivityRegistry = struct {
	sync.RWMutex
	sessions map[string]*liveActivityRecord
}{sessions: make(map[string]*liveActivityRecord)}

// registerActivityToken upserts the activity or push-to-start token for a session.
func registerActivityToken(sessionID, token string, isPushToStart bool) {
	now := time.Now().Unix()
	liveActivityRegistry.Lock()
	defer liveActivityRegistry.Unlock()
	rec := liveActivityRegistry.sessions[sessionID]
	if rec == nil {
		rec = &liveActivityRecord{}
		liveActivityRegistry.sessions[sessionID] = rec
	}
	if isPushToStart {
		rec.pushToStartToken = token
	} else {
		rec.activityToken = token
	}
	rec.seen = now
}

// evictExpiredActivityTokens removes records older than deviceTokenTTL (shared with the device registry).
func evictExpiredActivityTokens(now int64) {
	ttl := int64(deviceTokenTTL / time.Second)
	liveActivityRegistry.Lock()
	defer liveActivityRegistry.Unlock()
	for sid, rec := range liveActivityRegistry.sessions {
		if now-rec.seen >= ttl {
			delete(liveActivityRegistry.sessions, sid)
		}
	}
}

// liveActivityContentState is the Go mirror of ConduitSessionAttributes.ContentState.
//
// DATE ENCODING CONTRACT (pinned by TestLiveActivityDateEncoding):
// Swift's JSONEncoder encodes Date as a JSON number: Unix seconds as a float64
// (e.g. 1700000000.0). ActivityKit's default JSONDecoder expects the same.
// We emit lastUpdate as a float64 Unix timestamp — a mismatch drops the whole update silently.
type liveActivityContentState struct {
	Status            string   `json:"status"`
	PendingApprovals  int      `json:"pendingApprovals"`
	AgentName         *string  `json:"agentName,omitempty"`
	PendingApprovalID *string  `json:"pendingApprovalID,omitempty"`
	IsStreaming       bool     `json:"isStreaming"`
	Cost              *float64 `json:"cost,omitempty"`
	// LastDecision is a transient confirmation pushed once after a decision
	// resolves ("approved"/"rejected"); omitted in steady state. Mirrors the
	// Swift ContentState.lastDecision optional.
	LastDecision *string `json:"lastDecision,omitempty"`
	// lastUpdate encoded as a Unix fractional seconds float — matches Swift's
	// default JSONEncoder Date strategy and ActivityKit's default decoder.
	LastUpdate float64 `json:"lastUpdate"`
}

// liveActivityPayload is the full APNs payload for a Live Activity update.
type liveActivityPayload struct {
	APS liveActivityAPS `json:"aps"`
}

type liveActivityAPS struct {
	Timestamp    int64                    `json:"timestamp"`
	Event        string                   `json:"event"` // "update" or "end"
	ContentState liveActivityContentState `json:"content-state"`
	// StaleDate is optional: unix timestamp after which the Live Activity is
	// considered stale. We set it 30 min ahead — same as the local update path.
	StaleDate *int64 `json:"stale-date,omitempty"`
}

// pushLiveActivityApproval sends a Live Activity content-state update via APNs
// to signal a new pending approval. It uses the per-activity update token if
// one is registered, and falls back silently (the alert-push path still fires).
//
// PRIVACY: content-state contains ONLY the redacted summary; never the raw command.
func pushLiveActivityApproval(sessionID, approvalID, riskLevel, redactedSummary string, agentName *string) error {
	liveActivityRegistry.RLock()
	rec, ok := liveActivityRegistry.sessions[sessionID]
	var activityToken string
	if ok {
		activityToken = rec.activityToken
	}
	liveActivityRegistry.RUnlock()

	if !ok || activityToken == "" {
		return nil // no activity token registered yet; the alert push still fires
	}

	stale := time.Now().Add(30 * time.Minute).Unix()
	pending := 1
	contentState := liveActivityContentState{
		Status:            "connected",
		PendingApprovals:  pending,
		AgentName:         agentName,
		PendingApprovalID: &approvalID,
		IsStreaming:       false,
		LastUpdate:        float64(time.Now().UnixNano()) / 1e9,
	}

	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:    time.Now().Unix(),
			Event:        "update",
			ContentState: contentState,
			StaleDate:    &stale,
		},
	}

	return sendLiveActivityPush(activityToken, payload, 10)
}

// pushLiveActivityEnd sends a Live Activity "end" event when the session ends.
func pushLiveActivityEnd(sessionID string) error {
	liveActivityRegistry.RLock()
	rec, ok := liveActivityRegistry.sessions[sessionID]
	var activityToken string
	if ok {
		activityToken = rec.activityToken
	}
	liveActivityRegistry.RUnlock()

	if !ok || activityToken == "" {
		return nil
	}

	contentState := liveActivityContentState{
		Status:           "suspended",
		PendingApprovals: 0,
		LastUpdate:       float64(time.Now().UnixNano()) / 1e9,
	}
	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:    time.Now().Unix(),
			Event:        "end",
			ContentState: contentState,
		},
	}
	return sendLiveActivityPush(activityToken, payload, 10)
}

// sendLiveActivityPush delivers a Live Activity APNs push with the strict headers.
func sendLiveActivityPush(activityToken string, payload liveActivityPayload, priority int) error {
	keyID := mustEnv("APNS_KEY_ID")
	teamID := mustEnv("APNS_TEAM_ID")
	keyPath := mustEnv("APNS_KEY_PATH")
	bundleID := mustEnv("APNS_BUNDLE_ID")

	key, err := loadP8Key(keyPath)
	if err != nil {
		return fmt.Errorf("load APNs key: %w", err)
	}
	jwtToken, err := makeJWT(keyID, teamID, key)
	if err != nil {
		return fmt.Errorf("make JWT: %w", err)
	}

	buf, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal Live Activity payload: %w", err)
	}

	url := fmt.Sprintf("https://api.push.apple.com/3/device/%s", activityToken)
	req, err := http.NewRequest("POST", url, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+jwtToken)
	// apns-topic MUST be "<bundleID>.push-type.liveactivity" — the bare bundle id silently fails.
	req.Header.Set("apns-topic", bundleID+".push-type.liveactivity")
	req.Header.Set("apns-push-type", "liveactivity")
	req.Header.Set("apns-priority", fmt.Sprintf("%d", priority))
	req.Header.Set("content-type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("APNs Live Activity returned %d", resp.StatusCode)
	}
	return nil
}

// redactSummary returns a non-sensitive summary string for APNs payloads.
// The full command text, file contents, env values, and secrets are NEVER
// included. The lock screen and Live Activity content-state only carry this
// redacted form; full detail is fetched in-app after device unlock.
func redactSummary(risk, command string) string {
	tool := classifyTool(command)
	switch risk {
	case "critical":
		return fmt.Sprintf("%s · critical action", tool)
	case "high":
		return fmt.Sprintf("%s · high-risk action", tool)
	case "medium":
		return fmt.Sprintf("%s · action pending", tool)
	default:
		return fmt.Sprintf("%s · action pending", tool)
	}
}

// classifyTool returns a short, non-sensitive tool-category label derived from
// the beginning of the command string. Only the command name (first token) is
// examined — never file paths, arguments, or env values.
func classifyTool(command string) string {
	if command == "" {
		return "Agent"
	}
	// Extract only the first word (command name); ignore all arguments.
	name := command
	for i, c := range command {
		if c == ' ' || c == '\t' || c == '\n' {
			name = command[:i]
			break
		}
	}
	// Strip leading path components.
	for i := len(name) - 1; i >= 0; i-- {
		if name[i] == '/' {
			name = name[i+1:]
			break
		}
	}
	switch name {
	case "bash", "sh", "zsh", "fish", "ksh":
		return "Bash"
	case "python", "python3", "python2":
		return "Python"
	case "node", "bun", "deno":
		return "JS"
	case "go", "gofmt":
		return "Go"
	case "swift", "swiftc":
		return "Swift"
	case "curl", "wget":
		return "HTTP"
	case "git":
		return "Git"
	case "rm", "mv", "cp", "mkdir", "touch":
		return "Files"
	default:
		return "Command"
	}
}
