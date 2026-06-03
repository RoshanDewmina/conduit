# Cloud Execution Engine — Build-to-Production Handoff Plan

**Audience:** an implementing agent (or engineer) who will build the cloud execution engine end-to-end.
**Goal:** make **cloud-runtime hosted agents actually execute** (GCP Cloud Run + AWS Lightsail + Fly.io), stream real logs/status/artifacts back to the app, and be production-ready.
**Author of this plan:** prior session that audited the codebase ground-truth on 2026-06-03.

> **Read this whole document before writing code.** It contains the exact current state (with
> `file:line` references), the conventions you must follow, full code skeletons, security
> requirements, a test strategy, and an owner-run deploy runbook. Do not guess at backend
> conventions — they are documented below and must be mirrored exactly.

---

## 0. TL;DR — what is and isn't done

**The iOS app and the control-plane HTTP surface are essentially complete and cloud-ready.**
What is missing is the thing that *runs the container/VM and executes the agent command*.

| Layer | State | Evidence |
|---|---|---|
| iOS Create-Agent UI (Cloud/SSH toggle, region picker) | ✅ done | `CreateAgentSheet.swift` |
| iOS run-log live tail + cursor + merge | ✅ done | `AgentStore.loadNewRunLogs` (AgentStore.swift:367), `logLines(for:)` (:382) |
| iOS cloud cancel (POST /runs/{id}/cancel) | ✅ done | `AgentStore.cancelRun` (AgentStore.swift:507-520) |
| Backend run-logs store + ingest + tail | ✅ done | `run_logs.go` (`handleAppendRunLogs`, `handleGetRunLogs`) |
| Backend runner-token mint + scoped auth | ✅ done | `run_logs.go:77 mintRunToken`, `:94 resolveRunFromRunnerToken` |
| Backend `PATCH /runs/{id}` (status/exit) | ✅ done | `run_logs.go:250 handlePatchRun` |
| Backend `POST /runs/{id}/cancel` + `GET /runs/{id}/control` | ✅ done | `run_logs.go:282`, `:300` |
| Backend artifact metadata CRUD (+DELETE) | ✅ done | `artifacts.go` |
| **Dispatch: launch execution when a run is created** | ❌ **MISSING** | `handleCreateRun` (agents.go:203-261) never dispatches |
| **`agent-runner` binary (executes command, calls back)** | ❌ **MISSING** | `daemon/agent-runner/` does not exist |
| **GCP Cloud Run Jobs API call** | ❌ **STUB** | `submitCloudRunJobIfConfigured` (gcp_cloud_run.go:175) = `_ = spec; return nil` |
| **AWS Lightsail provisioning** | ❌ **STUB** | `provisionLightsailAgent` (runtime.go:42) = empty |
| **Fly.io provisioning** | ❌ **MISSING** | `runtime.go:37` falls through to `default: return nil` |
| **GCS artifact bytes (upload + signed-URL download)** | ❌ **MISSING** | `artifacts_gcs.go` only builds a `gs://` URI string |
| **Cloud SDKs in go.mod** | ❌ **MISSING** | `go.mod` has only `golang-jwt/jwt/v5` |
| **Runner image + Dockerfile + registry push** | ❌ **MISSING** | none exist |

**Net:** today, creating a Cloud agent and pressing "Start run" creates a `pending` run record
that **nothing ever executes**. This plan closes that gap.

---

## 1. Product & architecture context

**Conduit** is an iOS SSH/agent-management app. "Hosted agents" let a user define an agent
(a model + a command like `claude`) and run it either:

- **`ssh-host` runtime (on-device):** the app SSHes to the user's own machine and runs the command
  there, streaming logs/approvals via `conduitd`/`DaemonChannel`. **This already works.** All the
  interactive features (exec console, SFTP files, git workspace) target this runtime.
- **cloud runtimes (`gcp_cloud_run` / `lightsail` / `fly`):** the **control plane** (the Go
  `push-backend`) provisions a container/VM that runs the agent command, and that container streams
  results back to the control plane, which the app polls. **This is what you are building.**

### The cloud data flow you will implement

