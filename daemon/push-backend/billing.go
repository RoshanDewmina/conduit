package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const stripeAPIVersion = "2026-04-22.dahlia"

type checkoutRequest struct {
	Plan            string `json:"plan"`
	Email           string `json:"email,omitempty"`
	CustomerID      string `json:"customerId,omitempty"`
	AppAccountToken string `json:"appAccountToken,omitempty"`
}

type portalRequest struct {
	CustomerID string `json:"customerId"`
	ReturnURL  string `json:"returnUrl,omitempty"`
}

type stripeSession struct {
	ID            string            `json:"id"`
	URL           string            `json:"url"`
	Customer      stripeRef         `json:"customer"`
	CustomerEmail string            `json:"customer_email"`
	Subscription  stripeRef         `json:"subscription"`
	Metadata      map[string]string `json:"metadata"`
}

type stripeSubscription struct {
	ID               string            `json:"id"`
	Customer         stripeRef         `json:"customer"`
	Status           string            `json:"status"`
	CurrentPeriodEnd int64             `json:"current_period_end"`
	Metadata         map[string]string `json:"metadata"`
	Items            struct {
		Data []struct {
			Price struct {
				ID string `json:"id"`
			} `json:"price"`
		} `json:"data"`
	} `json:"items"`
}

type stripeRef string

func (r *stripeRef) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*r = stripeRef(s)
		return nil
	}
	var obj struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(data, &obj); err != nil {
		return err
	}
	*r = stripeRef(obj.ID)
	return nil
}

func registerBillingRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /billing/checkout", handleBillingCheckout)
	mux.HandleFunc("POST /billing/portal", handleBillingPortal)
	mux.HandleFunc("GET /billing/subscription-status", handleBillingStatus)
	mux.HandleFunc("GET /billing/entitlement", handleBillingEntitlement)
	mux.HandleFunc("POST /billing/webhook", handleBillingWebhook)
	mux.HandleFunc("GET /billing/return", handleBillingReturn)
}

