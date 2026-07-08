# Lancer Layers 4–6 — lane proposal (pre-dispatch, awaiting owner approval)

2026-07-08 · Claude Fable 5 · Continues `2026-07-07-lancer-layers-0-3-implementation-spec.md`
(same lane grammar: exclusive write-sets, acceptance command per task, one worktree per lane).
Grounded in repo state at the Layers-0–3 merge tip + the 2026-07-07 relay-delivery fix.

**Status: owner decisions landed 2026-07-08 — see bottom.** Scope below reflects those decisions;
this doc supersedes its own original "Explicitly NOT proposed now" section on Proof Reel and the
iOS-27 lane. Read the bottom section first if you're picking this up fresh.

## Leftovers from Layers 0–3 (do these first, they're small)

| Task | What | Write-set | Accept |
|---|---|---|---|
| L0.A4 | Approve-and-remember (spec §D A4, verbatim — it was fully specified) | `daemon/lancerd/approval.go`, `policy/`, tests | `go test -run 'TestApproveAndRemember' ./...` |
| L0.D2 | Entity-aware intent refactor (spec §D D2 verbatim; D1 entities exist, intents never adopted them) | `Lancer/RunControlIntents.swift`, `Lancer/DenyLatestApprovalIntent.swift`, `Lancer/LancerAppShortcuts.swift` | build-clean + metadata grep + routing unit tests |
| L0.D3 | Read-only Siri additions (spec §D D3 verbatim) | `Lancer/StatusQueryIntents.swift`, `LancerAppShortcuts.swift`, IntentsKit queries | same as D2 |
| L0.DL | Deep-link routing fix — `onOpenURL` rejects the exact paths auth/billing emit (build-sequence §Layer-3 "small") | `AppRoot.swift` URL handling + a UITest | UITest: each emitted URL routes; invalid URL rejected |

## Lane E — Question Cards + Ladder (Layer 4 core)

The schema already reserves `answersReserved` in `lancer.proof/v0`; `blockingQuestion` attention
reason exists and is derived from status text today (heuristic). This lane makes questions first-class.

- **E1 (daemon):** first-class `question` event: new relay kind `agentQuestion` + `agent.question.answer`
  RPC; typed options (Ladder) with free-text fallback; vendor support degrades visibly
  (`confidence: bestEffort` pattern from receipts). Write-set: `daemon/lancerd/question.go` (new),
  `dispatch.go` (hook/stream-json extraction), `e2e_router.go`, `server.go`, tests.
  Accept: `go test -run 'TestQuestion' ./...` — claude fixture → typed question event; answer RPC
  unblocks; timeout falls back to the same fail-closed hold as approvals.
- **E2 (iOS, depends E1):** QuestionCardView on the work thread (ToolCardView chrome), options as
  buttons, free-text via composer; answer rides the approval channel shape. Write-set:
  `SessionFeature/Chat/QuestionCardView.swift` (new), bridge/store handling alongside
  `approvalPending`, `CursorWorkThreadView.swift`. Accept: exhaustive-tests case + persistence test.
- **E3 (voice-answer intent, depends E2; per trust line: confirmation-gated, read-back before send):**
  `AnswerQuestionIntent` in IntentsKit + app-target shortcut. Accept: build-clean + metadata grep +
  unit test for resolution; **no approve intent — permanent rule.**

## Lane F — Return-to-Desk packet (Layer 4) — **PAUSED 2026-07-08, do not dispatch**

Owner call: pause for now, no reason given beyond priority. Spec below is left intact for when
it's picked back up — do not re-derive it from scratch later.

One screen composing existing Layer-1 data (receipt, contract, branch/worktree state, open risks,
copy-continuation-command). No new daemon work (receipt already carries `git` + `resume`).
Write-set: `AppFeature/CursorStyle/CursorReturnPacketView.swift` (new), a row/entry point in
`CursorWorkThreadView.swift`, tests. Accept: exhaustive-tests case renders packet from a receipt
fixture; copy-command matches `continueArgv` strings. Design check with owner before build
(master-plan §9 open question stands).

## Lane G — Git/PR ship actions (Layer 4, highest risk)

Branch/commit/PR from phone via daemon `gh`/git execution behind the existing approval pipeline.
**Ship actions are high-tier by definition: in-app only, staged, content-hashed; merge-from-phone
is deferred entirely** (the single most dangerous action in the product — propose separately with
its own gate design). Write-set: `daemon/lancerd/shipactions.go` (new) + `e2e_router.go`/`server.go`
+ iOS action sheet (`CursorPRDetailView.swift` adjacent). Accept: `go test -run 'TestShipActions'`
— preflight (repo auth state) surfaces readiness; every action routes through the approval store
with `risk: high`; e2e loopback test proves phone-initiated branch+commit+PR round-trip against a
fixture repo.

