package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestCreditsDeductionAndOverageBlock(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_credit", "credit-token")
	tok := clientTokenFor(t, "cus_credit")

	if err := setCreditBalance("cus_credit", 0.01, false); err != nil {
		t.Fatal(err)
	}

	mux := http.NewServeMux()
	registerUsageRoutes(mux)

	body := `{"cost":0.05}`
	req := httptest.NewRequest(http.MethodPost, "/usage", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("expected 402, got %d body=%s", rec.Code, rec.Body.String())
	}

	if err := setCreditBalance("cus_credit", 0.02, true); err != nil {
		t.Fatal(err)
	}
	req = httptest.NewRequest(http.MethodPost, "/usage", bytes.NewBufferString(`{"cost":0.10}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 with overage, got %d body=%s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("X-Credit-Overage") != "true" {
		t.Fatalf("expected overage header")
	}
}

func TestGetCredits(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_bal", "bal-token")
	tok := clientTokenFor(t, "cus_bal")
	_ = setCreditBalance("cus_bal", 12.5, true)

	mux := http.NewServeMux()
	registerCreditsRoutes(mux)
	req := httptest.NewRequest(http.MethodGet, "/billing/credits", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var bal CreditBalance
	if err := json.Unmarshal(rec.Body.Bytes(), &bal); err != nil {
		t.Fatal(err)
	}
	if bal.PrepaidUSD != 12.5 || !bal.AllowOverage {
		t.Fatalf("unexpected balance: %+v", bal)
	}
}

func TestArtifactsCRUD(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_art", "art-token")
	tok := clientTokenFor(t, "cus_art")

	agentMux := http.NewServeMux()
	registerAgentRoutes(agentMux)
	createReq := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Art Bot","runtime":"ssh-host"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createReq.Header.Set("Authorization", bearerHeader(tok))
	createRec := httptest.NewRecorder()
	agentMux.ServeHTTP(createRec, createReq)
	var agent Agent
	_ = json.Unmarshal(createRec.Body.Bytes(), &agent)

	runReq := httptest.NewRequest(http.MethodPost, "/runs", bytes.NewBufferString(`{"agentId":"`+agent.ID+`"}`))
	runReq.Header.Set("Content-Type", "application/json")
	runReq.Header.Set("Authorization", bearerHeader(tok))
	runRec := httptest.NewRecorder()
	agentMux.ServeHTTP(runRec, runReq)
	var run AgentRun
	_ = json.Unmarshal(runRec.Body.Bytes(), &run)

	artMux := http.NewServeMux()
	registerArtifactRoutes(artMux)
	postBody := `{"name":"log.txt","storageRef":"runs/` + run.ID + `/log.txt","contentType":"text/plain","sizeBytes":42}`
	req := httptest.NewRequest(http.MethodPost, "/runs/"+run.ID+"/artifacts", bytes.NewBufferString(postBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	artMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create artifact status=%d body=%s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID+"/artifacts", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	artMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list artifacts status=%d", rec.Code)
	}
}

func TestSchedulesAndTrigger(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_sched", "sched-token")
	tok := clientTokenFor(t, "cus_sched")

	agentMux := http.NewServeMux()
	registerAgentRoutes(agentMux)
	createReq := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Sched Bot","runtime":"ssh-host"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createReq.Header.Set("Authorization", bearerHeader(tok))
	createRec := httptest.NewRecorder()
	agentMux.ServeHTTP(createRec, createReq)
	var agent Agent
	_ = json.Unmarshal(createRec.Body.Bytes(), &agent)

	schedMux := http.NewServeMux()
	registerScheduleRoutes(schedMux)
	body := `{"cronExpr":"@hourly","command":"echo scheduled"}`
	req := httptest.NewRequest(http.MethodPost, "/agents/"+agent.ID+"/schedules", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create schedule status=%d body=%s", rec.Code, rec.Body.String())
	}
	var schedule Schedule
	if err := json.Unmarshal(rec.Body.Bytes(), &schedule); err != nil {
		t.Fatal(err)
	}
	if schedule.NextRunAt == "" {
		t.Fatal("expected nextRunAt")
	}

	req = httptest.NewRequest(http.MethodGet, "/agents/"+agent.ID+"/schedules", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list schedules status=%d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/schedules/"+schedule.ID+"/trigger", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("trigger schedule status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestScheduleUpdateAndDelete(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_schededit", "schededit-token")
	tok := clientTokenFor(t, "cus_schededit")

	agentMux := http.NewServeMux()
	registerAgentRoutes(agentMux)
	createReq := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Edit Bot","runtime":"ssh-host"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createReq.Header.Set("Authorization", bearerHeader(tok))
	createRec := httptest.NewRecorder()
	agentMux.ServeHTTP(createRec, createReq)
	var agent Agent
	_ = json.Unmarshal(createRec.Body.Bytes(), &agent)

	schedMux := http.NewServeMux()
	registerScheduleRoutes(schedMux)
	req := httptest.NewRequest(http.MethodPost, "/agents/"+agent.ID+"/schedules", bytes.NewBufferString(`{"cronExpr":"@hourly","command":"echo a"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	var schedule Schedule
	_ = json.Unmarshal(rec.Body.Bytes(), &schedule)
	originalNext := schedule.NextRunAt

	// PATCH: change cron to @daily, disable, change command.
	patchBody := `{"cronExpr":"@daily","command":"echo b","enabled":false}`
	req = httptest.NewRequest(http.MethodPatch, "/schedules/"+schedule.ID, bytes.NewBufferString(patchBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("patch schedule status=%d body=%s", rec.Code, rec.Body.String())
	}
	var updated Schedule
	if err := json.Unmarshal(rec.Body.Bytes(), &updated); err != nil {
		t.Fatal(err)
	}
	if updated.CronExpr != "@daily" || updated.Command != "echo b" || updated.Enabled {
		t.Fatalf("patch did not apply: %+v", updated)
	}
	if updated.NextRunAt == originalNext {
		t.Fatalf("nextRunAt should recompute on cron change (was %s)", originalNext)
	}

	// Invalid cron rejected.
	req = httptest.NewRequest(http.MethodPatch, "/schedules/"+schedule.ID, bytes.NewBufferString(`{"cronExpr":"0 * * * *"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for unsupported cron, got %d", rec.Code)
	}

	// DELETE.
	req = httptest.NewRequest(http.MethodDelete, "/schedules/"+schedule.ID, nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete schedule status=%d body=%s", rec.Code, rec.Body.String())
	}

	// Gone now.
	req = httptest.NewRequest(http.MethodDelete, "/schedules/"+schedule.ID, nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	schedMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 deleting missing schedule, got %d", rec.Code)
	}
}

func TestRunLogsAndStatusLifecycle(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_logs", "logs-token")
	tok := clientTokenFor(t, "cus_logs")

	agentMux := http.NewServeMux()
	registerAgentRoutes(agentMux)
	createReq := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Log Bot","runtime":"gcp_cloud_run"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createReq.Header.Set("Authorization", bearerHeader(tok))
	createRec := httptest.NewRecorder()
	agentMux.ServeHTTP(createRec, createReq)
	var agent Agent
	_ = json.Unmarshal(createRec.Body.Bytes(), &agent)

	runReq := httptest.NewRequest(http.MethodPost, "/runs", bytes.NewBufferString(`{"agentId":"`+agent.ID+`"}`))
	runReq.Header.Set("Content-Type", "application/json")
	runReq.Header.Set("Authorization", bearerHeader(tok))
	runRec := httptest.NewRecorder()
	agentMux.ServeHTTP(runRec, runReq)
	var run AgentRun
	_ = json.Unmarshal(runRec.Body.Bytes(), &run)

	// Mint a runner token (normally done at dispatch).
	runnerTok, err := mintRunToken(run.ID)
	if err != nil {
		t.Fatal(err)
	}

	logMux := http.NewServeMux()
	registerRunLogRoutes(logMux)

	// Runner appends logs.
	appendBody := `{"lines":[{"stream":"stdout","text":"hello"},{"stream":"stderr","text":"warn"}]}`
	req := httptest.NewRequest(http.MethodPost, "/runs/"+run.ID+"/logs", bytes.NewBufferString(appendBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(runnerTok))
	rec := httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("append logs status=%d body=%s", rec.Code, rec.Body.String())
	}

	// Wrong token rejected.
	req = httptest.NewRequest(http.MethodPost, "/runs/"+run.ID+"/logs", bytes.NewBufferString(appendBody))
	req.Header.Set("Authorization", bearerHeader("rt_bogus"))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for bad runner token, got %d", rec.Code)
	}

	// Client tails logs.
	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID+"/logs?since=0", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("get logs status=%d body=%s", rec.Code, rec.Body.String())
	}
	var logsResp struct {
		Lines     []RunLogEntry `json:"lines"`
		NextSince int           `json:"nextSince"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &logsResp); err != nil {
		t.Fatal(err)
	}
	if len(logsResp.Lines) != 2 || logsResp.NextSince != 2 {
		t.Fatalf("unexpected logs: %+v", logsResp)
	}

	// Incremental tail returns nothing new.
	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID+"/logs?since=2", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	_ = json.Unmarshal(rec.Body.Bytes(), &logsResp)
	if len(logsResp.Lines) != 0 {
		t.Fatalf("expected no new lines, got %d", len(logsResp.Lines))
	}

	// Client requests cancel.
	req = httptest.NewRequest(http.MethodPost, "/runs/"+run.ID+"/cancel", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("cancel status=%d", rec.Code)
	}

	// Runner sees the cancel request via control endpoint.
	req = httptest.NewRequest(http.MethodGet, "/runs/"+run.ID+"/control", nil)
	req.Header.Set("Authorization", bearerHeader(runnerTok))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	var control struct {
		Status          string `json:"status"`
		CancelRequested bool   `json:"cancelRequested"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &control)
	if !control.CancelRequested {
		t.Fatalf("expected cancelRequested true, got %+v", control)
	}

	// Runner patches terminal status + exit code.
	patchBody := `{"status":"succeeded","exitCode":0}`
	req = httptest.NewRequest(http.MethodPatch, "/runs/"+run.ID, bytes.NewBufferString(patchBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(runnerTok))
	rec = httptest.NewRecorder()
	logMux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("patch run status=%d body=%s", rec.Code, rec.Body.String())
	}

	// Confirm the run reflects the patch (completedAt auto-set on terminal).
	getReq := httptest.NewRequest(http.MethodGet, "/runs/"+run.ID, nil)
	getReq.Header.Set("Authorization", bearerHeader(tok))
	getRec := httptest.NewRecorder()
	agentMux.ServeHTTP(getRec, getReq)
	var finalRun AgentRun
	_ = json.Unmarshal(getRec.Body.Bytes(), &finalRun)
	if finalRun.Status != "succeeded" || finalRun.ExitCode == nil || *finalRun.ExitCode != 0 {
		t.Fatalf("run not patched: %+v", finalRun)
	}
	if finalRun.CompletedAt == "" {
		t.Fatal("expected completedAt to be auto-set on terminal status")
	}
}

func TestGCPCloudRunAgentCreate(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_gcp", "gcp-token")
	tok := clientTokenFor(t, "cus_gcp")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Cloud Job","runtime":"gcp_cloud_run"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create gcp agent status=%d body=%s", rec.Code, rec.Body.String())
	}
	var agent Agent
	if err := json.Unmarshal(rec.Body.Bytes(), &agent); err != nil {
		t.Fatal(err)
	}
	if agent.Runtime != "gcp_cloud_run" {
		t.Fatalf("runtime=%q", agent.Runtime)
	}
	if len(agent.Config) == 0 {
		t.Fatal("expected gcp config merged")
	}
}

func TestLightsailRuntimeAccepted(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_ls", "ls-token")
	tok := clientTokenFor(t, "cus_ls")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)
	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Lightsail Bot","runtime":"lightsail","config":{"region":"us-east-1"}}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("lightsail agent status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestQuotaMaxAgents(t *testing.T) {
	setupTestStores(t)
	t.Setenv("QUOTA_MAX_AGENTS", "1")
	seedActiveEntitlement(t, "cus_q", "q-token")
	tok := clientTokenFor(t, "cus_q")

	mux := http.NewServeMux()
	registerAgentRoutes(mux)

	req := httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"One"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("first agent status=%d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/agents", bytes.NewBufferString(`{"name":"Two"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
}

func TestOrgMembersStub(t *testing.T) {
	setupTestStores(t)
	cacheEntitlement(subscriptionEntitlement{
		CustomerID:      "cus_org",
		OrgID:           "org_test",
		SubscriptionID:  "sub_test",
		Status:          "active",
		Active:          true,
		AppAccountToken: "org-token",
		UpdatedAt:       seedTime(),
	})
	tok := clientTokenFor(t, "cus_org")

	mux := http.NewServeMux()
	registerOrgRoutes(mux)

	body := `{"email":"dev@example.com","role":"admin"}`
	req := httptest.NewRequest(http.MethodPost, "/orgs/org_test/members", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("invite status=%d body=%s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/orgs/org_test/members", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list members status=%d", rec.Code)
	}
}

func TestGetQuota(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_quota", "quota-token")
	tok := clientTokenFor(t, "cus_quota")
	_ = setCreditBalance("cus_quota", 7.5, true)

	mux := http.NewServeMux()
	registerQuotaRoutes(mux)
	req := httptest.NewRequest(http.MethodGet, "/billing/quota", nil)
	req.Header.Set("Authorization", bearerHeader(tok))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var snapshot QuotaSnapshot
	if err := json.Unmarshal(rec.Body.Bytes(), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.AgentsLimit != quotaMaxAgents() {
		t.Fatalf("agentsLimit=%d", snapshot.AgentsLimit)
	}
	if snapshot.CreditsRemainingUSD == nil || *snapshot.CreditsRemainingUSD != 7.5 {
		t.Fatalf("unexpected credits: %+v", snapshot.CreditsRemainingUSD)
	}
}

func TestEntitlementIncludesOrgName(t *testing.T) {
	setupTestStores(t)
	dir := t.TempDir()
	orgPath := filepath.Join(dir, "orgs.json")
	setOrgsPath(orgPath)
	_ = saveOrgsData(orgsData{
		Orgs: []Org{{ID: "org_test", Name: "Acme Eng"}},
	})
	cacheEntitlement(subscriptionEntitlement{
		CustomerID:      "cus_org_name",
		OrgID:           "org_test",
		SubscriptionID:  "sub_test",
		Status:          "active",
		Active:          true,
		AppAccountToken: "org-name-token",
		UpdatedAt:       seedTime(),
	})

	mux := http.NewServeMux()
	registerBillingRoutes(mux)
	req := httptest.NewRequest(http.MethodGet, "/billing/entitlement?appAccountToken=org-name-token", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var ent subscriptionEntitlement
	if err := json.Unmarshal(rec.Body.Bytes(), &ent); err != nil {
		t.Fatal(err)
	}
	if ent.OrgID != "org_test" || ent.OrgName != "Acme Eng" {
		t.Fatalf("unexpected entitlement: %+v", ent)
	}
}

func TestPhase2Phase3RoutesNot404(t *testing.T) {
	setupTestStores(t)
	seedActiveEntitlement(t, "cus_routes", "routes-token")
	tok := clientTokenFor(t, "cus_routes")

	mux := http.NewServeMux()
	registerBillingRoutes(mux)
	registerCreditsRoutes(mux)
	registerQuotaRoutes(mux)
	registerAgentRoutes(mux)
	registerArtifactRoutes(mux)
	registerScheduleRoutes(mux)
	registerRunLogRoutes(mux)
	registerOrgRoutes(mux)

	routes := []struct {
		method string
		path   string
	}{
		{http.MethodGet, "/billing/credits"},
		{http.MethodGet, "/billing/quota"},
		{http.MethodGet, "/runs/run_missing/artifacts"},
		{http.MethodGet, "/runs/run_missing/logs"},
		{http.MethodPost, "/runs/run_missing/cancel"},
		{http.MethodGet, "/runs/run_missing/control"},
		{http.MethodPatch, "/schedules/sched_missing"},
		{http.MethodDelete, "/schedules/sched_missing"},
		{http.MethodGet, "/agents/agent_missing/schedules"},
		{http.MethodPost, "/schedules/sched_missing/trigger"},
		{http.MethodGet, "/orgs/org_missing/members"},
	}
	for _, route := range routes {
		req := httptest.NewRequest(route.method, route.path, nil)
		req.Header.Set("Authorization", bearerHeader(tok))
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code == http.StatusNotFound && rec.Body.String() == "404 page not found\n" {
			t.Fatalf("%s %s is not registered (mux 404)", route.method, route.path)
		}
	}
}

func seedTime() string {
	return "2026-06-02T00:00:00Z"
}
