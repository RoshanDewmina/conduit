package main

import (
	"crypto/subtle"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// Limits for the approval-relay endpoints (/register, /approval, /run-complete,
// /secret-request, /question, /approval/decision, /decisions). These endpoints
// carry only small JSON control messages and — unlike the hosted-engine
// endpoints — are not behind an entitlement bearer token, so they need their
// own input bounds to resist memory-exhaustion DoS.
const (
	// maxRelayBodyBytes bounds every relay request body. 64 KiB is generous for a
	// device token / approval id / decision while preventing unbounded reads.
	maxRelayBodyBytes = 64 << 10

	maxSessionIDLen       = 256
	maxApprovalIDLen      = 256
	maxDeviceTokenLen     = 4096
	maxEditedToolInputLen = 32 << 10
	// maxRelayTokenLen bounds the per-session capability token. lancerd mints a
	// 32-byte base64url token (43 chars); the cap is generous headroom.
	maxRelayTokenLen = 512
)

// ───────────────────────────────────────────────────────────────────────────
// Two-tier authentication model for the approval relay
//
// Tier 1 — CONTROL PLANE (deployment-wide shared secret, APPROVAL_RELAY_SECRET):
//   guards /register, /approval, /run-complete, /secret-request, /question.
//   These are lancerd→backend (and app→backend for APNs registration) control
//   messages. The shared secret lets lancerd bootstrap a session's relayToken
//   BEFORE any per-session capability exists. Enforced by relayAuthorized().
//
// Tier 2 — PER-SESSION CAPABILITY (relayToken): guards POST /approval/decision
//   (from the app) and GET /decisions (from lancerd). lancerd mints a random
//   per-session relayToken, registers it via Tier 1, and delivers it to the app
//   over the authenticated DaemonChannel. Callers present it as
//   `Authorization: Bearer <relayToken>`; the backend constant-time-compares it
//   against the stored token for that sessionId. Enforced by
//   relaySessionAuthorized(). This is what stops a party that merely learned a
//   sessionId (it leaks via APNs payloads / query logs) — or even one holding
//   the shared secret — from forging a cross-session approve/approveAlways or
//   draining another session's decisions.
// ───────────────────────────────────────────────────────────────────────────

// relaySharedSecret returns the optional control-plane shared secret guarding
// the relay's Tier-1 endpoints, or "" when unset.
//
// SECURITY NOTE: this is the CONTROL-PLANE (Tier 1) secret only. The full fix
// for cross-session decision spoofing (docs/audit/findings/review-backend.md,
// BLOCKER-1 / B2) is the per-session capability token, which NOW EXISTS — see
// relaySessionAuthorized() and the two-tier model documented above. A single
// shared secret cannot distinguish one legitimate client from another, so it is
// NOT sufficient on the decision/poll endpoints; those use the per-session
// relayToken. The shared secret remains the right guard for /register,
// /approval and /run-complete because lancerd must register a session's
// relayToken before any per-session capability exists (bootstrap), and because
// these are control messages, not capability-scoped relay traffic.
func relaySharedSecret() string {
	return strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET"))
}

// relayAuthorized enforces the optional control-plane shared-secret guard
// (Tier 1) on /register, /approval and /run-complete. Returns true when the
// request may proceed. When no secret is configured the control plane is open
// (legacy behaviour) — main() logs one startup warning in that case.
func relayAuthorized(w http.ResponseWriter, r *http.Request) bool {
	secret := relaySharedSecret()
	if secret == "" {
		return true
	}
	// Constant-time compare to avoid leaking the secret via timing.
	if subtle.ConstantTimeCompare([]byte(bearerToken(r)), []byte(secret)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return false
	}
	return true
}

// bearerToken extracts the token from an `Authorization: Bearer <token>` header.
// Returns "" when the header is missing or malformed.
func bearerToken(r *http.Request) string {
	h := strings.TrimSpace(r.Header.Get("Authorization"))
	const prefix = "Bearer "
	if len(h) > len(prefix) && strings.EqualFold(h[:len(prefix)], prefix) {
		return strings.TrimSpace(h[len(prefix):])
	}
	return ""
}

// relaySessionAuthorized enforces the per-session capability (Tier 2) on the
// decision-relay endpoints. It constant-time-compares `provided` against the
// relayToken lancerd registered for sessionID. FAIL-CLOSED: an empty
// sessionId/token, an unknown session, a session with no registered relayToken,
// or a mismatch all return false (the caller must respond 401 with no side
// effects). On success it refreshes the session's last-seen stamp so an
// actively-polling/posting session slides past the 24h TTL.
func relaySessionAuthorized(sessionID, provided string) bool {
	if sessionID == "" || provided == "" {
		return false
	}
	registry.Lock()
	defer registry.Unlock()
	rec := registry.sessions[sessionID]
	if rec == nil || rec.relayToken == "" {
		return false
	}
	if subtle.ConstantTimeCompare([]byte(provided), []byte(rec.relayToken)) != 1 {
		return false
	}
	rec.seen = time.Now().Unix()
	return true
}

// decodeRelayJSON caps the request body and decodes JSON into dst. It returns
// false (after writing a 400) on any read/parse error. The error message is
// intentionally generic so decoder internals are never echoed to the caller.
func decodeRelayJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxRelayBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return false
	}
	return true
}

