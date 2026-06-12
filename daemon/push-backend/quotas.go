package main

import (
	"errors"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type quotaCheckKind int

const (
	quotaCheckAgent quotaCheckKind = iota
	quotaCheckRun
	quotaCheckUsage
	quotaCheckArtifact
)

var errQuotaExceeded = errors.New("quota exceeded")

func quotaMaxAgents() int {
	return envIntDefault("QUOTA_MAX_AGENTS", 20)
}

func quotaMaxConcurrentRuns() int {
	return envIntDefault("QUOTA_MAX_CONCURRENT_RUNS", 5)
}

func quotaDailyUsageUSD() float64 {
	return envFloatDefault("QUOTA_DAILY_USAGE_USD", 100)
}

func envIntDefault(key string, def int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	return n
}

func envFloatDefault(key string, def float64) float64 {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f < 0 {
		return def
	}
	return f
}

func enforceQuota(ent subscriptionEntitlement, kind quotaCheckKind) error {
	return enforceQuotaForCustomer(ent.CustomerID, kind)
}

func enforceQuotaForCustomer(customerID string, kind quotaCheckKind) error {
	switch kind {
	case quotaCheckAgent:
		count := countAgentsForCustomer(customerID)
		if count >= quotaMaxAgents() {
			return errQuotaExceeded
		}
	case quotaCheckRun:
		active := countActiveRunsForCustomer(customerID)
		if active >= quotaMaxConcurrentRuns() {
			return errQuotaExceeded
		}
	case quotaCheckUsage:
		spent := dailyUsageUSDForCustomer(customerID)
		if spent >= quotaDailyUsageUSD() {
			return errQuotaExceeded
		}
	case quotaCheckArtifact:
		return nil
	}
	return nil
}

func countAgentsForCustomer(customerID string) int {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	n := 0
	for _, a := range controlPlane.data.Agents {
		if a.CustomerID == customerID {
			n++
		}
	}
	return n
}

func countActiveRunsForCustomer(customerID string) int {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	return countActiveRunsForCustomerLocked(customerID)
}

// countActiveRunsForCustomerLocked counts active runs assuming the caller already
// holds controlPlane.mu (read or write). Used to re-check the concurrency quota
// inside the create-run critical section, closing the check-then-append TOCTOU
// window that the top-of-handler enforceQuota call alone leaves open.
func countActiveRunsForCustomerLocked(customerID string) int {
	n := 0
	for _, run := range controlPlane.data.Runs {
		if run.CustomerID != customerID {
			continue
		}
		if isActiveRunStatus(run.Status) {
			n++
		}
	}
	return n
}

func isActiveRunStatus(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "pending", "running", "submitted", "in_progress":
		return true
	default:
		return false
	}
}

func dailyUsageUSDForCustomer(customerID string) float64 {
	var usage usageData
	if err := loadJSONFile(usageStore.path, &usage); err != nil {
		return 0
	}
	prefix := time.Now().UTC().Format("2006-01-02")
	var total float64
	for _, rec := range usage.Records {
		if rec.CustomerID != customerID {
			continue
		}
		if strings.HasPrefix(rec.RecordedAt, prefix) {
			total += rec.Cost
		}
	}
	return total
}

func writeQuotaError(w http.ResponseWriter, err error) {
	if errors.Is(err, errQuotaExceeded) {
		http.Error(w, err.Error(), http.StatusTooManyRequests)
		return
	}
	http.Error(w, err.Error(), http.StatusInternalServerError)
}

type QuotaSnapshot struct {
	AgentsUsed          int      `json:"agentsUsed"`
	AgentsLimit         int      `json:"agentsLimit"`
	RunsToday           int      `json:"runsToday"`
	ConcurrentRuns      int      `json:"concurrentRuns"`
	ConcurrentRunsLimit int      `json:"concurrentRunsLimit"`
	UsageTodayUSD       float64  `json:"usageTodayUSD"`
	DailyUsageLimitUSD  float64  `json:"dailyUsageLimitUSD"`
	CreditsRemainingUSD *float64 `json:"creditsRemainingUSD,omitempty"`
}

func registerQuotaRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /billing/quota", handleGetQuota)
}

func handleGetQuota(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	writeJSON(w, http.StatusOK, quotaSnapshotForCustomer(ent.CustomerID))
}

func quotaSnapshotForCustomer(customerID string) QuotaSnapshot {
	snapshot := QuotaSnapshot{
		AgentsUsed:          countAgentsForCustomer(customerID),
		AgentsLimit:         quotaMaxAgents(),
		RunsToday:           countRunsTodayForCustomer(customerID),
		ConcurrentRuns:      countActiveRunsForCustomer(customerID),
		ConcurrentRunsLimit: quotaMaxConcurrentRuns(),
		UsageTodayUSD:       dailyUsageUSDForCustomer(customerID),
		DailyUsageLimitUSD:  quotaDailyUsageUSD(),
	}
	if bal, err := getOrCreateCreditBalance(customerID); err == nil {
		remaining := bal.PrepaidUSD
		snapshot.CreditsRemainingUSD = &remaining
	}
	return snapshot
}

func countRunsTodayForCustomer(customerID string) int {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	prefix := time.Now().UTC().Format("2006-01-02")
	n := 0
	for _, run := range controlPlane.data.Runs {
		if run.CustomerID != customerID {
			continue
		}
		if strings.HasPrefix(run.CreatedAt, prefix) {
			n++
		}
	}
	return n
}
