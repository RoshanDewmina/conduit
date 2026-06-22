package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type CreditBalance struct {
	CustomerID    string  `json:"customerId"`
	PrepaidUSD    float64 `json:"prepaidUsd"`
	OverageUSD    float64 `json:"overageUsd"`
	AllowOverage  bool    `json:"allowOverage"`
	UpdatedAt     string  `json:"updatedAt"`
}

type creditsData struct {
	Balances map[string]CreditBalance `json:"balances"`
}

var creditsStore = struct {
	mu   sync.Mutex
	path string
}{
	path: dataFilePath("CREDITS_FILE", "lancer-credits.json"),
}

func initCreditsStore() {
	var data creditsData
	if err := loadJSONFile(creditsStore.path, &data); err != nil {
		log.Printf("credits: load failed: %v", err)
	}
}

func loadCreditsData() (creditsData, error) {
	var data creditsData
	if err := loadJSONFile(creditsStore.path, &data); err != nil {
		return creditsData{}, err
	}
	if data.Balances == nil {
		data.Balances = make(map[string]CreditBalance)
	}
	return data, nil
}

func saveCreditsData(data creditsData) error {
	if data.Balances == nil {
		data.Balances = make(map[string]CreditBalance)
	}
	return saveJSONFile(creditsStore.path, data)
}

func creditsAllowOverageDefault() bool {
	v := strings.TrimSpace(os.Getenv("CREDITS_ALLOW_OVERAGE"))
	if v == "" {
		v = "true"
	}
	return v == "1" || v == "true" || v == "yes"
}

func creditsInitialUSD() float64 {
	if v := os.Getenv("CREDITS_INITIAL_USD"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err == nil && f >= 0 {
			return f
		}
	}
	return 0
}

func getOrCreateCreditBalance(customerID string) (CreditBalance, error) {
	creditsStore.mu.Lock()
	defer creditsStore.mu.Unlock()

	data, err := loadCreditsData()
	if err != nil {
		return CreditBalance{}, err
	}
	if bal, ok := data.Balances[customerID]; ok {
		return bal, nil
	}
	now := time.Now().UTC().Format(time.RFC3339)
	bal := CreditBalance{
		CustomerID:   customerID,
		PrepaidUSD:   creditsInitialUSD(),
		AllowOverage: creditsAllowOverageDefault(),
		UpdatedAt:    now,
	}
	data.Balances[customerID] = bal
	if err := saveCreditsData(data); err != nil {
		return CreditBalance{}, err
	}
	return bal, nil
}

type creditDeductResult struct {
	Balance       CreditBalance `json:"balance"`
	Overage       bool          `json:"overage"`
	Blocked       bool          `json:"blocked"`
	OverageAmount float64       `json:"overageAmount,omitempty"`
}

func deductCredits(customerID string, cost float64) (creditDeductResult, error) {
	if cost <= 0 {
		bal, err := getOrCreateCreditBalance(customerID)
		return creditDeductResult{Balance: bal}, err
	}

	creditsStore.mu.Lock()
	defer creditsStore.mu.Unlock()

	data, err := loadCreditsData()
	if err != nil {
		return creditDeductResult{}, err
	}
	if data.Balances == nil {
		data.Balances = make(map[string]CreditBalance)
	}
	bal, ok := data.Balances[customerID]
	if !ok {
		bal = CreditBalance{
			CustomerID:   customerID,
			PrepaidUSD:   creditsInitialUSD(),
			AllowOverage: creditsAllowOverageDefault(),
		}
	}

	remaining := cost
	if bal.PrepaidUSD >= remaining {
		bal.PrepaidUSD -= remaining
		remaining = 0
	} else {
		remaining -= bal.PrepaidUSD
		bal.PrepaidUSD = 0
	}

	result := creditDeductResult{Balance: bal}
	if remaining > 0 {
		if !bal.AllowOverage {
			result.Blocked = true
			return result, nil
		}
		bal.OverageUSD += remaining
		result.Overage = true
		result.OverageAmount = remaining
	}

	bal.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	data.Balances[customerID] = bal
	result.Balance = bal
	if err := saveCreditsData(data); err != nil {
		return creditDeductResult{}, err
	}
	return result, nil
}

func setCreditBalance(customerID string, prepaid float64, allowOverage bool) error {
	creditsStore.mu.Lock()
	defer creditsStore.mu.Unlock()

	data, err := loadCreditsData()
	if err != nil {
		return err
	}
	if data.Balances == nil {
		data.Balances = make(map[string]CreditBalance)
	}
	data.Balances[customerID] = CreditBalance{
		CustomerID:   customerID,
		PrepaidUSD:   prepaid,
		AllowOverage: allowOverage,
		UpdatedAt:    time.Now().UTC().Format(time.RFC3339),
	}
	return saveCreditsData(data)
}

func registerCreditsRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /billing/credits", handleGetCredits)
}

func handleGetCredits(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	bal, err := getOrCreateCreditBalance(ent.CustomerID)
	if err != nil {
		http.Error(w, "failed to load credits", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, bal)
}

func setCreditsPath(path string) {
	creditsStore.path = path
}

func resetCreditsForTests() {
	_ = saveJSONFile(creditsStore.path, creditsData{Balances: make(map[string]CreditBalance)})
}
