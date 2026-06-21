package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Device binding is intentionally separate from the relay's E2E key exchange.
// The QR challenge proves the phone approved this daemon; the daemon only ever
// redeems an opaque capability and never receives an account password or JWT.
type deviceBinding struct {
	ID                string     `json:"id"`
	UserID            string     `json:"userId,omitempty"`
	Name              string     `json:"name"`
	PublicFingerprint string     `json:"publicFingerprint"`
	SecretHash        string     `json:"-"`
	CredentialHash    string     `json:"-"`
	ExpiresAt         time.Time  `json:"expiresAt"`
	BoundAt           *time.Time `json:"boundAt,omitempty"`
	RedeemedAt        *time.Time `json:"redeemedAt,omitempty"`
	RevokedAt         *time.Time `json:"revokedAt,omitempty"`
}

type deviceBindingSnapshot struct {
	Devices map[string]deviceBinding `json:"devices"`
}

type deviceBindingStore struct {
	mu   sync.Mutex
	path string
	data deviceBindingSnapshot
}

var activeDeviceBindingStore = newDeviceBindingStore(dataFilePath("DEVICE_BINDINGS_FILE", "conduit-device-bindings.json"))

func newDeviceBindingStore(path string) *deviceBindingStore {
	s := &deviceBindingStore{path: path, data: deviceBindingSnapshot{Devices: map[string]deviceBinding{}}}
	if err := loadJSONFile(path, &s.data); err != nil {
		log.Printf("device bindings: load failed: %v", err)
	}
	if s.data.Devices == nil {
		s.data.Devices = map[string]deviceBinding{}
	}
	return s
}

func setDeviceBindingStoreForTest(store *deviceBindingStore) {
	activeDeviceBindingStore = store
}

func (s *deviceBindingStore) update(fn func(map[string]deviceBinding) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := fn(s.data.Devices); err != nil {
		return err
	}
	return saveJSONFile(s.path, s.data)
}

func (s *deviceBindingStore) list(userID string) []deviceBinding {
	s.mu.Lock()
	defer s.mu.Unlock()
	items := make([]deviceBinding, 0)
	for _, item := range s.data.Devices {
		if item.UserID == userID {
			items = append(items, publicDeviceBinding(item))
		}
	}
	return items
}

func publicDeviceBinding(binding deviceBinding) deviceBinding {
	binding.SecretHash = ""
	binding.CredentialHash = ""
	return binding
}

type createDeviceChallengeRequest struct {
	ChallengeID       string `json:"challengeId"`
	Secret            string `json:"secret"`
	Name              string `json:"name"`
	PublicFingerprint string `json:"publicFingerprint"`
}

type bindDeviceRequest struct {
	ChallengeID string `json:"challengeId"`
	Secret      string `json:"secret"`
}

type redeemDeviceRequest struct {
	ChallengeID string `json:"challengeId"`
	Secret      string `json:"secret"`
}

func registerDeviceBindingRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/devices/challenges", handleCreateDeviceChallenge)
	mux.HandleFunc("POST /v1/devices/bind", handleBindDevice)
	mux.HandleFunc("POST /v1/devices/redeem", handleRedeemDevice)
	mux.HandleFunc("GET /v1/devices", handleListDevices)
	mux.HandleFunc("POST /v1/devices/{id}/revoke", handleRevokeDevice)
}

// A daemon creates a short-lived, high-entropy challenge before showing its QR.
// The challenge is not useful until a signed-in phone binds it to an account.
func handleCreateDeviceChallenge(w http.ResponseWriter, r *http.Request) {
	var req createDeviceChallengeRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	if !validDeviceChallenge(req.ChallengeID, req.Secret, req.Name, req.PublicFingerprint) {
		http.Error(w, "invalid challenge", http.StatusBadRequest)
		return
	}
	now := time.Now().UTC()
	binding := deviceBinding{
		ID: req.ChallengeID, Name: req.Name, PublicFingerprint: req.PublicFingerprint,
		SecretHash: hashCapability(req.Secret), ExpiresAt: now.Add(10 * time.Minute),
	}
	err := activeDeviceBindingStore.update(func(devices map[string]deviceBinding) error {
		if _, exists := devices[binding.ID]; exists {
			return errors.New("challenge already exists")
		}
		devices[binding.ID] = binding
		return nil
	})
	if err != nil {
		http.Error(w, "challenge unavailable", http.StatusConflict)
		return
	}
	writeJSON(w, http.StatusCreated, publicDeviceBinding(binding))
}

