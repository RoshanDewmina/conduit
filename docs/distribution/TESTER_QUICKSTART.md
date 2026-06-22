# Lancer — tester quick start (self-host)

This is the fast path for a tester running their own host(s) and their own copy of
Lancer. Three steps: **install the daemon → pair the app → use the controls.**

> Lancer governs AI coding-agent loops (Claude Code, Codex, OpenCode, Kimi, …) that
> run on a Mac or Linux machine you control. The phone app is the control plane —
> it approves/rejects risky actions, lets you start a run, and (separately) opens a
> real SSH terminal into a host. It does not run agents itself.

---

## Prerequisites

- **A Mac or Linux host** you want to govern — the box where your agent CLI(s)
  already run (Claude Code, Codex, OpenCode, or Kimi). This is where `lancerd`
  installs and runs as a background daemon.
- **The Lancer iOS app** installed on your phone (TestFlight build or dev build).
- **For the interactive SSH terminal feature specifically:** the host you want to
  open a terminal on must be SSH-reachable (a normal `ssh user@host` from your
  network must already work). This is a separate feature from the approval loop —
  see "What 'control' looks like" below.
- **For push notifications / approvals to reach your phone:** the relay backend
  Lancer talks to must be live and reachable. If you're pointed at a self-hosted
  relay, confirm `GET <your-relay-url>/health` returns `200` before you start. If
  the relay is down, pairing may still complete but approvals will not reach your
  phone — see "If approvals don't show up" below.

---

## Step 1 — Install the daemon on your host

Run on the Mac/Linux box you want Lancer to govern:

```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh
```

This downloads a prebuilt `lancerd` binary for your OS/architecture, verifies its
checksum, and installs it to `~/.lancer/bin/lancerd`. It will also print next
steps and (unless skipped) immediately walk you into pairing.

Optional flags:
- `--hooks claude` (or `codex`, `both`) — also installs the PreToolUse hook for that
  agent CLI, so its risky actions actually route through Lancer's policy engine.
  Without a hook installed, `lancerd` runs but nothing calls into it yet.
- `--from-source` — build from Go source instead of downloading a binary (needs `go`
  installed).

After install, set the daemon up to run continuously in the background:

```bash
lancerd install   # registers a launchd (macOS) or systemd (Linux) service
```

---

## Step 2 — Pair your phone

On the host:

```bash
lancerd pair
```

This prints a QR code (and the relay URL it encodes) in your terminal.

On your phone, open Lancer and scan that QR code (Settings → Connection, or the
onboarding pairing screen if this is a fresh install). The app and the daemon now
share an encrypted channel through the relay — the relay itself never sees your
commands or approvals in plaintext.

If the QR doesn't fit your terminal or you're pairing a second device, `lancerd
pair` can be re-run any time to print fresh instructions.

For a deeper look at what's happening on the wire (relay framing, encryption), see
`daemon/push-backend/PAIRING_PROTOCOL.md` and `daemon/push-backend/SELF_HOST.md` in
this repo — not required reading to use the app, but useful if pairing fails and you
want to know what to check.

---

## Step 3 — What "control" looks like

Once paired, three things become possible from your phone:

### 1. Approve or reject risky agent actions
With a hook installed (Step 1) and a policy that doesn't blanket-allow everything,
your agent CLI will pause on actions it isn't sure about (e.g. `rm -rf`, a file
write, a shell command not covered by an allow rule) and send a card to your
phone's Inbox: what the agent wants to do, the matched rule, and the blast radius.
Tap **Approve** to let it continue, or **Reject** to block it. The agent CLI is
actually paused and waiting — your decision unblocks it (or it auto-denies after a
timeout if you don't respond).

### 2. Dispatch a run from your phone
From the New Chat surface in the app, pick a host/agent and send a prompt. Lancer
starts the agent CLI on your host and streams its output back to your phone in
real time, including any tool-call cards it generates along the way. You can send
a follow-up prompt afterward to continue the same conversation.

### 3. Open a real SSH terminal in a chat session
Separately from the approval loop, you can open an interactive terminal to any
SSH-reachable host directly from a chat session — a real SSH connection (not a
notification or relay message), so you can run commands by hand, inspect files, or
watch a live TUI (e.g. `vim`, `htop`) rendered inline.

---

## If approvals don't show up

- Confirm the relay is live: `curl <your-relay-url>/health` should return `200`.
  No card will ever reach your phone if the relay is down, even if pairing
  succeeded earlier — pairing and live delivery are separate concerns.
- Confirm a hook is installed on the host (`--hooks claude` etc. in Step 1) and
  that the policy isn't set to allow everything by default.
- If you expected a lock-screen / background push and didn't get one: push
  notifications require the app to have registered for remote notifications at
  least once in the foreground, and require Apple APNs to be configured on the
  relay backend you're pointed at. A self-hosted relay with no APNs key configured
  can still deliver approvals while the app is open/foregrounded, but will not wake
  a closed app.

---

## Uninstalling

```bash
lancerd uninstall   # stops and removes the background service, if supported by your install
rm -rf ~/.lancer     # removes the binary, socket, queue, policy, and audit log
```

Then remove the paired connection from the app (Settings → Connection → remove
device).
