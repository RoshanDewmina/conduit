# Deploying the Lancer blind relay

The `push-backend` binary doubles as the **blind WebSocket relay** for keyless
QR + relay pairing: it forwards opaque ciphertext between a `lancerd` daemon and
the phone on a shared 6-char pairing channel and never holds a key (see
[`PAIRING_PROTOCOL.md`](./PAIRING_PROTOCOL.md) for the exact wire contract the iOS
client must match).

The relay endpoint is `wss://<host>/ws/relay`. Point lancerd at it with:

```bash
export LANCER_RELAY_URL="wss://<host>"      # base URL, NO /ws/relay path
```

This document covers two ways to host it:
1. **Tailscale Funnel** — fastest path for testing / personal use (no public IP,
   no certs to manage). Bandwidth-limited — see the caveat.
2. **GCP cloud VM + systemd** — production option behind a real cert / load balancer.

---

## 0. Build

```bash
cd daemon/push-backend
CGO_ENABLED=0 go build -o push-backend .
./push-backend          # listens on :8080 by default (override with PORT)
curl localhost:8080/health   # → 200
```

The relay endpoint (`/ws/relay`) is **not** behind `APPROVAL_RELAY_SECRET` — it
carries only ciphertext, so it is intentionally open. `APPROVAL_RELAY_SECRET`
guards the *control-plane* HTTP endpoints (`/register`, `/approval`,
`/run-complete`) and is **mandatory in production** (the process refuses to start
without it when `FLY_APP_NAME`/`K_SERVICE`/`LANCER_ENV=production` is set — see
`relay_security.go`). Set it on any deployment that also serves those endpoints.

Relevant env vars:

| Var                     | Purpose                                                     |
|-------------------------|-------------------------------------------------------------|
| `PORT`                  | Listen port (default `8080`).                               |
| `APPROVAL_RELAY_SECRET` | Shared secret for control-plane HTTP endpoints (prod: required). |
| `LANCER_ENV`           | `production` to enable fail-closed startup checks.          |

---

## 1. Tailscale Funnel (testing / personal)

[Tailscale Funnel](https://tailscale.com/kb/1223/funnel) exposes a port on your
tailnet to the public internet over HTTPS, with an automatic
`<host>.<tailnet>.ts.net` cert — no public IP, no nginx, no Let's Encrypt.

**Funnel only allows public ports `443`, `8443`, and `10000`.** Run the relay on a
local port and Funnel-proxy one of those to it.

```bash
# On the Linux host (Tailscale installed + logged in):
# 1. Enable Funnel for your tailnet (one-time, in the admin console under
#    Access Controls → nodeAttrs → "funnel"), then:
sudo tailscale set --operator=$USER     # let your user drive tailscale (optional)

# 2. Run the relay on a local port (8080 here):
PORT=8080 APPROVAL_RELAY_SECRET="$(openssl rand -hex 32)" ./push-backend &

# 3. Funnel a public port (443) to the local relay:
sudo tailscale funnel --bg --https=443 http://127.0.0.1:8080

# 4. Confirm:
tailscale funnel status
#   https://<host>.<tailnet>.ts.net (443) → http://127.0.0.1:8080
```

Your relay base URL is then:

```
LANCER_RELAY_URL="wss://<host>.<tailnet>.ts.net"
```

(The daemon appends `/ws/relay`; WSS upgrades ride the same 443 Funnel.)

Tear down with `sudo tailscale funnel --https=443 off`.

> **⚠ Bandwidth caveat:** Funnel routes through Tailscale's DERP relays and is
> **bandwidth-limited / best-effort** — Tailscale explicitly does not guarantee
> throughput for Funnel traffic. It is great for testing and low-volume personal
> pairing (the relay only carries tiny JSON control frames), but **do not run
> production / multi-user load over Funnel** — move to the GCP option below.

---

## 2. GCP cloud VM + systemd (production)

A small `e2-micro`/`e2-small` Compute Engine VM is plenty — the relay is
near-stateless and carries only small control frames.

### 2a. Provision the VM

```bash
gcloud compute instances create lancer-relay \
  --machine-type=e2-small --zone=us-central1-a \
  --image-family=debian-12 --image-project=debian-cloud \
  --tags=https-server

# Allow 443 inbound:
gcloud compute firewall-rules create allow-https \
  --allow=tcp:443 --target-tags=https-server --direction=INGRESS
```

### 2b. Install the binary + TLS

Build (`CGO_ENABLED=0 go build -o push-backend .`) and `scp` the binary to
`/usr/local/bin/push-backend`. Terminate TLS in front of the relay — either:
- **Caddy** (simplest): `reverse_proxy 127.0.0.1:8080` with automatic HTTPS, or
- a **Google HTTPS Load Balancer** with a managed cert pointing at the VM, or
- nginx + certbot.

The relay itself serves plain HTTP on `PORT`; WebSocket upgrades pass through any
of the above unchanged.

### 2c. systemd unit

`/etc/systemd/system/lancer-relay.service`:

```ini
[Unit]
Description=Lancer blind relay
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/push-backend
Environment=PORT=8080
Environment=LANCER_ENV=production
EnvironmentFile=/etc/lancer-relay.env       # holds APPROVAL_RELAY_SECRET=...
Restart=always
RestartSec=2
User=lancer
DynamicUser=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
```

`/etc/lancer-relay.env` (mode `0600`):

```
APPROVAL_RELAY_SECRET=<openssl rand -hex 32>
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now lancer-relay
sudo systemctl status lancer-relay
curl https://<your-domain>/health     # → 200
```

Point lancerd at it:

```bash
LANCER_RELAY_URL="wss://<your-domain>"
```

---

## 3. Smoke test the deployment

```bash
# Health:
curl -fsS https://<host>/health && echo OK

# Pairing instructions (prints a code + the configured relay URL):
LANCER_RELAY_URL="wss://<host>" lancerd pair

# Run the daemon side against the relay:
LANCER_RELAY_URL="wss://<host>" LANCER_PAIRING_CODE=<code> lancerd relay
```

The full blind-forward + crypto round-trip is covered by
`go test ./...` in both `daemon/push-backend` and `daemon/lancerd`
(`TestRelayRoundTrip`, `TestRelayBuffersUntilPeerJoins`,
`TestE2ECryptoRoundTrip`, `TestE2ELoopbackThroughBlindRelay`).