// relaySecretStartupCheck is the pure, testable decision for the startup guard.
// It returns (fatal, warn): `fatal` non-empty means refuse to start; otherwise
// `warn` non-empty means log a warning and continue. Inputs are passed in so the
// behaviour can be unit-tested without touching the process environment or
// calling os.Exit.
//
//   - secret present                    → ("", "")        ok
//   - secret empty + production         → (fatalMsg, "")  refuse to start
//   - secret empty + non-production     → ("", warnMsg)   warn, continue
func relaySecretStartupCheck(secret string, isProd bool) (fatal, warn string) {
	if strings.TrimSpace(secret) != "" {
		return "", ""
	}
	if isProd {
		return "SECURITY: APPROVAL_RELAY_SECRET is unset in a production deployment " +
			"(Fly.io, Cloud Run, or LANCER_ENV=production). The control-plane endpoints /register, /approval and " +
			"/run-complete would be UNAUTHENTICATED — anyone could overwrite a session's " +
			"relayToken/APNs token. Refusing to start. Set APPROVAL_RELAY_SECRET to a strong random value.", ""
	}
	return "", "SECURITY WARNING: APPROVAL_RELAY_SECRET is unset — the control-plane endpoints /register, /approval and /run-complete are UNAUTHENTICATED, so anyone can register/overwrite a session's relayToken and APNs token (see docs/audit/findings/fix-backend-relay-auth.md). The per-session relayToken still gates /approval/decision and /decisions, but it is only as trustworthy as the registration that minted it. Set APPROVAL_RELAY_SECRET in production."
}

// warnIfRelayUnauthenticated guards the control-plane secret at startup.
// FAIL-CLOSED in production: when APPROVAL_RELAY_SECRET is unset AND the process
// is running as a deployed Fly app, Cloud Run service, or explicit production
// env, it log.Fatal()s rather than serve unauthenticated /register, /approval
// and /run-complete. In local/dev it logs one loud warning and continues.
// Called from main().
func warnIfRelayUnauthenticated() {
	fatal, warn := relaySecretStartupCheck(relaySharedSecret(), relayProductionDeployment())
	if fatal != "" {
		log.Fatal(fatal)
	}
	if warn != "" {
		log.Printf("%s", warn)
	}
}

func relayProductionDeployment() bool {
	return relayProductionDeploymentFromEnv(os.Getenv)
}

func relayProductionDeploymentFromEnv(getenv func(string) string) bool {
	for _, key := range []string{
		"FLY_APP_NAME",
		"K_SERVICE",
		"K_REVISION",
		"K_CONFIGURATION",
	} {
		if strings.TrimSpace(getenv(key)) != "" {
			return true
		}
	}
	switch strings.ToLower(strings.TrimSpace(getenv("LANCER_ENV"))) {
	case "prod", "production":
		return true
	}
	switch strings.ToLower(strings.TrimSpace(getenv("APP_ENV"))) {
	case "prod", "production":
		return true
	default:
		return false
	}
}
