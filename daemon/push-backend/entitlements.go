package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type subscriptionEntitlement struct {
	CustomerID       string `json:"customerId,omitempty"`
	OrgID            string `json:"orgId,omitempty"`
	OrgName          string `json:"orgName,omitempty"`
	SubscriptionID   string `json:"subscriptionId,omitempty"`
	Status           string `json:"status"`
	Active           bool   `json:"active"`
	PriceID          string `json:"priceId,omitempty"`
	AppAccountToken  string `json:"appAccountToken,omitempty"`
	CurrentPeriodEnd int64  `json:"currentPeriodEnd,omitempty"`
	UpdatedAt        string `json:"updatedAt"`
	// ClientToken is a server-issued opaque bearer token bound to this entitlement.
	// It is returned to the client once via /billing/entitlement and must be
	// presented as "Authorization: Bearer <token>" on all agent/run endpoints.
	// Never derived from, or accepted as, a client-supplied identity claim.
	ClientToken string `json:"clientToken,omitempty"`
}

type entitlementSnapshot struct {
	ByCustomer     map[string]subscriptionEntitlement `json:"byCustomer"`
	ByAppToken     map[string]string                  `json:"byAppToken"`
	ByClientToken  map[string]string                  `json:"byClientToken"`
}

type entitlementBackend interface {
	GetByCustomerID(customerID string) (subscriptionEntitlement, bool)
	GetByAppAccountToken(token string) (subscriptionEntitlement, bool)
	GetByClientToken(token string) (subscriptionEntitlement, bool)
	Put(entitlement subscriptionEntitlement) error
}

var (
	entitlementStoreMu sync.RWMutex
	activeEntitlementStore entitlementBackend
)

func initEntitlementStore() {
	entitlementStoreMu.Lock()
	defer entitlementStoreMu.Unlock()
	if activeEntitlementStore != nil {
		return
	}
	if redisURL := strings.TrimSpace(os.Getenv("ENTITLEMENTS_REDIS_URL")); redisURL != "" {
		store, err := newRedisEntitlementStore(redisURL)
		if err != nil {
			log.Printf("entitlements: Redis unavailable (%v), falling back to file store", err)
		} else {
			activeEntitlementStore = store
			return
		}
	}
	activeEntitlementStore = newFileEntitlementStore(dataFilePath("ENTITLEMENTS_FILE", "conduit-entitlements.json"))
}

func setEntitlementStore(store entitlementBackend) {
	entitlementStoreMu.Lock()
	activeEntitlementStore = store
	entitlementStoreMu.Unlock()
}

func getEntitlementStore() entitlementBackend {
	entitlementStoreMu.RLock()
	store := activeEntitlementStore
	entitlementStoreMu.RUnlock()
	if store == nil {
		initEntitlementStore()
		entitlementStoreMu.RLock()
		store = activeEntitlementStore
		entitlementStoreMu.RUnlock()
	}
	return store
}

type fileEntitlementStore struct {
	mu   sync.RWMutex
	path string
	data entitlementSnapshot
}

func newFileEntitlementStore(path string) *fileEntitlementStore {
	s := &fileEntitlementStore{
		path: path,
		data: entitlementSnapshot{
			ByCustomer:    make(map[string]subscriptionEntitlement),
			ByAppToken:    make(map[string]string),
			ByClientToken: make(map[string]string),
		},
	}
	if err := loadJSONFile(path, &s.data); err != nil {
		log.Printf("entitlements: load %s failed: %v", path, err)
	}
	if s.data.ByCustomer == nil {
		s.data.ByCustomer = make(map[string]subscriptionEntitlement)
	}
	if s.data.ByAppToken == nil {
		s.data.ByAppToken = make(map[string]string)
	}
	if s.data.ByClientToken == nil {
		s.data.ByClientToken = make(map[string]string)
	}
	return s
}

func (s *fileEntitlementStore) GetByCustomerID(customerID string) (subscriptionEntitlement, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	ent, ok := s.data.ByCustomer[customerID]
	return ent, ok
}

func (s *fileEntitlementStore) GetByAppAccountToken(token string) (subscriptionEntitlement, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	customerID, ok := s.data.ByAppToken[token]
	if !ok {
		return subscriptionEntitlement{}, false
	}
	ent, ok := s.data.ByCustomer[customerID]
	return ent, ok
}

