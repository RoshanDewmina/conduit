package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type openRouterKeyCreateRequest struct {
	Name       string  `json:"name"`
	Limit      float64 `json:"limit"`
	LimitReset string  `json:"limit_reset"`
	Disabled   bool    `json:"disabled,omitempty"`
}

type openRouterKeyCreateResponse struct {
	Data struct {
		Hash  string  `json:"hash"`
		Key   string  `json:"key"`
		Limit float64 `json:"limit"`
	} `json:"data"`
	Key string `json:"key"`
}

type openRouterClient struct {
	baseURL         string
	provisioningKey string
	httpClient      *http.Client
}

var (
	openRouterClientMu sync.RWMutex
	openRouter         *openRouterClient
	customerKeyHashes  = struct {
		sync.RWMutex
		byCustomer map[string]string
	}{
		byCustomer: make(map[string]string),
	}
)

func initOpenRouterClient() {
	openRouterClientMu.Lock()
	defer openRouterClientMu.Unlock()
	if openRouter != nil {
		return
	}
	baseURL := strings.TrimRight(os.Getenv("OPENROUTER_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = "https://openrouter.ai"
	}
	openRouter = &openRouterClient{
		baseURL:         baseURL,
		provisioningKey: os.Getenv("OPENROUTER_PROVISIONING_KEY"),
		httpClient:      &http.Client{Timeout: 15 * time.Second},
	}
}

func setOpenRouterClient(c *openRouterClient) {
	openRouterClientMu.Lock()
	openRouter = c
	openRouterClientMu.Unlock()
}

func getOpenRouterClient() *openRouterClient {
	openRouterClientMu.RLock()
	c := openRouter
	openRouterClientMu.RUnlock()
	if c == nil {
		initOpenRouterClient()
		openRouterClientMu.RLock()
		c = openRouter
		openRouterClientMu.RUnlock()
	}
	return c
}

func openRouterLimitForEntitlement(ent subscriptionEntitlement) (float64, string) {
	limitReset := "monthly"
	if v := os.Getenv("OPENROUTER_LIMIT_RESET"); v != "" {
		limitReset = v
	}

	annualPrice := os.Getenv("STRIPE_PRICE_ANNUAL")
	defaultLimit := 20.0
	if v := os.Getenv("OPENROUTER_LIMIT_MONTHLY"); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil {
			defaultLimit = parsed
		}
	}
	annualLimit := defaultLimit
	if v := os.Getenv("OPENROUTER_LIMIT_ANNUAL"); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil {
			annualLimit = parsed
		}
	} else {
		annualLimit = defaultLimit * 2
	}

	if ent.PriceID != "" && ent.PriceID == annualPrice {
		return annualLimit, limitReset
	}
	return defaultLimit, limitReset
}

func ensureOpenRouterSubKey(ent subscriptionEntitlement) (hash string, key string, err error) {
	customerKeyHashes.RLock()
	if existing, ok := customerKeyHashes.byCustomer[ent.CustomerID]; ok && existing != "" {
		customerKeyHashes.RUnlock()
		return existing, "", nil
	}
	customerKeyHashes.RUnlock()

	client := getOpenRouterClient()
	if client.provisioningKey == "" {
		// Dev/test fallback: synthetic hash when provisioning key is not configured.
		hash = "dev_" + ent.CustomerID
		customerKeyHashes.Lock()
		customerKeyHashes.byCustomer[ent.CustomerID] = hash
		customerKeyHashes.Unlock()
		return hash, "", nil
	}

	limit, limitReset := openRouterLimitForEntitlement(ent)
	name := fmt.Sprintf("lancer-%s", ent.CustomerID)
	created, err := client.createSubKey(name, limit, limitReset)
	if err != nil {
		return "", "", err
	}

	hash = created.Data.Hash
	customerKeyHashes.Lock()
	customerKeyHashes.byCustomer[ent.CustomerID] = hash
	customerKeyHashes.Unlock()
	// Persist the actual sub-key: OpenRouter only vends it once, but the cloud
	// runner needs it at dispatch time (which can be much later, after a process
	// restart). Without this the runner launches with no OPENROUTER_API_KEY and
	// the agent command fails auth.
	persistOpenRouterKey(ent.CustomerID, created.Key)
	return hash, created.Key, nil
}