func handleBillingCheckout(w http.ResponseWriter, r *http.Request) {
	var req checkoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err != io.EOF {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	priceID, err := stripePriceID(req.Plan)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	values := url.Values{}
	values.Set("mode", "subscription")
	values.Set("line_items[0][price]", priceID)
	values.Set("line_items[0][quantity]", "1")
	values.Set("allow_promotion_codes", "true")
	values.Set("success_url", publicBaseURL()+"/billing/return?session_id={CHECKOUT_SESSION_ID}")
	values.Set("cancel_url", websiteBaseURL()+"/subscribe?cancelled=1")
	if req.CustomerID != "" {
		values.Set("customer", req.CustomerID)
	} else if req.Email != "" {
		values.Set("customer_email", req.Email)
	}
	if req.AppAccountToken != "" {
		values.Set("client_reference_id", req.AppAccountToken)
		values.Set("metadata[app_account_token]", req.AppAccountToken)
		values.Set("subscription_data[metadata][app_account_token]", req.AppAccountToken)
	}

	body, status, err := stripePostForm("/v1/checkout/sessions", values)
	if err != nil {
		log.Printf("stripe checkout failed: %v", err)
		http.Error(w, err.Error(), status)
		return
	}

	var session stripeSession
	if err := json.Unmarshal(body, &session); err != nil {
		http.Error(w, "bad Stripe response", http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"id":  session.ID,
		"url": session.URL,
	})
}

func handleBillingPortal(w http.ResponseWriter, r *http.Request) {
	var req portalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.CustomerID == "" {
		http.Error(w, "customerId is required", http.StatusBadRequest)
		return
	}
	returnURL := req.ReturnURL
	if returnURL == "" {
		returnURL = websiteBaseURL() + "/subscribe"
	}

	values := url.Values{}
	values.Set("customer", req.CustomerID)
	values.Set("return_url", returnURL)

	body, status, err := stripePostForm("/v1/billing_portal/sessions", values)
	if err != nil {
		log.Printf("stripe portal failed: %v", err)
		http.Error(w, err.Error(), status)
		return
	}
	var response struct {
		ID  string `json:"id"`
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		http.Error(w, "bad Stripe response", http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func handleBillingStatus(w http.ResponseWriter, r *http.Request) {
	customerID := r.URL.Query().Get("customerId")
	sessionID := r.URL.Query().Get("checkoutSessionId")

	if customerID == "" && sessionID != "" {
		session, err := fetchCheckoutSession(sessionID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		customerID = string(session.Customer)
	}
	if customerID == "" {
		http.Error(w, "customerId or checkoutSessionId is required", http.StatusBadRequest)
		return
	}

	if stripeSecretKey() != "" {
		entitlement, err := fetchCustomerEntitlement(customerID)
		if err == nil {
			cacheEntitlement(entitlement)
			writeJSON(w, http.StatusOK, entitlement)
			return
		}
		log.Printf("stripe status lookup failed: %v", err)
	}

	if ent, ok := lookupEntitlement(customerID, ""); ok {
		writeJSON(w, http.StatusOK, ent)
		return
	}

	entitlement := subscriptionEntitlement{
		CustomerID: customerID,
		Status:     "not_found",
		Active:     false,
		UpdatedAt:  time.Now().UTC().Format(time.RFC3339),
	}
	writeJSON(w, http.StatusOK, entitlement)
}

func handleBillingWebhook(w http.ResponseWriter, r *http.Request) {
	payload, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := verifyStripeSignature(payload, r.Header.Get("Stripe-Signature"), os.Getenv("STRIPE_WEBHOOK_SECRET"), 5*time.Minute); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var event struct {
		Type string `json:"type"`
		Data struct {
			Object json.RawMessage `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &event); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		var session stripeSession
		if err := json.Unmarshal(event.Data.Object, &session); err == nil {
			entitlement := subscriptionEntitlement{
				CustomerID:      string(session.Customer),
				SubscriptionID:  string(session.Subscription),
				Status:          "checkout_completed",
				Active:          true,
				AppAccountToken: session.Metadata["app_account_token"],
				UpdatedAt:       time.Now().UTC().Format(time.RFC3339),
			}
			cacheEntitlement(entitlement)
		}
	case "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted":
		var sub stripeSubscription
		if err := json.Unmarshal(event.Data.Object, &sub); err == nil {
			cacheEntitlement(entitlementFromSubscription(sub))
		}
	}

	w.WriteHeader(http.StatusNoContent)
}

func handleBillingReturn(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("session_id")
	deepLink := "conduit://billing/complete"
	if sessionID != "" {
		deepLink += "?checkoutSessionId=" + url.QueryEscape(sessionID)
	}
	http.Redirect(w, r, deepLink, http.StatusFound)
}

func stripePriceID(plan string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(plan)) {
	case "", "monthly", "month":
		if v := os.Getenv("STRIPE_PRICE_MONTHLY"); v != "" {
			return v, nil
		}
	case "annual", "yearly", "year":
		if v := os.Getenv("STRIPE_PRICE_ANNUAL"); v != "" {
			return v, nil
		}
	default:
		return "", fmt.Errorf("unknown plan %q", plan)
	}
	return "", errors.New("Stripe price env vars are not configured")
}

func stripePostForm(path string, values url.Values) ([]byte, int, error) {
	return stripeRequest(http.MethodPost, path, strings.NewReader(values.Encode()), "application/x-www-form-urlencoded")
}

func stripeGet(path string, query url.Values) ([]byte, int, error) {
	if len(query) > 0 {
		path += "?" + query.Encode()
	}
	return stripeRequest(http.MethodGet, path, nil, "")
}

func stripeRequest(method, path string, body io.Reader, contentType string) ([]byte, int, error) {
	secret := stripeSecretKey()
	if secret == "" {
		return nil, http.StatusServiceUnavailable, errors.New("STRIPE_SECRET_KEY is not configured")
	}
	req, err := http.NewRequest(method, "https://api.stripe.com"+path, body)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	req.SetBasicAuth(secret, "")
	req.Header.Set("Stripe-Version", stripeAPIVersion)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		return nil, http.StatusBadGateway, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return data, resp.StatusCode, fmt.Errorf("Stripe returned %d: %s", resp.StatusCode, string(data))
	}
	return data, resp.StatusCode, nil
}

func fetchCheckoutSession(id string) (stripeSession, error) {
	query := url.Values{}
	query.Set("expand[]", "subscription")
	body, _, err := stripeGet("/v1/checkout/sessions/"+url.PathEscape(id), query)
	if err != nil {
		return stripeSession{}, err
	}
	var session stripeSession
	return session, json.Unmarshal(body, &session)
}

func fetchCustomerEntitlement(customerID string) (subscriptionEntitlement, error) {
	query := url.Values{}
	query.Set("customer", customerID)
	query.Set("status", "all")
	query.Set("limit", "10")
	query.Set("expand[]", "data.items.data.price")
	body, _, err := stripeGet("/v1/subscriptions", query)
	if err != nil {
		return subscriptionEntitlement{}, err
	}
	var list struct {
		Data []stripeSubscription `json:"data"`
	}
	if err := json.Unmarshal(body, &list); err != nil {
		return subscriptionEntitlement{}, err
	}
	if len(list.Data) == 0 {
		return subscriptionEntitlement{
			CustomerID: customerID,
			Status:     "not_found",
			Active:     false,
			UpdatedAt:  time.Now().UTC().Format(time.RFC3339),
		}, nil
	}
	best := list.Data[0]
	for _, sub := range list.Data[1:] {
		if sub.CurrentPeriodEnd > best.CurrentPeriodEnd {
			best = sub
		}
	}
	return entitlementFromSubscription(best), nil
}

func entitlementFromSubscription(sub stripeSubscription) subscriptionEntitlement {
	priceID := ""
	if len(sub.Items.Data) > 0 {
		priceID = sub.Items.Data[0].Price.ID
	}
	return subscriptionEntitlement{
		CustomerID:       string(sub.Customer),
		SubscriptionID:   sub.ID,
		Status:           sub.Status,
		Active:           subscriptionIsActive(sub.Status),
		PriceID:          priceID,
		AppAccountToken:  sub.Metadata["app_account_token"],
		CurrentPeriodEnd: sub.CurrentPeriodEnd,
		UpdatedAt:        time.Now().UTC().Format(time.RFC3339),
	}
}

func subscriptionIsActive(status string) bool {
	switch status {
	case "active", "trialing":
		return true
	default:
		return false
	}
}

func verifyStripeSignature(payload []byte, header, secret string, tolerance time.Duration) error {
	if secret == "" {
		return errors.New("STRIPE_WEBHOOK_SECRET is not configured")
	}
	var timestamp string
	var signatures []string
	for _, part := range strings.Split(header, ",") {
		key, value, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			continue
		}
		switch key {
		case "t":
			timestamp = value
		case "v1":
			signatures = append(signatures, value)
		}
	}
	if timestamp == "" || len(signatures) == 0 {
		return errors.New("missing Stripe signature")
	}
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return errors.New("bad Stripe signature timestamp")
	}
	if tolerance > 0 && time.Since(time.Unix(ts, 0)) > tolerance {
		return errors.New("stale Stripe signature")
	}

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(timestamp))
	mac.Write([]byte("."))
	mac.Write(payload)
	expected := mac.Sum(nil)
	for _, sig := range signatures {
		got, err := hex.DecodeString(sig)
		if err == nil && hmac.Equal(got, expected) {
			return nil
		}
	}
	return errors.New("invalid Stripe signature")
}

func stripeSecretKey() string {
	return os.Getenv("STRIPE_SECRET_KEY")
}

func publicBaseURL() string {
	if v := strings.TrimRight(os.Getenv("PUBLIC_BASE_URL"), "/"); v != "" {
		return v
	}
	return "https://conduit.dev"
}

func websiteBaseURL() string {
	if v := strings.TrimRight(os.Getenv("WEBSITE_BASE_URL"), "/"); v != "" {
		return v
	}
	return "https://conduit.dev"
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
