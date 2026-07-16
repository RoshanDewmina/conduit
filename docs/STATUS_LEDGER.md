# Lancer status ledger

**Last updated:** 2026-07-15 (integration/2026-07-15-daily-drive merged to master @ `65bed890`;
the 2026-07-12 block below is superseded history, kept for context — see `plans/orchestrator-state.md`).
**Active branch:** `master` (`65bed890`) — re-check `git rev-parse HEAD` / `gh pr list` before citing
anything here.

> **2026-07-15 in one line:** five fixes landed and merged to master via
> `integration/2026-07-15-daily-drive`: relay generation-guard for the cross-reconnect
> replay-poisoning bug (`fix/relay-generation-guard`, `eeb562fa`/`aef83354`/`cc3bce2b`),
> structured-attachment upload integration (`feat/attachment-integration` +
> `feat/attachment-daemon-dispatch` + `feat/attachment-ios-ux`, `6b5329fe`/`75445047`/`72fd250e`),
> an Agents-continuity fix for false unreachable alarms + blank observed-session adopts
> (`fix/s2-agents-continuity`, `00485128`), a per-dispatch "Full tools" opt-out of the strict
> MCP config (`feat/s4-fulltools-toggle`, `77da7612`), and a stacked-sheet/duplicate-turn +
> concurrent-send dispatch-race fix (`4bbb86eb`, `95c6b06d`). **Evidence and a caveat:** a
> **10/10 sim proof** for the relay generation-guard reconnect fix was claimed 2026-07-15 but
> its evidence bundle was never committed (integrity gap); re-prove or restore before citing
> — it is **not yet re-proven on a physical device**. ⚠️ **A safety
> incident during that testing orphaned the owner's real phone pairing**: an isolated-daemon
> test invoked `lancerd pair --help`, which the binary doesn't recognize and silently ran
> `pair` for real against the default (unset `LANCER_STATE_DIR`) state dir — i.e. the owner's
> real `~/.lancer` — dropping the resident daemon's live relay session. The owner's phone
> needs to **re-pair** before any further device work; the only on-disk backup
> (`relay-pairing.json.owner-backup-KEEP`) is stale (2026-07-12) and is not a safe restore
> point. Separately, the **desktop-session "Decryption failed" fix** (`fix/desktop-session-decrypt`)
> is DONE as of 2026-07-15 night: root cause was `SessionMessage.Role` missing `.thinking`;
> fixed + 3 regression tests + live-proven on a paired sim against the production relay
> (DesktopSessionDecryptUITests PASSED) — **PR #127 open**, part of the
> `integration/2026-07-15-night` stack (PRs #120–#127, see `docs/CHANGELOG.md`).
>
> **2026-07-12 in one line (historical, superseded by the above):** owner P0 "multiple
> command-center rows" fixed end-to-end (#95 app bucketing · #96 daemon cwd hygiene +
> prunable approvals · #97 chat-loop close-mid-run/retry/reopen · #98 tilde
> sandbox-expansion — the on-device recurrence); proven by a live dogfood run (agent fixed
> real compiler warnings via Lancer itself, approval on the owner's phone, `226f2307`). New
> owner asks queued: full terminal (`product/2026-07-12-orca-terminal-port-map.md`), context
> uploads + readiness gaps (`product/2026-07-12-full-time-readiness-audit.md`). Relay
> pairing code/state from this era is stale — see the 07-15 phone re-pair note above.
**Direction SSOT:** [`docs/product/2026-07-10-lancer-daily-driver-definition.md`](product/2026-07-10-lancer-daily-driver-definition.md)
**Build how:** [`docs/product/2026-07-10-lancer-agent-build-roadmap.md`](product/2026-07-10-lancer-agent-build-roadmap.md)

> **Docs purge 2026-07-10:** docs/ reduced from ~600 files to the minimum set (owner-directed).
> Deleted docs live in git history only — do not recreate or cite them. Merge/PR archaeology
> formerly recorded here lives in `git log` / `gh pr list`.

---

## Current priority

**Phase 0 — git hygiene: DONE 2026-07-11** (evidence in [`plans/orchestrator-state.md`](plans/orchestrator-state.md)):
W0.A landed (incl. repair of an empty-tree tip commit `1c102940` → `4c350a52`, and the
dispatch-cwd fail-fast fix `4c2634df`); wipe worktree + branch removed (tip was ancestor of
master); `build_sim` SUCCEEDED on the kept W0.A shell. Owner-gated remainder: Tier 0 re-proof.

**SUPERSEDED same day — frontend reversal (owner, 2026-07-11 PM):** the owner clarified with
the Cursor Design reference set (`docs/design/cursor-reference/`) that the intended frontend
is the **Codex Workspaces shell** (`80407933..b472ffd3`), not W0.A. PR #75 restores it; the
W0.A CursorStyle shell is retired; PRs #72/#73/#74 closed as superseded (their shell-agnostic
logic — tool-call pairing, question-ingest observer, warning cleanup — re-queued against the
restored line). The paragraph below documents the original #69 resolution for history only.

