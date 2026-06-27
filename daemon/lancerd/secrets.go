package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type secretsStore struct {
	mu             sync.RWMutex
	path           string
	secrets        map[string]*secretEntry
	authorizations map[string]*secretAuth
	pending        map[string]*pendingSecretRequest
}

type secretEntry struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Type       string     `json:"type"`
	Scope      string     `json:"scope"`
	Value      string     `json:"-"`
	AddedAt    time.Time  `json:"addedAt"`
	LastUsedAt *time.Time `json:"lastUsedAt,omitempty"`
	UseCount   int        `json:"useCount"`
}

type secretAuth struct {
	RequestID string     `json:"requestId"`
	Scope     string     `json:"scope"`
	ExpiresAt *time.Time `json:"expiresAt,omitempty"`
	OneTime   bool       `json:"oneTime"`
	AllowedBy string     `json:"allowedBy"`
}

type pendingSecretRequest struct {
	Request    SecretRequestParams `json:"request"`
	ReceivedAt time.Time           `json:"receivedAt"`
}

// SecretRequestParams mirrors the Swift SecretRequest wire format.
type SecretRequestParams struct {
	ID             string `json:"id"`
	Agent          string `json:"agent"`
	ToolName       string `json:"toolName"`
	CredentialType string `json:"credentialType"`
	RequestedScope string `json:"requestedScope"`
	HostID         string `json:"hostID"`
	Timestamp      string `json:"timestamp"`
}

// secretStoreEntry is the JSON-serializable form persisted to disk (includes the Value field).
type secretStoreEntry struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Type       string     `json:"type"`
	Scope      string     `json:"scope"`
	Value      string     `json:"value"`
	AddedAt    time.Time  `json:"addedAt"`
	LastUsedAt *time.Time `json:"lastUsedAt,omitempty"`
	UseCount   int        `json:"useCount"`
}

type secretsFile struct {
	Secrets        []secretStoreEntry `json:"secrets"`
	Authorizations []secretAuth       `json:"authorizations"`
}

func newSecretsStore(home string) *secretsStore {
	s := &secretsStore{
		path:           filepath.Join(home, ".lancer", "secrets.json"),
		secrets:        make(map[string]*secretEntry),
		authorizations: make(map[string]*secretAuth),
		pending:        make(map[string]*pendingSecretRequest),
	}
	s.load()
	return s
}

func (s *secretsStore) load() {
	data, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	var file secretsFile
	if json.Unmarshal(data, &file) != nil {
		return
	}
	for i := range file.Secrets {
		e := &file.Secrets[i]
		s.secrets[e.ID] = &secretEntry{
			ID:         e.ID,
			Name:       e.Name,
			Type:       e.Type,
			Scope:      e.Scope,
			Value:      e.Value,
			AddedAt:    e.AddedAt,
			LastUsedAt: e.LastUsedAt,
			UseCount:   e.UseCount,
		}
	}
	for i := range file.Authorizations {
		s.authorizations[file.Authorizations[i].RequestID] = &file.Authorizations[i]
	}
}

func (s *secretsStore) persistLocked() {
	file := secretsFile{}
	for _, e := range s.secrets {
		file.Secrets = append(file.Secrets, secretStoreEntry{
			ID:         e.ID,
			Name:       e.Name,
			Type:       e.Type,
			Scope:      e.Scope,
			Value:      e.Value,
			AddedAt:    e.AddedAt,
			LastUsedAt: e.LastUsedAt,
			UseCount:   e.UseCount,
		})
	}
	for _, a := range s.authorizations {
		file.Authorizations = append(file.Authorizations, *a)
	}
	_ = os.MkdirAll(filepath.Dir(s.path), 0700)
	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.path, data, 0600)
}

// store adds a secret and returns its ID. Called from phone authorization.
func (s *secretsStore) store(name, secretType, scope, value string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := newUUID()
	now := time.Now().UTC()
	s.secrets[id] = &secretEntry{
		ID:      id,
		Name:    name,
		Type:    secretType,
		Scope:   scope,
		Value:   value,
		AddedAt: now,
	}
	s.persistLocked()
	return id
}

// authorize stores an authorization for a secret request. A concrete scope is
// required: empty or "*" scopes are rejected so a phone tap can never silently
// grant access to every stored secret (fail-closed — broad access must be an
// explicit, named scope).
func (s *secretsStore) authorize(requestID, scope string, expiresAt *time.Time, oneTime bool, allowedBy string) error {
	scope = strings.TrimSpace(scope)
	if scope == "" || scope == "*" {
		return fmt.Errorf("a concrete scope is required to authorize a secret")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.authorizations[requestID] = &secretAuth{
		RequestID: requestID,
		Scope:     scope,
		ExpiresAt: expiresAt,
		OneTime:   oneTime,
		AllowedBy: allowedBy,
	}
	s.persistLocked()
	return nil
}

// revoke removes an authorization.
func (s *secretsStore) revoke(requestID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.authorizations[requestID]
	if ok {
		delete(s.authorizations, requestID)
		s.persistLocked()
	}
	return ok
}

// delete removes a stored secret.
func (s *secretsStore) delete(secretID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.secrets[secretID]
	if ok {
		delete(s.secrets, secretID)
		s.persistLocked()
	}
	return ok
}

// list returns metadata for all stored secrets (no values).
func (s *secretsStore) list() []secretEntry {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]secretEntry, 0, len(s.secrets))
	for _, e := range s.secrets {
		out = append(out, secretEntry{
			ID:         e.ID,
			Name:       e.Name,
			Type:       e.Type,
			Scope:      e.Scope,
			AddedAt:    e.AddedAt,
			LastUsedAt: e.LastUsedAt,
			UseCount:   e.UseCount,
		})
	}
	return out
}

// addPending stores a secret request awaiting phone approval.
func (s *secretsStore) addPending(req SecretRequestParams) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pending[req.ID] = &pendingSecretRequest{
		Request:    req,
		ReceivedAt: time.Now().UTC(),
	}
}

// removePending removes a pending request.
func (s *secretsStore) removePending(requestID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.pending, requestID)
}

// listPending returns all pending secret requests.
func (s *secretsStore) listPending() []pendingSecretRequest {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]pendingSecretRequest, 0, len(s.pending))
	for _, p := range s.pending {
		out = append(out, *p)
	}
	return out
}

// scopeMatches checks if the authorized scope covers the secret's scope.
// Matching is segment-wise on ":" boundaries: an authorized scope covers a
// secret scope only when it equals it, or is a strict segment-prefix of it
// (e.g. "api" covers "api:github" but never "api-admin"). Empty/wildcard
// scopes match nothing — they are rejected at authorize() time, and this
// function fails closed if one ever reaches it.
func scopeMatches(authorized, secretScope string) bool {
	if authorized == "" || authorized == "*" || secretScope == "" {
		return false
	}
	if authorized == secretScope {
		return true
	}
	authSegs := strings.Split(authorized, ":")
	secretSegs := strings.Split(secretScope, ":")
	// The authorized scope must be broader (fewer segments) to cover the secret;
	// an equal or greater segment count that isn't an exact match cannot broaden.
	if len(authSegs) >= len(secretSegs) {
		return false
	}
	for i := range authSegs {
		if authSegs[i] != secretSegs[i] {
			return false
		}
	}
	return true
}
