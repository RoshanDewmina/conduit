# L1 — Core loop — PARTIAL (serial re-run)

**When:** 2026-07-19 ~17:54–18:00 local  
**Worktree:** `/Volumes/LancerDev/lancer/.worktrees/sim-serial-lanes` @ `7c4b1eca`  
**Lease:** `lease-242` (shared serial)  
**Isolated daemon:** `LANCER_STATE_DIR=/tmp/sweep-C4` · pair codes `497453` (and earlier probes)  
**Prod pairing:** **intact** — `~/.lancer/relay-pairing.json` mtime still `2026-07-19 10:26:47`

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Isolated pair (sim ↔ daemon via relay) | **PASS** | `L1-01-after-pair.png` — Trusted Machines shows Relay host **connected**; `isolated-daemon.log` `e2e: paired with phone` |
| Dispatch prompt into live thread | **PASS** | `L1-05-after-privacy.png` — thread titled with prompt, user bubble present, cwd `target-repo` |
| Agent reply / round-trip | **FAIL** | `L1-06`…`L1-10` — “Couldn't get a reply / No connected machine”; daemon `push-backend /run-start rejected: HTTP 401` (`daemon-dispatch.excerpt.txt`) |
| Screenshots | **PASS** | `screenshots/L1-01`…`L1-10` (+ L4 cross-refs) |

## Blockers (documented)

1. **iOS notification permission alert** blocked HID until dismissed via `axe tap --label "Don’t Allow"` (`axe-tap2.txt`).
2. **Connect race / session churn** after terminate+relaunch — machine dropped; Retry could not recover without re-pair.
3. **Isolated daemon push-backend HTTP 401** on `/run-start` and token registration — expected for non-prod identity; does not block local relay pair but weakens hosted push path.

## Cross-lane note

Same serial lease earlier ran `SweepLaneC4Tests` (**PASS**, L4) which exercised composer → thread with attachments (`screenshots/L1-xref-L4-composer.png`, `L1-xref-L4-thread.png`). That is governance-lane evidence, not a clean L1 reply receipt.

## Status: **PARTIAL**
