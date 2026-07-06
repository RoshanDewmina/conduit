# Lancer consolidated status — 2026-07-06

Compiled from Codex session `019f3763-db95-77e0-bee2-6fae3224a4cf`, subagents Fermat (chat synthesis) and Bacon (feature inventory), plus verification on branch `codex/tier-0-live-cursor-shell`.

Canonical tactical sources: [ARCHITECTURE.md](../../ARCHITECTURE.md) §0.1 + §4.1, [feature gap matrix](2026-07-06-feature-implementation-gap-matrix.md), [PUBLISH_READINESS_CHECKLIST.md](../PUBLISH_READINESS_CHECKLIST.md).

---

## 1. Chat synthesis (what the referenced conversations decided)

### Source limitation

Cursor conversation `bc-2860762c-7b0f-49de-8e23-2f1b3c102faa` was **not** available as a normal transcript locally. Evidence came from Cursor cloud-agent metadata, plan registry, and the associated worktree diff. Claude Code sessions referenced from that thread were read via local JSONL transcripts.

### Core product decision

- **V1 wedge:** phone steers, reviews, approves, and continues agent work — **not** a phone IDE.
- **Immediate engineering priority:** prove **Tier 0** through the live Cursor shell (`LANCER_CURSOR_SHELL_LIVE=1`).
- **Tier 0 exit criteria:** pair → dispatch prompt → receive approval → approve/deny → follow-up/continue against real `lancerd`.
- **Freeze Tier 2** until Tier 0 is proven: Away Mode, Proof Suite/Reel, Git/PR ship actions, Siri fast-follow, Watch, further IA redesign.

### Worktree warning

Do **not** merge `.claude/worktrees/amazing-mayer-246fef` wholesale. Useful commits/docs may exist, but the uncommitted diff is deletion-heavy (settings, onboarding, chat history, observed sessions, run-detail, legacy sidebar). Cherry-pick verified slices only. See [amazing-mayer audit](../design-audit/view-sweep-2026-07-06/amazing-mayer-worktree-audit.md).

### Stale / superseded docs

- iOS deployment target is **26.0** in `project.yml` (not 27 despite older doc wording).
- Cursor shell is **merged**; "future merge" language in July 4/5 docs is stale.
- `docs/LANCER_PROJECT_DOSSIER.md` is archived — do not cite.
- Tab bar / Control / Activity roots are vestigial; home is sidebar + New Chat (or Cursor shell in DEBUG/live modes).

### Session implementation outcomes (Codex 2026-07-06)

| Slice | Branch | Status |
|-------|--------|--------|
| Tier 0 live Cursor shell wiring | `codex/tier-0-live-cursor-shell` | Committed + simulator UI test PASS |
| BiometricGate fail-closed (P0) | same | Committed; 8 tests PASS |
| Daemon atomic emergency stop (P0) | same | Committed; `go test ./...` PASS |
| Consolidated doc (this file) | same | This commit |
| Full device governed loop | — | Owner-gated; see [proof run](../test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) |

---

## 2. Feature inventory

### Implemented (production backend + core app)

| Area | Summary |
|------|---------|
| **Product shape** | Three layers: iOS app, `lancerd`, push-backend + agent-runner. Phone steers/approves; execution on owned machines. V1 transport = blind E2E relay. |
| **Navigation shell** | Sidebar + durable New Chat (legacy). Cursor shell merged under DEBUG flags (`LANCER_CURSOR_SHELL`, `LANCER_CURSOR_SHELL_LIVE`). |
| **Chat & threads** | `ConversationSyncCoordinator`, persistent mirrors, follow-up, artifacts, run controls, host-ledger refresh. |
| **Governed approvals** | Daemon policy fail-closed; deny > ask > allow; content-hash decisions; inbox with relay/SSH routing. |
| **Audit** | Append-only JSONL with hash chain, verify, export. |
| **Relay / C2** | Pairing, E2E relay, dispatch/files/commands/run-control RPCs over relay. |
| **Daemon dispatch** | Explicit argv for Claude/Codex/Kimi/OpenCode; dispatch, cancel, pause, resume, continue, observed-session resume. |
| **Conversation ledger** | Host-authoritative SQLite; CloudKit mirror only. |
| **Notifications** | APNs, actionable approvals, Live Activities, push-to-start. |
| **Security** | TOFU, Keychain, biometric gates, App Attest work, artifact hardening, secret redaction. |
| **Settings / account** | Sync engines, backend URL, SSH keys, relay fleet, emergency stop UI, policy presets. |
| **CloudKit** | Host/snippet sync + conversation mirror (mirror layer, not execution truth). |
| **Worktrees** | Daemon RPCs for create/remove/list; iOS surfaces metadata. |
| **Platform** | iOS 26.0, Swift 6.2 strict concurrency, widgets, Live Activities, watch target defined. |

