package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// resetRegistryForTest clears the shared session registry between tests.
func resetRegistryForTest() {
	registry.Lock()
	registry.sessions = make(map[string]*sessionRecord)
	registry.Unlock()
}

// seedRelayToken registers a per-session relayToken directly (bypassing the
// /register control-plane secret) so decision/poll auth tests have a token to
// match against.
func seedRelayToken(t *testing.T, sessionID, token string) {
	t.Helper()
	registry.Lock()
	rec := registry.sessions[sessionID]
	if rec == nil {
		rec = &sessionRecord{}
		registry.sessions[sessionID] = rec
	}
	rec.relayToken = token
	rec.seen = time.Now().Unix()
	registry.Unlock()
}

// Tier 1 (control plane): when APPROVAL_RELAY_SECRET is set, /register must
// require the matching bearer secret; absence/mismatch → 401.
func TestControlPlaneSecretEnforcedOnRegister(t *testing.T) {
	resetRegistryForTest()
	t.Setenv("APPROVAL_RELAY_SECRET", "s3cret")

	body, _ := json.Marshal(map[string]string{"sessionId": "sess-A", "relayToken": "rt-abc"})

	noAuth := httptest.NewRecorder()
	handleRegister(noAuth, httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body)))
	if noAuth.Code != http.StatusUnauthorized {
		t.Fatalf("register without secret: status = %d, want 401", noAuth.Code)
	}

	wrong := httptest.NewRecorder()
	reqWrong := httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body))
	reqWrong.Header.Set("Authorization", "Bearer nope")
	handleRegister(wrong, reqWrong)
	if wrong.Code != http.StatusUnauthorized {
		t.Fatalf("register with wrong secret: status = %d, want 401", wrong.Code)
	}

	ok := httptest.NewRecorder()
	reqOK := httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body))
	reqOK.Header.Set("Authorization", "Bearer s3cret")
	handleRegister(ok, reqOK)
	if ok.Code != http.StatusNoContent {
		t.Fatalf("register with secret: status = %d, want 204", ok.Code)
	}
}

func TestHandleRegisterValidation(t *testing.T) {
	cases := []struct {
		name string
		body map[string]string
		want int
	}{
		{"ok deviceToken", map[string]string{"sessionId": "s", "deviceToken": "tok"}, http.StatusNoContent},
		{"ok relayToken", map[string]string{"sessionId": "s", "relayToken": "rt"}, http.StatusNoContent},
		{"ok both", map[string]string{"sessionId": "s", "deviceToken": "tok", "relayToken": "rt"}, http.StatusNoContent},
		{"missing both tokens", map[string]string{"sessionId": "s"}, http.StatusBadRequest},
		{"missing sessionId", map[string]string{"deviceToken": "tok"}, http.StatusBadRequest},
		{"empty", map[string]string{}, http.StatusBadRequest},
		{"oversized sessionId", map[string]string{"sessionId": strings.Repeat("a", maxSessionIDLen+1), "deviceToken": "tok"}, http.StatusBadRequest},
		{"oversized deviceToken", map[string]string{"sessionId": "s", "deviceToken": strings.Repeat("b", maxDeviceTokenLen+1)}, http.StatusBadRequest},
		{"oversized relayToken", map[string]string{"sessionId": "s", "relayToken": strings.Repeat("c", maxRelayTokenLen+1)}, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetRegistryForTest()
			body, _ := json.Marshal(tc.body)
			rec := httptest.NewRecorder()
			handleRegister(rec, httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body)))
			if rec.Code != tc.want {
				t.Fatalf("status = %d, want %d", rec.Code, tc.want)
			}
		})
	}
}

// lancerd's /register call carrying only a relayToken must upsert it without
// clobbering an APNs token the app registered separately (and vice versa).
func TestRegisterUpsertsRelayAndApnsIndependently(t *testing.T) {
	resetRegistryForTest()

	// App registers its APNs token first.
	appBody, _ := json.Marshal(map[string]string{"sessionId": "sess-A", "deviceToken": "apns-1"})
	recApp := httptest.NewRecorder()
	handleRegister(recApp, httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(appBody)))
	if recApp.Code != http.StatusNoContent {
		t.Fatalf("app register: status = %d, want 204", recApp.Code)
	}

	// lancerd registers the relayToken for the same session.
	cdBody, _ := json.Marshal(map[string]string{"sessionId": "sess-A", "relayToken": "rt-xyz"})
	recCD := httptest.NewRecorder()
	handleRegister(recCD, httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(cdBody)))
	if recCD.Code != http.StatusNoContent {
		t.Fatalf("lancerd register: status = %d, want 204", recCD.Code)
	}

	registry.RLock()
	rec := registry.sessions["sess-A"]
	registry.RUnlock()
	if rec == nil || rec.apnsToken != "apns-1" || rec.relayToken != "rt-xyz" {
		t.Fatalf("merged record = %+v, want apns-1 / rt-xyz", rec)
	}
}

