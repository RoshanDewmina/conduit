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

The Conduit remote daemon is installed at `~/conduitd` (v0.1.0, linux-amd64).

```bash
~/conduitd version        # 0.1.0
~/conduitd serve          # start approval bridge (iOS app spawns this automatically)
```

The Claude Code pre-tool hook is wired at `~/.claude/hooks/pre-tool.sh`.
Codex uses `~/.codex/hooks/conduit-hook.sh` with `~/.codex/hooks.json`.
When `conduitd serve` is running, matching Claude Code and Codex tool calls
route an approval request to the connected iOS app before executing.
If `conduitd serve` is not connected, `conduitd agent-hook` intentionally
auto-approves so a disconnected phone does not strand the remote agent.

Codex hook install on the server:

```bash
mkdir -p ~/.codex/hooks ~/.conduit/bin
cp ~/conduitd ~/.conduit/bin/conduitd
chmod 700 ~/.codex/hooks
chmod 755 ~/.conduit/bin/conduitd
cp docs/codex-conduit-hook.sh ~/.codex/hooks/conduit-hook.sh
cp docs/codex-hooks.json ~/.codex/hooks.json
chmod 700 ~/.codex/hooks/conduit-hook.sh
codex --version
```

Run `/hooks` inside Codex to trust the hook. For disposable smoke tests only,
Codex can be launched with `--dangerously-bypass-hook-trust`.

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
gcloud compute scp conduitd-linux-amd64 conduit-dev:~/conduitd \
  --project=gen-lang-client-0839010810 --zone=australia-southeast1-a
gcloud compute ssh conduit-dev --project=gen-lang-client-0839010810 --zone=australia-southeast1-a \
  --command="chmod +x ~/conduitd && ~/conduitd version"
```