### Partial / debug / proof-gated

| Area | Status (2026-07-06 evening) |
|------|----------------------------|
| **Cursor live shell** | Wired through `CursorShellLiveBridge`; simulator live-shell UI test PASS; device install + launch PASS; device UI test needs fixture-tolerant assertions. |
| **Cursor mock Tier 1** | Onboarding, PR diff, search, composer chain — UI/tests exist; not all live-backed. |
| **BiometricGate** | **Fixed** on `codex/tier-0-live-cursor-shell` — fail-closed on no-passcode / biometry unavailable. |
| **Emergency stop** | **Fixed** on same branch — daemon latch blocks new launches + cancels active runs. |
| **CloudKit two-device QA** | Code present; hardware QA not verified. |
| **JWT auth** | HS256-only (P1). |
| **Watch app** | Target exists; not embedded in iOS app (P1). |
| **Relay E2E harness** | `relay-approval-e2e.sh` fails — legacy Inbox tab assertions incompatible with Cursor shell navigation. |
| **Vendor CLI drift** | Continue/resume argv implemented; per-vendor live smoke still needed. |

### Planned / deferred (V1 scope boundary)

- Away Launch Composer, Proof Suite/Reel, Mobile QA, Question Cards, Git/PR/Merge ship actions, Flight Recorder
- Hosted-cloud execution V2 (retained code, unwired)
- Full interactive terminal, SFTP, preview, port forwarding
- First-class Loop primitive; broader vendor abstraction / open-source `lancerd`
- External beta gates: remote-host E2E, StoreKit TestFlight purchase, security review, two-device CloudKit QA

### Deprecated / superseded

- Tab bar IA (`enum Tab` vestigial)
- Quarantined tab-navigation UI tests
- Archived dossier and pre-Cursor design handoffs (context only)
- `PreviewFeature` and dead split-shell files
- Phone-as-terminal product framing

---

## 3. Recommended next actions

1. **Owner manual proof:** pair → dispatch → approval → continue on physical iPhone with live shell + running `lancerd` ([runbook](../LIVE_LOOP_RUNBOOK.md)).
2. **Fix harnesses:** device-tolerant live-shell UI test; relay E2E for Cursor-shell approval surface.
3. **Integration decision:** cherry-pick from `codex/tier-0-live-cursor-shell` into any simplification branch — do not wholesale-merge `amazing-mayer`.
4. **Hold Tier 2** until B10 in publish checklist is closed.

---

## Source index

| Source | Role |
|--------|------|
| Codex `019f3763-db95-77e0-bee2-6fae3224a4cf` | Parent session; Tier 0 plan + implementation |
| Subagent Fermat `019f3787-36f6…0c78` | Chat/history synthesis |
| Subagent Bacon `019f3787-5563…ecdf` | Feature inventory (base for §2) |
| Subagent Goodall `019f3787-7130…6836` | BiometricGate P0 fix |
| Subagent Ohm `019f3787-8c6f…1732` | Emergency stop P0 fix |
| [Tier 0 proof run](../test-runs/2026-07-06-tier-0-live-cursor-shell-proof.md) | Verification evidence |
