package main

import "testing"

// The shared-key fallback: with no per-customer provisioned key, openRouterKeyForCustomer
// returns OPENROUTER_SHARED_KEY so cloud runs still get a working OpenRouter key.
func TestOpenRouterSharedKeyFallback(t *testing.T) {
	setupTestStores(t)
	t.Setenv("OPENROUTER_SHARED_KEY", "sk-or-shared")

	if got := openRouterKeyForCustomer("cus_no_subkey"); got != "sk-or-shared" {
		t.Fatalf("expected shared key fallback, got %q", got)
	}
	// Empty customerId still resolves the shared key (defensive).
	if got := openRouterKeyForCustomer(""); got != "sk-or-shared" {
		t.Fatalf("expected shared key for empty customer, got %q", got)
	}
}

// A per-customer provisioned key takes precedence over the shared key.
func TestOpenRouterPerCustomerKeyWinsOverShared(t *testing.T) {
	setupTestStores(t)
	t.Setenv("OPENROUTER_SHARED_KEY", "sk-or-shared")
	persistOpenRouterKey("cus_has_subkey", "sk-or-percustomer")

	if got := openRouterKeyForCustomer("cus_has_subkey"); got != "sk-or-percustomer" {
		t.Fatalf("per-customer key must win over shared, got %q", got)
	}
	// A different customer without a sub-key still gets the shared key.
	if got := openRouterKeyForCustomer("cus_other"); got != "sk-or-shared" {
		t.Fatalf("other customer should fall back to shared, got %q", got)
	}
}

// With neither a per-customer key nor a shared key, the result is empty (no key).
func TestOpenRouterNoKeyWhenNeitherConfigured(t *testing.T) {
	setupTestStores(t) // clears OPENROUTER_SHARED_KEY
	if got := openRouterKeyForCustomer("cus_x"); got != "" {
		t.Fatalf("expected empty when no shared/per-customer key, got %q", got)
	}
}