```
iOS app                control plane (push-backend)            cloud provider            agent-runner (in container)
  │  POST /runs            │                                        │                          │
  ├───────────────────────▶ handleCreateRun                        │                          │
  │                        │  persist run(status=pending)          │                          │
  │                        │  mintRunToken(runID) ──► rt_xxx        │                          │
  │                        │  dispatchRun(agent, run):             │                          │
  │                        │    execute Cloud Run Job / launch VM ──▶ start container          │
  │                        │      env: CONDUIT_RUN_ID,             │   with env ──────────────▶ main()
  │                        │           CONDUIT_RUNNER_TOKEN,       │                          │  exec command
  │                        │           CONDUIT_CONTROL_PLANE_URL,  │                          │  POST /runs/{id}/logs  (rt auth)
  │  GET /runs/{id}/logs   │           CONDUIT_COMMAND             │                          │  ◀── batches of stdout/stderr
  │  ?since=N  (poll)      │                                       │                          │  PATCH /runs/{id} status/exit
  ◀───── lines ───────────┤ ◀─────────────────────────────────────┼──────────────────────────┤  POST artifacts (+GCS bytes)
  │                        │                                       │                          │  GET /runs/{id}/control (poll cancel)
  │  POST /runs/{id}/cancel│  set cancelRequested=true             │                          │  ◀── {cancelRequested:true} ► exit
  └────────────────────────┴───────────────────────────────────────┴──────────────────────────┘
```

**Security model (already partly built — preserve it):**
- The **runner token** (`rt_…`, minted by `mintRunToken`) is per-run, random, scoped to exactly one
  run, and used by the container to authenticate `POST /logs`, `PATCH /runs/{id}`, and `GET /control`.
  It is **never** returned to the app and is **never** the user's `clientToken`. Validation:
  `resolveRunFromRunnerToken(r)` must equal the path's run id (see `handleAppendRunLogs`:201-205).
- The app authenticates with its **`clientToken`** via `resolveEntitlementFromBearer(r)` and ownership
  is checked with `resourceVisibleToEntitlement(ent, customerID, orgID)` / `customerOwnsRun(ent, runID)`.

---

## 2. Backend conventions you MUST follow

These are observed throughout `daemon/push-backend/`. Mirror them exactly so the new code is idiomatic.

- **Routing:** Go 1.22 `http.ServeMux` with method+path patterns and `r.PathValue("id")`.
  Register routes in a `registerXxxRoutes(mux *http.ServeMux)` function, called from `main.go:64-72`.
- **Init:** each store has an `initXxxStore()` called from `main.go:74-83`.
- **Persistence:** mutex-guarded JSON files via `store.go`: `loadJSONFile(path, &dest)` /
  `saveJSONFile(path, src)` (atomic tmp-rename, `MarshalIndent`). File path via
  `dataFilePath("ENV_OVERRIDE", "default-name.json")` → respects `DATA_DIR`, falls back to `TempDir`.
- **IDs:** `newResourceID("prefix")` → `prefix_<24 hex>` (agents.go:82).
- **Timestamps:** `time.Now().UTC().Format(time.RFC3339)`.
- **Auth (app):** `ent, err := resolveEntitlementFromBearer(r)` (entitlements.go:334) → 401 on error.
- **Ownership (app):** `resourceVisibleToEntitlement(ent, customerID, orgID)` (orgs.go:175);
  for runs use `customerOwnsRun(ent, runID)` (artifacts.go:188).
- **Auth (runner):** `runID, ok := resolveRunFromRunnerToken(r)` then check `ok && runID == pathID`.
- **Run mutation:** `updateRunFields(runID, func(run *AgentRun){ … })` (run_logs.go:162) — locks,
  applies, bumps `UpdatedAt`, persists. Use it; do not hand-roll control-plane writes.
- **JSON responses:** `writeJSON(w, http.StatusXxx, payload)`. Errors: `http.Error(w, msg, code)`.
- **Quota:** mutating app endpoints call `enforceQuota(ent, quotaCheckXxx)` then `writeQuotaError(w, err)`.
- **Tests:** there is a `*_test.go` per area; `resetXxxForTests()` + `setXxxPath()` helpers exist for
  every store. Follow `phase2_phase3_test.go` (588 lines) as the integration-test exemplar — it spins
  the handlers with a temp `DATA_DIR` and exercises full request/response cycles.

**Key existing types (do not redefine):**
- `Agent` (agents.go:14): `ID, CustomerID, OrgID, AppAccountToken, Name, Runtime, Config json.RawMessage, OpenRouterKeyHash, …`
- `AgentRun` (agents.go:28): `ID, AgentID, CustomerID, OrgID, Status, Command, StartedAt, CompletedAt, ExitCode *int, CancelRequested bool, …`
- `RunLogEntry` (run_logs.go:14): `Seq, Stream, Text, Ts`.
- `Artifact` (artifacts.go:10): `ID, RunID, CustomerID, OrgID, Name, ContentType, SizeBytes, StorageRef, GCSURI, CreatedAt`.
- `GCPJobOrchestration` (gcp_cloud_run.go:13): per-agent Cloud Run Job record.
- `subscriptionEntitlement` (entitlements.go:18): `CustomerID, OrgID, AppAccountToken, ClientToken, …`.

