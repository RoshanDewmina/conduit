package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type Schedule struct {
	ID         string `json:"id"`
	AgentID    string `json:"agentId"`
	CustomerID string `json:"customerId"`
	OrgID      string `json:"orgId,omitempty"`
	CronExpr   string `json:"cronExpr"`
	Command    string `json:"command,omitempty"`
	Enabled    bool   `json:"enabled"`
	NextRunAt  string `json:"nextRunAt"`
	LastRunAt  string `json:"lastRunAt,omitempty"`
	CreatedAt  string `json:"createdAt"`
	UpdatedAt  string `json:"updatedAt"`
}

type createScheduleRequest struct {
	CronExpr string `json:"cronExpr"`
	Command  string `json:"command,omitempty"`
	Enabled  *bool  `json:"enabled,omitempty"`
}

type schedulesData struct {
	Schedules []Schedule `json:"schedules"`
}

var schedulesStore = struct {
	path string
}{
	path: dataFilePath("SCHEDULES_FILE", "conduit-schedules.json"),
}

func initSchedulesStore() {
	var data schedulesData
	if err := loadJSONFile(schedulesStore.path, &data); err != nil {
		log.Printf("schedules: load failed: %v", err)
	}
}

func loadSchedulesData() (schedulesData, error) {
	var data schedulesData
	if err := loadJSONFile(schedulesStore.path, &data); err != nil {
		return schedulesData{}, err
	}
	return data, nil
}

func saveSchedulesData(data schedulesData) error {
	return saveJSONFile(schedulesStore.path, data)
}

func registerScheduleRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /agents/{id}/schedules", handleCreateSchedule)
	mux.HandleFunc("GET /agents/{id}/schedules", handleListSchedules)
	mux.HandleFunc("POST /schedules/{id}/trigger", handleTriggerSchedule)
}

