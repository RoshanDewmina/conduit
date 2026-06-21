package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type accountDeviceChallenge struct {
	ID     string
	Secret string
}

type accountDeviceCredential struct {
	DeviceID   string `json:"deviceId"`
	Credential string `json:"credential"`
}

func createAccountDeviceChallenge(backendURL, name, fingerprint string) (accountDeviceChallenge, error) {
	id, err := randomAccountPairingValue()
	if err != nil {
		return accountDeviceChallenge{}, err
	}
	secret, err := randomAccountPairingValue()
	if err != nil {
		return accountDeviceChallenge{}, err
	}
	body, err := json.Marshal(map[string]string{
		"challengeId":       id,
		"secret":            secret,
		"name":              name,
		"publicFingerprint": fingerprint,
	})
	if err != nil {
		return accountDeviceChallenge{}, err
	}
	url := strings.TrimRight(backendURL, "/") + "/v1/devices/challenges"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return accountDeviceChallenge{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		return accountDeviceChallenge{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		return accountDeviceChallenge{}, fmt.Errorf("challenge endpoint returned %d", resp.StatusCode)
	}
	return accountDeviceChallenge{ID: id, Secret: secret}, nil
}

func waitForAccountDeviceCredential(backendURL, challengeID, secret string, timeout time.Duration) (accountDeviceCredential, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		credential, status, err := redeemAccountDeviceCredential(backendURL, challengeID, secret)
		if err == nil {
			return credential, nil
		}
		if status != http.StatusUnauthorized && status != http.StatusBadRequest {
			return accountDeviceCredential{}, err
		}
		time.Sleep(2 * time.Second)
	}
	return accountDeviceCredential{}, fmt.Errorf("timed out waiting for phone approval")
}

func redeemAccountDeviceCredential(backendURL, challengeID, secret string) (accountDeviceCredential, int, error) {
	body, err := json.Marshal(map[string]string{"challengeId": challengeID, "secret": secret})
	if err != nil {
		return accountDeviceCredential{}, 0, err
	}
	url := strings.TrimRight(backendURL, "/") + "/v1/devices/redeem"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return accountDeviceCredential{}, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		return accountDeviceCredential{}, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		return accountDeviceCredential{}, resp.StatusCode, fmt.Errorf("redeem endpoint returned %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	var credential accountDeviceCredential
	if err := json.NewDecoder(resp.Body).Decode(&credential); err != nil || credential.DeviceID == "" || credential.Credential == "" {
		return accountDeviceCredential{}, resp.StatusCode, fmt.Errorf("invalid device credential response")
	}
	return credential, resp.StatusCode, nil
}

func accountDeviceCredentialPath() (string, error) {
	dir, err := conduitDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "account-device.json"), nil
}

func writeAccountDeviceCredential(credential accountDeviceCredential) error {
	path, err := accountDeviceCredentialPath()
	if err != nil {
		return err
	}
	data, err := json.Marshal(credential)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func randomAccountPairingValue() (string, error) {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return hex.EncodeToString(value), nil
}

func publicKeyFingerprint(publicKey string) string {
	sum := sha256.Sum256([]byte(publicKey))
	return hex.EncodeToString(sum[:])
}

func hostnameForPairing() string {
	if name, err := os.Hostname(); err == nil && strings.TrimSpace(name) != "" {
		return name
	}
	return "conduitd host"
}
