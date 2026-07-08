# Lancer Layers 0–3 — Cursor-executable implementation spec

2026-07-07 · Claude Fable 5 · Third doc in the set (verdict → build sequence → **this: the how, exactly**)
Grounded in code read today at `master` `54a31915`: `AppRoot.swift`, `LiveActivityManager.swift`, `LancerLiveActivityWidget.swift`, `ApprovalActionIntent.swift`, `E2ERelayMessage.swift`, `LancerDProtocol.swift`, `ChatConversation.swift`, `ChatConversationRepository.swift`, `AppDatabase.swift`, `CursorThreadAttention.swift`, daemon `approval.go` / `dispatch.go` / `policy/types.go` / `hook.go` / `server.go` / `conversation_rpc.go` / `e2e_router.go`, push-backend `liveactivity.go` — plus line-level reads of happier's `permissionHandler.ts` / `permissionRpc.ts` / `encryption.ts` and lfg's `tmux.ts` / `sessions.ts`.

---

## A. The one thing to confirm before dispatch

**Only item that requires Milroy, not Cursor:** run the physical-device Tier 0 checklist (`docs/test-runs/2026-07-07-tier0-owner-checklist.md`) after task D0.1 below corrects it. Steps 4–5 (approve on device, APNs lock-screen approve) cannot be automated. Everything else in this spec is decided; no other owner input is needed.

---

## B. Corrections — where the prior docs are wrong about the code

The build-sequence doc (and the 07-02/07-03 audits it drew from) is stale on six points. **Cursor: trust this table over those docs.**

