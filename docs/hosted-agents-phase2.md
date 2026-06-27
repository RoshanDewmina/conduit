# Hosted Agents — Phase 2 & 3 (push-backend)

Control-plane extensions in `daemon/push-backend` for prepaid credits, artifacts, scheduling, GCP Cloud Run Jobs runtime, quotas, team orgs, and Lightsail runtime acceptance.

## API routes

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/billing/credits` | Bearer | Prepaid balance + overage ledger for customer |
| POST | `/usage` | Bearer | Ingest usage; deduct credits; `402` if blocked |
| POST | `/runs/{id}/artifacts` | Bearer | Register artifact metadata + storage ref |
| GET | `/runs/{id}/artifacts` | Bearer | List artifacts for a run |
| POST | `/agents/{id}/schedules` | Bearer | Create schedule (`cronExpr`, `command`) |
| GET | `/agents/{id}/schedules` | Bearer | List schedules for agent |
| POST | `/schedules/{id}/trigger` | Bearer | Manual run trigger for schedule |
| GET | `/orgs/{id}/members` | Bearer | List org members (stub) |
| POST | `/orgs/{id}/members` | Bearer | Invite member stub (`email`, `role`) |

Existing routes (`/agents`, `/runs`, `/billing/*`) unchanged; quotas enforced on create agent/run and usage ingest.

### Agent runtimes

- `ssh-host`, `fly` — unchanged
- `gcp_cloud_run` — writes orchestration record + job spec JSON on agent `config.gcpCloudRun`
- `lightsail` — accepted for iOS `LightsailProvisioner` callbacks; no AWS calls from backend yet

### Schedule cron expressions (MVP)

- `@hourly`, `@daily`, `@weekly`
- `every:<seconds>` — fixed interval

Background ticker runs every minute unless `SCHEDULE_TICKER_ENABLED=false`.

## Environment variables

### Phase 2 — credits & artifacts

| Variable | Default | Purpose |
|----------|---------|---------|
| `CREDITS_FILE` | `lancer-credits.json` | JSON credit balances |
| `CREDITS_INITIAL_USD` | `0` | Starting prepaid on first access |
| `CREDITS_ALLOW_OVERAGE` | `true` | Allow overage ledger when prepaid exhausted |
| `ARTIFACTS_FILE` | `lancer-artifacts.json` | Artifact metadata store |
| `GCS_ARTIFACTS_BUCKET` | — | If set, populate `gcsUri` as `gs://bucket/ref` |
| `SCHEDULES_FILE` | `lancer-schedules.json` | Schedules store |
| `SCHEDULE_TICKER_ENABLED` | `true` | Set `false` to disable background scheduler |
| `GCP_ORCHESTRATION_FILE` | `lancer-gcp-orchestrations.json` | GCP job orchestration records |
| `GCP_PROJECT` | — | Enables `spec_ready` / submit stub when set |
| `GCP_REGION` | `us-central1` | Cloud Run region |
| `GCP_CLOUD_RUN_IMAGE` | `gcr.io/cloudrun/hello` | Container image in generated spec |
| `GOOGLE_APPLICATION_CREDENTIALS` | — | Optional; for future real GCP API calls |

### Phase 3 — quotas & orgs

| Variable | Default | Purpose |
|----------|---------|---------|
| `QUOTA_MAX_AGENTS` | `20` | Max agents per customer |
| `QUOTA_MAX_CONCURRENT_RUNS` | `5` | Active runs (`pending`, `running`, …) |
| `QUOTA_DAILY_USAGE_USD` | `100` | Daily summed `cost` from usage records |
| `ORGS_FILE` | `lancer-orgs.json` | Org member invites |

Entitlements may include `orgId`; agents/runs/schedules/artifacts inherit org scope when set.

## GCP Cloud Run Jobs deploy (orchestration stub → production)

1. Create GCP project; enable Cloud Run Admin API.
2. Create per-agent service account (name pattern `lancer-agent-<id>` in generated spec).
3. Set Fly/local secrets: `GCP_PROJECT`, `GCP_REGION`, `GCP_CLOUD_RUN_IMAGE`, credentials.
4. Deploy push-backend; create agent with `"runtime": "gcp_cloud_run"`.
5. Inspect `config.gcpCloudRun` and `lancer-gcp-orchestrations.json` for generated Job spec.
6. **Production:** implement `submitCloudRunJobIfConfigured` against Cloud Run Jobs API (currently records spec only).

## Stub vs production-ready

| Feature | Status |
|---------|--------|
| Bearer auth + JSON file stores | Production-ready (MVP) |
| Credit deduct + overage flag/block | Production-ready |
| Artifacts metadata | Production-ready; GCS upload is client-side |
| Schedule ticker + manual trigger | Production-ready (simple cron) |
| GCP Cloud Run | **Stub** — spec + orchestration record; no GCP API submit |
| Lightsail runtime | **Stub** — API accepts runtime; provisioning on device |
| Org members | **Stub** — invite/list only, no email delivery |
| Quotas | Production-ready (env-tunable) |

## Tests

```bash
cd daemon/push-backend && go test ./...
```

Covers credits, overage block, artifacts, schedules/trigger, GCP agent create, Lightsail runtime, quotas, org members.
