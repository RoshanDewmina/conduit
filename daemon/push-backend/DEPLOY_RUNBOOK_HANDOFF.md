# Push-backend redeploy runbook (P0-A handoff)

> **Status of this document:** prepared, NOT executed. No deploy command was run.
> No secret values are recorded anywhere below — placeholders only.
> Scope: `daemon/push-backend` only. Does not touch `project.yml`, `daemon/conduitd`, or `Packages/`.

---

## 0. Gate result (read this first)

```
cd daemon/push-backend && go test ./...   →  ok   conduit/push-backend   0.544s
cd daemon/push-backend && go build ./...  →  (no output — success)
```

Both green. The package compiles and all tests pass as of this branch
(`codex/ios27-shell-workspace`). No blocker from the code itself.

---

## 1. Live diagnosis — the relay is NOT actually unreachable right now

Before writing the rest of this runbook I re-checked the URL from the problem statement.
**As of this session, both of the following return HTTP 200:**

```
curl -sSI https://35.201.3.231.sslip.io/health                       → HTTP/2 200, via: 1.1 Caddy
curl -sSI https://conduit-push-y4wpy6zeva-ts.a.run.app/health          → HTTP/2 200, server: Google Frontend
```

These are **two different backends**, confirmed by response headers and `OPTIONS` preflight:

