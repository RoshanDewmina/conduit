// push-backend: minimal APNs delivery server for Lancer approval alerts.
//
// Deploy to Fly.io or AWS Lambda (as a Lambda function URL) — it receives
// a JSON-RPC lancerd event forwarded by the lancerd daemon and pushes
// a local notification to the registered iOS device.
//
// Build: CGO_ENABLED=0 GOOS=linux go build -o push-backend .
//
//	Run:   APNS_KEY_ID=... APNS_TEAM_ID=... APNS_KEY_PATH=AuthKey_XXX.p8 \
//	       APNS_BUNDLE_ID=dev.lancer.mobile ./push-backend
package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// sessionRecord holds the per-session relay state the backend learns from its
// two control-plane registration sources (both hit POST /register, authenticated
// by APPROVAL_RELAY_SECRET):
//   - apnsToken:  APNs device token, registered by the iOS app, used to push.
//   - relayToken: the per-session capability secret minted by lancerd. The app
//     and lancerd present it as `Authorization: Bearer <relayToken>` on the
//     decision-relay endpoints (POST /approval/decision, GET /decisions) and the
//     backend constant-time-compares it here. TREAT AS SECRET — never logged.
//   - seen:       last-touch unix time (registration or a successful relay auth),
//     used for TTL eviction so the map stays bounded.
//
// The two fields are upserted independently so the app's APNs registration and
// lancerd's relay-token registration can arrive in any order.
type sessionRecord struct {
	apnsToken  string
	relayToken string
	seen       int64
}

// registry maps sessionID → sessionRecord.
// In production, back this with Redis or DynamoDB.
var registry = struct {
	sync.RWMutex
	sessions map[string]*sessionRecord
}{sessions: make(map[string]*sessionRecord)}

const (
	// deviceTokenTTL evicts session records that haven't been refreshed. The
	// per-session relayToken shares this TTL (and the janitor sweep) so it stays
	// bounded; a live, actively-polling session slides past it because a
	// successful relay auth refreshes `seen`.
	deviceTokenTTL = 24 * time.Hour
	// maxRegisteredDevices hard-caps the session registry size.
	maxRegisteredDevices = 100_000
)

type registerRequest struct {
	SessionID   string `json:"sessionId"`
	DeviceToken string `json:"deviceToken,omitempty"`
	RelayToken  string `json:"relayToken,omitempty"`
}

type approvalEvent struct {
	ID        string `json:"id"`
	SessionID string `json:"sessionId"`
	Command   string `json:"command"`
	Risk      string `json:"risk"`
	HostName  string `json:"hostName"`
}

type runCompleteEvent struct {
	SessionID string `json:"sessionId"`
	Command   string `json:"command"`
	ExitCode  int    `json:"exitCode"`
	HostName  string `json:"hostName"`
}

// runStartEvent is the body for POST /run-start — lancerd's integration point
// for originating a Live Activity via push-to-start when a relay dispatch
// starts a run and the phone has no locally-running Activity for the session
// (see pushLiveActivityStart's no-op heuristic in liveactivity.go).
type runStartEvent struct {
	SessionID       string  `json:"sessionId"`
	HostID          string  `json:"hostId"`
	HostName        string  `json:"hostName"`
	Agent           *string `json:"agent,omitempty"`
	ApprovalID      *string `json:"approvalId,omitempty"`
	RedactedSummary string  `json:"redactedSummary,omitempty"`
}

// secretRequestEvent is the body for POST /secret-request — posted by
// lancerd's postSecretRequestPush (server.go) whenever an agent asks for a
// stored credential and the running phone client isn't attached to catch the
// live agent.secret.request notification. Mirrors approvalEvent's shape.
type secretRequestEvent struct {
	ID             string `json:"id"`
	SessionID      string `json:"sessionId"`
	Agent          string `json:"agent"`
	ToolName       string `json:"toolName"`
	CredentialType string `json:"credentialType"`
	RequestedScope string `json:"requestedScope"`
	HostName       string `json:"hostName"`
}

