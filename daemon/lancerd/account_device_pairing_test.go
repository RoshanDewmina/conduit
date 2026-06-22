package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAccountDeviceChallengeAndRedeemCarryNoPassword(t *testing.T) {
	challengeID := ""
	secretSeen := ""
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/devices/challenges":
			var req map[string]string
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatal(err)
			}
			challengeID = req["challengeId"]
			secretSeen = req["secret"]
			if req["name"] == "" || req["publicFingerprint"] == "" || req["password"] != "" {
				t.Fatalf("unexpected challenge body: %#v", req)
			}
			w.WriteHeader(http.StatusCreated)
		case "/v1/devices/redeem":
			var req map[string]string
			_ = json.NewDecoder(r.Body).Decode(&req)
			if req["challengeId"] != challengeID || req["secret"] != secretSeen || req["password"] != "" {
				t.Fatalf("unexpected redeem body: %#v", req)
			}
			_ = json.NewEncoder(w).Encode(accountDeviceCredential{DeviceID: "device-1", Credential: "opaque-credential"})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	challenge, err := createAccountDeviceChallenge(server.URL, "devbox", "abcdef0123456789")
	if err != nil {
		t.Fatal(err)
	}
	if challenge.ID == "" || challenge.Secret == "" || challenge.ID != challengeID {
		t.Fatalf("bad challenge: %#v", challenge)
	}
	credential, status, err := redeemAccountDeviceCredential(server.URL, challenge.ID, challenge.Secret)
	if err != nil || status != http.StatusOK || credential.Credential != "opaque-credential" {
		t.Fatalf("bad redeem: credential=%#v status=%d err=%v", credential, status, err)
	}
}