func handleBindDevice(w http.ResponseWriter, r *http.Request) {
	user, ok := requireAuthenticatedUser(w, r)
	if !ok {
		return
	}
	var req bindDeviceRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	var result deviceBinding
	err := activeDeviceBindingStore.update(func(devices map[string]deviceBinding) error {
		binding, found := devices[req.ChallengeID]
		if !found || time.Now().After(binding.ExpiresAt) || binding.BoundAt != nil || !sameCapability(binding.SecretHash, req.Secret) {
			return errors.New("invalid or expired challenge")
		}
		now := time.Now().UTC()
		binding.UserID = user.ID
		binding.BoundAt = &now
		devices[binding.ID] = binding
		result = binding
		return nil
	})
	if err != nil {
		http.Error(w, "invalid or expired challenge", http.StatusBadRequest)
		return
	}
	writeJSON(w, http.StatusOK, publicDeviceBinding(result))
}

func handleRedeemDevice(w http.ResponseWriter, r *http.Request) {
	var req redeemDeviceRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	credential, err := randomCapability()
	if err != nil {
		http.Error(w, "credential unavailable", http.StatusInternalServerError)
		return
	}
	var result deviceBinding
	err = activeDeviceBindingStore.update(func(devices map[string]deviceBinding) error {
		binding, found := devices[req.ChallengeID]
		if !found || binding.UserID == "" || binding.BoundAt == nil || binding.RedeemedAt != nil || binding.RevokedAt != nil || time.Now().After(binding.ExpiresAt) || !sameCapability(binding.SecretHash, req.Secret) {
			return errors.New("challenge cannot be redeemed")
		}
		now := time.Now().UTC()
		binding.CredentialHash = hashCapability(credential)
		binding.RedeemedAt = &now
		devices[binding.ID] = binding
		result = binding
		return nil
	})
	if err != nil {
		http.Error(w, "challenge cannot be redeemed", http.StatusUnauthorized)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"deviceId": result.ID, "credential": credential})
}

func handleListDevices(w http.ResponseWriter, r *http.Request) {
	user, ok := requireAuthenticatedUser(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, activeDeviceBindingStore.list(user.ID))
}

func handleRevokeDevice(w http.ResponseWriter, r *http.Request) {
	user, ok := requireAuthenticatedUser(w, r)
	if !ok {
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	err := activeDeviceBindingStore.update(func(devices map[string]deviceBinding) error {
		binding, found := devices[id]
		if !found || binding.UserID != user.ID {
			return errors.New("not found")
		}
		now := time.Now().UTC()
		binding.RevokedAt = &now
		binding.CredentialHash = ""
		devices[id] = binding
		return nil
	})
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func validDeviceChallenge(id, secret, name, fingerprint string) bool {
	return len(id) >= 16 && len(id) <= 128 && len(secret) >= 32 && len(secret) <= 256 && len(name) > 0 && len(name) <= 120 && len(fingerprint) >= 16 && len(fingerprint) <= 256
}

func hashCapability(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func sameCapability(expectedHash, value string) bool {
	actual, err := hex.DecodeString(hashCapability(value))
	if err != nil {
		return false
	}
	expected, err := hex.DecodeString(expectedHash)
	if err != nil || len(expected) != len(actual) {
		return false
	}
	return subtle.ConstantTimeCompare(expected, actual) == 1
}

func randomCapability() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
