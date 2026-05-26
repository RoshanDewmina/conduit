# Test Server

GCP Compute Engine instance for Conduit iOS app development and testing.

## Connection details

| | |
|---|---|
| **Provider** | Google Cloud Platform |
| **Project** | `gen-lang-client-0839010810` |
| **Instance** | `conduit-dev` |
| **Zone** | `australia-southeast1-a` (Sydney) |
| **IP** | `35.201.3.231` |
| **Port** | `22` |
| **Username** | `roshansilva` |
| **Auth** | Ed25519 key (gcloud-managed at `~/.ssh/google_compute_engine`) |
| **OS** | Debian 12 (x86_64) |

## Connect from terminal

```bash
gcloud compute ssh conduit-dev \
  --project=gen-lang-client-0839010810 \
  --zone=australia-southeast1-a
```

Or directly via SSH:

```bash
ssh -i ~/.ssh/google_compute_engine roshansilva@35.201.3.231
```

## Connect from Conduit iOS app

1. Open Conduit → Workspaces → Add host
2. Fill in:
   - **Name:** GCP Dev
   - **Hostname:** `35.201.3.231`
   - **Port:** `22`
   - **Username:** `roshansilva`
   - **Auth:** Ed25519 — select your key from the Keys screen
3. Tap Save → Connect

To add your iOS device key to the server:

```bash
gcloud compute ssh conduit-dev \
  --project=gen-lang-client-0839010810 \
  --zone=australia-southeast1-a \
  --command='echo "YOUR_IOS_PUBLIC_KEY" >> ~/.ssh/authorized_keys'
```

## conduitd

The Conduit remote daemon is installed at `~/.conduit/bin/conduitd` (v0.1.0, linux-amd64).

```bash
~/.conduit/bin/conduitd version   # 0.1.0
```

`conduitd serve` reads JSON-RPC frames from stdin and is **spawned automatically by the iOS
app** over its SSH connection — do not start it manually. When `conduitd serve` is running
(i.e. the iOS app is connected), matching Codex tool calls route an approval request to the
phone before executing. When the phone is disconnected, `conduitd agent-hook` auto-approves
so a disconnected phone does not strand the remote agent.

Current hook locations (already installed):
- `~/.codex/hooks/conduit-hook.sh` — PreToolUse hook script
- `~/.codex/hooks.json` — Codex hook config

Codex hook install on the server (run once if re-provisioning):

```bash
mkdir -p ~/.codex/hooks ~/.conduit/bin
cp ~/conduitd ~/.conduit/bin/conduitd   # migrate legacy path
chmod 700 ~/.codex/hooks
chmod 755 ~/.conduit/bin/conduitd
cp docs/codex-conduit-hook.sh ~/.codex/hooks/conduit-hook.sh
cp docs/codex-hooks.json ~/.codex/hooks.json
chmod 700 ~/.codex/hooks/conduit-hook.sh
codex --version
```

Trust the hook (one-time, inside Codex REPL):
```
codex
/hooks   ← select conduit-hook.sh and trust it
```

End-to-end approval loop test:
1. Open Conduit iOS → connect to `35.201.3.231` (Inbox tab stays open)
2. On server: run `codex` and give it a file-write task
3. Approval card appears in Conduit Inbox → tap Allow or Reject
4. Allow: task proceeds; Reject: Codex sees exit code 2 and aborts the tool call
5. Check `~/.conduit/codex-hook-events.jsonl` for the event record

## Manage the instance

```bash
# Start / stop
gcloud compute instances start  conduit-dev --zone=australia-southeast1-a --project=gen-lang-client-0839010810
gcloud compute instances stop   conduit-dev --zone=australia-southeast1-a --project=gen-lang-client-0839010810

# Check status
gcloud compute instances describe conduit-dev --zone=australia-southeast1-a --project=gen-lang-client-0839010810 --format="table(status,networkInterfaces[0].accessConfigs[0].natIP)"
```

## Update conduitd

```bash
# From the repo root — cross-compile and push
cd daemon/conduitd
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 /opt/homebrew/bin/go build -ldflags="-s -w" -o conduitd-linux-amd64 .
gcloud compute scp conduitd-linux-amd64 conduit-dev:~/.conduit/bin/conduitd \
  --project=gen-lang-client-0839010810 --zone=australia-southeast1-a
gcloud compute ssh conduit-dev --project=gen-lang-client-0839010810 --zone=australia-southeast1-a \
  --command="chmod +x ~/.conduit/bin/conduitd && ~/.conduit/bin/conduitd version"
```