**Integration resolution (2026-07-11 merge of master into W0.A):** master had grown a
*parallel* frontend line since `e850b126` (wipe `80407933` + Workspaces-shell rebuild + M2–M4
+ in-thread questions PR #68). Per owner directive (W0.A shell KEPT, approved 2026-07-11), the
merge takes **W0.A for the entire iOS UI surface** (AppFeature/CursorStyle, DesignSystem,
widgets, UITests, Package.swift/resolved, project.yml, Lancer/) and **master for the backend**
(daemon incl. questions M3 stdio responder; LancerCore `E2ERelayMessage` + SessionFeature
`E2ERelayBridge` wire fixes; InboxFeature VM). The w0a dispatch-cwd fail-fast fix was re-applied
onto master's dispatch.go. **Dropped from tree (git history keeps them):** master's
Workspaces-shell UI incl. the M1 in-thread Question *card* and M4 approve/deny *surfaces* —
re-porting those onto the W0.A shell is a Phase 1 lane. All gates green post-merge
(go build/vet/test · swift build · build_sim).

**Then Phase 1 — dogfood MVP (weeks 1–2):** six pieces (pairing/trusted machines · thread list ·
chat thread finesse · composer · push approvals incl. lock screen · emergency stop), per the
build roadmap §1. Exit bar: owner completes the full loop on a physical phone 5 days of 7.
Owner starts `docs/dogfood-log.md` (one line/day; every laptop-reach is a bug or scope insight).

**September target (owner, 07-10): App Store launch at iOS 27 GA (~Sept 14)** — S27 + LAUNCH
work packages in the build roadmap §3.1/§3.1b; billing + legal/review unfreeze early August.
Dogfood log by mid-Aug is the go/no-go input (downgrade path: TestFlight-only).
**Still frozen:** team tier, hosted-cloud, Away Launch Composer. Watch: cut (owner, Jul 8).

**Execution model + process (owner, 07-10):** [`ENGINEERING_PROCESS.md`](ENGINEERING_PROCESS.md)
— Cursor CLI (Grok 4.5 high / Composer 2.5) codes, Sonnet 5 high is fallback + sensitive paths,
Fable orchestrates via [`plans/orchestrator-state.md`](plans/orchestrator-state.md)
+ the `swarm-orchestrator` skill.

## Tier 0 / device evidence (current)

| Item | Status | Evidence |
|------|--------|----------|
| Governed loop on device (D0.2) | Historical PASS 2026-07-08 evening on `732071a7`; **re-proof on current tip PENDING** | [`test-runs/2026-07-08-tier0-5c-retest-results.md`](test-runs/2026-07-08-tier0-5c-retest-results.md), [`test-runs/2026-07-09-tier0-device-proof-results.md`](test-runs/2026-07-09-tier0-device-proof-results.md) |
| APNs lock-screen approve (5c) | Historical PASS on `732071a7`; re-proof PENDING | same + [`test-runs/2026-07-08-5c-root-cause.md`](test-runs/2026-07-08-5c-root-cause.md) |
| Owner checklist | [`test-runs/2026-07-07-tier0-owner-checklist.md`](test-runs/2026-07-07-tier0-owner-checklist.md) | — |
| Phone dogfood notes | [`test-runs/2026-07-09-phone-dogfood-results.md`](test-runs/2026-07-09-phone-dogfood-results.md) | — |
| Reconnect 10x (relay generation-guard) | **10/10 sim proof claimed 2026-07-15 but its evidence bundle was never committed (integrity gap); re-prove or restore before citing.** Physical-device re-proof still PENDING, blocked until the owner re-pairs their phone (safety incident above) | — (missing `test-runs/2026-07-15-reconnect-10x-sim/`) |

## Open P0 / P1 (correctness)

| Gap | Severity | Status |
|-----|----------|--------|
| Tier 0 / 5c re-proof on current tip | P0 | Pending (owner-gated) |
| W0.A dirty tree + abandoned wipe worktree + stash | P0 | Phase 0 defuses |
| Production burn list (GCS `lancerd` publish, VPS, CloudKit Production schema) | P1 | [`product/2026-07-09-production-readiness-gaps.md`](product/2026-07-09-production-readiness-gaps.md); owner-gated |
| JWT HS256-only | P1 | Open |
| StoreKit IAP dormant vs Stripe entitlement | P1 | Open — frozen until fork |
| Audit chain no external anchor | P1 | Open |
| Daemon single relay pairing slot | P2 | Open by design |

## Canonical doc map (post-purge)

| Question | Read this |
|----------|-----------|
| What is Lancer / architecture | [`ARCHITECTURE.md`](../ARCHITECTURE.md) §0.1 + §4.1 |
| Direction, MVP, phases, wedge | [`product/2026-07-10-lancer-daily-driver-definition.md`](product/2026-07-10-lancer-daily-driver-definition.md) (+ HTML report alongside) |
| Per-feature build + reference code | [`product/2026-07-10-lancer-agent-build-roadmap.md`](product/2026-07-10-lancer-agent-build-roadmap.md) |
| Chat UI patterns (Orca/Happier/Omnara) | [`product/2026-07-09-chat-ui-port-map.md`](product/2026-07-09-chat-ui-port-map.md) |
| Receipt/contract spec | [`plans/2026-07-07-lancer-layers-0-3-implementation-spec.md`](plans/2026-07-07-lancer-layers-0-3-implementation-spec.md) |
| Siri / iOS 27 | [`plans/2026-07-09-siri-ios27-all-in-roadmap.md`](plans/2026-07-09-siri-ios27-all-in-roadmap.md), [`plans/2026-07-09-wwdc-ios-capability-inventory.md`](plans/2026-07-09-wwdc-ios-capability-inventory.md) |
| Evidence/proof workflow ideas (V2) | [`product/2026-07-07-harness-feature-borrow-report.md`](product/2026-07-07-harness-feature-borrow-report.md) |
| Cross-device QA | [`product/2026-07-09-cross-device-continuity-study.md`](product/2026-07-09-cross-device-continuity-study.md) |
| Backlog inventory | [`product/FEATURE_BACKLOG.md`](product/FEATURE_BACKLOG.md) |
| Device loop / owner test | [`LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md), [`product/OWNER_RELAY_TEST_GUIDE.md`](product/OWNER_RELAY_TEST_GUIDE.md) |
| Daemon contract / adapters | [`agent-contract.md`](agent-contract.md), [`adapter-spi.md`](adapter-spi.md), [`lancerd-resident.md`](lancerd-resident.md) |
| ADRs / threat model | [`architecture/`](architecture/), [`security/`](security/), [`SECURITY-REVIEW.md`](SECURITY-REVIEW.md) |
| Launch collateral (frozen) | [`PUBLISH_READINESS_CHECKLIST.md`](PUBLISH_READINESS_CHECKLIST.md), [`legal/`](legal/), [`distribution/`](distribution/) (ASC metadata lives under `distribution/APP_STORE_CONNECT_METADATA.md`) |
| Hook install artifacts (FUNCTIONAL — referenced by `daemon/lancerd/install.go`/`hook_install.go`; never delete) | `lancer-hook.sh`, `codex-lancer-hook.sh`, `claude-settings-hook.json`, `codex-hooks.json`, `opencode-lancer-gate-plugin.js`, `policy.example.yaml`, `opencode-hook-fixtures/` |

## Branch / worktree state (2026-07-10)

| Item | State |
|------|-------|
| `master` (`732071a7`+) | Layers 0–4 merged; iOS 26.0 target; source of truth for merged work |
| `feat/chat-overhaul-w0a` | Active; W0.A dogfood dirty — land in Phase 0 |
| `feat/frontend-scorched-wipe` (worktree) | **Abandoned** — frontend kept; remove in Phase 0 |
| `checkpoint/w0a-dogfood-pre-scorched-wipe` + `stash@{0}` | Safety checkpoint — keep until Phase 0 lands |
| `claude/amazing-mayer-246fef` | Do not wholesale-merge; cherry-pick only |
