# Hosted-agents GCP Cloud Run — production cutover runbook

Status: **the cloud-execution path is verified working end-to-end on real GCP.** A live
smoke test (agent → Cloud Run Job → run streams output back → `succeeded`, plus agent
delete tearing the Job down) passed against an actual Cloud Run deployment. This doc is
the remaining step: pointing the **real app backend** at that path.

## What exists now

| Resource | Value |
|---|---|
| GCP project | `conduit-runner-0603190634` (billing linked) |
| Runner image | `gcr.io/conduit-runner-0603190634/agent-runner:latest` (amd64, ships agent-runner + claude CLI on node 22) |
| push-backend image | `gcr.io/conduit-runner-0603190634/push-backend:smoke` (amd64; has a **baked smoke entitlement** — do NOT use as real prod) |
| Smoke service | Cloud Run `conduit-push-smoke` (scaled to `min-instances=0`; re-runnable, ~$0 idle) |
| Runtime SA | `161446405814-compute@developer.gserviceaccount.com` — granted `run.admin`, `iam.serviceAccountUser`, `artifactregistry.reader` |

Re-run the live smoke anytime:
```bash
CONDUIT_STAGING_URL=https://conduit-push-smoke-ufeid7srfq-uc.a.run.app \
CONDUIT_CLIENT_TOKEN=<the smoke token> \
scripts/gcp-staging-smoke.sh --cleanup-agent
```

## Required GCP env on ANY production push-backend

```
GCP_PROJECT=conduit-runner-0603190634
GCP_REGION=us-central1
GCP_CLOUD_RUN_IMAGE=gcr.io/conduit-runner-0603190634/agent-runner:latest
CONTROL_PLANE_PUBLIC_URL=<this backend's own public URL, reachable from GCP>
```
The backend must authenticate to GCP with a credential (ADC) whose identity has
`roles/run.admin` + `roles/iam.serviceAccountUser` on `conduit-runner-0603190634`.

---

## Path A — cut over the existing VM (35.201.3.231)

The app currently targets this host (`PUBLIC_BASE_URL` in `scripts/deploy-push-backend.sh`).
This is the smallest change to make the shipped app use cloud execution.

1. **Give the VM a GCP identity with Cloud Run perms on the new project.** The VM is not
   in `conduit-runner-0603190634`, so create a service account there, grant it
   `roles/run.admin` + `roles/iam.serviceAccountUser`, download a key, and place it on the
   VM. (Workload Identity Federation is the keyless alternative and preferred if available.)
   ```bash
   gcloud iam service-accounts create conduit-backend \
     --project conduit-runner-0603190634 --display-name "Conduit backend"
   SA=conduit-backend@conduit-runner-0603190634.iam.gserviceaccount.com
   for R in roles/run.admin roles/iam.serviceAccountUser; do
     gcloud projects add-iam-policy-binding conduit-runner-0603190634 \
       --member="serviceAccount:$SA" --role="$R" --condition=None
   done
   gcloud iam service-accounts keys create /tmp/conduit-backend.json --iam-account "$SA"
   scp /tmp/conduit-backend.json roshansilva@35.201.3.231:~/.conduit/push-backend/gcp-sa.json
   ```
2. **Set env on the VM** (`~/.conduit/push-backend/.env`): the four GCP vars above, plus
   `GOOGLE_APPLICATION_CREDENTIALS=/home/roshansilva/.conduit/push-backend/gcp-sa.json`, and
   `CONTROL_PLANE_PUBLIC_URL=http://35.201.3.231:8080` (must be reachable from GCP egress —
   open the firewall for inbound 8080 if not already).
3. **Deploy the current binary + restart** via `scripts/deploy-push-backend.sh` (already
   updated to write `CONTROL_PLANE_PUBLIC_URL` and the GCP vars).
4. **Verify**: `scripts/gcp-staging-smoke.sh` with `CONDUIT_STAGING_URL=http://35.201.3.231:8080`
   and a real entitlement token from the VM's control plane.

> ⚠️ Caveat: the VM's push-backend uses the local JSON file store — fine for the current
> single-host deploy, but it is not horizontally scalable. Keep it single-instance.

---

## Path B — promote a proper Cloud Run production service (recommended longer-term)

Cleaner than the hand-managed VM, but two things must change before it can be the real
backend:

1. **Durable storage.** The file store under `DATA_DIR=/tmp` is per-instance and ephemeral.
   Back entitlements/control-plane/run-logs/tokens with the Redis store (already present:
   `redis_client.go`, `redisEntitlementStore`) or Firestore before serving real traffic, and
   drop `min/max-instances=1`.
2. **Real entitlements.** Remove the baked smoke seed; entitlements must come from the live
   Stripe webhook path. Build a clean prod image (no seed) from `daemon/push-backend/Dockerfile`.
3. Deploy, set the four GCP env vars + `CONTROL_PLANE_PUBLIC_URL=<service URL>`, grant the
   runtime SA the three roles above, then repoint the iOS app's `PUBLIC_BASE_URL` to the
   service URL (requires an app release).

---

## OpenRouter (agent model auth) — VERIFIED LIVE

The runner routes the bundled Claude Code CLI through OpenRouter's Anthropic-compatible
API (`agent-runner/main.go` `agentChildEnv`): sets `ANTHROPIC_BASE_URL=https://openrouter.ai/api`,
`ANTHROPIC_AUTH_TOKEN=<key>`, and `ANTHROPIC_API_KEY=` (empty). The key comes from
`dispatchRun` → `openRouterKeyForCustomer`, which prefers a per-customer provisioned
sub-key and falls back to `OPENROUTER_SHARED_KEY`.

Two modes:
- **Provisioning (preferred, multi-tenant):** set `OPENROUTER_PROVISIONING_KEY` (an
  OpenRouter *management* key). The backend mints a capped sub-key per customer.
- **Shared key (MVP/single-tenant):** set `OPENROUTER_SHARED_KEY` to an ordinary
  inference key; all runs share it. Cap its spend in the OpenRouter dashboard.

The VM (35.201.3.231) is currently running **shared-key mode**, verified live:
`claude -p hello --output-format json` over the full VM→Cloud Run→agent path returned
`subtype:success`, `stop_reason:end_turn`, with a real model call
(`nvidia/nemotron-3-super-120b-a12b:free`, 22k in / 147 out tokens).

> ⚠️ The configured key is **free-tier** — it can only call `:free` models (rate-limited,
> often empty/odd output). For real Claude-model agents, add OpenRouter credits (or set a
> provisioning key on a funded account). The plumbing is correct; this is purely a
> credits/model-access matter.

## Cleanup (if abandoning the smoke harness)
```bash
gcloud run services delete conduit-push-smoke --project conduit-runner-0603190634 --region us-central1
```
Images are cheap to retain and are reused by both paths.
