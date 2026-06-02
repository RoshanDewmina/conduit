// push-backend: minimal APNs delivery server for Conduit approval alerts.
//
// Deploy to Fly.io or AWS Lambda (as a Lambda function URL) — it receives
// a JSON-RPC conduitd event forwarded by the conduitd daemon and pushes
// a local notification to the registered iOS device.
//
// Build: CGO_ENABLED=0 GOOS=linux go build -o push-backend .
//
//	Run:   APNS_KEY_ID=... APNS_TEAM_ID=... APNS_KEY_PATH=AuthKey_XXX.p8 \
//	       APNS_BUNDLE_ID=dev.conduit.mobile ./push-backend
package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// DeviceRegistry maps sessionID → APNs device token.
// In production, back this with Redis or DynamoDB.
var registry = struct {
	sync.RWMutex
	tokens map[string]string
}{tokens: make(map[string]string)}

type registerRequest struct {
	SessionID   string `json:"sessionId"`
	DeviceToken string `json:"deviceToken"`
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

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /register", handleRegister)
	mux.HandleFunc("POST /approval", handleApproval)
	mux.HandleFunc("POST /run-complete", handleRunComplete)
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
	registerOrgRoutes(mux)

	initEntitlementStore()
	initControlPlaneStore()
	initOpenRouterClient()
	initCreditsStore()
	initArtifactsStore()
	initSchedulesStore()
	initGCPOrchestrationStore()
	initOrgsStore()
	startScheduleTicker()

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
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Stripe-Signature, X-Customer-Id, X-App-Account-Token")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	registry.Lock()
	registry.tokens[req.SessionID] = req.DeviceToken
	registry.Unlock()
	log.Printf("registered device token for session %s", req.SessionID)
	w.WriteHeader(http.StatusNoContent)
}

func handleApproval(w http.ResponseWriter, r *http.Request) {
	var ev approvalEvent
	if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	registry.RLock()
	token, ok := registry.tokens[ev.SessionID]
	registry.RUnlock()
	if !ok {
		log.Printf("no device token for session %s — dropping", ev.SessionID)
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if err := pushApproval(token, ev); err != nil {
		log.Printf("APNs push failed: %v", err)
		http.Error(w, "push failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func handleRunComplete(w http.ResponseWriter, r *http.Request) {
	var ev runCompleteEvent
	if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	registry.RLock()
	token, ok := registry.tokens[ev.SessionID]
	registry.RUnlock()
	if !ok {
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
	body := fmt.Sprintf("%s — exit %d", ev.Command, ev.ExitCode)

	payload := map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{"title": title, "body": body},
			"sound": "default",
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
	body := ev.Command
	if body == "" {
		body = "Agent action pending"
	}

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
	host := "api.push.apple.com"
	url := fmt.Sprintf("https://%s/3/device/%s", host, deviceToken)

	req, _ := http.NewRequest("POST", url, bytes.NewReader(buf))
	req.Header.Set("authorization", "bearer "+token)
	req.Header.Set("apns-topic", bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
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