---

## 3. Milestones

Build in this order. Each is independently compilable/testable. **CE1 (dispatch spine) is the
critical path** — it makes *any* provider work and is fully testable locally with a fake provider
before you touch a single cloud SDK.

> **Verification discipline (applies to every milestone):**
> 1. `cd daemon/push-backend && go build ./... && go vet ./... && go test ./...`
> 2. `cd Packages/ConduitKit && swift build`
> 3. **iOS app target build** via XcodeBuildMCP `build_sim` (Conduit / iPhone 17 Pro) — this is the
>    ONLY gate that type-checks `#if os(iOS)` code under strict concurrency. `swift build` compiles
>    for macOS and **strips all iOS-only code** (memory `project_ws10_qa`). Do not skip it.
> 4. Update `CLAUDE.md` / `docs/` if you change an externally-visible contract.

---

### CE1 — Dispatch spine + provider interface + local fake provider *(fully testable now)*

**Why first:** decouples "when/what to launch" from "which cloud." Once this lands, a run flips
`pending → running → succeeded` end-to-end against a **fake in-process provider**, with the runner
token minted and the control endpoints exercised — no cloud account required.

**New file: `daemon/push-backend/dispatch.go`**

```go
package main

// RunnerEnv is the env contract handed to every runner, regardless of provider.
type RunnerEnv struct {
    RunID           string // CONDUIT_RUN_ID
    RunnerToken     string // CONDUIT_RUNNER_TOKEN  (rt_… from mintRunToken)
    ControlPlaneURL string // CONDUIT_CONTROL_PLANE_URL (controlPlaneBaseURL())
    Command         string // CONDUIT_COMMAND (the agent command to exec)
    Model           string // CONDUIT_MODEL (optional; from agent config)
    OpenRouterKey   string // CONDUIT_OPENROUTER_KEY (optional; provisioned sub-key, see note)
    AgentID         string // CONDUIT_AGENT_ID
}

// RuntimeProvider launches a single run's container/VM. Implementations must be
// non-blocking beyond the launch call: they kick off execution and return.
// Cancellation is cooperative — the runner polls GET /runs/{id}/control.
type RuntimeProvider interface {
    // Launch starts execution for one run. Returns a provider-specific handle
    // string (job execution name / instance id / machine id) for bookkeeping.
    Launch(agent *Agent, run *AgentRun, env RunnerEnv) (handle string, err error)
    // Cancel best-effort terminates the underlying execution. Called when the
    // app posts /cancel AND the provider supports hard-kill (optional; the
    // cooperative poll is the primary path).
    Cancel(handle string) error
}

// providerFor selects the provider for an agent's runtime. ssh-host returns nil
// (on-device path, never dispatched server-side).
func providerFor(runtime string) RuntimeProvider {
    switch normalizeRuntime(runtime) {
    case "gcp_cloud_run":
        return gcpCloudRunProvider{}
    case "lightsail":
        return lightsailProvider{}
    case "fly":
        return flyProvider{}
    default:
        return nil
    }
}

// dispatchRun is invoked AFTER a run is persisted (handleCreateRun, schedule trigger).
// It mints a scoped runner token, builds the env, and launches via the provider.
// On any failure it marks the run failed with a log line (never leaves it stuck pending).
func dispatchRun(agent *Agent, run *AgentRun) {
    prov := providerFor(agent.Runtime)
    if prov == nil {
        return // ssh-host: executed on-device by the app, not here.
    }
    token, err := mintRunToken(run.ID)
    if err != nil {
        failRun(run.ID, "failed to mint runner token")
        return
    }
    env := RunnerEnv{
        RunID:           run.ID,
        RunnerToken:     token,
        ControlPlaneURL: controlPlaneBaseURL(),
        Command:         resolveAgentCommand(agent, run),
        Model:           agentConfigString(agent, "model"),
        AgentID:         agent.ID,
        // OpenRouterKey: see §6 note — provision/inject per security policy.
    }
    handle, err := prov.Launch(agent, run, env)
    if err != nil {
        failRun(run.ID, "failed to launch cloud runtime: "+err.Error())
        return
    }
    updateRunFields(run.ID, func(r *AgentRun) {
        r.Status = "running"
        // optionally stash handle on the run or an orchestration record
    })
    recordDispatch(run.ID, agent.Runtime, handle) // append to a dispatch ledger json (optional but recommended)
}

// failRun marks a run failed and appends an explanatory log line so the app shows why.
func failRun(runID, msg string) {
    _, _ = appendRunLogs(runID, []RunLogEntry{{Stream: "stderr", Text: msg}})
    updateRunFields(runID, func(r *AgentRun) {
        r.Status = "failed"
        if r.CompletedAt == "" {
            r.CompletedAt = nowRFC3339()
        }
    })
}
```