## Lane H — Proof Reel, structured replay (elevated 2026-07-08 — headline feature, not interview-gated)

Owner override: this is now a priority feature, explicitly *not* waiting on interview evidence.
Scope is deliberately the **cheap version only** — the build-sequence doc's own recommended first
cut ("build the 30-second structured replay, not video, first"). Full video/frame capture is a
separate, larger ask — do not scope-creep into it here; propose it as its own lane later if wanted.

Reuses data already captured by the Layers 0–3 receipt pipeline — no new daemon events needed
beyond what `lancer.proof/v0` and (once Lane E lands) `agentQuestion` already carry.
- **H1 (iOS):** a scrubber/timeline view over a run's existing events — commands (with exit codes),
  files touched (with diff stat), criteria met/unmet/unknown, questions asked/answered (once E
  lands) — laid out in chronological order with play/scrub controls, not literal video frames.
  Write-set: `SessionFeature/Chat/ProofReelView.swift` (new), an entry point from `ReceiptCardView`
  (the existing "Open on desktop" action row is the pattern to extend). Accept: exhaustive-tests
  case scrubs a multi-event fixture and renders each stop correctly; screenshot at 3 scrub
  positions.
- **H2 (daemon, only if needed):** if the receipt's existing `commands[]`/`filesTouched[]`/
  `criteria[]` timestamps aren't granular enough for a smooth scrub (check before building
  anything — they may already be sufficient), add per-event ordering/sequence numbers to
  `lancer.proof/v0`. Write-set: `daemon/lancerd/receipt.go`. Accept: `go test -run 'TestReceipt'`
  — event ordering is stable and monotonic across a multi-command run.

## Lane I — iOS 27 App Intents, Phase 1 (elevated 2026-07-08 — approved to start now, not September)

Owner override: build this now, in parallel with iOS-26-safe work, not gated on the Sept GA prep
window the build-sequence doc originally assumed. **Architecture: one app, one App Store listing,
deployment target stays iOS 26** — new iOS-27-only APIs are adopted behind `@available(iOS 27, *)`
so the same binary keeps running on 26 devices and lights up extra capability on 27 devices (beta
testers now, everyone after ~Sept 14 GA). Do not raise the project's deployment target for this.

