package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestOpenRouterProvisioning(t *testing.T) {
	setupTestStores(t)

	var captured openRouterKeyCreateRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/keys" || r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &captured)
		if !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer mgmt_") {
			http.Error(w, "missing auth", http.StatusUnauthorized)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"data": map[string]any{
				"hash": "hash_abc",
				"key":  "sk-or-v1-test",
			},
			"key": "sk-or-v1-test",
		})
	}))
	defer server.Close()
	defer func() {
		t.Setenv("OPENROUTER_PROVISIONING_KEY", "")
		setOpenRouterClient(&openRouterClient{
			baseURL:         "https://openrouter.ai",
			provisioningKey: "",
			httpClient:      &http.Client{Timeout: 15 * time.Second},
		})
		resetOpenRouterKeyCache()
	}()

	setOpenRouterClient(&openRouterClient{
		baseURL:         server.URL,
		provisioningKey: "mgmt_test",
		httpClient:      server.Client(),
	})

	ent := subscriptionEntitlement{
		CustomerID: "cus_or",
		Status:     "active",
		Active:     true,
		PriceID:    "price_monthly",
	}
	t.Setenv("OPENROUTER_LIMIT_MONTHLY", "25")

	hash, key, err := ensureOpenRouterSubKey(ent)
	if err != nil {
		t.Fatalf("ensureOpenRouterSubKey: %v", err)
	}
	if hash != "hash_abc" || key != "sk-or-v1-test" {
		t.Fatalf("unexpected key result hash=%q key=%q", hash, key)
	}
	if captured.Limit != 25 || captured.LimitReset != "monthly" {
		t.Fatalf("unexpected provisioning payload: %+v", captured)
	}

	hash2, _, err := ensureOpenRouterSubKey(ent)
	if err != nil || hash2 != hash {
		t.Fatalf("expected cached hash, got %q err=%v", hash2, err)
	}
}

func TestOpenRouterLimitForEntitlement(t *testing.T) {
	t.Setenv("STRIPE_PRICE_ANNUAL", "price_annual")
	t.Setenv("OPENROUTER_LIMIT_MONTHLY", "20")
	t.Setenv("OPENROUTER_LIMIT_ANNUAL", "50")

	monthlyLimit, reset := openRouterLimitForEntitlement(subscriptionEntitlement{
		Active:  true,
		PriceID: "price_monthly",
	})
	if monthlyLimit != 20 || reset != "monthly" {
		t.Fatalf("monthly limit = %v reset=%q", monthlyLimit, reset)
	}

	annualLimit, _ := openRouterLimitForEntitlement(subscriptionEntitlement{
		Active:  true,
		PriceID: "price_annual",
	})
	if annualLimit != 50 {
		t.Fatalf("annual limit = %v", annualLimit)
	}
}