**Helpers to add (dispatch.go or a small `helpers.go`):**
- `controlPlaneBaseURL() string` → `os.Getenv("CONTROL_PLANE_PUBLIC_URL")` (e.g. `https://api.conduit.dev`),
  trimmed, no trailing slash. **Required** for the runner to call back. If empty in a cloud dispatch,
  `failRun` with a clear message (don't launch a runner that can't phone home).
- `resolveAgentCommand(agent, run) string` → `run.Command` if non-empty else the agent's configured
  command (`agentConfigString(agent, "command")`) else `"claude"`.
- `agentConfigString(agent *Agent, key string) string` → unmarshal `agent.Config` (json.RawMessage)
  to `map[string]any`, return the string at `key` or "".
- `nowRFC3339() string` → `time.Now().UTC().Format(time.RFC3339)` (factor the repeated literal).

**Wire dispatch into run creation:**
- `agents.go:255-260` `handleCreateRun`: after `persistControlPlane()` succeeds and **before**
  `writeJSON`, launch dispatch in the background so the HTTP response isn't blocked on a cloud API:
  ```go
  // capture copies; the goroutine must not touch the locked slice
  agentCopy, runCopy := *agent, run
  go dispatchRun(&agentCopy, &runCopy)
  ```
  (Run creation currently holds `controlPlane.mu` via `defer` at agents.go:225 — dispatch must run
  **after** the handler returns / outside the lock, since `dispatchRun` → `updateRunFields` re-locks.
  Spawning a goroutine that runs post-return is the clean fix; verify no deadlock.)
- `schedules.go` trigger path (`triggerScheduleByID`, the `AgentRun{}` built at schedules.go:326 and
  appended at :339): after persist, call the same `go dispatchRun(&agentCopy, &runCopy)`.

**Fake provider for tests: `daemon/push-backend/dispatch_fake_test.go`**
- Implement a `fakeProvider` whose `Launch` spins a goroutine that, using the run's minted token,
  hits the real handlers in-process: `POST /runs/{id}/logs` (a couple of lines), then
  `PATCH /runs/{id}` to `succeeded` with `exitCode:0`. Assert the app-side `GET /runs/{id}/logs`
  returns those lines and `GET /runs/{id}` shows `succeeded`. This proves the whole spine without cloud.

**Definition of done (CE1):** `go test ./...` includes a test that creates a run and observes it
transition `pending → running → succeeded` with real log lines, entirely via the fake provider.

---

### CE2 — `agent-runner` binary + Dockerfile *(testable locally as a plain process)*

**New Go module: `daemon/agent-runner/`** (its own `go.mod` so the control plane stays lean — the
runner only needs stdlib + maybe the GCS client for artifact upload).

```
daemon/agent-runner/
  go.mod              // module conduit/agent-runner; go 1.22
  main.go             // entrypoint: read env, exec command, stream callbacks
  client.go           // control-plane HTTP client (logs/patch/control/artifacts)
  client_test.go
  Dockerfile          // multi-stage: build static binary, copy claude/codex CLIs + runtime
  README.md
```

**`main.go` responsibilities (exec via argv — never `sh -c` with interpolated user input):**
1. Read env: `CONDUIT_RUN_ID`, `CONDUIT_RUNNER_TOKEN`, `CONDUIT_CONTROL_PLANE_URL`,
   `CONDUIT_COMMAND`, `CONDUIT_MODEL`, `CONDUIT_OPENROUTER_KEY`, `CONDUIT_AGENT_ID`. Fail fast (non-zero
   exit + a best-effort `PATCH status=failed`) if any required one is missing.
2. `exec.CommandContext(ctx, argv[0], argv[1:]...)` where argv is parsed from `CONDUIT_COMMAND`
   (use a shell-words split, e.g. a vendored `shellwords`, OR require the command be passed as a JSON
   array env `CONDUIT_COMMAND_ARGV` to avoid any shell at all — **prefer the JSON array** for
   injection-safety). Wire `OPENROUTER_API_KEY`/`ANTHROPIC_*` into the child env as the agent expects.
3. Stream stdout+stderr: wrap each pipe in a scanner; batch lines (e.g. flush every 250ms or 50 lines)
   to `POST {CONTROL_PLANE_URL}/runs/{RUN_ID}/logs` with `Authorization: Bearer {RUNNER_TOKEN}` and body
   `{"lines":[{"stream":"stdout","text":"…"}]}`. Honor the `nextSince` response (informational).
