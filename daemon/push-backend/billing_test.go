package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"testing"
	"time"
)

func TestVerifyStripeSignature(t *testing.T) {
	payload := []byte(`{"type":"checkout.session.completed"}`)
	secret := "whsec_test"
	timestamp := time.Now().Unix()

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(fmt.Sprintf("%d.%s", timestamp, payload)))
	header := fmt.Sprintf("t=%d,v1=%s", timestamp, hex.EncodeToString(mac.Sum(nil)))

	if err := verifyStripeSignature(payload, header, secret, 5*time.Minute); err != nil {
		t.Fatalf("expected valid signature: %v", err)
	}
	if err := verifyStripeSignature(payload, header, "wrong", 5*time.Minute); err == nil {
		t.Fatal("expected invalid signature for wrong secret")
	}
}

func TestStripePriceID(t *testing.T) {
	t.Setenv("STRIPE_PRICE_MONTHLY", "price_monthly")
	t.Setenv("STRIPE_PRICE_ANNUAL", "price_annual")

	if got, err := stripePriceID("monthly"); err != nil || got != "price_monthly" {
		t.Fatalf("monthly price = %q, %v", got, err)
	}
	if got, err := stripePriceID("annual"); err != nil || got != "price_annual" {
		t.Fatalf("annual price = %q, %v", got, err)
	}
	if _, err := stripePriceID("lifetime"); err == nil {
		t.Fatal("expected unknown plan error")
	}
}

func TestSubscriptionIsActive(t *testing.T) {
	for _, status := range []string{"active", "trialing"} {
		if !subscriptionIsActive(status) {
			t.Fatalf("%s should be active", status)
		}
	}
	for _, status := range []string{"past_due", "canceled", "incomplete", ""} {
		if subscriptionIsActive(status) {
			t.Fatalf("%s should not be active", status)
		}
	}
}
