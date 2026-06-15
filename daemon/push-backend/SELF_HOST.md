# Self-hosting the Conduit push-backend relay

The `push-backend` binary serves two roles:
- **Blind WebSocket relay** (`/ws/relay`) — forwards opaque ciphertext for QR + relay pairing.
- **APNs push delivery** — sends approval alerts and run-complete notifications to iOS.

You can self-host just the relay (no APNs keys needed) or the full backend.

---

## Quick start with Docker

### One-line run

```bash
docker run -d --name conduit-relay \
  -p 8080:8080 \
  -e APPROVAL_RELAY_SECRET="$(openssl rand -hex 32)" \
  conduit-relay
```

### With docker compose

Copy the example env file and edit as needed:

```bash
cp .env.example .env
# Edit .env — at minimum set APPROVAL_RELAY_SECRET
# For relay-only use you can leave APNS_* vars blank
docker compose up -d
```

Verify:

```bash
curl http://localhost:8080/health    # → 200
```

---

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `PORT` | no | `8080` | HTTP listen port |
| `APPROVAL_RELAY_SECRET` | recommended | — | Shared secret for control-plane endpoints. Set to `openssl rand -hex 32` |
| `CONDUIT_ENV` | no | — | Set to `production` to enable fail-closed startup checks |
| `CORS_ALLOW_ORIGIN` | no | `*` | CORS origin header value |
| `APNS_KEY_ID` | for push | — | Apple APNs key ID (10 chars) |
| `APNS_TEAM_ID` | for push | — | Apple team ID (10 chars) |
| `APNS_KEY_PATH` | for push | — | Path to the `.p8` key file |
| `APNS_BUNDLE_ID` | for push | `dev.conduit.mobile` | iOS bundle ID for push topic |

**Relay-only:** the `APNS_*` vars and all Stripe/GCP/OpenRouter vars are unused — the relay endpoint (`/ws/relay`) needs nothing but `PORT`. The container starts and runs without them.

**Approval relay:** set `APPROVAL_RELAY_SECRET` to a strong random value. Without it the control-plane endpoints (`/register`, `/approval`, `/run-complete`) are unauthenticated; the process logs a loud warning at startup and refuses to start if `CONDUIT_ENV=production` is set.

---

## Pointing the iOS app at your relay

The iOS client resolves the relay URL in this priority order (see `RelaySettings.swift`):

1. **In-app override** — Settings → Relay Server text field.
2. **`CONDUIT_RELAY_URL` env var** — via Xcode scheme or launch arguments (debug builds).
3. **Compiled default** — currently `wss://hermes-box.tail8c17ee.ts.net:8443` (the hosted relay).

Enter `wss://<your-host>:<port>` in the Settings → Relay Server field. The app appends `/ws/relay` automatically — do not include the path.

---

## TLS / wss://

iOS requires a secure WebSocket connection (`wss://`). The relay serves plain HTTP on its `PORT`; you must terminate TLS in front of it.

### Option A: Caddy (sidecar)

Add a Caddy container to your compose file:

```yaml
services:
  caddy:
    image: caddy:2
    ports:
      - "443:443"
    volumes:
      - caddy_data:/data
      - ./Caddyfile:/etc/caddy/Caddyfile
  conduit-relay:
    build: .
    ports:
      - "8080"
```

`Caddyfile`:

```
your-domain.com {
    reverse_proxy conduit-relay:8080
}
```

Caddy provisions a Let's Encrypt cert automatically.

### Option B: Tailscale Funnel

Follow the instructions in [DEPLOY.md](./DEPLOY.md#1-tailscale-funnel-testing--personal). Funnel exposes port 443 with an auto cert at `<host>.<tailnet>.ts.net`.

### Option C: nginx / other reverse proxy

Terminate TLS with any front-end proxy and forward to the relay on `localhost:PORT`. WebSocket upgrades pass through unchanged.

---

## Data persistence

The in-memory session registry and decision store are **ephemeral** — restarting the container clears all active pairing sessions. This is acceptable because:
- The relay buffers messages only while both peers are connected; if the container restarts, clients reconnect with their pairing code.
- For production, add a `DATA_DIR` volume mount so JSON-backed stores persist:

```yaml
volumes:
  - conduit-data:/data
environment:
  - DATA_DIR=/data
```

---

## Health check

`GET /health` returns `200 OK`. The compose file above probes this endpoint every 30 s.
