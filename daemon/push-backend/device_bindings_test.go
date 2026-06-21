package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func signedSupabaseToken(t *testing.T, secret, userID, email string) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub":   userID,
		"email": email,
		"aud":   []string{"authenticated"},
		"exp":   time.Now().Add(time.Hour).Unix(),
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func TestDeviceBindingRequiresVerifiedUserAndRedeemsOnce(t *testing.T) {
	secret := "supabase-test-secret"
	t.Setenv("SUPABASE_JWT_SECRET", secret)
	setDeviceBindingStoreForTest(newDeviceBindingStore(filepath.Join(t.TempDir(), "devices.json")))
	mux := http.NewServeMux()
	registerDeviceBindingRoutes(mux)

	challengeID := strings.Repeat("a", 32)
	pairingSecret := strings.Repeat("b", 64)
	challenge := createDeviceChallengeRequest{
		ChallengeID: challengeID, Secret: pairingSecret, Name: "Rohan's Mac", PublicFingerprint: strings.Repeat("c", 64),
	}
	body, _ := json.Marshal(challenge)
	req := httptest.NewRequest(http.MethodPost, "/v1/devices/challenges", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("challenge status = %d: %s", rec.Code, rec.Body.String())
	}

	bindBody, _ := json.Marshal(bindDeviceRequest{ChallengeID: challengeID, Secret: pairingSecret})
	req = httptest.NewRequest(http.MethodPost, "/v1/devices/bind", bytes.NewReader(bindBody))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("unauthed bind status = %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/v1/devices/bind", bytes.NewReader(bindBody))
	req.Header.Set("Authorization", "Bearer "+signedSupabaseToken(t, secret, "user-1", "person@example.com"))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("bind status = %d: %s", rec.Code, rec.Body.String())
	}

	redeemBody, _ := json.Marshal(redeemDeviceRequest{ChallengeID: challengeID, Secret: pairingSecret})
	req = httptest.NewRequest(http.MethodPost, "/v1/devices/redeem", bytes.NewReader(redeemBody))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("redeem status = %d: %s", rec.Code, rec.Body.String())
	}
	var redeemed map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &redeemed); err != nil || redeemed["credential"] == "" {
		t.Fatalf("bad redeem response: %v %#v", err, redeemed)
	}
	if strings.Contains(rec.Body.String(), pairingSecret) {
		t.Fatal("redeem response leaked the pairing secret")
	}

	req = httptest.NewRequest(http.MethodPost, "/v1/devices/redeem", bytes.NewReader(redeemBody))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("second redeem status = %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/v1/devices/"+challengeID+"/revoke", nil)
	req.Header.Set("Authorization", "Bearer "+signedSupabaseToken(t, secret, "user-1", "person@example.com"))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("revoke status = %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSupabaseJWTRejectsWrongSignature(t *testing.T) {
	t.Setenv("SUPABASE_JWT_SECRET", "expected-secret")
	request := httptest.NewRequest(http.MethodGet, "/v1/devices", nil)
	request.Header.Set("Authorization", "Bearer "+signedSupabaseToken(t, "wrong-secret", "user-1", "person@example.com"))
	if _, err := resolveAuthenticatedUser(request); err == nil {
		t.Fatal("expected invalid JWT to be rejected")
	}
}
