# Lancer — agent build roadmap with reference implementations (2026-07-10)

**Audience: AI agents executing build tasks.** Read this before architecting any feature below.
Direction and scope authority: [`2026-07-10-lancer-daily-driver-definition.md`](2026-07-10-lancer-daily-driver-definition.md)
(owner-confirmed; supersedes pre-07-10 strategy framing). This doc adds the **how**: for each
feature, the best already-engineered reference implementation in our local competitor clones,
so agents port proven designs instead of guessing architecture.

**Wedge (do not drift from it):** "Don't watch your agents — govern them." Competitors are
remote chat windows for *watching*; Lancer is the governed gate console for the time you're
*not watching* (loop supervision: approvals, questions, verdicts, kill — from pocket/lock
screen/Siri). Chat is the vehicle and must be good; it is not the differentiator.

---

## 0. Reference codebases — index, licenses, standing rules

Clones live at `research-repos/` (canonical, gitignored). `research_repos/` has extras.

| Repo | Stack | License | Best donor for |
|---|---|---|---|
| `research-repos/happier` | React Native + TS, E2E-encrypted seq-event sync | MIT in clone (`LICENCE`, "Happy Coder Contributors") — **re-verify file before any verbatim reuse; default to patterns-only** | Sync protocol, streaming, tool-call state machine, permission/auto-approve matrix, stop ladder, attachments, push tokens |
| `research-repos/orca` | Electron + TS, PTY-scraping harness | **MIT** — logic portable verbatim with attribution | Auto-scroll math, streaming overlay rule, tool fold/summary, transcript tail-follower, session-resume CLI evidence |
| `research-repos/omnara` | RN mobile + FastAPI/Postgres | **Apache-2.0** — portable with attribution + NOTICE (README marks it deprecated; still a complete reference) | Push notification backend/preferences, derived-offline liveness, markdown preprocessing, read cursors, notify-then-re-read |
| `research_repos/vibe-kanban` | Rust (executors/git/git-host crates) | check `LICENSE` in clone | Loop/task orchestration board, executor abstraction, git-host (PR) integration — Phase 3 loop-supervision reference |

**Rules for all ports (repo standing policy):**
1. **Patterns, schemas, state machines, thresholds — yes. UI pixels/JSX — never.** All three are
   React; nothing renders in SwiftUI anyway.
2. Attribution comment at the port site (`// Pattern from orca <path> (MIT)`); Apache-2.0 ports
   also get a NOTICE line. Never commit competitor code files.
3. Prior-art docs are already written — **read them before re-mining the clones:**
   - [`2026-07-09-chat-ui-port-map.md`](2026-07-09-chat-ui-port-map.md) — 9 chat gaps × 3 repos, exact file:line, ranked steal list. **The chat bible.**
   - [`2026-07-07-harness-feature-borrow-report.md`](2026-07-07-harness-feature-borrow-report.md) — evidence/proof workflow ideas (Proof Matrix, PR Proof Packet).
   - [`2026-07-09-cross-device-continuity-study.md`](2026-07-09-cross-device-continuity-study.md) — continuity QA.
4. Verify against the clone at read time — cited line numbers drift.
5. Evidence gate unchanged (AGENTS.md): no "done" without the command + output.

