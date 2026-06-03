package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func setupTestStores(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("ENTITLEMENTS_FILE", filepath.Join(dir, "entitlements.json"))
	t.Setenv("CONTROL_PLANE_FILE", filepath.Join(dir, "control-plane.json"))
	t.Setenv("USAGE_FILE", filepath.Join(dir, "usage.json"))
	t.Setenv("CREDITS_FILE", filepath.Join(dir, "credits.json"))
	t.Setenv("ARTIFACTS_FILE", filepath.Join(dir, "artifacts.json"))
	t.Setenv("SCHEDULES_FILE", filepath.Join(dir, "schedules.json"))
	t.Setenv("GCP_ORCHESTRATION_FILE", filepath.Join(dir, "gcp-orchestrations.json"))
	t.Setenv("ORGS_FILE", filepath.Join(dir, "orgs.json"))
	t.Setenv("SCHEDULE_TICKER_ENABLED", "false")
	setEntitlementStore(newFileEntitlementStore(filepath.Join(dir, "entitlements.json")))
	setControlPlanePath(filepath.Join(dir, "control-plane.json"))
	setUsagePath(filepath.Join(dir, "usage.json"))
	setCreditsPath(filepath.Join(dir, "credits.json"))
	setArtifactsPath(filepath.Join(dir, "artifacts.json"))
	setSchedulesPath(filepath.Join(dir, "schedules.json"))
	setRunLogsPath(filepath.Join(dir, "run-logs.json"))
	setRunTokensPath(filepath.Join(dir, "run-tokens.json"))
	setGCPOrchestrationPath(filepath.Join(dir, "gcp-orchestrations.json"))
	setOrgsPath(filepath.Join(dir, "orgs.json"))
	setOpenRouterKeysPath(filepath.Join(dir, "openrouter-keys.json"))
	resetOpenRouterKeyCache()
	resetOpenRouterKeysForTests()
	t.Setenv("OPENROUTER_PROVISIONING_KEY", "")
	setOpenRouterClient(&openRouterClient{
		baseURL:         "https://openrouter.ai",
		provisioningKey: "",
		httpClient:      &http.Client{Timeout: 15 * time.Second},
	})
	// Reset dispatch override so cloud-runtime dispatch is a no-op in tests by
	// default. Tests that exercise dispatch (dispatch_test.go) override this
	// themselves and restore it via t.Cleanup.
	providerOverrideForTest = func(_ string) RuntimeProvider { return nil }
	t.Cleanup(func() { providerOverrideForTest = nil })
	resetControlPlaneForTests()
	resetUsageForTests()
	resetCreditsForTests()
	resetArtifactsForTests()
	resetSchedulesForTests()
	resetRunLogsForTests()
	resetGCPOrchestrationForTests()
	resetOrgsForTests()
}

func seedActiveEntitlement(t *testing.T, customerID, appToken string) {
	t.Helper()
	cacheEntitlement(subscriptionEntitlement{
		CustomerID:      customerID,
		SubscriptionID:  "sub_test",
		Status:          "active",
		Active:          true,
		AppAccountToken: appToken,
		UpdatedAt:       time.Now().UTC().Format(time.RFC3339),
	})
}

func TestEntitlementPersistenceAndLookup(t *testing.T) {
	dir := t.TempDir()
	entPath := filepath.Join(dir, "entitlements.json")
	t.Setenv("ENTITLEMENTS_FILE", entPath)
	setEntitlementStore(newFileEntitlementStore(entPath))

	customerID := "cus_persist"
	appToken := "app-token-123"

	cacheEntitlement(subscriptionEntitlement{
		CustomerID:      customerID,
		Status:          "active",
		Active:          true,
		AppAccountToken: appToken,
		UpdatedAt:       time.Now().UTC().Format(time.RFC3339),
	})

	store := getEntitlementStore()
	ent, ok := store.GetByCustomerID(customerID)
	if !ok || !ent.Active {
		t.Fatalf("expected persisted entitlement for customer")
	}
	ent, ok = store.GetByAppAccountToken(appToken)
	if !ok || ent.CustomerID != customerID {
		t.Fatalf("expected lookup by appAccountToken")
	}

	reloaded := newFileEntitlementStore(entPath)
	ent, ok = reloaded.GetByCustomerID(customerID)
	if !ok || !ent.Active {
		t.Fatalf("expected entitlement to survive file reload")
	}
}

func TestBillingEntitlementEndpoint(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_ent", "token-abc")

	mux := http.NewServeMux()
	registerBillingRoutes(mux)

	req := httptest.NewRequest(http.MethodGet, "/billing/entitlement?appAccountToken=token-abc", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body=%s", rec.Code, rec.Body.String())
	}
	var ent subscriptionEntitlement
	if err := json.Unmarshal(rec.Body.Bytes(), &ent); err != nil {
		t.Fatal(err)
	}
	if !ent.Active || ent.CustomerID != "cus_ent" {
		t.Fatalf("unexpected entitlement: %+v", ent)
	}
}

func TestWebhookUpdatesPersistedEntitlement(t *testing.T) {
	setupTestStores(t)
	t.Setenv("STRIPE_WEBHOOK_SECRET", "whsec_test")

	payload := []byte(`{
		"type":"customer.subscription.updated",
		"data":{"object":{
			"id":"sub_123",
			"customer":"cus_webhook",
			"status":"active",
			"current_period_end":1893456000,
			"metadata":{"app_account_token":"wh-token"},
			"items":{"data":[{"price":{"id":"price_monthly"}}]}
		}}
	}`)

	ts := time.Now().Unix()
	header := stripeTestSignatureHeader(payload, "whsec_test", ts)

	mux := http.NewServeMux()
	registerBillingRoutes(mux)
	req := httptest.NewRequest(http.MethodPost, "/billing/webhook", bytes.NewReader(payload))
	req.Header.Set("Stripe-Signature", header)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("webhook status = %d body=%s", rec.Code, rec.Body.String())
	}

	ent, ok := getEntitlementStore().GetByCustomerID("cus_webhook")
	if !ok || !ent.Active || ent.AppAccountToken != "wh-token" {
		t.Fatalf("webhook did not persist entitlement: %+v ok=%v", ent, ok)
	}
}

func stripeTestSignatureHeader(payload []byte, secret string, timestamp int64) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(fmt.Sprintf("%d.", timestamp)))
	mac.Write(payload)
	return fmt.Sprintf("t=%d,v1=%s", timestamp, hex.EncodeToString(mac.Sum(nil)))
}
