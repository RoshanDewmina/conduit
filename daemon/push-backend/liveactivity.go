package main

// ActivityKit APNs sender for Lancer Live Activities.
//
// Strict contract — updates fail SILENTLY at the iOS side if any of these are wrong:
//   - apns-topic MUST be "<bundleID>.push-type.liveactivity" (NOT the bare bundle id).
//   - apns-push-type: liveactivity
//   - apns-priority: 10 for user-visible changes (budgeted by iOS); 5 for background updates.
//   - Payload: aps.timestamp (unix secs), aps.event ("update"|"end"), aps.content-state.
//   - aps.content-state MUST decode exactly into LancerSessionAttributes.ContentState.
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
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// liveActivityRecord holds a per-session Live Activity push token.
// Keyed by sessionID, separate from the device (alert) token.
type liveActivityRecord struct {
	activityToken    string // per-activity update token; changes on every new Activity
	pushToStartToken string // push-to-start token; stable per install
	seen             int64
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

// liveActivityContentState is the Go mirror of LancerSessionAttributes.ContentState.
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
	Event        string                   `json:"event"` // "start", "update", or "end"
	ContentState liveActivityContentState `json:"content-state"`
	// StaleDate is optional: unix timestamp after which the Live Activity is
	// considered stale. We set it 30 min ahead — same as the local update path.
	StaleDate *int64 `json:"stale-date,omitempty"`
	// AttributesType/Attributes/Alert are required by APNs only on "start" —
	// see "Construct the payload that starts a Live Activity" in Apple's
	// ActivityKit push notification doc. Omitted (empty) on "update"/"end".
	AttributesType string             `json:"attributes-type,omitempty"`
	Attributes     *liveActivityAttrs `json:"attributes,omitempty"`
	Alert          *liveActivityAlert `json:"alert,omitempty"`
}

// liveActivityAttrs is the Go mirror of LancerSessionAttributes' fixed
// (non-content-state) fields — required on a "start" push so the system knows
// which host the new Activity belongs to.
type liveActivityAttrs struct {
	HostName string `json:"hostName"`
	HostID   string `json:"hostID"`
}

// liveActivityAlert makes a push-to-start notification highlight the device —
// Apple's doc requires an alert on "start" pushes so a person isn't surprised
// by a Live Activity appearing with no accompanying notification.
type liveActivityAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	Sound string `json:"sound,omitempty"`
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

// pushLiveActivityDecision sends a transient "decision landed" content-state so
// the lock screen / Dynamic Island can confirm a just-resolved approval — including
// the cold path, where a killed-app Approve is resolved server-side and only a push
// can confirm it. The widget shows a ✓ for ~4s; a subsequent update/end clears it.
// PRIVACY: carries only the decision verb, never command text.
func pushLiveActivityDecision(sessionID, decision string) error {
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

	stale := time.Now().Add(30 * time.Minute).Unix()
	d := decision
	contentState := liveActivityContentState{
		Status:           "connected",
		PendingApprovals: 0,
		IsStreaming:      false,
		LastDecision:     &d,
		LastUpdate:       float64(time.Now().UnixNano()) / 1e9,
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

// pushLiveActivityStart originates a NEW Live Activity purely from a server
// push, via the registered push-to-start token — the only way to start one
// when the app is fully closed and no local daemon connection exists (relay-
// only V1 architecture; see docs/wwdc26-lancer-opportunity-audit/04-live-
// activities-and-dynamic-island.md Gap #3).
//
// No-ops (returns nil) when there's no push-to-start token on file for the
// session, or when an activity update token IS on file — a heuristic for "a
// local Activity is probably already running," since starting a second one
// for the same session would just duplicate the Lock Screen card. This is a
// best-effort signal, not a guarantee: the registry has no explicit "the app
// ended its local Activity" event, so a stale activityToken can suppress a
// start this heuristic should have allowed. Reusing the existing per-session
// registry (rather than adding a new store) keeps this consistent with
// pushLiveActivityApproval/pushLiveActivityDecision above.
//
// PRIVACY: content-state and the alert body carry only the redacted summary,
// never the raw command — same contract as pushLiveActivityApproval.
func pushLiveActivityStart(sessionID, hostID, hostName string, agentName *string, approvalID *string, redactedSummary string) error {
	liveActivityRegistry.RLock()
	rec, ok := liveActivityRegistry.sessions[sessionID]
	var pushToStartToken, existingActivityToken string
	if ok {
		pushToStartToken = rec.pushToStartToken
		existingActivityToken = rec.activityToken
	}
	liveActivityRegistry.RUnlock()

	if !ok || pushToStartToken == "" || existingActivityToken != "" {
		return nil
	}

	stale := time.Now().Add(30 * time.Minute).Unix()
	pending := 0
	if approvalID != nil {
		pending = 1
	}
	contentState := liveActivityContentState{
		Status:            "connected",
		PendingApprovals:  pending,
		AgentName:         agentName,
		PendingApprovalID: approvalID,
		IsStreaming:       true,
		LastUpdate:        float64(time.Now().UnixNano()) / 1e9,
	}

	title := fmt.Sprintf("Lancer · %s", hostName)
	body := redactedSummary
	if body == "" {
		body = "Agent run started"
	}

	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:      time.Now().Unix(),
			Event:          "start",
			ContentState:   contentState,
			StaleDate:      &stale,
			AttributesType: "LancerSessionAttributes",
			Attributes:     &liveActivityAttrs{HostName: hostName, HostID: hostID},
			Alert:          &liveActivityAlert{Title: title, Body: body, Sound: "default"},
		},
	}

	return sendLiveActivityPush(pushToStartToken, payload, 10)
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

	// Production first, sandbox on 400 BadDeviceToken — same two-host strategy
	// and rationale as sendAPNsAlert (main.go): development-signed builds get
	// sandbox activity tokens that api.push.apple.com rejects with 400.
	hosts := []string{"api.push.apple.com", "api.sandbox.push.apple.com"}
	var lastStatus int
	var lastReason string
	for _, host := range hosts {
		url := fmt.Sprintf("https://%s/3/device/%s", host, activityToken)
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
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode == http.StatusOK {
			return nil
		}
		lastStatus = resp.StatusCode
		lastReason = strings.TrimSpace(string(body))
		if resp.StatusCode != http.StatusBadRequest {
			break
		}
		log.Printf("APNs %s rejected Live Activity token (HTTP %d: %s) — trying next host", host, lastStatus, lastReason)
	}
	return fmt.Errorf("APNs Live Activity returned %d: %s", lastStatus, lastReason)
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