4. Poll `GET {CONTROL_PLANE_URL}/runs/{RUN_ID}/control` every ~3s; if `{"cancelRequested":true}`,
   cancel the context (SIGTERM the child, then SIGKILL after a grace period), and `PATCH status=cancelled`.
5. On child exit: `PATCH {CONTROL_PLANE_URL}/runs/{RUN_ID}` with
   `{"status":"succeeded|failed","exitCode":N,"completedAt":"<RFC3339>"}` (succeeded iff exit 0 and not cancelled).
6. Artifact upload (depends on CE4): for any declared output dir, upload bytes to GCS, then
   `POST /runs/{id}/artifacts` to register metadata (the runner uses its runner token; **note**: the
   artifact create handler currently requires the *app* entitlement — see CE4 for the runner-auth path).

**`Dockerfile` (sketch):**
```dockerfile
# build stage
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./ && go mod download
COPY . . && CGO_ENABLED=0 go build -o /agent-runner .

# runtime stage — include the agent CLIs the command needs (claude/codex/node, git, gh)
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates curl \
    && npm i -g @anthropic-ai/claude-code   # or whatever the 'claude' command resolves to
COPY --from=build /agent-runner /usr/local/bin/agent-runner
ENTRYPOINT ["/usr/local/bin/agent-runner"]
```

**Local test (no cloud):** run the control plane locally (`go run .` with a temp `DATA_DIR`),
manually insert a run + mint a token (or add a debug endpoint), then:
```bash
CONDUIT_RUN_ID=run_x CONDUIT_RUNNER_TOKEN=rt_x \
CONDUIT_CONTROL_PLANE_URL=http://localhost:8080 \
CONDUIT_COMMAND_ARGV='["bash","-lc","echo hello && sleep 1 && echo bye"]' \
go run ./daemon/agent-runner
```
Then `GET /runs/run_x/logs` should show `hello`/`bye` and the run should be `succeeded`.

**Definition of done (CE2):** the runner, pointed at the local control plane, streams logs and flips
status. `client_test.go` covers batching, the control-poll cancel path, and the terminal PATCH.

---

### CE3 — GCP Cloud Run provider (real Jobs API) *(build-verified locally; e2e owner-run)*

Replace the stub. **Decision: provision the Cloud Run *Job* once per agent (already modeled by
`GCPJobOrchestration` / `provisionGCPCloudRunAgent`), and *execute* it per run with env overrides.**

**`go.mod` (control plane):** add `google.golang.org/api/run/v2` (Cloud Run Admin v2 — supports Jobs +
executions) and `golang.org/x/oauth2/google` for ADC. Use Application Default Credentials
(`GOOGLE_APPLICATION_CREDENTIALS` or workload identity).

**`gcp_cloud_run.go` changes:**
- `cloudRunDefaultImage()` (:186): default must become the **runner image** in Artifact Registry, e.g.
  `os.Getenv("GCP_CLOUD_RUN_IMAGE")` with NO `gcr.io/cloudrun/hello` fallback in production (keep a
  clearly-labelled dev fallback only behind a debug flag).
- Implement `submitCloudRunJobIfConfigured(spec)` → actually **create-or-update the Job** via
  `run.Projects.Locations.Jobs.Create/Patch` with the container image = runner image and the static
  env (`CONDUIT_AGENT_ID`, `CONDUIT_CONTROL_PLANE_URL`, `CONDUIT_MODEL`). Idempotent on job name.
- New `gcpCloudRunProvider{}` implementing `RuntimeProvider`:
  - `Launch(agent, run, env)` → `run.Projects.Locations.Jobs.Run` with a **per-execution
    `overrides.containerOverrides[].env`** injecting `CONDUIT_RUN_ID`, `CONDUIT_RUNNER_TOKEN`,
    `CONDUIT_COMMAND_ARGV`. Return the execution name as the handle.
  - `Cancel(handle)` → `run.Projects.Locations.Jobs.Executions.Cancel`.
- Region/project from `gcpRegion()` / `gcpProject()` (already present, gcp_cloud_run.go:44-53). Map the
  app's `CloudRegion.slug` (e.g. `us-east`) → GCP region (`us-east1`) with a small table; default
  `us-central1`.

**Acceptance (owner-run, §7):** create a `gcp_cloud_run` agent, start a run, watch the Cloud Run Job
execution appear in GCP console, logs stream into the app, status flips, exit code shown.

---

### CE4 — GCS artifact bytes (upload + signed-URL download) *(build-verified locally; e2e owner-run)*

Today `artifacts_gcs.go` only string-builds a `gs://` URI. Add real bytes.