**Architecture posture (why we don't copy their backends wholesale):** Happier's shipped sync
(seq event log, localId reconciliation, version-conflict) is architecturally identical to our
host ledger (`conversation_events.seq`, `clientTurnID`, `SyncState.conflict`) — independently
arrived at, validated, build on it with confidence. Orca's PTY-scraping is structurally weaker
evidence than our hook/stream-json path — never regress toward scraping. Omnara is
server-authoritative Postgres — wrong trust model for us (our relay is blind/E2E); borrow its
*client* patterns only.

---

## Phase 0 — git hygiene (a day) · no reference code needed

Land in-flight W0.A deliberately · remove the abandoned wipe worktree (`feat/frontend-scorched-wipe`)
· the 07-10 scorched-wipe HANDOFF is superseded and was deleted in the 07-10 docs purge — **no
agent deletes frontend chrome without a fresh owner ask** · `build_sim` green on the kept frontend.

## Phase 1 — dogfood MVP (weeks 1–2)

Goal: owner completes pair → dispatch → approve → follow-up → review on a physical phone,
5 days of 7. Fix only what the dogfood log surfaces. Features + references:

### 1.1 Chat thread finesse (streaming, markdown, tool cards, indicators, scroll, stop)
Port map is authoritative; execute its ranked steal list in order:
1. **Streaming dual-throttle + synthetic-overlay** — Happier `apps/ui/sources/components/sessions/transcript/streaming/useStreamingTextSmoothing.ts` (+`useThrottledStreamingMarkdownText.ts`); Orca `src/shared/native-chat-streaming.ts`. Frame-paced commits; markdown re-parse behind 250–400 ms settle; overlay wins only while longer than persisted text.
2. **Auto-scroll policy + jump-to-latest** — Orca `src/renderer/.../native-chat-autoscroll.ts` (pure functions, MIT, port verbatim: 48 pt near-bottom; follow-only-when-near); Happier's unread-count badge.
3. **Tool-call cards** — Happier `apps/ui/sources/sync/reducer/phases/toolCalls.ts` (id-paired start/result, **orphan-result buffer**, `running|completed|error` + permission overlay) + Orca `native-chat-tool-fold.ts`/`native-chat-tool-summary.ts` (fold + one-line summary, 4 KB result cap) + auto-expand-only-small-groups (`resolveToolCallsGroupAutoExpandPolicy.ts`).
4. **Markdown preprocessing** — Omnara `apps/web/src/components/dashboard/markdownConfig.tsx:11-25` (`preprocessMarkdown`: unicode bullets, wrap vendor `*** Begin Patch` in ```diff fences) as a pure `String -> String` pass; Happier `CodeBlockViewFrame.tsx` per-block copy w/ 1.5 s check state.
5. **Stop ladder + derived-offline** — Happier `sync/ops/sessionStopStrategy.ts` (3-tier: kill-RPC → session RPC → best-effort mark-ended; UI always lands in stopped state) + Omnara `ChatWorkingIndicator.tsx:13-29` (liveness derived from heartbeat TTL, never trusted from stored status — show "host unreachable", not an eternal spinner).
Working-indicator enum per Orca `native-chat-live-status.ts:26-77`: `starting/thinking/toolRunning(name)/streaming`, mutually exclusive with streamed text.

### 1.2 Push approvals incl. lock screen (re-prove on tip)
Ours is already ahead (content-hash binding, risk tiers, `IntentAuthenticationPolicy` — merged,
device-proven 07-08 on `732071a7`). References for the edges:
- Omnara push backend shape: `src/backend/api/push_notifications.py`, `src/servers/shared/notification_utils.py` / `notification_base.py`, mobile `apps/mobile/src/services/notifications.ts` + `NotificationSettingsScreen.tsx` — per-user notification **preferences** model worth mirroring in Settings.
- Happier `apps/ui/sources/sync/domains/state/pushTokenRegistration.ts` — token re-registration lifecycle (our known Live-Activity token-churn issue is the same class).
- Approve-and-remember semantics: Happier permission test matrix (`packages/tests/suites/providers/harness.permissionAutoApprovePolicy.test.ts`, `providerSpecs.permissionModePromptMatrix.test.ts`, `harness.permissionBlockTimeout.test.ts`) — port the **test matrix shape** (per-vendor × per-mode × timeout) into our Go policy tests; our scoped-with-expiry allow rules are stronger than their `allowedTools` — keep ours.
Acceptance: fresh `docs/test-runs/` device proof on current tip (Tier 0 + 5c).

### 1.3 Composer + thread list + emergency stop
Engines exist. Thread list ordering = existing `AttentionReason` priority (approval > question >
failed > auth/credits > receiptReady > working). Omnara's `last_read_message_id` read-cursor
(`src/shared/database/models.py:157-166`) is the reference for unread state on the list.
**All-clear honesty rule stands:** never render "all clear" over a stale relay — as-of timestamp
when degraded (product rule from Layers spec §C).

### 1.4 Dogfood log (new, tiny)
`docs/dogfood-log.md`: one line/day — dispatches, lock-screen approvals, phone follow-ups, every
"reached for the laptop instead" moment. Each laptop-reach is a bug or scope insight. Agents:
when the owner reports one, file it against the relevant feature here.

## Phase 2 — hands-free + trust surfaces (weeks 3–4) · the wedge made visible

### 2.1 Siri Phase 1 polish (26-safe slice — ALREADY MERGED, dogfood + fix)
IntentsKit entities D1–D3, voice-answer E3, CoreSpotlight I2 are on master. Work = polish against
real use, not build. **No approve intent, ever. No Face ID reintroduction.** Freshness rule:
intents must surface staleness ("as of 2 min ago; machine unreachable") — pair with the Omnara
derived-offline pattern above. No competitor has any of this (all React Native) — **uncontested
surface; our own merged code is the reference.**

### 2.2 Live Activities into the daily loop
No competitor reference exists (RN). Our own prior work is the reference: push-to-start sender
in `daemon/push-backend/liveactivity.go`, token forwarding `AppRoot.swift`, risk-gated buttons in
`LancerLiveActivityWidget.swift`. Constraints (verified 07-07): 8 h active +4 h lock-screen cap →
re-start-via-push for long loops; sparse updates (stage changes, not ticks) to respect push
budgets; low-risk-only inline approve, else "Review in Lancer" deep link.

### 2.3 Receipt card + contract echo (backend done — `lancer.proof/v0`)
Spec: `2026-07-07-lancer-layers-0-3-implementation-spec.md` §C1–C3, B3–B4 (still the build spec;
receipt daemon+types merged, card UI died in the wipe → rebuild per B3 on the kept shell).
Mobile-review insight from research: **verdict-first beats diff-first on a phone** — criteria
✓/✕/○ + tests + files, evidence on demand; Omnara's raw-diff review fights the form factor.
Diff rendering when needed: Happier's rendered-diff ↔ raw toggle with byte-budget gate
(`MarkdownCodeBlock.tsx:19-22,101-148`).
A wrong "met" is the product's worst failure — keep v0's honest `unknown` semantics.

### 2.4 Context/budget sheet (small, differentiator)
Happier `agentInput/contextWarning.ts` — port thresholds verbatim (warn ≤10 %, critical ≤5 %
context remaining) + `TokenUsageRing`. Wire cost against our `budgetUSD` for a **budget-fullness
ring** — governance surface none of the three ship.

### 2.5 Sync refinements (from port map gap 9 — cheap, do alongside)
(1) persistent-vs-**ephemeral** event split (Happier `docs/protocol.md`) — typing/thinking/usage
ticks never become ledger rows; (2) **notify-then-re-read** (Omnara `agents.py:260-409`) — a push
means "fetch since seq," never "trust the push payload"; (3) Orca `transcript-watch.ts:1-255`
tail-follower (byte-offset, complete-lines-only, truncation reset) when the daemon tails vendor
JSONL for tool events.

## Phase 3 — Aug→Sept: deep Siri lane + loop supervision + the fork

### 3.1 iOS 27 deep Siri (Apple-gated ~Sept 14 GA; prep in August)
`LongRunningIntent` Siri-dispatched runs · `IndexedEntityQuery` semantic search over runs ·
Foundation Models advisory copilot (never authoritative; availability fallback mandatory).
Reference: our own `docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md` + WWDC inventory.
AppIntentsTesting first (regression-guards the two Siri bug classes already hit).

### 3.2 Loop supervision (owner-agreed direction, 07-10)
Lancer supervises loops; it does not construct them (Conductor/CLI/Ralph plugins own that).
- **Observed loops:** extend observed sessions (J1/J2, merged) to import Conductor/CLI-launched
  worktree sessions → "keep Conductor; Lancer is its pocket gate console."
- **Loop-aware thread state:** iteration count, criteria status, budget burn on the thread row.
- Reference: `research_repos/vibe-kanban` crates (`executors/`, `git/`, `git-host/`) for
  orchestrator/task-board/PR-integration shapes; our contract `doneCriteria` + receipt already
  *is* the Ralph exit condition — render it as such.
- Dogfood experiment (owner): run one Ralph-style loop with a contract; gate it entirely from
  the phone for a day. Magical → double-down signal.

### 3.3 The fork (with evidence)
Usage log + dated competitive re-check (all three clones + fresh web: has anyone closed
own-subs + own-machines + OpenCode + governed hands-free?) → product (outreach, pricing unfreezes)
or tool (open-source/portfolio). Pricing/team/billing stay frozen until here.

## V2 backlog (owner-flagged, not scheduled)

- **Easy-proof / shareable proof packet** (owner, 07-10: "consider, maybe V2") — one-tap share of
  a receipt as PR comment / link. Reference: borrow report §"PR Proof Packet" + receipt schema;
  ship actions remain high-tier gated.
- Question Ladder typed-options UI · attachments pipeline (Orca drop-dir transport
  `native-chat-image-paste.ts` now, Happier draft state machine `attachmentDraftModel.ts` when
  composer matures) · voice input (Omnara `VoiceInputVisualizer.tsx` is UI-only; real work is
  dictation-confirm flow) · Proof Reel (only if receipts prove insufficient) · team tier ·
  hosted-cloud.

---

## Standing constraints (unchanged, for every phase)

No Siri approve intent · no Face ID reintroduction · voice-approve permanently rejected ·
fail-closed on mutating kinds · never "all clear" on stale data · UI copy says "asked of the
agent," never "guaranteed" · daemon `dispatch.go` changes go through `vendor-cli-adapter-audit`
skill · parallel agents never share write-sets · evidence before "done."
