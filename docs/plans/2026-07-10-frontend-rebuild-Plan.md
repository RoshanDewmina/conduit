# Frontend rebuild — Implementation Plan

**Goal:** Rebuild Lancer’s iOS UI as a thin, Apple-native chat-first shell on surviving engines, ending Milestone 4 with pair → dispatch → stream reply → in-thread Approve/Deny on a real device path.

**Approved:** 2026-07-10 (owner `APPROVED` after locked decisions + Approach 2).

**Architecture:** Hang new SwiftUI on existing `SessionFeature` / `AppFeature` stores / GRDB / relay. Hybrid plumbing: restore **contracts/models** from pre-wipe commit; rewrite **all SwiftUI** and a **new thin live bridge**. No `DesignSystem` module in M1–M4. No daemon edits on this track.

**Base:** `feat/frontend-scorched-wipe` @ `80407933` (scorched wipe committed; **not** merged to master).  
**Implement branch:** `feat/frontend-rebuild-m1` (cut from wipe tip; rename/extend as milestones land).  
**Worktree:** prefer `.worktrees/frontend-scorched-wipe` or a fresh worktree on the rebuild branch — do not whole-file `cp` across worktrees.

**Tech stack / areas:** `AppFeature`, `SessionFeature` (engines only), `SettingsFeature` VMs, `Lancer/` app target, XcodeGen `project.yml`. Deployment target **iOS 26.0**.

**Orchestration (owner 2026-07-10):** GPT-5.6 **Sol** in Cursor is the **advisor / delegator only** — it does **not** write product code. Implementation is done by **Claude Code CLI** with **`--model sonnet`** (Sonnet 5). One Plan milestone per Sol session. Sol stays token-efficient: short briefs, no transcript dumps, no re-deriving the Plan.

---

## Orchestration — Sol delegates; Claude Code CLI (Sonnet) implements

### Roles

| Role | Who | Does | Does not |
|---|---|---|---|
| Advisor / delegator | GPT-5.6 Sol (this Cursor chat) | Read Plan/Status; write a tight Claude brief; run `claude -p …`; re-verify build; update Status; stop | Edit Swift/Go/UI; large file dumps; implement “just this one fix” itself |
| Implementer | Claude Code CLI `--model sonnet` | Edit code in the rebuild worktree; run builds/tests as asked; report files changed + evidence | Expand past the milestone; touch `daemon/**`; merge to master |

### Token-efficiency rules for Sol

1. **Do not code.** No `ApplyPatch` / Write on `Packages/`, `Lancer/`, or `project.yml`. Exception: Status.md / Plan Progress checkboxes only.
2. **Do not re-read the whole repo.** Point Claude at Plan paths + 3–8 concrete files max per dispatch.
3. **One Claude dispatch per attempt.** Brief = Goal + write-set + constraints + Done-when. No chat history paste.
4. **Verify yourself** after Claude returns (distrust self-report): `git status` / `git diff --stat` + XcodeBuildMCP `build_sim` (or xcodebuild).
5. **Max 3 Claude fix rounds** for the milestone; then STOP and ask the owner.
6. Prefer `--output-format text` for summaries; use `json` only when parsing programmatically.

### Claude Code CLI — how to use (verified on this machine)

Binary: `/opt/homebrew/bin/claude` · version **2.1.205**. Always `cd` the rebuild worktree first.

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe
# confirm branch
git branch --show-current   # expect: feat/frontend-rebuild-m1
```

**Flags that matter:**

| Flag | Use |
|---|---|
| `-p` / `--print` | Non-interactive: run prompt, print result, exit (required for Sol delegation) |
| `--model sonnet` | Sonnet 5 implementer (alias; do **not** use opus/fable for routine M1–M4 impl) |
| `--permission-mode acceptEdits` | Allow file edits without interactive prompts (implement) |
| `--permission-mode plan` | Read-only / no edits (scout / answer questions) |
| `--output-format text` | Human summary (default for Sol) |
| `--output-format json` | Machine-parseable when needed |
| `< /dev/null` | Avoid CLI waiting on stdin when run from agents/scripts |

**Scout (read-only) — verified 2026-07-10:**

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe
claude -p --model sonnet --output-format text --permission-mode plan \
  "Reply with exactly three lines: (1) git branch --show-current output, (2) whether Packages/LancerKit/Sources/AppFeature/CursorStyle exists (yes/no), (3) first line of docs/plans/2026-07-10-frontend-rebuild-Plan.md. Do not edit any files." \
  < /dev/null
# Observed stdout:
# feat/frontend-rebuild-m1
# no
# # Frontend rebuild — Implementation Plan
```

**Implement (edits allowed) — template Sol must use:**

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe
claude -p --model sonnet --permission-mode acceptEdits --output-format text \
  "$(cat <<'EOF'