// openRouterKeysStore persists customerID -> provisioned sub-key. The sub-key is
// rate/spend-capped per customer; it is injected into the cloud runner env at
// dispatch as LANCER_OPENROUTER_KEY. Stored alongside the other control-plane
// JSON files. NOTE (security follow-up): this is plaintext-at-rest, consistent
// with the existing MVP store posture (entitlement client tokens, runner tokens);
// migrate all of these to a secrets manager / encrypted-at-rest before GA.
var openRouterKeysStore = struct {
	mu   sync.Mutex
	path string
}{
	path: dataFilePath("OPENROUTER_KEYS_FILE", "lancer-openrouter-keys.json"),
}

type openRouterKeysData struct {
	Keys map[string]string `json:"keys"`
}

func persistOpenRouterKey(customerID, key string) {
	if customerID == "" || key == "" {
		return
	}
	openRouterKeysStore.mu.Lock()
	defer openRouterKeysStore.mu.Unlock()
	var data openRouterKeysData
	_ = loadJSONFile(openRouterKeysStore.path, &data)
	if data.Keys == nil {
		data.Keys = map[string]string{}
	}
	data.Keys[customerID] = key
	if err := saveJSONFile(openRouterKeysStore.path, data); err != nil {
		// Non-fatal: the key is still returned to the immediate caller; only the
		// later cloud-dispatch lookup would miss. Log so it's diagnosable.
		fmt.Printf("openrouter: persist key for %s failed: %v\n", customerID, err)
	}
}

// openRouterKeyForCustomer returns the OpenRouter key injected into a customer's
// cloud runs. Precedence: a per-customer provisioned sub-key (from the provisioning
// flow) wins; otherwise it falls back to a single shared inference key
// (OPENROUTER_SHARED_KEY), the MVP/single-tenant mode for deployments that have an
// ordinary OpenRouter key but no management/provisioning key. Returns "" if neither
// is available.
func openRouterKeyForCustomer(customerID string) string {
	if customerID != "" {
		openRouterKeysStore.mu.Lock()
		var data openRouterKeysData
		_ = loadJSONFile(openRouterKeysStore.path, &data)
		openRouterKeysStore.mu.Unlock()
		if k := data.Keys[customerID]; k != "" {
			return k
		}
	}
	return openRouterSharedKey()
}

// openRouterSharedKey is a single OpenRouter inference key shared across all customers
// when per-customer provisioning is not configured. Set via OPENROUTER_SHARED_KEY.
// Trades per-customer spend isolation for simplicity; set OPENROUTER_PROVISIONING_KEY
// to mint capped per-customer sub-keys instead. Cap spend on the key in the OpenRouter
// dashboard when using this mode.
func openRouterSharedKey() string {
	return strings.TrimSpace(os.Getenv("OPENROUTER_SHARED_KEY"))
}

func setOpenRouterKeysPath(path string) { openRouterKeysStore.path = path }

func resetOpenRouterKeysForTests() {
	openRouterKeysStore.mu.Lock()
	defer openRouterKeysStore.mu.Unlock()
	_ = saveJSONFile(openRouterKeysStore.path, openRouterKeysData{})
}

func (c *openRouterClient) createSubKey(name string, limit float64, limitReset string) (openRouterKeyCreateResponse, error) {
	var empty openRouterKeyCreateResponse
	if c.provisioningKey == "" {
		return empty, errors.New("OPENROUTER_PROVISIONING_KEY is not configured")
	}

	body, err := json.Marshal(openRouterKeyCreateRequest{
		Name:       name,
		Limit:      limit,
		LimitReset: limitReset,
	})
	if err != nil {
		return empty, err
	}

	req, err := http.NewRequest(http.MethodPost, c.baseURL+"/api/v1/keys", bytes.NewReader(body))
	if err != nil {
		return empty, err
	}
	req.Header.Set("Authorization", "Bearer "+c.provisioningKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return empty, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return empty, fmt.Errorf("OpenRouter returned %d: %s", resp.StatusCode, string(raw))
	}

	var parsed openRouterKeyCreateResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return empty, err
	}
	if parsed.Data.Hash == "" && parsed.Key == "" {
		return empty, errors.New("OpenRouter response missing key data")
	}
	if parsed.Key == "" {
		parsed.Key = parsed.Data.Key
	}
	return parsed, nil
}

func resetOpenRouterKeyCache() {
	customerKeyHashes.Lock()
	customerKeyHashes.byCustomer = make(map[string]string)
	customerKeyHashes.Unlock()
}
