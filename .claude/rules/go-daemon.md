---
paths:
  - "daemon/**"
---
# Go daemon (conduitd / push-backend / conduit-mcp)

**Verify (matches CI `.github/workflows/ci.yml`, Go 1.25)** — from the module dir, not the repo root:

```bash
cd daemon/<mod> && go build ./... && go vet ./... && go test ./...   # mod ∈ conduitd, push-backend, conduit-mcp
```

**Before changing `daemon/conduitd/dispatch.go`** — the agent-CLI adapters (Claude Code, Codex,
OpenCode, Kimi) drift fast: run the `vendor-cli-adapter-audit` skill and re-check
`which` / `--version` / `--help` for each vendor CLI. **Never `sh -c` an interpolated prompt** —
build an explicit argv array. The `continue` path must re-pass the same approval gates as the
initial launch.

**The policy engine is fail-closed:** default = `ask`; daemon unreachable → mutating kinds
blocked; approval timeout → `deny`. Never log secrets (the Redactor strips PEM / Bearer / JWT /
API-key patterns). `push-backend` scopes every handler per request
(`resolveEntitlementFromBearer` + `resourceVisibleToEntitlement`); artifact downloads are
prefix-checked (`runs/<runID>/`). Don't weaken these.