- **`go.mod`:** add `cloud.google.com/go/storage`.
- **Runner upload (in `agent-runner`):** for each output file, `storage.Writer` to
  `gs://$GCS_ARTIFACTS_BUCKET/runs/{runID}/{name}`; then register metadata.
- **Runner→control-plane artifact registration auth:** `handleCreateArtifact` (artifacts.go:66)
  currently requires `resolveEntitlementFromBearer` (app token). Add a **runner-token branch**: accept
  either an app entitlement OR a valid runner token scoped to `{id}` (mirror `handleAppendRunLogs`).
  Factor a helper `authorizeRunWrite(r, runID) (ent *subscriptionEntitlement, viaRunner bool, ok bool)`.
  When `viaRunner`, set `CustomerID/OrgID` from the run record, not from a (absent) entitlement.
- **App download:** add `GET /runs/{id}/artifacts/{artifactId}/download` (app-auth) that, when a
  `GCSURI` is set, returns a **short-lived V4 signed URL** (`storage.SignedURL`, ~10 min, `GET`).
  For ssh-host artifacts (no GCSURI), the app already downloads via SFTP — leave that path.
- **iOS:** add `func artifactDownloadURL(runID:artifactID:) async throws -> URL` to
  `HostedAgentRuntime.swift`, and a download/share affordance in `AgentRunDetailView.swift` artifacts
  section for cloud artifacts (ssh-host keeps the existing SFTP "Attach from host" path).

**Security:** signed URLs must be short-TTL and per-object; never expose the bucket publicly; never
log signed URLs or runner tokens.

---

### CE5 — AWS Lightsail provider *(build-verified locally; e2e owner-run)*

Replace `provisionLightsailAgent` (runtime.go:42) and add a `lightsailProvider{}`.

- **`go.mod`:** `github.com/aws/aws-sdk-go-v2/config` + `…/service/lightsail`.
- Model: **one Lightsail instance per run** (simplest, clean teardown) launched with a **user-data
  script** that `docker run`s the runner image with the env injected (or installs the runner binary
  and runs it). Tag the instance `conduit-run-id={runID}`.
- `Launch` → `CreateInstances` with `userData` = a templated bootstrap that exports the `CONDUIT_*`
  env and starts the runner; return the instance name as handle.
- `Cancel` → `DeleteInstance(handle)`. Also have the runner self-terminate (signal the control plane,
  exit) so instances don't leak; add a backstop sweep (a periodic goroutine that deletes instances for
  terminal runs) — note this in the ledger.
