package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestBindRejectsWithoutValidAttestation is the item-4 regression: with App
// Attest configured, a bind carrying the CORRECT QR capability secret must
// still be rejected unless a verifiable attestation accompanies it.
func TestBindRejectsWithoutValidAttestation(t *testing.T) {
	secret := "supabase-test-secret"
	t.Setenv("SUPABASE_JWT_SECRET", secret)
	setDeviceBindingStoreForTest(newDeviceBindingStore(filepath.Join(t.TempDir(), "devices.json")))
	setAppAttestConfigForTest(appAttestConfig{TeamID: "39HM2X8GS6", BundleID: "dev.lancer.mobile", Env: "production"})
	t.Cleanup(func() { setAppAttestConfigForTest(loadAppAttestConfig()) })

	mux := http.NewServeMux()
	registerDeviceBindingRoutes(mux)

	challengeID := strings.Repeat("a", 32)
	pairingSecret := strings.Repeat("b", 64)
	body, _ := json.Marshal(createDeviceChallengeRequest{
		ChallengeID: challengeID, Secret: pairingSecret, Name: "Test Mac", PublicFingerprint: strings.Repeat("c", 64),
	})
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/devices/challenges", bytes.NewReader(body)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("challenge status = %d: %s", rec.Code, rec.Body.String())
	}

	auth := "Bearer " + signedSupabaseToken(t, secret, "user-1", "person@example.com")
	postBind := func(reqBody bindDeviceRequest) *httptest.ResponseRecorder {
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/v1/devices/bind", bytes.NewReader(b))
		req.Header.Set("Authorization", auth)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	// Correct secret, no attestation at all.
	if rec := postBind(bindDeviceRequest{ChallengeID: challengeID, Secret: pairingSecret}); rec.Code != http.StatusUnauthorized {
		t.Fatalf("bind without attestation status = %d, want 401", rec.Code)
	}

	// Correct secret + garbage attestation against a real minted challenge.
	req := httptest.NewRequest(http.MethodPost, "/v1/devices/attest-challenge", nil)
	req.Header.Set("Authorization", auth)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("attest-challenge status = %d: %s", rec.Code, rec.Body.String())
	}
	var minted map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &minted); err != nil || minted["attestChallengeId"] == "" || minted["challenge"] == "" {
		t.Fatalf("bad attest-challenge response: %v %#v", err, minted)
	}
	garbage := bindDeviceRequest{
		ChallengeID:       challengeID,
		Secret:            pairingSecret,
		AttestChallengeID: minted["attestChallengeId"],
		AttestKeyID:       base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32)),
		AttestationObject: base64.StdEncoding.EncodeToString([]byte("not-an-attestation")),
	}
	if rec := postBind(garbage); rec.Code != http.StatusUnauthorized {
		t.Fatalf("bind with garbage attestation status = %d, want 401", rec.Code)
	}

	// The attest challenge is single-use: even a would-be-valid retry against
	// the same challenge must fail (it was consumed by the garbage attempt).
	if rec := postBind(garbage); rec.Code != http.StatusUnauthorized {
		t.Fatalf("bind reusing a consumed attest challenge status = %d, want 401", rec.Code)
	}

	// The device challenge must still be bindable once attestation passes —
	// i.e. the failed attempts above did not consume or corrupt the binding.
	setAppAttestConfigForTest(appAttestConfig{})
	if rec := postBind(bindDeviceRequest{ChallengeID: challengeID, Secret: pairingSecret}); rec.Code != http.StatusOK {
		t.Fatalf("bind after re-disabling attestation status = %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAttestChallengeIsPerUserAndExpires(t *testing.T) {
	store := &attestChallengeStore{challenges: map[string]attestChallenge{}}
	now := time.Now().UTC()

	id, _, err := store.mint("user-1", now)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := store.consume(id, "user-2", now); ok {
		t.Fatal("challenge minted for user-1 must not be consumable by user-2")
	}
	// consume is destructive even on a mismatch — the nonce is burned.
	if _, ok := store.consume(id, "user-1", now); ok {
		t.Fatal("challenge must be single-use")
	}

	id, _, err = store.mint("user-1", now)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := store.consume(id, "user-1", now.Add(6*time.Minute)); ok {
		t.Fatal("expired challenge must not be consumable")
	}
}

func TestVerifyAppAttestationRejectsMalformedInput(t *testing.T) {
	cfg := appAttestConfig{TeamID: "39HM2X8GS6", BundleID: "dev.lancer.mobile", Env: "production"}
	challenge := bytes.Repeat([]byte{1}, 32)
	keyID := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{2}, 32))
	now := time.Now().UTC()

	cases := map[string]struct{ attestation, key string }{
		"not base64":  {"%%%", keyID},
		"not CBOR":    {base64.StdEncoding.EncodeToString([]byte("junk")), keyID},
		"short keyId": {base64.StdEncoding.EncodeToString([]byte("junk")), base64.StdEncoding.EncodeToString([]byte("short"))},
		"empty":       {"", keyID},
	}
	for name, tc := range cases {
		if err := verifyAppAttestation(tc.attestation, tc.key, challenge, cfg, now); err == nil {
			t.Fatalf("%s: expected verification failure", name)
		}
	}
}

func TestAppAttestStartupCheck(t *testing.T) {
	if fatal, _ := appAttestStartupCheck(false, true); fatal == "" {
		t.Fatal("unset App Attest config in production must be fatal")
	}
	if fatal, warn := appAttestStartupCheck(false, false); fatal != "" || warn == "" {
		t.Fatal("unset App Attest config in dev must warn, not die")
	}
	if fatal, warn := appAttestStartupCheck(true, true); fatal != "" || warn != "" {
		t.Fatal("configured App Attest must be silent")
	}
}
