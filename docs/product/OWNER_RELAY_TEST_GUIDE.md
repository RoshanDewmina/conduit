# Owner + agent relay test guide

**Purpose:** Step through Tier 0 with you on the Mac and simulator/device while the agent drives builds, logs, and fixes.  
**Canonical detail:** `docs/LIVE_LOOP_RUNBOOK.md` (this guide is the **interactive short form**).

**Prep (agent does before session):**

```bash
cd daemon/lancerd && go build -o lancerd . && go test ./...
cd Packages/LancerKit && swift build
# App build + install to sim or device
```

---

## Phase A — Simulator smoke (agent-led, ~20 min)

You watch; agent runs commands and shares screenshots.

| Step | Agent action | You confirm |
|------|--------------|-------------|
| A1 | Build + launch Lancer on **iPhone 17 Pro sim** (default = live Cursor shell, no env flags) | App opens to **Workspaces**, no sidebar |
| A2 | Open profile → Settings | **Cursor** dark settings sheet — **not** cream Policy Bridge |
| A3 | Run `LegacyUIRemovalTests` + `CursorShellLiveApprovalTests` | All PASS |
| A4 | Run `relay-approval-e2e.sh` through Cursor nav | Script exits 0 |

**Stop if:** legacy "POLICY BRIDGE" or sidebar appears → file bug, don't continue.

---

## Phase B — Mac daemon + relay (you + agent, ~30 min)

| Step | Who | Action |
|------|-----|--------|
| B1 | You | Confirm `lancerd` resident: `pgrep -fl lancerd` or start per `docs/lancerd-resident.md` |
| B2 | Agent | Rebuild `lancerd` from `daemon/lancerd`, install to `~/.lancer/bin/lancerd` |
| B3 | You | Confirm `push-backend` reachable (or local relay URL agent provides) |
| B4 | Agent | Tail relay / daemon logs in a terminal pane |
| B5 | You | On sim or **physical iPhone**: Profile → Pair machine → enter code from Mac |
| B6 | You | Send a **low-risk** test prompt from Workspaces composer |
| B7 | Both | Trigger an **ask** approval (agent provides scoped hook in `/tmp/lancer-e2e-workspace`) |
| B8 | You | Tap **Approve** on work thread banner or review sheet |
| B9 | Agent | Verify audit line + agent unblocked in hook terminal |

**Checkpoint B PASS:** approval decision returns in &lt;120s; audit shows `approve`.

---

## Phase C — Physical device + push (owner-required, ~45 min)

Simulators **cannot** receive production APNs. Needs your iPhone.

| Step | Who | Action |
|------|-----|--------|
| C1 | Agent | Install dev build to your device (you approve reinstall if paired state matters) |
| C2 | You | Allow notifications; complete pairing if needed |
| C3 | You | **Background or kill the app** |
| C4 | Agent | Trigger `ask` approval on hooked agent |
| C5 | You | Approve from **lock-screen notification** or Live Activity button |
| C6 | Agent | Verify `decide()` reached daemon; hook unblocks |

**Checkpoint C PASS:** decision without opening app (or one tap from lock screen).

---

## Phase D — Continue / follow-up (sim OK)

| Step | Action |
|------|--------|
| D1 | From work thread, send follow-up via collapsed composer (`Follow up...`) |
| D2 | Agent verifies `performContinueConversation` / vendor argv in logs |
| D3 | Repeat for **Claude** first; Codex/OpenCode per `vendor-cli-adapter-audit` if time |

---

## Paste-this prompt to start a session

```
Let's run docs/product/OWNER_RELAY_TEST_GUIDE.md together.

I'm at the Mac with lancerd ready. Start with Phase A on the simulator.
Pause after each step for me to confirm. Use the amazing-mayer worktree.
When we hit Phase B, tell me exactly what to tap and what you need in the logs.
Do not mark device APNs green unless we complete Phase C on my physical iPhone.
```

---

## Report template (agent fills after session)

| Phase | PASS/FAIL | Evidence |
|-------|-----------|----------|
| A Sim smoke | | UITest log / screenshot path |
| B Pair + approve | | audit tail / relay log snippet |
| C Push + lock screen | | owner confirmed Y/N |
| D Continue | | vendor + log line |

Update `docs/test-runs/` with dated proof file if any phase passes on device.