// questionEvent is the body for POST /question — posted by lancerd's
// postQuestionPush (question.go) whenever an agent's AskUserQuestion (or
// equivalent) tool call is pending and the running phone client isn't
// attached to catch the live agent.question.pending notification. Deliberately
// carries no question text or option labels — see pushQuestion's redaction note.
type questionEvent struct {
	ID         string `json:"id"`
	SessionID  string `json:"sessionId"`
	Agent      string `json:"agent"`
	HostName   string `json:"hostName"`
	Confidence string `json:"confidence,omitempty"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws/relay", handleWebSocketRelay)
	mux.HandleFunc("POST /register", handleRegister)
	mux.HandleFunc("POST /register-activity-token", handleRegisterActivityToken)
	mux.HandleFunc("POST /approval", handleApproval)
	mux.HandleFunc("POST /run-complete", handleRunComplete)
	mux.HandleFunc("POST /run-start", handleRunStart)
	mux.HandleFunc("POST /secret-request", handleSecretRequest)
	mux.HandleFunc("POST /question", handleQuestion)
	mux.HandleFunc("/approval/decision", handlePostDecision)
	mux.HandleFunc("/decisions", handlePollDecisions)
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	registerBillingRoutes(mux)
	registerCreditsRoutes(mux)
	registerQuotaRoutes(mux)
	registerAgentRoutes(mux)
	registerUsageRoutes(mux)
	registerArtifactRoutes(mux)
	registerScheduleRoutes(mux)
	registerRunLogRoutes(mux)
	registerOrgRoutes(mux)
	registerDeviceBindingRoutes(mux)
	initWebhookRoutes(mux)

	initEntitlementStore()
	initControlPlaneStore()
	initOpenRouterClient()
	initCreditsStore()
	initArtifactsStore()
	initSchedulesStore()
	initRunLogsStore()
	initGCPOrchestrationStore()
	initOrgsStore()
	startScheduleTicker()
	startRunReaper()
	startRelayJanitor()
	warnIfRelayUnauthenticated()
	warnIfAppAttestDisabled()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("push-backend listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(mux)))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := os.Getenv("CORS_ALLOW_ORIGIN")
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Stripe-Signature, X-Customer-Id, X-App-Account-Token")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// handleRegister is the lancerd→backend / app→backend control-plane endpoint.
// It is guarded by APPROVAL_RELAY_SECRET (the deployment-wide control-plane
// secret) so lancerd can bootstrap a session's relayToken before any
// per-session capability exists. It upserts whichever of {deviceToken,
// relayToken} the caller supplied for the session.
func handleRegister(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var req registerRequest
	if !decodeRelayJSON(w, r, &req) {
		return
	}
	if req.SessionID == "" || (req.DeviceToken == "" && req.RelayToken == "") {
		http.Error(w, "sessionId and at least one of deviceToken/relayToken required", http.StatusBadRequest)
		return
	}
	if len(req.SessionID) > maxSessionIDLen ||
		len(req.DeviceToken) > maxDeviceTokenLen ||
		len(req.RelayToken) > maxRelayTokenLen {
		http.Error(w, "field too large", http.StatusBadRequest)
		return
	}
	now := time.Now().Unix()
	registry.Lock()
	rec := registry.sessions[req.SessionID]
	if rec == nil {
		if len(registry.sessions) >= maxRegisteredDevices {
			registry.Unlock()
			http.Error(w, "registry capacity reached", http.StatusServiceUnavailable)
			return
		}
		rec = &sessionRecord{}
		registry.sessions[req.SessionID] = rec
	}
	if req.DeviceToken != "" {
		rec.apnsToken = req.DeviceToken
	}
	if req.RelayToken != "" {
		rec.relayToken = req.RelayToken
	}
	rec.seen = now
	registry.Unlock()
	// Log presence only — never the token material itself.
	log.Printf("registered session %s (apns=%t relay=%t)", req.SessionID, req.DeviceToken != "", req.RelayToken != "")
	w.WriteHeader(http.StatusNoContent)
}

// startRelayJanitor periodically evicts expired pending decisions and stale
// device registrations so the in-memory relay maps stay bounded. Started from
// main(); tests exercise the eviction helpers directly.
func startRelayJanitor() {
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			now := time.Now().Unix()
			decisions.Lock()
			evictExpiredDecisionsLocked(now)
			decisions.Unlock()
			evictExpiredDevices(now)
			evictExpiredActivityTokens(now)
			pairAttemptLimiter.sweepStale()
		}
	}()
}

// evictExpiredDevices removes session records (APNs token + relayToken) older
// than deviceTokenTTL. This is what keeps the per-session relayToken bounded.
func evictExpiredDevices(now int64) {
	ttl := int64(deviceTokenTTL / time.Second)
	registry.Lock()
	defer registry.Unlock()
	for sid, rec := range registry.sessions {
		if now-rec.seen >= ttl {
			delete(registry.sessions, sid)
		}
	}
}

// pushApprovalFn is the seam tests swap to avoid real APNs calls.
var pushApprovalFn = pushApproval

func handleApproval(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var ev approvalEvent
	if !decodeRelayJSON(w, r, &ev) {
		return
	}
	if ev.SessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}

	registry.RLock()
	rec, ok := registry.sessions[ev.SessionID]
	var token string
	if ok {
		token = rec.apnsToken
	}
	registry.RUnlock()
	if !ok || token == "" {
		log.Printf("no device token for session %s — dropping", ev.SessionID)
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if err := pushApprovalFn(token, ev); err != nil {
		log.Printf("APNs push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func handleRunComplete(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var ev runCompleteEvent
	if !decodeRelayJSON(w, r, &ev) {
		return
	}
	if ev.SessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}

	registry.RLock()
	rec, ok := registry.sessions[ev.SessionID]
	var token string
	if ok {
		token = rec.apnsToken
	}
	registry.RUnlock()
	if !ok || token == "" {
		log.Printf("no device token for session %s — dropping run-complete", ev.SessionID)
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if err := pushRunComplete(token, ev); err != nil {
		log.Printf("APNs run-complete push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleRunStart: POST /run-start. Guarded by the same Tier-1 control-plane
// secret as /approval and /run-complete. Fires a Live Activity push-to-start
// when a relay dispatch starts a run and the session has a push-to-start
// token on file — see pushLiveActivityStart's no-op heuristic (missing token,
// or an activity token already on file) for when this is skipped.
func handleRunStart(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var ev runStartEvent
	if !decodeRelayJSON(w, r, &ev) {
		return
	}
	if ev.SessionID == "" || ev.HostID == "" || ev.HostName == "" {
		http.Error(w, "sessionId, hostId and hostName required", http.StatusBadRequest)
		return
	}
	if len(ev.SessionID) > maxSessionIDLen || len(ev.HostID) > maxSessionIDLen {
		http.Error(w, "field too large", http.StatusBadRequest)
		return
	}

	if err := pushLiveActivityStart(ev.SessionID, ev.HostID, ev.HostName, ev.Agent, ev.ApprovalID, ev.RedactedSummary); err != nil {
		log.Printf("push-to-start Live Activity push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// pushSecretRequestFn is the seam tests swap to avoid real APNs calls.
var pushSecretRequestFn = pushSecretRequest

// handleSecretRequest: POST /secret-request. Guarded by the same Tier-1
// control-plane secret as /approval and /run-complete. lancerd's
// postSecretRequestPush (server.go) posts here whenever an agent asks for a
// stored credential and the phone isn't attached to catch the live
// agent.secret.request notification over the direct channel.
func handleSecretRequest(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var ev secretRequestEvent
	if !decodeRelayJSON(w, r, &ev) {
		return
	}
	if ev.SessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}

	registry.RLock()
	rec, ok := registry.sessions[ev.SessionID]
	var token string
	if ok {
		token = rec.apnsToken
	}
	registry.RUnlock()
	if !ok || token == "" {
		log.Printf("no device token for session %s — dropping secret-request", ev.SessionID)
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if err := pushSecretRequestFn(token, ev); err != nil {
		log.Printf("APNs secret-request push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// pushQuestionFn is the seam tests swap to avoid real APNs calls.
var pushQuestionFn = pushQuestion

// handleQuestion: POST /question. Guarded by the same Tier-1 control-plane
// secret as /approval and /run-complete. lancerd's postQuestionPush
// (question.go) posts here whenever an agent's question (AskUserQuestion or
// equivalent) is pending and the phone isn't attached to catch the live
// agent.question.pending notification — closing the gap where a
// backgrounded/killed app never learns the agent is blocked waiting on input.
func handleQuestion(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var ev questionEvent
	if !decodeRelayJSON(w, r, &ev) {
		return
	}
	if ev.SessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}

	registry.RLock()
	rec, ok := registry.sessions[ev.SessionID]
	var token string
	if ok {
		token = rec.apnsToken
	}
	registry.RUnlock()
	if !ok || token == "" {
		log.Printf("no device token for session %s — dropping question", ev.SessionID)
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if err := pushQuestionFn(token, ev); err != nil {
		log.Printf("APNs question push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func pushRunComplete(deviceToken string, ev runCompleteEvent) error {
	keyID := mustEnv("APNS_KEY_ID")
	teamID := mustEnv("APNS_TEAM_ID")
	keyPath := mustEnv("APNS_KEY_PATH")
	bundleID := mustEnv("APNS_BUNDLE_ID")

	key, err := loadP8Key(keyPath)
	if err != nil {
		return fmt.Errorf("load APNs key: %w", err)
	}
	token, err := makeJWT(keyID, teamID, key)
	if err != nil {
		return fmt.Errorf("make JWT: %w", err)
	}

	ok := ev.ExitCode == 0
	title := fmt.Sprintf("Run complete · %s", ev.HostName)
	if !ok {
		title = fmt.Sprintf("Run failed · %s", ev.HostName)
	}
	// PRIVACY: never expose raw command text on the lock screen. Use tool category + exit code.
	tool := classifyTool(ev.Command)
	body := fmt.Sprintf("%s — exit %d", tool, ev.ExitCode)

	payload := map[string]any{
		"aps": map[string]any{
			"alert":    map[string]string{"title": title, "body": body},
			"sound":    "default",
			"category": "run-complete",
		},
		"sessionId": ev.SessionID,
		"exitCode":  ev.ExitCode,
	}

	buf, _ := json.Marshal(payload)
	url := fmt.Sprintf("https://api.push.apple.com/3/device/%s", deviceToken)

	req, _ := http.NewRequest("POST", url, bytes.NewReader(buf))
	req.Header.Set("authorization", "bearer "+token)
	req.Header.Set("apns-topic", bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "5") // non-time-critical
	req.Header.Set("content-type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("APNs returned %d", resp.StatusCode)
	}
	return nil
}

func pushApproval(deviceToken string, ev approvalEvent) error {
	keyID := mustEnv("APNS_KEY_ID")
	teamID := mustEnv("APNS_TEAM_ID")
	keyPath := mustEnv("APNS_KEY_PATH")
	bundleID := mustEnv("APNS_BUNDLE_ID")

	key, err := loadP8Key(keyPath)
	if err != nil {
		return fmt.Errorf("load APNs key: %w", err)
	}

	token, err := makeJWT(keyID, teamID, key)
	if err != nil {
		return fmt.Errorf("make JWT: %w", err)
	}

	risk := ev.Risk
	if risk == "" {
		risk = "unknown"
	}
	title := fmt.Sprintf("Approval needed · %s", ev.HostName)
	// PRIVACY: never put raw command text, file paths, env values, or secrets
	// in the APNs alert body — it appears on the lock screen. Use a redacted
	// summary (risk + tool category). Full detail is fetched in-app post-unlock.
	body := redactSummary(risk, ev.Command)

	payload := map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{
				"title": title,
				"body":  body,
			},
			"sound":    "default",
			"badge":    1,
			"category": "approval",
		},
		"approvalId": ev.ID,
		"sessionId":  ev.SessionID,
		"risk":       risk,
	}

	buf, _ := json.Marshal(payload)
	if err := sendAPNsAlert(deviceToken, bundleID, token, buf, "10"); err != nil {
		return err
	}

	// Also update the Live Activity (best-effort; errors don't fail the alert push).
	_ = pushLiveActivityApproval(ev.SessionID, ev.ID, risk, body, nil)

	return nil
}

// pushSecretRequest sends an APNs alert for a pending agent.secret.request.
//
// PRIVACY: never put the credential's name, its requestedScope, or the
// requesting tool's raw arguments in the alert body — it appears on the lock
// screen. The credential TYPE category (e.g. "API key") is the most specific
// thing surfaced there; full detail is fetched in-app post-unlock, same
// discipline as pushApproval's redactSummary.
func pushSecretRequest(deviceToken string, ev secretRequestEvent) error {
	keyID := mustEnv("APNS_KEY_ID")
	teamID := mustEnv("APNS_TEAM_ID")
	keyPath := mustEnv("APNS_KEY_PATH")
	bundleID := mustEnv("APNS_BUNDLE_ID")

	key, err := loadP8Key(keyPath)
	if err != nil {
		return fmt.Errorf("load APNs key: %w", err)
	}
	token, err := makeJWT(keyID, teamID, key)
	if err != nil {
		return fmt.Errorf("make JWT: %w", err)
	}

	title := fmt.Sprintf("Credential requested · %s", ev.HostName)
	body := redactCredentialSummary(ev.CredentialType)

	payload := map[string]any{
		"aps": map[string]any{
			"alert":    map[string]string{"title": title, "body": body},
			"sound":    "default",
			"badge":    1,
			"category": "secret-request",
		},
		"requestId": ev.ID,
		"sessionId": ev.SessionID,
	}

	buf, _ := json.Marshal(payload)
	return sendAPNsAlert(deviceToken, bundleID, token, buf, "10")
}

// redactCredentialSummary returns a non-sensitive summary for a secret-request
// alert body. Only a generic credential-type category is surfaced — never the
// credential's name, value, or requested scope.
func redactCredentialSummary(credentialType string) string {
	kind := strings.TrimSpace(credentialType)
	if kind == "" {
		kind = "a credential"
	} else {
		kind = "a " + kind + " credential"
	}
	return fmt.Sprintf("An agent is requesting access to %s", kind)
}

// pushQuestion sends an APNs alert for a pending agent.question.pending event.
//
// PRIVACY: never put the question text, option labels, or free-text answer
// hints in the alert body — it appears on the lock screen. This is the whole
// point of the gap this closes (an unattended app must not leak
// AskUserQuestion content via a push preview). Full detail is fetched in-app
// post-unlock, same discipline as pushApproval's redactSummary.
func pushQuestion(deviceToken string, ev questionEvent) error {
	keyID := mustEnv("APNS_KEY_ID")
	teamID := mustEnv("APNS_TEAM_ID")
	keyPath := mustEnv("APNS_KEY_PATH")
	bundleID := mustEnv("APNS_BUNDLE_ID")

	key, err := loadP8Key(keyPath)
	if err != nil {
		return fmt.Errorf("load APNs key: %w", err)
	}
	token, err := makeJWT(keyID, teamID, key)
	if err != nil {
		return fmt.Errorf("make JWT: %w", err)
	}

	title := fmt.Sprintf("Question pending · %s", ev.HostName)
	body := "Agent has a question and is waiting for your input"

	payload := map[string]any{
		"aps": map[string]any{
			"alert":    map[string]string{"title": title, "body": body},
			"sound":    "default",
			"badge":    1,
			"category": "question",
		},
		"questionId": ev.ID,
		"sessionId":  ev.SessionID,
	}

	buf, _ := json.Marshal(payload)
	return sendAPNsAlert(deviceToken, bundleID, token, buf, "10")
}

// sendAPNsAlert POSTs an alert payload to APNs, trying the production host first
// and falling back to the sandbox host on a 400 BadDeviceToken. Development-signed
// builds (Xcode automatic signing forces aps-environment=development) get sandbox
// tokens that production rejects with 400; TestFlight/App Store builds get
// production tokens. Trying both makes push work for either without per-build
// configuration. The reason is logged so token-environment issues are diagnosable.
func sendAPNsAlert(deviceToken, bundleID, jwt string, payload []byte, priority string) error {
	hosts := []string{"api.push.apple.com", "api.sandbox.push.apple.com"}
	var lastStatus int
	var lastReason string
	for _, host := range hosts {
		url := fmt.Sprintf("https://%s/3/device/%s", host, deviceToken)
		req, _ := http.NewRequest("POST", url, bytes.NewReader(payload))
		req.Header.Set("authorization", "bearer "+jwt)
		req.Header.Set("apns-topic", bundleID)
		req.Header.Set("apns-push-type", "alert")
		req.Header.Set("apns-priority", priority)
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
		// Only a 400 (e.g. BadDeviceToken — wrong environment) is worth retrying on
		// the other host; other statuses are terminal.
		if resp.StatusCode != http.StatusBadRequest {
			break
		}
		log.Printf("APNs %s rejected token (HTTP %d: %s) — trying next host", host, resp.StatusCode, lastReason)
	}
	return fmt.Errorf("APNs returned %d: %s", lastStatus, lastReason)
}

// registerActivityTokenRequest is the body for POST /register-activity-token.
type registerActivityTokenRequest struct {
	SessionID      string `json:"sessionId"`
	ActivityToken  string `json:"activityToken,omitempty"`
	IsPushToStart  bool   `json:"isPushToStart,omitempty"`
}

// handleRegisterActivityToken: POST /register-activity-token
// Guarded by the same Tier-1 control-plane secret as /register.
// The iOS app posts here whenever its Live Activity push token (or the
// push-to-start token) changes.
func handleRegisterActivityToken(w http.ResponseWriter, r *http.Request) {
	if !relayAuthorized(w, r) {
		return
	}
	var req registerActivityTokenRequest
	if !decodeRelayJSON(w, r, &req) {
		return
	}
	if req.SessionID == "" || req.ActivityToken == "" {
		http.Error(w, "sessionId and activityToken required", http.StatusBadRequest)
		return
	}
	if len(req.SessionID) > maxSessionIDLen || len(req.ActivityToken) > maxDeviceTokenLen {
		http.Error(w, "field too large", http.StatusBadRequest)
		return
	}
	registerActivityToken(req.SessionID, req.ActivityToken, req.IsPushToStart)
	log.Printf("registered activity token for session %s (pushToStart=%t)", req.SessionID, req.IsPushToStart)
	w.WriteHeader(http.StatusNoContent)
}

func makeJWT(keyID, teamID string, key *ecdsa.PrivateKey) (string, error) {
	claims := jwt.RegisteredClaims{
		Issuer:   teamID,
		IssuedAt: jwt.NewNumericDate(time.Now()),
	}
	t := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	t.Header["kid"] = keyID
	return t.SignedString(key)
}

func loadP8Key(path string) (*ecdsa.PrivateKey, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("no PEM block found")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	ec, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("not an ECDSA key")
	}
	return ec, nil
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("required env var %s is not set", k)
	}
	return v
}
