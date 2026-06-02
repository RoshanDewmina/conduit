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
	Name        string  `json:"name"`
	Limit       float64 `json:"limit"`
	LimitReset  string  `json:"limit_reset"`
	Disabled    bool    `json:"disabled,omitempty"`
}

type openRouterKeyCreateResponse struct {
	Data struct {
		Hash  string `json:"hash"`
		Key   string `json:"key"`
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
	name := fmt.Sprintf("conduit-%s", ent.CustomerID)
	created, err := client.createSubKey(name, limit, limitReset)
	if err != nil {
		return "", "", err
	}

	hash = created.Data.Hash
	customerKeyHashes.Lock()
	customerKeyHashes.byCustomer[ent.CustomerID] = hash
	customerKeyHashes.Unlock()
	return hash, created.Key, nil
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