Implement Plan milestone M1 ONLY.
Read: docs/plans/2026-07-10-frontend-rebuild-Plan.md (M1 section).
Write-set: AppFeature AppShell + Home/Workspaces/Settings stubs; rewire AppRoot; drop DesignSystem/Cursor* UI deps; restore minimal non-UI contracts from 80407933^ only if required to compile.
Constraints: no DesignSystem module; no daemon/**; no M2–M4; thin Apple-native TabView; no Face ID; no Siri Approve.
Done when: iOS app-target build_sim (or xcodebuild scheme Lancer) succeeds; three tabs launch; list files changed + build evidence.
EOF
)" < /dev/null
```

**Continue a prior Claude session** (same cwd) if a fix round is needed:

```bash
claude -p --model sonnet --permission-mode acceptEdits -c \
  "Fix remaining build errors only. Do not start M2. Paste xcodebuild/build_sim result." \
  < /dev/null
```

**Permission modes (from `claude --help`):** `acceptEdits` | `auto` | `bypassPermissions` | `manual` | `dontAsk` | `plan`.  
Prefer `acceptEdits` for implement; `plan` for scout. Avoid `bypassPermissions` unless owner says so.

### Sol session checklist (every milestone)

1. Confirm cwd + branch (`feat/frontend-rebuild-m1`).
2. Optional scout with `--permission-mode plan` (broken refs only).
3. Dispatch implement brief via `claude -p --model sonnet --permission-mode acceptEdits`.
4. Independently re-run Plan verify command; paste evidence into Status.md.
5. If red: one tighter fix brief (errors only) — max 3 rounds.
6. STOP for owner OK — do not start the next milestone.

---

## Global constraints

- Follow `AGENTS.md` / `docs/agent-contract.md` / `docs/AGENT_READ_FIRST.md`.
- Small diffs; **one milestone → verify → stop**. Do not batch M2–M4 in the same session as M1.
- **Sol does not implement product code** — Claude Code CLI `--model sonnet` does (see Orchestration).
- Study competitors before inventing UX: `research-repos/{orca,happier,omnara}` + `docs/product/2026-07-09-chat-ui-port-map.md`. Patterns/state machines only; MIT/Apache with attribution; **never** commit competitor code.
- Apple-native minimal UI: system `TabView` + `NavigationStack` + `List` / `TextField` / standard buttons. No custom DesignSystem, no Cursor token module, no glass chrome kits.
- Security: fail-closed; no Face ID reintroduction; **no Siri Approve intent**; never log secrets.
- Do not touch `daemon/**` on this track.
- Do not reinstall the owner’s physical phone without explicit ask.
- Do not revert unrelated dirty files on other checkouts.
- Distrust “done” without command evidence.

## Out of scope (until after M4)

- Markdown polish / syntax highlighting / jump-to-latest polish beyond bare stream text
- Proof Reel, Receipt cards UI, Away Mode, Launch Composer
- DiffFeature / FilesFeature rebuild
- Widgets / Live Activity **UI** sources (engines may remain)
- Watch UI
- Full Home attention ordering / search overlay polish
- Merging wipe or rebuild into `master` until M4 verify is green (owner merges)

## Competitor + Apple notes (M1–M4)

| Donor | Borrow |
|---|---|
| Happier (MIT) | Streaming coalesce + approval/question as first-class client state; orphan tool-result buffer later |
| Orca (MIT) | Working indicator mutually exclusive with visible streamed text |
| Omnara (Apache-2.0) | Derived “host unreachable” from heartbeat — fail-visible |
| Apple | `TabView` + `NavigationStack`; iOS **26.0** deployment; no iOS-27-only APIs required for M1–M4 |

---

## Milestones

### M1 — Compile + launch thin 3-root shell

**Intent:** App builds and launches on simulator with Home / Workspaces / Settings tabs. Stub content OK. Unbreak `AppRoot` / `DesignSystem` / deleted `Cursor*` references enough to compile.

**Files (expected write-set):**
- `Packages/LancerKit/Sources/AppFeature/AppShell.swift` (new) — `TabView` roots
- `Packages/LancerKit/Sources/AppFeature/Home/HomeView.swift` (new, stub)
- `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift` (new, stub list)
- `Packages/LancerKit/Sources/AppFeature/Settings/SettingsRootView.swift` (new, stub)
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — point UI at `AppShell`; remove `CursorAppShell` / `CursorShellLiveBridge` / `DesignSystem` deps
- `Packages/LancerKit/Sources/InboxFeature/InboxViewModel.swift` — drop `DesignSystem` import if unused
- Restore **minimal compile contracts** from `80407933^` only as needed (e.g. `QuestionCardModel` helpers still referenced by `CommandGateway`) — **no SwiftUI** from history
- `Packages/LancerKit/Package.swift` — ensure targets compile without DesignSystem product
- `project.yml` only if XcodeGen membership requires it

**Acceptance:**
- [ ] iOS app-target simulator build succeeds
- [ ] App launches; three tabs visible with stub labels
- [ ] No new DesignSystem module; no daemon changes

**Verify:**
```bash
# Prefer XcodeBuildMCP: session_show_defaults → build_sim (scheme Lancer)
# Fallback:
cd /Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe  # or rebuild worktree
xcodebuild -project Lancer.xcodeproj -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Paste build result (success / first errors if fail).

**Stop:** Do not implement pairing or chat in this milestone.

---

### M2 — Settings pairing + trusted machines

**Intent:** Full Settings pairing flow + list/remove trusted machines on real relay state (owner lock C).

**Files:** Settings views under `AppFeature/Settings/`; wire existing pairing / host / relay stores; reuse patterns from pre-wipe `CursorRelayPairingSheet` / `CursorTrustedMachinesView` **as behavior reference only** (rewrite SwiftUI).

**Acceptance:**
- [ ] Pair from Settings; machine appears in trusted list
- [ ] Remove machine works (no ghost Connect)
- [ ] `build_sim` green

**Verify:** `build_sim` + owner/manual: pair → see machine → remove → gone.

**Stop:** No work-thread chat yet.

---

### M3 — Work thread + composer + stream

**Intent:** Open/create thread, send prompt, stream assistant text via **new** `ShellLiveBridge` onto `E2ERelayBridge` / `RunDispatchService` / `ConversationSyncCoordinator`. Restore transcript **contracts** from `80407933^`; rewrite views.

**Files:** `AppFeature/Chat/*`, `AppFeature/Bridge/ShellLiveBridge.swift`; Workspaces → thread navigation.

**Acceptance:**
- [ ] Send prompt on paired host; streamed (or completed) reply visible
- [ ] Working indicator exclusive with streamed text (Orca rule)
- [ ] `build_sim` green; unit tests for transcript mapping if restored types warrant them

**Verify:** `build_sim` + dogfood send/receive. Optional: `cd Packages/LancerKit && swift test` for any new pure tests.

**Stop:** No in-thread approval card yet (notification path may still exist).

---

### M4 — In-thread Approve/Deny

**Intent:** Approval card on the work thread wired to `ApprovalIngest` / `ApprovalRelay` / existing decision path.

**Acceptance:**
- [ ] Pending approval appears in-thread
- [ ] Approve and Deny both complete the governed step
- [ ] `build_sim` green
- [ ] Document manual dogfood steps in Status.md

**Verify:** `build_sim` + dogfood: dispatch → approval → Approve/Deny → continue.

**After M4:** Owner decides merge to `master` (wipe+rebuild still not auto-merged).

---

## Progress

- [x] Scorched wipe committed on `feat/frontend-scorched-wipe` (`80407933`) — not merged to master
- [x] Plan approved 2026-07-10
- [ ] M1 — Compile + launch thin 3-root shell
- [ ] M2 — Settings pairing + trusted machines
- [ ] M3 — Work thread + composer + stream
- [ ] M4 — In-thread Approve/Deny

## Decision log

- 2026-07-10: Wipe lands on feature branch only (A) — keep master buildable.
- 2026-07-10: Chat-first vertical slice (B).
- 2026-07-10: Hybrid restore contracts/models; rewrite SwiftUI + bridge (C).
- 2026-07-10: M1 product bar includes approval card — sequenced as plan **M4** so compile/pairing/chat stay debuggable.
- 2026-07-10: Apple-native minimal look (A) for M1–M4.
- 2026-07-10: Full Settings pairing + trusted machines (C) — plan **M2**.
- 2026-07-10: Approach 2 — four verify-gated milestones; owner APPROVED.
- 2026-07-10: GPT-5.6 Sol = advisor/delegator only (token-efficient); Claude Code CLI `--model sonnet` implements. CLI smoke-tested (`claude` 2.1.205).

## Related docs

- Wipe handoff: `docs/plans/2026-07-10-frontend-scorched-wipe-HANDOFF.md`
- Prior wipe inventory: `docs/plans/2026-07-09-fable-frontend-wipe-rebuild-Plan.md` (execute scope superseded by scorched wipe)
- Chat port map: `docs/product/2026-07-09-chat-ui-port-map.md`
- Roadmap (external): `~/Downloads/Important Docs - Lancer/` Layers 0–3 specs — product north star; trust live code over stale “missing” claims in those docs
- Status: `docs/plans/2026-07-10-frontend-rebuild-Status.md`