| | `35.201.3.231.sslip.io` (current `CONDUIT_PUSH_BACKEND_URL`) | `conduit-push-y4wpy6zeva-ts.a.run.app` |
|---|---|---|
| Fronted by | Caddy on a GCP Compute VM (`via: 1.1 Caddy`, Let's Encrypt cert CN=`35.201.3.231.sslip.io`) | Cloud Run direct URL (`server: Google Frontend`) |
| `Access-Control-Allow-Headers` | `Content-Type, Stripe-Signature, X-Customer-Id, X-App-Account-Token` (**no `Authorization`**) | `Authorization, Content-Type, Stripe-Signature, X-Customer-Id, X-App-Account-Token` |
| Build | **STALE** — predates commit `5bd81663` (`feat(account): standard accounts, JWT auth, QR device binding + management`), which added the `Authorization` CORS header in `main.go`'s `corsMiddleware` | **CURRENT** — matches `main.go` on this branch |
| GCP project | Not the two projects this account can introspect (`roshan-agent-f1c2466d`, `conduit-runner-0603190634`) — likely a third project, or a VM provisioned by hand per `DEPLOY.md` §2 | `roshan-agent-f1c2466d` ("Hermes Google Access"), Cloud Run service `conduit-push`, region `australia-southeast1`, latest revision `conduit-push-00005-zwm` (Ready=True, 100% traffic) |

**Read-only `gcloud` inspection of `roshan-agent-f1c2466d` / `conduit-push` (region `australia-southeast1`)
found the running revision's env is incomplete:**

```
APNS_KEY_PATH   = /secrets/apns.p8        (set)
APNS_BUNDLE_ID  = dev.conduit.mobile      (set)
APPROVAL_RELAY_SECRET = <secret ref: APPROVAL_RELAY_SECRET:latest>   (set)
APNS_KEY_ID     = NOT SET
APNS_TEAM_ID    = NOT SET
```

`APNS_KEY_ID`/`APNS_TEAM_ID` missing means **any** real push attempt from this Cloud Run revision
would `log.Fatal` the request goroutine — `mustEnv("APNS_KEY_ID")` panics-via-Fatal if unset (see
`main.go:300-303` and `liveactivity.go:217-220`). `/health` cannot reveal this because APNs env is
read lazily, only at first push attempt (this matches the existing caveat already recorded in
`docs/push-backend-deploy-env.md`).

A third, unrelated Cloud Run service `conduit-push-smoke` also exists in project
`conduit-runner-0603190634` (different URL, likely a smoke-test deployment — not in scope here).

**Conclusion:** the *symptom* "relay unreachable" may be transient/already self-resolved, or the
owner was hitting it at a moment of an outage/restart on the VM. But the *deeper* problem is real:
**the publicly-pinned host (`35.201.3.231.sslip.io`) is running stale code without the new
JWT-auth/CORS changes, while the up-to-date build sits on Cloud Run under a different, non-public
URL with an incomplete APNs env.** Either path below fixes this; recommendation is below.

---

## 2. Auth.go findings — SUPABASE_JWT_SECRET / SUPABASE_JWT_ISSUER (HS256)

File: `daemon/push-backend/auth.go`.

| Var | Required? | Default | Behavior if unset |
|---|---|---|---|
| `SUPABASE_JWT_SECRET` | Required to enable standard-account auth | none | **Fails closed for that feature, not the whole server.** `supabaseJWTConfigured()` returns `false`; `resolveAuthenticatedUser` returns the error `"standard account authentication is not configured"` before even looking at the request; `requireAuthenticatedUser` then writes `401 unauthorized`. The server still starts and serves all other routes (relay, APNs registration, billing, etc.) normally — this gate is scoped to standard-account endpoints only, not a global kill switch. |
| `SUPABASE_JWT_ISSUER` | Optional | none (issuer check skipped) | If unset, the JWT parser does **not** add `jwt.WithIssuer(...)` to its option list — issuer claim is simply not verified. If set, tokens whose `iss` claim doesn't match are rejected as `"invalid access token"`. |

Verification logic: HS256 only (`jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()})`,
and the keyfunc itself also asserts `*jwt.SigningMethodHMAC` — belt and suspenders against alg
confusion). Requires `aud: "authenticated"` (`jwt.WithAudience`), requires `exp` to be present
(`jwt.WithExpirationRequired`), 30s leeway. Subject (`sub`) claim must be non-empty — that becomes
`authenticatedUser.ID`. `email` claim is optional, copied through as-is.

**Net effect for this deploy:** if you don't set `SUPABASE_JWT_SECRET` on the redeployed instance,
the new standard-account/device-binding endpoints (`device_bindings.go`,
`account_device_pairing.go` callers on the daemon side) will 401 every request, but **the relay,
APNs push, and billing paths are unaffected** — they don't call `resolveAuthenticatedUser`. This is
NOT a hard blocker for the P0 "get the relay back" goal; it only blocks the newer standard-account
feature surface introduced in commit `5bd81663`.

---

## 3. Complete environment variable matrix

Built from `grep -rn 'os.Getenv\|mustEnv(' --include='*.go' .` across every non-test file in
`daemon/push-backend`.

### 3a. Core HTTP / relay control-plane

| Var | Required? | Default | Read by | What breaks if missing |
|---|---|---|---|---|
| `PORT` | No | `8080` | `main.go:124` | Server listens elsewhere only if you set it; harmless. |
| `CORS_ALLOW_ORIGIN` | No | `*` | `main.go:134` | Wide-open CORS if unset — fine for this relay's threat model, tighten for prod if desired. |
| `APPROVAL_RELAY_SECRET` | **Required in production** | none (open) | `relay_security.go:67`, checked at startup by `warnIfRelayUnauthenticated()` | **Fails closed in prod.** If unset AND the process detects it's a production deployment (`FLY_APP_NAME`, `K_SERVICE`, `K_REVISION`, `K_CONFIGURATION` env present, or `CONDUIT_ENV`/`APP_ENV` = `prod`/`production`) → `log.Fatal()`, **process refuses to start.** Outside those signals (e.g. bare `go run .` locally) it just logs a loud warning and the control-plane endpoints (`/register`, `/approval`, `/run-complete`) run **unauthenticated**. Cloud Run sets `K_SERVICE`/`K_REVISION`/`K_CONFIGURATION` automatically, so this is enforced there. |
| `CONDUIT_ENV` | No | none | `relay_security.go:191` (`relayProductionDeploymentFromEnv`) | Only matters as one of several signals for the prod-detection above; not otherwise consumed. |

### 3b. Auth (new — commit `5bd81663`)

| Var | Required? | Default | Read by | What breaks if missing |
|---|---|---|---|---|
| `SUPABASE_JWT_SECRET` | Required only for standard-account endpoints | none | `auth.go:28,32` | See §2 — standard-account auth 401s; rest of server unaffected. |
| `SUPABASE_JWT_ISSUER` | Optional | none (skip issuer check) | `auth.go:52` | Issuer claim simply not verified. |

(`CONDUIT_SUPABASE_URL` is **not** a push-backend server env var — it's an **iOS app** build
setting in `project.yml`, read by `AccountConfiguration.fromBundle` on-device. Not consumed
anywhere in this Go package. Do not confuse it with the two vars above.)

### 3c. APNs push delivery

| Var | Required? | Default | Read by | What breaks if missing |
|---|---|---|---|---|
| `APNS_KEY_ID` | Required for any push | none | `main.go:300,356`, `liveactivity.go:217` via `mustEnv` | `mustEnv` calls `log.Fatalf` → **crashes the whole process**, not just the request, the moment any code path tries to send a push (approval alert, run-complete alert, or Live Activity update). Health checks won't catch this until a real push fires. |
| `APNS_TEAM_ID` | Required for any push | none | same call sites | Same — `log.Fatalf` on first push attempt. |
| `APNS_KEY_PATH` | Required for any push | none | same call sites, then `loadP8Key()` | Same — `log.Fatalf` on first push attempt. If the path is set but wrong/missing file, `loadP8Key` returns an error which is wrapped and returned as a 500 to the relay caller (does NOT crash the process — only `mustEnv` does that). |
| `APNS_BUNDLE_ID` | Required for any push | none | same call sites | Same `log.Fatalf` pattern. `.env.example` documents a default of `dev.conduit.mobile`, but there is no in-code default — it's still `mustEnv`. |

**This is the sharpest footgun in the whole service:** because `mustEnv` calls `log.Fatalf` instead
of returning an error, a missing APNs var doesn't just fail one request — **it kills the container**
on the first approval/run-complete push, and Cloud Run / Fly will then restart it into a crash loop
once traffic actually exercises the push path. The current Cloud Run revision is missing
`APNS_KEY_ID`/`APNS_TEAM_ID` (confirmed by read-only `gcloud run services describe`), so this WILL
crash on first real push if redirected without fixing the env first.

### 3d. Server URLs (Stripe checkout / cloud-runner callbacks)

| Var | Required? | Default | Read by | What breaks if missing |
|---|---|---|---|---|
| `PUBLIC_BASE_URL` | Recommended | `https://conduit.dev` (hardcoded fallback) | `billing.go:496` (`publicBaseURL()`), `dispatch.go:131,133` (fallback) | Stripe checkout success/cancel redirect URLs point at the wrong host (`conduit.dev`) instead of this backend; cloud-runner callback URL (`controlPlaneBaseURL()`) also falls back to it. |
| `CONTROL_PLANE_PUBLIC_URL` | Recommended for cloud dispatch | falls back to `PUBLIC_BASE_URL` | `dispatch.go:131` | This is the URL a **Fly Machine or Cloud Run Job runner** calls back into to report run status. If both this and `PUBLIC_BASE_URL` are unset, `controlPlaneBaseURL()` returns `""` and cloud dispatch (`fly_provider.go`/`gcp_cloud_run.go`/`lightsail_provider.go` callers) breaks — but this only matters for the **hosted-agent-runner** feature, not the relay/APNs path that's the P0 concern. `dispatch.go`'s own comment notes the historical mismatch bug this fallback was added to fix. |
| `WEBSITE_BASE_URL` | No | `https://conduit.dev` | `billing.go:503` | Stripe checkout cancel-redirect target only. Cosmetic if wrong. |

### 3e. Persistence / data dir

| Var | Required? | Default | Read by | What breaks if missing |
|---|---|---|---|---|
| `DATA_DIR` | No | OS temp dir | `store.go:15` | All JSON-file stores (entitlements, control-plane, usage, credits, artifacts, schedules, GCP orchestration, orgs) fall back to `os.TempDir()`. **On Cloud Run this means state is lost on every cold start/revision** since temp is not persistent — fine for the relay/APNs-only use case, a real problem for billing/entitlements/credits durability. Each store also has its own override var (`ENTITLEMENTS_FILE`, `CONTROL_PLANE_FILE`, `USAGE_FILE`, `CREDITS_FILE`, `ARTIFACTS_FILE`, `SCHEDULES_FILE`, `GCP_ORCHESTRATION_FILE`, `ORGS_FILE` — all optional, all default to `DATA_DIR/<name>.json` or temp). |
| `ENTITLEMENTS_REDIS_URL` | No | none (JSON file) | `entitlements.go:65` | If unset, entitlements persist to the JSON file above instead of Redis. Not required for the relay/APNs path. |

### 3f. Billing / Stripe (not required for the relay/APNs P0, but present)

`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_ANNUAL` — all
optional reads via plain `os.Getenv` (no `mustEnv`), each guarding only its own billing code path
(checkout creation, webhook signature verification). Missing values degrade billing features, not
the relay.

### 3g. OpenRouter managed AI (not required for relay/APNs)

`OPENROUTER_PROVISIONING_KEY`, `OPENROUTER_BASE_URL` (default `https://openrouter.ai`),
`OPENROUTER_LIMIT_MONTHLY`, `OPENROUTER_LIMIT_ANNUAL`, `OPENROUTER_LIMIT_RESET`,
`OPENROUTER_SHARED_KEY` — all optional, gate the OpenRouter-managed-keys feature only.

### 3h. Quotas / reaper / schedules (not required for relay/APNs)

| Var | Default |
|---|---|
| `QUOTA_MAX_AGENTS` | `20` |
| `QUOTA_MAX_CONCURRENT_RUNS` | `5` |
| `QUOTA_DAILY_USAGE_USD` | `100` |
| `RUN_REAPER_INTERVAL_SEC` | `120` (2 min) |
| `RUN_MAX_DURATION_SEC` | `3600` (60 min) |
| `CONDUIT_DISABLE_REAPER` | unset (reaper runs) — set to `1` to disable |
| `SCHEDULE_TICKER_ENABLED` | `true` — set to `false` to disable |

### 3i. Hosted-agent cloud dispatch providers (not required for relay/APNs)

| Var | Used by | Notes |
|---|---|---|
| `FLY_APP_NAME`, `FLY_API_TOKEN` | `fly_provider.go` | For launching agent-run **Fly Machines** — unrelated to deploying push-backend itself to Fly (that's `fly.toml`, §5 path B below). Also `FLY_APP_NAME` doubles as one of the production-detection signals in `relay_security.go`. |
| `GCP_PROJECT`, `GCP_REGION` (default `us-central1`), `GCP_CLOUD_RUN_IMAGE` | `gcp_cloud_run.go`, `gcp_run_provider.go` | For launching agent-run **Cloud Run Jobs** — unrelated to deploying push-backend itself. |
| `AWS_REGION` | `lightsail_provider.go` | For the Lightsail agent-runner provider. |
| `GCS_ARTIFACTS_BUCKET` | `artifacts_gcs.go` | Optional artifact storage URI prefix. |
| `GITHUB_WEBHOOK_SECRET` | `webhooks.go` | GitHub webhook signature verification. |

---

## 4. Deploy tooling inventory

| File | Purpose |
|---|---|
| `Dockerfile` | Two-stage build: `golang:1.25-alpine` → `CGO_ENABLED=0 GOOS=linux go build` → `alpine:3.19` runtime, non-root `conduit` user, `EXPOSE 8080`. Used by both Cloud Run `--source` deploys and `docker compose`. |
| `docker-compose.yml` | Local/self-host: builds from `Dockerfile`, maps `8080:8080`, reads `.env`, healthcheck against `/health`. |
| `fly.toml` | `app = "conduit-push"`, `primary_region = "iad"`, builds via the same `Dockerfile`, `internal_port = 8080`, `auto_stop/start_machines`, `min_machines_running = 0`. **This is for deploying push-backend itself to Fly — distinct from `fly_provider.go`, which uses the Fly Machines API to launch per-run agent containers.** |
| `fly_provider.go`, `gcp_cloud_run.go`, `gcp_run_provider.go`, `lightsail_provider.go` | All **agent-run dispatch providers** (`dispatch.go`'s `providerFor`) — they launch a container per hosted agent *run*, not the push-backend service itself. Not part of how you redeploy push-backend. |
| `DEPLOY.md` | Documents the **blind-relay-only** deploy story: Tailscale Funnel (testing) or a GCP Compute VM + systemd + Caddy/nginx/LB for TLS (production). This is almost certainly what's actually running at `35.201.3.231.sslip.io` today (see §1 — `via: 1.1 Caddy`). |
| `SELF_HOST.md` | Generic Docker self-host guide (any host), env var table, TLS options (Caddy sidecar / Tailscale Funnel / nginx), `DATA_DIR` persistence note. |
| `docs/push-backend-deploy-env.md` | **The canonical, owner-authored Cloud Run deploy doc** — documents the exact `gcloud run deploy conduit-push --source . --region australia-southeast1` flow plus `gcloud secrets create`/`gcloud run services update --set-secrets` for APNs. This matches what's actually deployed in `roshan-agent-f1c2466d` right now (service name, region, image path all match read-only `gcloud` inspection in §1). |

**Two distinct production deploy stories exist in this repo and neither one is what's live on
the public host today, fully:**
- The Cloud Run path (`docs/push-backend-deploy-env.md`) is live in `roshan-agent-f1c2466d` but its
  URL (`*.run.app`) is **not** the one baked into `project.yml`, and its env is missing
  `APNS_KEY_ID`/`APNS_TEAM_ID`.
- The Caddy-on-VM path (`DEPLOY.md` §2) appears to be what's actually answering
  `35.201.3.231.sslip.io`, but is running **stale code** (pre-`5bd81663`) and lives in a GCP project
  this account cannot currently introspect (Compute Engine API disabled / no access on the two
  visible projects).

---

## 5. Two concrete deploy paths

### Path A (RECOMMENDED) — redeploy to the SAME target, keep the URL

**Goal:** ship the current `codex/ios27-shell-workspace` build (with the new `auth.go` JWT code and
CORS header) to whatever is answering `35.201.3.231.sslip.io` today, with zero `project.yml` change
and zero iOS rebuild.

**Blocker before this can run:** confirm which infra actually owns that IP. Given the `via: 1.1
Caddy` header and Let's Encrypt cert matching `DEPLOY.md`'s VM+systemd+Caddy pattern, the most
likely target is a GCP Compute VM in a GCP project this `gcloud` session cannot currently see (the
two visible projects both have Compute Engine API disabled, and neither shows a forwarding
rule/static IP for `35.201.3.231`). The owner must either:
- switch `gcloud config set project <the-right-project>` and re-run the discovery below, or
- SSH directly to the known VM (if its instance name/zone is recorded somewhere outside this repo)
  and confirm `systemctl status conduit-relay` / `caddy` there.

**Once the right project/VM is identified, the redeploy is:**

```bash
# 0. Confirm which project/instance owns 35.201.3.231 (read-only — do this FIRST):
gcloud projects list
gcloud config set project <THE-RIGHT-PROJECT>
gcloud compute instances list --format='table(name,zone,EXTERNAL_IP)' | grep 35.201.3.231
# Identify <INSTANCE_NAME> and <ZONE> from the line that matches.

# 1. Build the new binary locally (matches DEPLOY.md §0):
cd daemon/push-backend
CGO_ENABLED=0 GOOS=linux go build -o push-backend .

# 2. Copy the new binary to the VM (replaces the running stale build):
gcloud compute scp ./push-backend <INSTANCE_NAME>:/tmp/push-backend --zone=<ZONE>

# 3. On the VM (via `gcloud compute ssh <INSTANCE_NAME> --zone=<ZONE>`), install + restart:
sudo systemctl stop conduit-relay
sudo mv /tmp/push-backend /usr/local/bin/push-backend
sudo chmod +x /usr/local/bin/push-backend
# Confirm /etc/conduit-relay.env already has APPROVAL_RELAY_SECRET (DO NOT print it):
sudo test -s /etc/conduit-relay.env && echo "env file present"
# Add the new auth vars (placeholders — owner fills in the real values, never echoed to a shell history file):
sudo tee -a /etc/conduit-relay.env >/dev/null <<'EOF'
SUPABASE_JWT_SECRET=$SUPABASE_JWT_SECRET
SUPABASE_JWT_ISSUER=$SUPABASE_JWT_ISSUER
EOF
sudo chmod 600 /etc/conduit-relay.env
sudo systemctl start conduit-relay
sudo systemctl status conduit-relay --no-pager

# 4. Confirm Caddy/nginx in front of it is untouched (TLS termination + the
#    35.201.3.231.sslip.io routing should already be configured — this redeploy
#    only swaps the binary + env, not the reverse proxy).
```

**Where the static IP / ingress lives:** per `DEPLOY.md` §2, the relay binary listens on plain HTTP
on `PORT` (default 8080) behind Caddy (or nginx/GCP HTTPS LB) terminating TLS on 443 at the VM's
external/static IP. `sslip.io` is wildcard DNS that resolves `<any-ip>.sslip.io` → `<any-ip>` with
no DNS records to manage — so `35.201.3.231.sslip.io` resolves directly to the VM's external IP
(confirmed: `dig +short 35.201.3.231.sslip.io` → `35.201.3.231`). No domain mapping, no load
balancer config to touch — just the VM's own external IP + Caddy's automatic Let's Encrypt cert for
that sslip.io hostname.

**If instead the live target turns out to be the Cloud Run service in `roshan-agent-f1c2466d`** (i.e.
if `35.201.3.231` actually fronts Cloud Run via a Serverless NEG + external HTTPS LB the owner set up
out-of-band), the redeploy is the already-documented flow in `docs/push-backend-deploy-env.md`:

```bash
cd daemon/push-backend
gcloud config set project roshan-agent-f1c2466d
gcloud run deploy conduit-push --source . --region australia-southeast1 \
  --allow-unauthenticated --min-instances 1 --port 8080

# Add the missing APNs vars + new auth vars (placeholders only):
gcloud run services update conduit-push --region australia-southeast1 \
  --update-secrets APNS_KEY_ID=APNS_KEY_ID:latest,APNS_TEAM_ID=APNS_TEAM_ID:latest \
  --set-secrets SUPABASE_JWT_SECRET=SUPABASE_JWT_SECRET:latest \
  --set-env-vars SUPABASE_JWT_ISSUER="$SUPABASE_JWT_ISSUER"
```

Note: `APNS_KEY_ID`/`APNS_TEAM_ID` secrets were referenced as already created in
`docs/push-backend-deploy-env.md`'s one-time setup, but the **running revision doesn't have them
wired as env/secrets** (confirmed read-only above) — re-run the `--update-secrets` step regardless
of which deploy path is chosen.

### Path B — deploy to Fly (`fly.toml`) — NEW URL, requires `project.yml` + iOS rebuild

```bash
cd daemon/push-backend

# One-time (if the Fly app doesn't exist yet):
fly launch --no-deploy --copy-config --name conduit-push

# Deploy:
fly deploy

# Set every required secret (placeholders only — never real values in shell history/logs):
fly secrets set APPROVAL_RELAY_SECRET="$APPROVAL_RELAY_SECRET"
fly secrets set APNS_KEY_ID="$APNS_KEY_ID"
fly secrets set APNS_TEAM_ID="$APNS_TEAM_ID"
fly secrets set APNS_BUNDLE_ID="$APNS_BUNDLE_ID"
fly secrets set SUPABASE_JWT_SECRET="$SUPABASE_JWT_SECRET"
fly secrets set SUPABASE_JWT_ISSUER="$SUPABASE_JWT_ISSUER"
fly secrets set PUBLIC_BASE_URL="https://conduit-push.fly.dev"
# Optional, only if billing/OpenRouter features are exercised on this deploy target:
fly secrets set STRIPE_SECRET_KEY="$STRIPE_SECRET_KEY"
fly secrets set STRIPE_WEBHOOK_SECRET="$STRIPE_WEBHOOK_SECRET"

# Mount the APNs .p8 — Fly has no native secret-file mount like Cloud Run's
# --update-secrets volume trick; the common pattern is to base64-encode the
# key into a secret and decode it to disk at boot, OR use a Fly Volume:
base64 -i ~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8 | fly secrets set APNS_KEY_P8_BASE64=-
# (then either add a small init step in the Dockerfile/entrypoint that decodes
#  APNS_KEY_P8_BASE64 to /secrets/apns.p8 before exec'ing push-backend, or attach
#  a Fly Volume and scp the .p8 onto it once — NOT yet wired into this repo's
#  Dockerfile; this is a gap if Path B is chosen and must be implemented first)
fly secrets set APNS_KEY_PATH="/secrets/apns.p8"
```

**Required follow-up if Path B is chosen** (NOT done here, per instructions):
1. Get the new Fly URL: `fly status` → `https://conduit-push.fly.dev` (or whatever hostname Fly
   assigns).
2. Update `project.yml` line 26: `CONDUIT_PUSH_BACKEND_URL: "https://conduit-push.fly.dev"`.
3. Rebuild and resubmit the iOS app (the value is baked into the app binary as a build setting —
   `ConduitApp.swift` reads it at runtime, but it's compiled in, not fetched dynamically).
4. Every previously-paired device/session's relay registration is irrelevant (new backend, no
   shared state) — re-pairing is required.

**Recommendation: Path A.** It keeps `CONDUIT_PUSH_BACKEND_URL` (and therefore `project.yml` and
every already-shipped/TestFlight iOS build) unchanged, requires no app rebuild, and the live host
is already proven reachable today — only the binary + a couple of new env vars need to move. Path B
trades a clean Fly-native deploy for a forced URL change, an iOS rebuild/resubmission, and an
unsolved APNs-key-mounting gap that doesn't exist on the current target.

---

## 6. APNs .p8 + secret-setting commands (placeholders only)

Confirmed against code: `APNS_KEY_ID=L8LVU9X82W`, `APNS_TEAM_ID=39HM2X8GS6`,
`APNS_BUNDLE_ID=dev.conduit.mobile` match `docs/push-backend-deploy-env.md` and
`.env.example`'s documented shape (10-char key ID, 10-char team ID, bundle ID literal). The `.p8`
source path `~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` is referenced in
`docs/push-backend-deploy-env.md` and `docs/LIVE_LOOP_RUNBOOK.md` Phase 5a — this runbook does not
read or print its contents.

**Cloud Run (Path A, GCP variant) — secret commands, placeholders only:**

```bash
printf '%s' "$APNS_KEY_ID" | gcloud secrets create APNS_KEY_ID --data-file=- --project=<PROJECT>
printf '%s' "$APNS_TEAM_ID" | gcloud secrets create APNS_TEAM_ID --data-file=- --project=<PROJECT>
printf '%s' "$APPROVAL_RELAY_SECRET" | gcloud secrets create APPROVAL_RELAY_SECRET --data-file=- --project=<PROJECT>
printf '%s' "$SUPABASE_JWT_SECRET" | gcloud secrets create SUPABASE_JWT_SECRET --data-file=- --project=<PROJECT>
gcloud secrets create APNS_KEY --data-file "/absolute/path/AuthKey_L8LVU9X82W.p8" --project=<PROJECT>

gcloud run services update conduit-push --region <REGION> --project=<PROJECT> \
  --set-secrets APPROVAL_RELAY_SECRET=APPROVAL_RELAY_SECRET:latest,APNS_KEY_ID=APNS_KEY_ID:latest,APNS_TEAM_ID=APNS_TEAM_ID:latest,SUPABASE_JWT_SECRET=SUPABASE_JWT_SECRET:latest \
  --update-secrets /secrets/apns.p8=APNS_KEY:latest \
  --set-env-vars APNS_KEY_PATH=/secrets/apns.p8,APNS_BUNDLE_ID=dev.conduit.mobile,SUPABASE_JWT_ISSUER="$SUPABASE_JWT_ISSUER"
```

**VM + systemd (Path A, Caddy variant):** see §5 Path A step 3 — values go in
`/etc/conduit-relay.env` (mode `0600`), never in shell history or a committed file.

**Fly (Path B):** see §5 Path B's `fly secrets set` block above.

---

## 7. Post-deploy verification / acceptance checklist

Per `docs/push-backend-deploy-env.md` and `docs/LIVE_LOOP_RUNBOOK.md` Phase 5a/5b — **`/health`
returning 200 does NOT prove APNs or JWT auth are correctly configured**, because both are read
lazily (APNs at first push send; JWT secret only when a standard-account endpoint is hit). Full
acceptance:

- [ ] `curl -fsS https://<host>/health` → `200` (proves the process is up and serving — does NOT
      prove APNs/JWT env is correct)
- [ ] `curl -sSI -X OPTIONS https://<host>/health` → confirm `Access-Control-Allow-Headers` includes
      `Authorization` (proves the deployed binary is the CURRENT build, not the stale
      pre-`5bd81663` one currently live at `35.201.3.231.sslip.io`)
- [ ] Re-run the read-only env check: `gcloud run services describe <service> --region <region>
      --format=json` (or `systemctl show conduit-relay -p Environment` on the VM) and confirm
      `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`, `APNS_BUNDLE_ID`, `APPROVAL_RELAY_SECRET`,
      `SUPABASE_JWT_SECRET` are all present (names/refs only — do not print values)
- [ ] **Relay approval round-trip** per `docs/LIVE_LOOP_RUNBOOK.md` Phase 5b: pair a session to the
      redeployed relay (Settings → Connection, or
      `SIMCTL_CHILD_CONDUIT_RELAY_CODE=<6-digit code>` in DEBUG), disconnect SSH, trigger an `ask`
      from the host side, and confirm the approval card still reaches the Inbox and Approve still
      unblocks the agent over the relay path (🛑 CHECKPOINT 5b in that doc). This is the
      acceptance bar for "the relay redeploy actually works," not just `/health`.
- [ ] (Defer to a physical device per Phase 5c — out of scope for this redeploy prep) confirm a
      real APNs push fires and is delivered with the app backgrounded/closed, since that's the only
      way to catch the `mustEnv` crash-loop risk in §3c for real.

---

## 8. Summary for the owner

- **Biggest blocker:** identifying which GCP project/VM actually answers
  `35.201.3.231.sslip.io` (Compute Engine API is disabled on both `gcloud`-visible projects, and
  neither shows a matching static IP/forwarding rule) — without that, Path A cannot be executed by
  this session. Path A's Cloud Run variant is fully ready to go (project/service/region all
  confirmed) as a fallback if the VM can't be located, but switching the public host from
  VM→Cloud-Run would itself change the answering IP unless a domain mapping or LB is added in front
  — which reopens the "does this require a `project.yml` change" question. Confirm with the owner
  before executing either variant.
- **Second blocker:** providing the actual secret values (`APPROVAL_RELAY_SECRET`,
  `APNS_KEY_ID`/`TEAM_ID`/`.p8`, and the new `SUPABASE_JWT_SECRET`/`ISSUER`) — none of these were
  read, printed, or stored by this prep pass.
- **No code changes were made.** `go test`/`go build` already pass on this branch as-is.