// Exercises concurrent posts/polls/registrations so `go test -race` can prove
// every shared-map access is properly locked.
func TestRelayConcurrentAccess(t *testing.T) {
	resetDecisionsForTest()
	resetRegistryForTest()
	const workers = 64
	done := make(chan struct{}, workers*3)

	for i := 0; i < workers; i++ {
		sid := "sess-" + string(rune('A'+i%26)) + string(rune('0'+i%10))
		go func(sid string) {
			body, _ := json.Marshal(map[string]string{"approvalId": "a-" + sid, "sessionId": sid, "decision": "approve"})
			rec := httptest.NewRecorder()
			handlePostDecision(rec, httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body)))
			done <- struct{}{}
		}(sid)
		go func(sid string) {
			rec := httptest.NewRecorder()
			handlePollDecisions(rec, httptest.NewRequest(http.MethodGet, "/decisions?sessionId="+sid, nil))
			done <- struct{}{}
		}(sid)
		go func(sid string) {
			body, _ := json.Marshal(map[string]string{"sessionId": sid, "relayToken": "rt-" + sid})
			rec := httptest.NewRecorder()
			handleRegister(rec, httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body)))
			done <- struct{}{}
		}(sid)
	}
	for i := 0; i < workers*3; i++ {
		<-done
	}
}

// Stale session records (APNs token AND relayToken) are evicted by the janitor;
// fresh ones survive. This is what bounds the per-session relayToken store.
func TestEvictExpiredDevices(t *testing.T) {
	now := time.Now().Unix()
	registry.Lock()
	registry.sessions = map[string]*sessionRecord{
		"fresh": {apnsToken: "tok1", relayToken: "rt1", seen: now},
		"stale": {apnsToken: "tok2", relayToken: "rt2", seen: now - int64(deviceTokenTTL/time.Second) - 1},
	}
	registry.Unlock()

	evictExpiredDevices(now)

	registry.RLock()
	_, freshOK := registry.sessions["fresh"]
	_, staleOK := registry.sessions["stale"]
	registry.RUnlock()
	if !freshOK {
		t.Fatal("fresh session was evicted")
	}
	if staleOK {
		t.Fatal("stale session was not evicted")
	}

	// After eviction the stale session's relayToken no longer authorizes.
	if relaySessionAuthorized("stale", "rt2") {
		t.Fatal("evicted relayToken still authorized")
	}
}

// TestRelaySecretStartupCheck pins the production fail-fast guard: an empty
// APPROVAL_RELAY_SECRET must refuse startup in production and only warn in dev;
// a configured secret is always ok.
func TestRelaySecretStartupCheck(t *testing.T) {
	cases := []struct {
		name      string
		secret    string
		isProd    bool
		wantFatal bool
		wantWarn  bool
	}{
		{"empty+prod => fatal", "", true, true, false},
		{"empty+dev => warn", "", false, false, true},
		{"empty+dev whitespace => warn", "   ", false, false, true},
		{"set+prod => ok", "s3cret", true, false, false},
		{"set+dev => ok", "s3cret", false, false, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fatal, warn := relaySecretStartupCheck(c.secret, c.isProd)
			if (fatal != "") != c.wantFatal {
				t.Errorf("fatal: got %q, wantFatal=%v", fatal, c.wantFatal)
			}
			if (warn != "") != c.wantWarn {
				t.Errorf("warn: got %q, wantWarn=%v", warn, c.wantWarn)
			}
			if c.wantFatal && c.wantWarn {
				t.Fatal("test invariant: fatal and warn are mutually exclusive")
			}
		})
	}
}

func TestRelayProductionDeploymentFromEnv(t *testing.T) {
	cases := []struct {
		name string
		env  map[string]string
		want bool
	}{
		{"local", map[string]string{}, false},
		{"fly", map[string]string{"FLY_APP_NAME": "lancer-push"}, true},
		{"cloud run service", map[string]string{"K_SERVICE": "lancer-push"}, true},
		{"cloud run revision", map[string]string{"K_REVISION": "lancer-push-0001"}, true},
		{"explicit production", map[string]string{"LANCER_ENV": "production"}, true},
		{"app env prod", map[string]string{"APP_ENV": "prod"}, true},
		{"staging", map[string]string{"LANCER_ENV": "staging"}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := relayProductionDeploymentFromEnv(func(key string) string { return c.env[key] })
			if got != c.want {
				t.Fatalf("relayProductionDeploymentFromEnv() = %v, want %v", got, c.want)
			}
		})
	}
}