func handleCreateSchedule(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	agentID := r.PathValue("id")
	agent, ok := findAgentForEntitlement(ent, agentID)
	if !ok {
		http.Error(w, "agent not found", http.StatusNotFound)
		return
	}

	var req createScheduleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.CronExpr) == "" {
		http.Error(w, "cronExpr is required", http.StatusBadRequest)
		return
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}

	now := time.Now().UTC()
	nextRun, err := computeNextRun(req.CronExpr, now)
	if err != nil {
		if errors.Is(err, errInvalidCron) {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	schedule := Schedule{
		ID:         newResourceID("sched"),
		AgentID:    agent.ID,
		CustomerID: ent.CustomerID,
		OrgID:      ent.OrgID,
		CronExpr:   req.CronExpr,
		Command:    req.Command,
		Enabled:    enabled,
		NextRunAt:  nextRun.UTC().Format(time.RFC3339),
		CreatedAt:  now.Format(time.RFC3339),
		UpdatedAt:  now.Format(time.RFC3339),
	}

	data, err := loadSchedulesData()
	if err != nil {
		http.Error(w, "failed to load schedules", http.StatusInternalServerError)
		return
	}
	data.Schedules = append(data.Schedules, schedule)
	if err := saveSchedulesData(data); err != nil {
		http.Error(w, "failed to persist schedule", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, schedule)
}

func handleListSchedules(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	agentID := r.PathValue("id")
	if _, ok := findAgentForEntitlement(ent, agentID); !ok {
		http.Error(w, "agent not found", http.StatusNotFound)
		return
	}

	data, err := loadSchedulesData()
	if err != nil {
		http.Error(w, "failed to load schedules", http.StatusInternalServerError)
		return
	}
	out := make([]Schedule, 0)
	for _, s := range data.Schedules {
		if s.AgentID == agentID && resourceVisibleToEntitlement(ent, s.CustomerID, s.OrgID) {
			out = append(out, s)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"schedules": out})
}

func handleTriggerSchedule(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckRun); err != nil {
		writeQuotaError(w, err)
		return
	}

	scheduleID := r.PathValue("id")
	run, schedule, err := triggerScheduleByID(ent, scheduleID)
	if err != nil {
		var nf notFoundError
		if errors.As(err, &nf) {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"schedule": schedule,
		"run":      run,
	})
}

func triggerScheduleByID(ent subscriptionEntitlement, scheduleID string) (AgentRun, Schedule, error) {
	data, err := loadSchedulesData()
	if err != nil {
		return AgentRun{}, Schedule{}, err
	}
	var schedule *Schedule
	for i := range data.Schedules {
		if data.Schedules[i].ID == scheduleID {
			schedule = &data.Schedules[i]
			break
		}
	}
	if schedule == nil || !resourceVisibleToEntitlement(ent, schedule.CustomerID, schedule.OrgID) {
		return AgentRun{}, Schedule{}, errNotFound("schedule not found")
	}
	return executeSchedule(schedule, data)
}

type notFoundError string

func (e notFoundError) Error() string { return string(e) }

func errNotFound(msg string) error { return notFoundError(msg) }

func executeSchedule(schedule *Schedule, data schedulesData) (AgentRun, Schedule, error) {
	if !schedule.Enabled {
		return AgentRun{}, Schedule{}, errNotFound("schedule disabled")
	}
	if _, ok := findAgentByID(schedule.AgentID); !ok {
		return AgentRun{}, Schedule{}, errNotFound("agent not found")
	}

	now := time.Now().UTC().Format(time.RFC3339)
	run := AgentRun{
		ID:         newResourceID("run"),
		AgentID:    schedule.AgentID,
		CustomerID: schedule.CustomerID,
		OrgID:      schedule.OrgID,
		Status:     "pending",
		Command:    schedule.Command,
		StartedAt:  now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	controlPlane.mu.Lock()
	controlPlane.data.Runs = append(controlPlane.data.Runs, run)
	if err := persistControlPlane(); err != nil {
		controlPlane.mu.Unlock()
		return AgentRun{}, Schedule{}, err
	}
	controlPlane.mu.Unlock()

	next, err := computeNextRun(schedule.CronExpr, time.Now().UTC())
	if err != nil {
		return run, *schedule, err
	}
	schedule.LastRunAt = now
	schedule.NextRunAt = next.UTC().Format(time.RFC3339)
	schedule.UpdatedAt = now

	for i := range data.Schedules {
		if data.Schedules[i].ID == schedule.ID {
			data.Schedules[i] = *schedule
			break
		}
	}
	if err := saveSchedulesData(data); err != nil {
		return run, *schedule, err
	}
	return run, *schedule, nil
}

func processDueSchedules() {
	data, err := loadSchedulesData()
	if err != nil {
		log.Printf("schedules: process due failed load: %v", err)
		return
	}
	now := time.Now().UTC()
	for i := range data.Schedules {
		s := &data.Schedules[i]
		if !s.Enabled {
			continue
		}
		nextRun, err := time.Parse(time.RFC3339, s.NextRunAt)
		if err != nil || nextRun.After(now) {
			continue
		}
		if _, ok := findAgentByID(s.AgentID); !ok {
			continue
		}
		if err := enforceQuotaForCustomer(s.CustomerID, quotaCheckRun); err != nil {
			log.Printf("schedules: skip %s quota: %v", s.ID, err)
			continue
		}
		if _, _, err := executeSchedule(s, data); err != nil {
			log.Printf("schedules: execute %s failed: %v", s.ID, err)
			continue
		}
		data, _ = loadSchedulesData()
	}
}

func computeNextRun(cronExpr string, from time.Time) (time.Time, error) {
	expr := strings.TrimSpace(strings.ToLower(cronExpr))
	switch expr {
	case "@hourly", "hourly":
		return from.Add(time.Hour), nil
	case "@daily", "daily":
		return from.Add(24 * time.Hour), nil
	case "@weekly", "weekly":
		return from.Add(7 * 24 * time.Hour), nil
	}
	if strings.HasPrefix(expr, "every:") {
		secs, err := strconv.Atoi(strings.TrimPrefix(expr, "every:"))
		if err != nil || secs <= 0 {
			return time.Time{}, errInvalidCron
		}
		return from.Add(time.Duration(secs) * time.Second), nil
	}
	return time.Time{}, errInvalidCron
}

var errInvalidCron = errors.New("unsupported cronExpr; use @hourly, @daily, @weekly, or every:<seconds>")

func startScheduleTicker() {
	if strings.EqualFold(os.Getenv("SCHEDULE_TICKER_ENABLED"), "false") {
		return
	}
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			processDueSchedules()
		}
	}()
}

func setSchedulesPath(path string) {
	schedulesStore.path = path
}

func resetSchedulesForTests() {
	_ = saveJSONFile(schedulesStore.path, schedulesData{})
}