| Prior claim | Reality in code today |
|---|---|
| "`.end()` on background breaks push-driven Live Activities" (Layer 3a) | **Already fixed.** `AppRoot.swift:340` explicitly does *not* end activities on background (comment documents the one-way-terminal reasoning). 3a is done; do not re-do it. |
| "Content-hash binding is missing" (Layer 3d / ranking #1) | **Built end-to-end.** `approval.go:45,55,71` — `ContentHash` (SHA-256 over `command\x1f patch\x1f cwd\x1f toolInput`) set at creation, echoed in `ApprovalDecision`, verified in `resolve()`; mismatch = logged security event, decision rejected non-destructively. Swift side mirrors it (shared test vectors, `content_hash_test.go`). |
| "8s fail-open grace window approves anything" (ranking #2) | **Fixed.** `hook.go:165` — mutating kinds (incl. command/bash) always hold; read-only kinds fail open only with explicit `LANCER_HOOK_READONLY_FAIL_OPEN=1`. |
| "No riskLevel in Live Activity content state; buttons not risk-gated" (Layer 3c / #7) | **Built.** `LancerSessionAttributes.ContentState.pendingApprovalRisk: Int?` (0–3); widget renders elevated-risk badge + different button set (`LancerLiveActivityWidget.swift:120–324`); `ApprovalActionIntent` applies `IntentAuthenticationPolicy.requiresAuthentication` for approve (fails closed on unknown risk), reject stays unauthenticated, `openAppWhenRun = true` — so the widget-extension-can't-relay problem is already designed around: approve opens the app. |
| "push-backend has no `event:"start"` sender; relay path registers wrong token type" (Layer 3b / #5–6) | **Built.** `liveactivity.go` sends `start`/`update`/`end` with `attributes-type`/`attributes`/`alert`, correct `apns-topic` suffix; push-to-start tokens registered per install; `AppRoot.swift:1634–1650` forwards activity tokens over *both* daemonChannel and relay bridge; `activityTokenRegister` is an E2E relay kind. |
| "Face ID removed entirely, device unlock is the only check" | **Half-true.** The *in-app* biometric gate is gone (`9e18d679`). The *system-mediated* auth on lock-screen approve (`IntentAuthenticationPolicy`) remains and is correct. The owner checklist's step 4 wording ("Approve with Face ID" in-app) is what's stale. |

Consequence: **Layer 3's daemon/push work is ~80% done.** What actually remains across Layers 0–3: the Proof Receipt pipeline (nothing exists — no receipt/summary anywhere in `lancerd` or `LancerCore`), Home needs-you ordering (enum exists at `CursorThreadAttention.swift`, no priority/sort logic), contract passthrough (no contract fields in `dispatchParams`), Siri entities (zero `AppEntity` in production — `RunControlIntents.swift:10` admits it), and one doc fix.

Apple facts, settled: Live Activity = **8h active max, +4h Lock Screen persistence (12h total)** — confirmed against Apple docs/forums; long runs need re-start-via-push after 8h (noted in A4, not a blocker). Push-to-start payload shape — verified by Lancer's own working sender + tests; no action. View Annotations OS gate — still unverified, **irrelevant here** (Layer 5, Sept lane); do not depend on it.

Competitor patterns adopted (from code, not marketing): from **happier** — `PermissionRpcPayload`'s `answers: Record<string,string>` (structured question-answering rides the *same* approval channel — reserved in our schema below, built in Layer 4) and `allowedTools`/`updatedPermissions` ("approve and remember" → task A4, mapping onto Lancer's existing scoped allow-always policy rules with expiry, which happier has no equivalent of); versioned byte layouts everywhere (we version the receipt schema from day 0). From **lfg** — machine-readable blocked reasons (`"model_unavailable" | "out_of_credits" | "provider_auth" | "provider_error"`, detail capped 180 chars) → adopted verbatim into the attention model (task C1); their tmux-pane-scraping approach confirms Lancer's hook/stream-json path is structurally better evidence — left behind.

---

## C. Fixed contracts (all lanes code against these; do not renegotiate mid-task)

### C1. `lancer.proof/v0` — the run receipt

Daemon → phone, emitted once per run at terminal status. JSON-RPC method `agent.run.receipt` (SSH path) and new E2E relay kind `runReceipt` (relay path). Also fetchable via `agent.run.receipt.get {runId}` for reconnecting clients.

```json
{
  "schema": "lancer.proof/v0",
  "runId": "r-...", "conversationId": "c-...",
  "agent": "claude", "model": "sonnet",
  "startedAt": "2026-07-07T18:01:02Z", "endedAt": "...", "exitCode": 0,
  "status": "completed",
  "contract": {
    "goal": "Fix the flaky relay reconnect test",
    "doneCriteria": ["go test ./... passes", "no new lint warnings"],
    "validationCommands": ["go test ./..."]
  },
  "commands": [
    {"command": "go test ./...", "exitCode": 0, "kind": "test", "startedAt": "..."}
  ],
  "filesTouched": [{"path": "daemon/lancerd/conn.go", "additions": 12, "deletions": 3}],
  "tests": {"ran": true, "passed": 42, "failed": 0},
  "criteria": [
    {"text": "go test ./... passes", "status": "met", "evidence": "go test ./... exit 0"},
    {"text": "no new lint warnings", "status": "unknown", "evidence": null}
  ],
  "git": {"startRef": "abc123", "endRef": "def456", "dirtyAtStart": false, "worktreePath": null},
  "confidence": {"commands": "complete", "files": "complete", "tests": "bestEffort"},
  "resume": {"agent": "claude", "vendorSessionId": "..."},
  "answersReserved": null
}
```

Decisions baked in (rationale, one line each): `status` ∈ `completed|failed|stopped|budgetExceeded` — mirrors existing `agent.run.status` semantics. `criteria[].status` ∈ `met|unmet|unknown`; v0 marks `met`/`unmet` **only** when a `validationCommands` entry string-matches a run command (normalized whitespace) and exited 0/non-0 — anything else is `unknown`, because a wrong "met" is the product's worst failure. `confidence` per section ∈ `complete|bestEffort|unavailable`, set per vendor (claude = `complete` for commands — stream-json `item.completed` is lossless; codex/kimi/opencode = `bestEffort`; see `dispatch.go:734,760`). `filesTouched` from `git diff --numstat <startRef>` — vendor-independent, so `files` is `complete` whenever the CWD is a git repo, `unavailable` otherwise. `answersReserved` is a reserved key for Layer 4 Question Cards (happier's `answers` pattern) — present and null so v0 parsers tolerate it. Hard cap: serialized receipt ≤ 32 KB (matches the existing 64 KB artifact payload cap with headroom); `commands` truncates oldest-first past 50 entries with `"truncated": true`.

### C2. Contract on dispatch

Extend `dispatchParams` (`dispatch.go:220`) — wire-compatible (new optional key):

```go
Contract *runContract `json:"contract,omitempty"`

type runContract struct {
    Goal               string   `json:"goal"`
    DoneCriteria       []string `json:"doneCriteria,omitempty"`       // ≤ 8 entries, each ≤ 200 chars
    ValidationCommands []string `json:"validationCommands,omitempty"` // ≤ 4 entries
}
```

No enforcement in v0 — display + receipt-echo only. UI copy must say "asked of the agent", never "guaranteed" (enforcement is a later, separate feature).

### C3. iOS artifact representation

`ChatArtifact.Kind` (`ChatConversation.swift:254`) gains `case receipt` (raw `"receipt"`). The `kind` column is TEXT — **no GRDB migration needed**; older builds decode unknown kinds… verify: `Kind` is a non-optional enum decoded from raw — older app builds would fail to decode a `receipt` row. Acceptable: forward-compat for old builds is out of scope, and decode failures in `artifacts(conversationID:)` must skip-not-throw (task B1 makes that explicit). Receipt payload persists as `payloadJSON` (already capped at 64 KB by `ChatConversationRepository.upsertArtifact`).

### C4. Attention reasons (Home ordering)

```swift
public enum AttentionReason: String, Codable, Sendable {
    case pendingApproval, blockingQuestion, runFailed, providerAuth,
         outOfCredits, modelUnavailable, providerError, receiptReady, none
}
```

Priority order for Home sort (highest first): `pendingApproval` > `blockingQuestion` > `runFailed` > `providerAuth` = `outOfCredits` = `modelUnavailable` = `providerError` > `receiptReady` > working > ready > idle. One-line `detail: String?` capped at 180 chars (lfg's cap — long errors are unreadable in a row).

---

## D. Task list

Ground rules (repo's own): parallel agents never write the same file; every task ends with its acceptance command run and output pasted; a subagent's "done" without evidence is not done. Lane = one git worktree. **File ownership per lane is exclusive for the duration of the layer** — the lists below are the write-sets; read anything, write only your own.

### Lane 0 — serial, first, trivial (main branch, direct)

**D0.1 — Fix the stale owner checklist.**
Modify: `docs/test-runs/2026-07-07-tier0-owner-checklist.md` only.
Change step 4 to: "tap through to Review and **Approve** (in-app; no biometric gate — removed `9e18d679`)"; note on step 5 that lock-screen **approve** may present system authentication (`ApprovalActionIntent` `.requiresAuthentication`), **reject** will not.
Accept: `grep -c "Face ID" docs/test-runs/2026-07-07-tier0-owner-checklist.md` returns occurrences only in the corrected system-auth note (≤1), and the doc's automated-coverage claims still match `git log` reality.

**D0.2 — Owner runs the checklist** (Milroy, ~5 min; see §A). Blocks nothing below from *building*, but blocks the layer from being declared shipped.

### Lane A — daemon (Go) · worktree `spec/receipt-daemon`

Write-set: `daemon/lancerd/receipt.go` (new), `receipt_test.go` (new), `dispatch.go`, `server.go`, `e2e_router.go`, `conversation_store.go`, testdata additions. No other lane touches Go.

**A1 — Run-evidence accumulator.**
Create `daemon/lancerd/receipt.go`: `type runReceipt struct` mirroring C1 exactly (one Go struct, `json` tags matching the schema byte-for-byte). Hook accumulation into `wrapEmitForRun` (`dispatch.go:941`) — intercept `agent.tool.start` / `agent.run.output` (`item.completed` for claude, per-vendor branches at `dispatch.go:734,760`) to collect `commands[]`; classify `kind: "test"` by first-token match against `{go test, swift test, pytest, npm test, yarn test, cargo test, xcodebuild test}` (fixed list, v0). Capture `git.startRef` + `dirtyAtStart` in `runDispatch` immediately after worktree resolution (`git rev-parse HEAD` / `git status --porcelain` in the resolved CWD; both nil-safe when not a repo). At terminal status (the `onRunTerminal` path, `dispatch.go:959`): run `git diff --numstat <startRef>` for `filesTouched`, evaluate `criteria` per C1's match rule, set per-vendor `confidence`, emit.
Accept: `cd daemon/lancerd && go test -run 'TestReceipt' ./...` passes with new tests covering: claude fixture run → `confidence.commands == "complete"` + correct commands; opencode fixture → `"bestEffort"`; non-git CWD → `files: "unavailable"`; validation command exit 0 → criterion `met`; no validation command → `unknown`; 51 commands → truncation flag. Plus full `go test ./...` clean.

**A2 — Emit + fetch + relay plumbing.** (depends A1)
Modify `server.go` (add `agent.run.receipt.get` to the RPC switch near `:908`), `e2e_router.go` (route `runReceipt` outbound like `approvalPending`), `conversation_store.go` (persist receipt JSON on the conversation so `receipt.get` and late-joining clients replay it — same pattern as existing conversation events).
Accept: extend the existing loopback test (`e2e_loopback_test.go` pattern): dispatch a fake run through the loopback relay → assert a `runReceipt` frame arrives with `schema == "lancer.proof/v0"`; then `agent.run.receipt.get {runId}` returns the identical payload. `go test ./...` clean.

**A3 — Contract passthrough.** (depends A1; touches `dispatch.go` — same lane, serial after A1)
Add `Contract` per C2 to `dispatchParams`; validate caps (reject with `dispatchResult.Status: "error"`, message `"contract too large"`); store on the run record; echo into the receipt.
Accept: `go test -run 'TestDispatchContract|TestReceipt' ./...` — new test: dispatch with contract → receipt echoes it verbatim; oversized contract → error result, no run started.

**A4 — Approve-and-remember (stretch — build only after A1–A3 are merged and green).**
Add optional `AllowRule *policy.Rule` to `ApprovalDecision` (`approval.go:49`); on approve-with-rule, validate it is `effect: allow` scoped (must carry `Repo` or `PathPattern` or `Tool`, and a required `ExpiresAt` ≤ 30 days out — unbounded phone-created allows are forbidden), then append via the existing policy load/save machinery (`policy/load.go`); audit-log the rule creation.
Accept: `go test -run 'TestApproveAndRemember' ./...` — approve with rule → next identical hook event auto-allows; rule without `ExpiresAt` → rejected; audit chain contains the rule event.

### Lane B — iOS receipt pipeline · worktree `spec/receipt-ios`

Write-set: `Packages/LancerKit/Sources/LancerCore/ProofReceipt.swift` (new), `LancerCore/E2ERelayMessage.swift`, `LancerCore/ChatConversation.swift`, `LancerCore/LancerDProtocol.swift`, `SessionFeature/CursorShellLiveBridge-adjacent handling` (see B2), `SessionFeature/Chat/ReceiptCardView.swift` (new), `AppFeature/CursorStyle/CursorWorkThreadView.swift`, `CursorStyle/CursorComposerSheet.swift`, plus tests. **Lane C must not touch any of these.**

**B1 — Types + decode plumbing.**
Create `ProofReceipt: Codable, Sendable` in LancerCore mirroring C1 (field-for-field; `answersReserved` decoded as optional and ignored). Add `case receipt` to `ChatArtifact.Kind`; change artifact row decoding (`ChatConversationRepository`) to **skip rows whose `kind` fails to decode** instead of throwing (one `compactMap`, comment why). Add `runReceipt(ProofReceipt)` to `E2ERelayMessage` kinds and the matching `ServerEvent` case in `LancerDProtocol.swift` for the SSH path (`"agent.run.receipt"` in the method switch near `:519`).
Accept: `cd Packages/LancerKit && swift test --filter ProofReceiptTests` — round-trip decode of the C1 example JSON verbatim (store it as a test fixture string; this doubles as the cross-language contract test against Go's serializer), unknown-kind artifact row skipped not thrown.

**B2 — Persist + surface on the work thread.** (depends B1)
On receiving `runReceipt` (both transports), `upsertArtifact(kind: .receipt, runID:, payloadJSON:, status: .done)` via the existing repository, and post the thread update the same way approvals do. Handle it where approval/loop events are already handled (follow the existing `approvalPending` handling path from bridge → store → repository — same files, same pattern; do not invent a new pipeline).
Accept: `swift test --filter ReceiptPersistenceTests` — synthetic `runReceipt` event → artifact row exists with kind `receipt`, `artifacts(runID:)` returns it.

**B3 — Receipt card UI.** (depends B2)
Create `ReceiptCardView.swift` (SessionFeature/Chat, alongside `ToolCardView.swift`, reusing its card chrome + DesignSystem tokens). Sections in order: status line (status + exit + duration) · done-criteria checklist (met ✓ / unmet ✕ / unknown ○ with `evidence` line) · tests summary · files touched (top 5, "+N more" expands) · commands (collapsed by default) · per-section confidence tags rendered as small captions ("best effort" / "unavailable") — never hidden. Three actions: **Accept** (sets artifact status `.done`-acknowledged via a `acceptedAt` key merged into payloadJSON — no schema change), **Request another pass** (opens composer pre-filled: "These criteria are unmet/unknown: … Please address them." + carries the same contract), **Open on desktop** (copies `resume`-derived command: `claude --continue` form built from `resume.agent` + `vendorSessionId` — exact strings per `continueArgv` in `dispatch.go:73`).
Render in `CursorWorkThreadView` wherever `ChatArtifact` kinds are switched for display.
Accept: add `ReceiptCard` cases to `CursorAppShellExhaustiveTests` (the existing 21-test pattern): thread with a receipt artifact renders the card; unmet criterion shows ✕; "Request another pass" opens composer with prefill. `xcodebuild test -scheme Lancer -only-testing:...CursorAppShellExhaustiveTests` passes, screenshots attached.

**B4 — Composer contract chips.** (depends B1 for the type; UI-independent of B2/B3)
In `CursorComposerSheet`: an optional, collapsed "Contract" disclosure — goal (defaults to first line of prompt, editable), done-criteria (add up to 8 short rows), validation command (up to 4). Serialize into `dispatchParams.contract` through the existing dispatch call path in the live bridge. Draft-persist with the existing `CursorComposerDraftStore`.
Accept: UITest — compose with 2 criteria → dispatch payload (assert via the bridge's test seam, same seam the existing dispatch tests use) contains the contract; kill/relaunch → draft restores chips.

### Lane C — Home attention ordering · worktree `spec/home-attention`

Write-set: `AppFeature/CursorStyle/CursorThreadAttention.swift`, `CursorStyle/CursorWorkspaceThreadListView.swift`, `CursorAppShell.swift` (home list section only), plus tests. Reads (never writes): AgentStore / bridge published state.

**C1 — Attention model + sort.**
Extend `CursorThreadAttention` with `AttentionReason` + `priority: Int` per §C4 and a `detail: String?` (cap 180). Derivation is a **pure function** `CursorThreadAttention.derive(threadState) -> (CursorThreadAttention, AttentionReason, String?)` in the same file, fed by already-published state (pending approval presence → `pendingApproval`; terminal failure → `runFailed` with exit line; receipt artifact unacknowledged → `receiptReady`; provider-auth/credit failures matched from status text per lfg's reason set).
Accept: `swift test --filter ThreadAttentionTests` — table-driven: each reason maps to expected priority; sort of a mixed fixture list is exactly `[pendingApproval, blockingQuestion, runFailed, providerAuth, receiptReady, working, ready, idle]`.

**C2 — Home renders needs-you-first.** (depends C1)
Sort the home/workspace thread list by `(priority desc, updatedAt desc)`; section header "Needs you (N)" above priority-positive rows, "All clear ✓ — nothing needs you" state when N==0 **and** relay is healthy; when the relay is degraded/stale, replace All-clear with "As of <relative time> — reconnecting" (never claim all-clear on stale data — this is a product rule, not a style choice). Reason `detail` renders as the row's one-line subtitle.
Accept: UITest in the exhaustive-tests pattern: fixture with 1 pending approval + 1 working + 1 idle renders approval row first with reason line; zero-needs fixture + healthy bridge shows All clear; zero-needs + stale bridge shows the as-of state. Screenshots attached.

### Lane D — Siri entities · worktree `spec/siri-entities`

Write-set: `Packages/LancerKit/Sources/IntentsKit/` (new module: `MachineEntity.swift`, `ConversationEntity.swift`, `ApprovalEntity.swift`, `RunEntity.swift`, queries), `Packages/LancerKit/Package.swift` (add target — **coordinate: this is the one shared file; land D1's Package.swift change as its own tiny commit first, other lanes rebase**), `Lancer/RunControlIntents.swift`, `Lancer/DenyLatestApprovalIntent.swift`, `Lancer/StatusQueryIntents.swift`, `Lancer/LancerAppShortcuts.swift`.

**D1 — Entity layer.**
New `IntentsKit` target (depends: LancerCore, PersistenceKit; iOS 17+ availability annotations matching the existing intents). Four entities per the 07-03 plan's model, resolved from existing repositories — `MachineEntity` (`HostRepository`; `IndexedEntity` deferred — plain `EntityQuery` now, indexing is a Layer-5 concern), `ConversationEntity` (`ChatConversationRepository`, `EntityStringQuery` over the existing FTS), `ApprovalEntity` (`ApprovalRepository` pending rows; **volatile** — `EntityStringQuery`, never cached), `RunEntity` (`ActiveRunRegistry`). Display representations must include host + risk for approvals ("Deny 'rm -rf build' · high · mac-studio") — disambiguation quality is the point of this task.
Accept: `swift test --filter IntentsKitTests` — each query: exact-ID hit, fuzzy-title hit, ambiguous → multiple results (system disambiguates), empty store → empty. `xcodebuild build -scheme Lancer` clean (metadata extraction must not warn `No AppShortcuts found` — the provider stays in `Lancer/LancerAppShortcuts.swift`, untouched location, per the known constraint).

**D2 — Entity-aware intent refactor.** (depends D1)
`PauseRunIntent`/`StopRunIntent` gain `@Parameter var run: RunEntity` (default: sole active run; multiple → system disambiguation — deletes the "only works with exactly one run" limitation at `RunControlIntents.swift:36,58`). `DenyLatestApprovalIntent` → `DenyApprovalIntent` with `@Parameter var approval: ApprovalEntity` (fixes pick-newest + empty-`hostID` audit pollution); keep the old phrase mapped to "most recent" resolution so existing users' habit still works. Stop keeps its confirmation dialog; deny keeps confirmation; **no approve intent is added — permanent rule.** Dialogs must state machine + title + risk and distinguish: no machines / offline / no pending / ambiguous.
Accept: unit tests for routing + disambiguation paths; `xcodebuild build` clean with intents metadata listing exactly the intended shortcuts (assert via the build-log grep the repo already uses for this bug class); manual Siri smoke on simulator noted in PR description.

**D3 — Read-only additions.** (depends D1)
`SearchLancerIntent(query:)` (opens app to existing FTS results — `openAppWhenRun = true`), `OpenConversationIntent(conversation:)`, and extend the existing status intent to speak per-machine detail from `MachineEntity`. Register phrases in `LancerAppShortcuts.swift` (stays ≤ 10 shortcuts total; Apple's soft limit).
Accept: build-clean + metadata check as D2; query unit tests.

### Dependency / parallelism summary

```
D0.1 ──► (owner) D0.2
A1 ──► A2 ──► (A3 same-lane serial) ──► A4(stretch)
B1 ──► B2 ──► B3          B1 ──► B4
C1 ──► C2
D1 ──► D2, D3
Lanes A, B, C, D fully parallel (disjoint write-sets; D's Package.swift commit lands first).
Cross-lane contract: A and B meet only at the C1 JSON fixture — byte-identical test vector in both suites.
Integration (serial, after A2+B2 merge): run relay-approval-e2e.sh extended with a receipt assertion.
```

### Layer exit bar (the whole spec's acceptance)

1. `cd daemon/lancerd && go test ./...` — clean.
2. `cd Packages/LancerKit && swift test` — clean.
3. `xcodebuild test -scheme Lancer -only-testing:...CursorAppShellExhaustiveTests` — clean incl. new receipt/attention cases, screenshots in `docs/test-runs/`.
4. `relay-approval-e2e.sh` (extended per Integration) — PASS through the live Cursor shell.
5. Simulator end-to-end: dispatch with contract → approve → run completes → receipt card renders with correct criteria states → Home shows `receiptReady` then All-clear after Accept.
6. D0.2 owner device run recorded in `docs/test-runs/2026-07-07-tier0-device-proof-results.md`.

Anything failing any bar: fix or explicitly re-scope in the PR description — no silent deferrals.
