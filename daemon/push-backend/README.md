# push-backend

Minimal Go service for Conduit: APNs delivery, Stripe billing, hosted agents control plane.

## Build & test

```bash
cd daemon/push-backend
go build -o push-backend .
go test ./...
```

## Hosted agents (Phase 1–3)

See [docs/hosted-agents-phase2.md](../../docs/hosted-agents-phase2.md) for Phase 2/3 routes, env vars, and GCP deploy notes.

Copy [.env.example](.env.example) for local configuration.

## Deploy (Fly.io)

```bash
fly deploy
fly secrets set STRIPE_SECRET_KEY=... OPENROUTER_PROVISIONING_KEY=...
```

Optional Phase 2/3 secrets: `GCP_PROJECT`, `GCS_ARTIFACTS_BUCKET`, `QUOTA_MAX_AGENTS`, `CREDITS_INITIAL_USD`.