- **I1 — resurrect the parked Siri Phase 2 branch first, before writing anything new.**
  `ARCHITECTURE.md` §0.1 records that App Intents Phase 2 (RelevantEntities, App Shortcuts
  relevance, run-start intent) is **already implemented and device-tested** on
  `cursor/siri-phase2-fixes-9257` (PRs #16/#24) but was never merged, on the assumption that the
  deployment target had to move to 27.0+ first. Before building anything new: check out that
  branch, verify whether it actually requires a deployment-target raise or can be re-landed as-is
  with its iOS-27 symbols wrapped in `@available` (likely — App Shortcuts/App Intents providers
  commonly ship this way). If re-landable without the raise, this is close to a free win. If it
  genuinely can't be (real reason, not just historical caution), report why before proceeding.
  Accept: branch re-integrated to current tip or a clear written reason why not, either way with
  `xcodebuild build` clean on both iOS 26 and iOS 27 simulators.
- **I2 (depends I1):** the rest of the [26-safe] Siri Phase 1 slice from the original build-sequence
  §Layer 3e that Phase 2 didn't cover (if anything remains after I1).
- **I3 — new iOS 27 App Intents surface, current WWDC26 APIs (research before building):**
  `LongRunningIntent` (Siri-dispatched missions >30s with auto-Live-Activity progress —
  the original doc's "tell Siri to start work and walk away" moment), `IndexedEntityQuery` +
  Core Spotlight semantic search over runs/conversations, `SyncableEntity` (cross-device entity
  identity — pairs naturally with the existing CloudKit conversation-sync engine so the same
  run/approval resolves consistently from iPhone/Watch/Mac), and `AppUnionValueCasesProviding`
  (`@UnionValue` macro) if it simplifies the search/open intents' parameter picker. **Read the
  current WWDC26 App Intents sessions and API reference before implementing** — the framework
  moved between beta 1 and beta 3, and the repo's own wwdc26 audit was SDK-grepped, not
  session-video-sourced, so it may be missing latest-beta changes. **No approve intent, ever —
  permanent rule, unchanged by any of this.** Write-set: `Packages/LancerKit/Sources/IntentsKit/`,
  `Lancer/*Intents.swift`. Accept: `xcodebuild build` clean on iOS 27 simulator with the new
  intents' metadata registered (build-log grep, per the known `AppShortcutsProvider`-placement bug
  class); `swift test --filter IntentsKitTests` for query/entity logic.
- **I4 — verify, don't rebuild, what already works.** Live Activity and Dynamic Island are
  **already implemented and working** — landscape Dynamic Island layout shipped (`7595e264`), the
  "Live Activity ends after one turn" bug is fixed (`74f880e0`, owner-confirmed live on device),
  and the relay-delivery bugs found in the 2026-07-07 debugging pass are fixed. Before any new
  work here, run a quick confirmation pass (existing `RenderPreview` states + one physical-device
  check) rather than assuming something's broken. If iOS 27's Dynamic Island changes (compact/
  minimal now visible in landscape, `isDynamicIslandLimitedInWidth`) need anything beyond what's
  already built for the landscape fix, scope that as a small add here, not a rebuild.

## Explicitly NOT proposed now

- **Full Proof Reel video/frame capture** — Lane H is the structured-replay cut only; the heavy
  version stays a separate future proposal.
- **Layer 6 extras** — evidence-dependent, no dates.
- **Watch embedding — dropped from scope entirely (owner decision 2026-07-08)**, not just
  deferred. Do not schedule it after Lane E or anywhere else without being asked again.

## Dispatch plan (per the orchestration brief)

Composer 2.5 for E2, L0.D3, L0.DL, H1 (clear spec + mechanical acceptance); Sonnet 5
(`claude-sonnet-5-medium`) for E1, G, L0.A4, I1, I3 (protocol/security judgment or genuinely new
iOS-27 API surface); Fable reviews all lane merges + runs the exit bar, and does the WWDC26
research pass for I3 itself before writing that lane's subagent prompt (this is exactly the kind
of "read the current docs, decompose, then dispatch" work Fable should not delegate). Lanes
E/G/H/I parallel (disjoint write-sets — confirm I1/I3 don't touch anything E/G/H also own before
dispatching both); L0 leftovers land first, serially (D2/D3 share `LancerAppShortcuts.swift`, and
I1's branch resurrection likely also touches Siri-adjacent files — sequence L0.D2/D3 and I1
against each other explicitly, don't assume they're independent just because they're different
lanes). Lane F stays parked, no dispatch.

## Exit bar (Layer 4, updated)

1. `cd daemon/lancerd && go test ./...` clean
2. `cd Packages/LancerKit && swift test` clean
3. Exhaustive UI tests incl. question card + proof-reel cases, screenshots in `docs/test-runs/`
4. `relay-approval-e2e.sh` extended with a question round-trip assertion — PASS
5. Sim walk: dispatch → question → voice-answerable → receipt → proof reel scrub
6. `xcodebuild build` clean on both an iOS 26 and an iOS 27 simulator (new — proves the
   single-binary availability-gating approach actually holds, not just compiles on one SDK)
7. Owner device run of the question loop recorded in `docs/test-runs/`

## Owner decisions — answered 2026-07-08

1. Lanes E/G/H/I approved as scoped above. Lane F (Return-to-Desk) paused — spec kept, not
   dispatched. Watch embedding cut from scope entirely.
2. Return-to-Desk design check: moot while paused: revisit when un-paused.
3. Git ship actions: confirmed, merge-from-phone stays out of scope. Reason (for anyone picking
   this up without the chat history): merge is irreversible in a way approve/deny/pause aren't — a
   wrong deny just re-asks, a wrong merge rewrites shared history. It also doesn't yet have the
   protocol-level compensating controls (in-app-only staging, content-hash binding at the specific
   merge-commit level) that make phone-approved actions safe elsewhere in the trust line, and
   repo-auth state (SSH keys, `gh` login) varies per machine, so a phone-initiated merge could fail
   destructively mid-action on an unprepared host. It's deferred because the gate design doesn't
   exist yet, not because it's hard to code.
4. Proof Reel: build now (Lane H), structured-replay scope only, not interview-gated.
5. iOS 27 features: build now, single-app/availability-gated architecture (not two separate
   builds), starting with resurrecting the already-built Siri Phase 2 branch (I1) before any new
   iOS-27 work.
6. No marketing/demo-capture task added to scope — owner will capture their own demo content once
   features land.