func (s *fileEntitlementStore) GetByClientToken(token string) (subscriptionEntitlement, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	customerID, ok := s.data.ByClientToken[token]
	if !ok {
		return subscriptionEntitlement{}, false
	}
	ent, ok := s.data.ByCustomer[customerID]
	return ent, ok
}

func (s *fileEntitlementStore) Put(entitlement subscriptionEntitlement) error {
	if entitlement.CustomerID == "" {
		return errors.New("customerId is required")
	}
	if entitlement.UpdatedAt == "" {
		entitlement.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	}
	if entitlement.ClientToken == "" {
		b := make([]byte, 32)
		if _, err := rand.Read(b); err != nil {
			return fmt.Errorf("generate client token: %w", err)
		}
		entitlement.ClientToken = hex.EncodeToString(b)
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.ByCustomer[entitlement.CustomerID] = entitlement
	if entitlement.AppAccountToken != "" {
		s.data.ByAppToken[entitlement.AppAccountToken] = entitlement.CustomerID
	}
	s.data.ByClientToken[entitlement.ClientToken] = entitlement.CustomerID
	return saveJSONFile(s.path, s.data)
}

type redisEntitlementStore struct {
	url string
}

func newRedisEntitlementStore(url string) (*redisEntitlementStore, error) {
	store := &redisEntitlementStore{url: url}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := store.ping(ctx); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *redisEntitlementStore) ping(ctx context.Context) error {
	conn, err := dialRedis(ctx, s.url)
	if err != nil {
		return err
	}
	defer conn.Close()
	return conn.Ping(ctx)
}

func (s *redisEntitlementStore) GetByCustomerID(customerID string) (subscriptionEntitlement, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := dialRedis(ctx, s.url)
	if err != nil {
		log.Printf("entitlements redis get: %v", err)
		return subscriptionEntitlement{}, false
	}
	defer conn.Close()

	raw, err := conn.Get(ctx, redisCustomerKey(customerID))
	if err != nil || raw == "" {
		return subscriptionEntitlement{}, false
	}
	var ent subscriptionEntitlement
	if err := json.Unmarshal([]byte(raw), &ent); err != nil {
		return subscriptionEntitlement{}, false
	}
	return ent, true
}

func (s *redisEntitlementStore) GetByAppAccountToken(token string) (subscriptionEntitlement, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := dialRedis(ctx, s.url)
	if err != nil {
		log.Printf("entitlements redis get token: %v", err)
		return subscriptionEntitlement{}, false
	}
	defer conn.Close()

	customerID, err := conn.Get(ctx, redisAppTokenKey(token))
	if err != nil || customerID == "" {
		return subscriptionEntitlement{}, false
	}
	return s.GetByCustomerID(customerID)
}

func (s *redisEntitlementStore) GetByClientToken(token string) (subscriptionEntitlement, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := dialRedis(ctx, s.url)
	if err != nil {
		log.Printf("entitlements redis get client token: %v", err)
		return subscriptionEntitlement{}, false
	}
	defer conn.Close()

	customerID, err := conn.Get(ctx, redisClientTokenKey(token))
	if err != nil || customerID == "" {
		return subscriptionEntitlement{}, false
	}
	return s.GetByCustomerID(customerID)
}

func (s *redisEntitlementStore) Put(entitlement subscriptionEntitlement) error {
	if entitlement.CustomerID == "" {
		return errors.New("customerId is required")
	}
	if entitlement.UpdatedAt == "" {
		entitlement.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	}
	if entitlement.ClientToken == "" {
		b := make([]byte, 32)
		if _, err := rand.Read(b); err != nil {
			return fmt.Errorf("generate client token: %w", err)
		}
		entitlement.ClientToken = hex.EncodeToString(b)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := dialRedis(ctx, s.url)
	if err != nil {
		return err
	}
	defer conn.Close()

	raw, err := json.Marshal(entitlement)
	if err != nil {
		return err
	}
	if err := conn.Set(ctx, redisCustomerKey(entitlement.CustomerID), string(raw)); err != nil {
		return err
	}
	if entitlement.AppAccountToken != "" {
		if err := conn.Set(ctx, redisAppTokenKey(entitlement.AppAccountToken), entitlement.CustomerID); err != nil {
			return err
		}
	}
	if err := conn.Set(ctx, redisClientTokenKey(entitlement.ClientToken), entitlement.CustomerID); err != nil {
		return err
	}
	return nil
}

func redisCustomerKey(customerID string) string {
	return fmt.Sprintf("conduit:entitlement:customer:%s", customerID)
}

func redisAppTokenKey(token string) string {
	return fmt.Sprintf("conduit:entitlement:app:%s", token)
}

func redisClientTokenKey(token string) string {
	return fmt.Sprintf("conduit:entitlement:clienttoken:%s", token)
}

func cacheEntitlement(entitlement subscriptionEntitlement) {
	if entitlement.CustomerID == "" {
		return
	}
	if err := getEntitlementStore().Put(entitlement); err != nil {
		log.Printf("entitlements: persist failed: %v", err)
	}
}

func lookupEntitlement(customerID, appAccountToken string) (subscriptionEntitlement, bool) {
	store := getEntitlementStore()
	if customerID != "" {
		if ent, ok := store.GetByCustomerID(customerID); ok {
			return ent, true
		}
	}
	if appAccountToken != "" {
		if ent, ok := store.GetByAppAccountToken(appAccountToken); ok {
			return ent, true
		}
	}
	return subscriptionEntitlement{}, false
}

// resolveEntitlementFromBearer validates the Authorization: Bearer token and
// returns the entitlement bound to it. customerId is derived server-side from
// the token — never trusted from client input. Use this for all /agents and
// /runs endpoints.
func resolveEntitlementFromBearer(r *http.Request) (subscriptionEntitlement, error) {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(auth, "Bearer ") {
		return subscriptionEntitlement{}, fmt.Errorf("missing bearer token")
	}
	token := strings.TrimPrefix(auth, "Bearer ")
	if token == "" {
		return subscriptionEntitlement{}, fmt.Errorf("missing bearer token")
	}
	ent, ok := getEntitlementStore().GetByClientToken(token)
	if !ok {
		return subscriptionEntitlement{}, fmt.Errorf("invalid token")
	}
	if !ent.Active {
		return ent, fmt.Errorf("subscription inactive")
	}
	return ent, nil
}

// resolveEntitlement resolves via customerId/appAccountToken — only for the
// billing status endpoints where the client is establishing or checking its own
// subscription, not performing operations on owned resources.
func resolveEntitlement(r *httpRequestEntitlement) (subscriptionEntitlement, error) {
	ent, ok := lookupEntitlement(r.CustomerID, r.AppAccountToken)
	if !ok {
		return subscriptionEntitlement{}, fmt.Errorf("entitlement not found")
	}
	if !ent.Active {
		return ent, fmt.Errorf("subscription inactive")
	}
	return ent, nil
}

type httpRequestEntitlement struct {
	CustomerID      string
	AppAccountToken string
}

func entitlementFromRequest(r *http.Request, bodyCustomerID, bodyAppToken string) httpRequestEntitlement {
	customerID := strings.TrimSpace(r.Header.Get("X-Customer-Id"))
	if customerID == "" {
		customerID = strings.TrimSpace(r.URL.Query().Get("customerId"))
	}
	if customerID == "" {
		customerID = strings.TrimSpace(bodyCustomerID)
	}

	appToken := strings.TrimSpace(r.Header.Get("X-App-Account-Token"))
	if appToken == "" {
		appToken = strings.TrimSpace(r.URL.Query().Get("appAccountToken"))
	}
	if appToken == "" {
		appToken = strings.TrimSpace(bodyAppToken)
	}
	return httpRequestEntitlement{
		CustomerID:      customerID,
		AppAccountToken: appToken,
	}
}

func handleBillingEntitlement(w http.ResponseWriter, r *http.Request) {
	req := entitlementFromRequest(r, "", "")
	if req.CustomerID == "" && req.AppAccountToken == "" {
		http.Error(w, "customerId or appAccountToken is required", http.StatusBadRequest)
		return
	}

	if ent, ok := lookupEntitlement(req.CustomerID, req.AppAccountToken); ok {
		writeJSON(w, http.StatusOK, enrichEntitlementForClient(ent))
		return
	}

	if req.CustomerID != "" && stripeSecretKey() != "" {
		entitlement, err := fetchCustomerEntitlement(req.CustomerID)
		if err == nil {
			cacheEntitlement(entitlement)
			writeJSON(w, http.StatusOK, enrichEntitlementForClient(entitlement))
			return
		}
		log.Printf("stripe entitlement lookup failed: %v", err)
	}

	notFound := subscriptionEntitlement{
		CustomerID: req.CustomerID,
		Status:     "not_found",
		Active:     false,
		UpdatedAt:  time.Now().UTC().Format(time.RFC3339),
	}
	writeJSON(w, http.StatusOK, notFound)
}