- Credentials via standard AWS env (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION`) or role.

**Cost guardrail:** Lightsail instances bill hourly. The runner MUST PATCH terminal status and the
provider MUST delete the instance on completion/cancel. Document the sweep interval.

---

### CE6 — Fly.io provider *(build-verified locally; e2e owner-run)*

Add `case "fly"` to `provisionRuntimeIfNeeded` (runtime.go:37) and a `flyProvider{}`.

- Use the **Fly Machines REST API** (`https://api.machines.dev/v1/apps/{app}/machines`) with
  `FLY_API_TOKEN`; no SDK needed (plain `net/http`). `fly.toml` already exists in the repo — reuse the
  app name / org.
- `Launch` → `POST …/machines` with `config.image` = runner image, `config.env` = the `CONDUIT_*` map,
  `config.auto_destroy=true`, `restart.policy="no"`. Return machine id as handle.
- `Cancel` → `POST …/machines/{id}/stop` then `DELETE …/machines/{id}`.

---

### CE7 — iOS polish & cloud-path verification *(testable now + after CE3)*

The iOS side is mostly done; this milestone is **verify + small additions**:

1. **Confirm the cloud poll loop runs.** `AgentStore.loadNewRunLogs` (AgentStore.swift:367) exists, but
   verify there is a driver that calls it on an interval while a cloud `selectedRun` is non-terminal
   (a `Task` in `AgentRunDetailView.task{}` that loops `await store.loadNewRunLogs(runID:)` every ~2s
   until `run.status.isTerminal`, also calling `await store.refreshRun(runID)` to flip status). If it
   doesn't exist, add it. Add a "● live" indicator while polling.
2. **Cloud cancel** already posts (`cancelRun` AgentStore.swift:507) — verify against a real run in CE3.
3. **Artifact download (CE4)** — add the cloud download/share affordance.
4. Run the **app-target build** (`build_sim`) and a sim pass on the Agents surface
   (`SIMCTL_CHILD_*` / `-conduitDebugCloudEntitlement YES`) to confirm no regressions.

---

## 4. Exact file change map

**Backend — new:**
- `daemon/push-backend/dispatch.go` (CE1) — provider interface, `dispatchRun`, `failRun`, helpers.
- `daemon/push-backend/dispatch_test.go` + `dispatch_fake_test.go` (CE1) — fake-provider spine test.
- `daemon/push-backend/gcp_run_provider.go` (CE3) — `gcpCloudRunProvider` (or extend gcp_cloud_run.go).
- `daemon/push-backend/lightsail_provider.go` (CE5).
- `daemon/push-backend/fly_provider.go` (CE6).
- `daemon/agent-runner/**` (CE2) — new module: `main.go`, `client.go`, `Dockerfile`, tests.

**Backend — modified:**
- `agents.go:255-260` — `go dispatchRun(...)` after run persist (CE1).
- `schedules.go` (~:339) — `go dispatchRun(...)` after scheduled run persist (CE1).
- `gcp_cloud_run.go:175,186` — real Jobs API + runner image (CE3).
- `runtime.go:37,42` — Fly case (CE6) + real Lightsail (CE5).
- `artifacts.go:66` — runner-token write branch (CE4) + new download route/handler (CE4).
- `artifacts_gcs.go` — real GCS upload/signed-URL (CE4).
- `go.mod` — `google.golang.org/api`, `cloud.google.com/go/storage`, `aws-sdk-go-v2/{config,service/lightsail}`, `golang.org/x/oauth2` (CE3-6).
- `main.go` — register any new routes/init (e.g. download route, dispatch ledger init).

**iOS — modified (small):**
- `AgentKit/HostedAgentRuntime.swift` — `artifactDownloadURL(runID:artifactID:)` (CE4).
- `AppFeature/AgentRunDetailView.swift` — live-poll driver + "● live" + cloud artifact download (CE7).
- (Verify only) `AppFeature/AgentStore.swift` — poll loop already has `loadNewRunLogs`/`logLines`/`cancelRun`.

---

## 5. Testing strategy

**Backend (runs in CI, no cloud):**
- `go build ./... && go vet ./... && go test ./...` for both modules.
- Extend `phase2_phase3_test.go`-style integration tests:
  - run-create → fake-provider → logs visible → status `succeeded` (CE1).
  - runner-token scoping: wrong/absent token → 401 on `/logs`, `/control`, `PATCH`, runner-auth artifact create.
  - cancel: `POST /cancel` sets flag; `GET /control` reflects it.
  - artifact runner-auth branch + signed-URL handler returns a URL only with a configured bucket (mock).
- `agent-runner/client_test.go`: batching, cancel-poll, terminal PATCH against an `httptest.Server`.

**iOS:**
- `cd Packages/ConduitKit && swift build` (fast inner loop) — but it compiles for macOS and strips
  `#if os(iOS)`. **Always finish with the app-target build:**
- XcodeBuildMCP `build_sim` (Conduit / iPhone 17 Pro) — strict-concurrency gate for AppFeature/AgentStore.
- `swift test` for the mapping/DTO suites (extend `HostedAgentM6Tests` etc. if you add DTO fields).

**Local end-to-end (no cloud) — the big confidence test:**
1. `cd daemon/push-backend && DATA_DIR=/tmp/cp go run .`
2. Seed an entitlement (see `entitlements_test.go` / existing seed path) so the app token resolves.
3. Build the runner: `docker build -t agent-runner:dev daemon/agent-runner` (or run as a plain process).
4. Point dispatch at a **local "process" provider** (a debug provider that just `exec`s the runner
   binary locally with the env, instead of a cloud call) — gated behind `CONDUIT_LOCAL_RUNNER=1`. This
   exercises the *entire* real pipeline (dispatch → runner → logs/status/artifacts) with zero cloud.
5. Drive from the app (sim) or `curl POST /runs` and watch `GET /runs/{id}/logs` stream.

> Strongly recommend building the **`CONDUIT_LOCAL_RUNNER=1` process provider** as part of CE1/CE2 —
> it is the highest-leverage test harness and makes CE3/5/6 a thin, low-risk swap.

---

## 6. Security requirements (do not regress)

- **Runner token:** random, per-run, scoped to one run; never returned to the app; never the user
  `clientToken`. Every runner-authenticated handler must check `resolveRunFromRunnerToken(r) == pathID`.
  Consider expiring tokens when the run reaches terminal status (delete from `runTokensStore`).
- **Command execution in the runner:** prefer `CONDUIT_COMMAND_ARGV` (JSON array) and `exec.Command`
  with explicit argv — **no `sh -c` string interpolation** of user/agent-controlled content.
- **OpenRouter / model key:** the control plane already provisions a hashed sub-key per agent
  (`ensureOpenRouterSubKey`, agents.go:123). Decide the injection path: either (a) the runner fetches a
  scoped key via a runner-token-auth endpoint, or (b) the control plane injects a short-lived key into
  the launch env. **Do not bake long-lived provider keys into the image.** Document the choice.
- **Signed URLs:** short TTL (≤15 min), per-object, `GET` only; bucket private; never logged.
- **Control-plane URL injection:** `CONTROL_PLANE_PUBLIC_URL` is operator-set (not user-controlled), so
  no SSRF surface from the app. Keep it that way — never let an agent's config override the callback URL.
- **TOFU on ssh-host paths stays intact** — this plan does not touch the ssh-host runtime; don't.
- **Quota:** ensure cloud run creation still flows through `enforceQuota(ent, quotaCheckRun)` (it does,
  agents.go:209) so cloud execution can't bypass plan limits.
- Run `semgrep` (the repo's PostToolUse hook) clean on new Go; address findings.

---

## 7. Owner-run production deploy runbook (gated on cloud creds)

These steps require accounts/creds the implementing agent won't have. Document them; the owner runs them.

1. **Build & push the runner image** to Artifact Registry:
   `gcloud builds submit daemon/agent-runner --tag $REGION-docker.pkg.dev/$GCP_PROJECT/conduit/agent-runner:vX`
   (and an equivalent for any AWS/Fly registry if not reusing the same image).
2. **Backend env** (Cloud Run / Fly / wherever push-backend deploys):
   `CONTROL_PLANE_PUBLIC_URL=https://api.conduit.dev`, `GCP_PROJECT`, `GCP_REGION`,
   `GCP_CLOUD_RUN_IMAGE=<runner image>`, `GCS_ARTIFACTS_BUCKET`, `GOOGLE_APPLICATION_CREDENTIALS`
   (or workload identity), `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION`, `FLY_API_TOKEN`,
   plus the existing APNs + Stripe + OpenRouter envs.
3. **IAM:** service account needs `run.jobs.run`/`run.executions.*`, `storage.objects.create/get` +
   signing (`iam.serviceAccounts.signBlob` for V4 signed URLs), Lightsail create/delete, Fly app scope.
4. **Deploy the backend** (existing `Dockerfile` for push-backend).
5. **Smoke test per provider:** create a `gcp_cloud_run` agent → start run → confirm execution in GCP
   console, logs stream in the app, status flips, exit code shown, artifact uploads + downloads via
   signed URL. Repeat for `lightsail` and `fly`. Confirm cancel terminates within the poll interval and
   no instances/machines leak.
6. **Cost/cleanup audit:** verify terminal runs delete Lightsail instances & Fly machines; confirm the
   backstop sweep works; set budget alerts.

---

## 8. Definition of done (production-ready)

- [ ] Creating a cloud agent + starting a run executes a real container/VM on the selected provider.
- [ ] Logs stream live into the app; status transitions `pending → running → succeeded|failed`; exit
      code shown. Cancel works within one poll interval and tears down the execution.
- [ ] Artifacts upload to GCS and download in-app via short-lived signed URLs.
- [ ] All three providers (GCP Cloud Run, Lightsail, Fly) pass the per-provider smoke test.
- [ ] Runner-token auth enforced on every callback; no token/secret leakage in logs; signed URLs short-TTL.
- [ ] `go build/vet/test ./...` green (both modules); `swift build` + `build_sim` green; `swift test` green.
- [ ] ssh-host runtime untouched and still working (TOFU intact); quota still enforced for cloud runs.
- [ ] No orphaned cloud resources after terminal runs (verified by the cleanup audit).
- [ ] `CLAUDE.md` / `docs/` updated to describe the cloud execution path and the new envs.

---

## 9. Suggested sequencing for the implementing agent

1. **CE1** dispatch spine + fake provider + **`CONDUIT_LOCAL_RUNNER` process provider** (highest leverage).
2. **CE2** agent-runner binary + Dockerfile (test against the local control plane).
3. **CE4** GCS bytes + runner-auth artifact branch + app download (independent of which cloud).
4. **CE3** GCP Cloud Run (first real provider) — full owner-run smoke.
5. **CE5 / CE6** Lightsail + Fly (parallelizable; same `RuntimeProvider` contract).
6. **CE7** iOS poll-loop verify + cloud artifact download + sim pass.
7. Owner runs the §7 deploy runbook; this session's author verifies the diffs and the local-runner e2e.

> When done, ping the reviewer (the session that wrote this) to verify: they will re-audit
> `handleCreateRun` dispatch wiring, runner-token scoping, the fake/local-runner e2e test, and run
> `build_sim` + `go test ./...` themselves before sign-off.
