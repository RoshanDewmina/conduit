# Lancer — Current-State Audit & Prioritized Launch Plan (2026-06-18)

> Code-grounded readiness audit. Synthesizes the two canonical trackers and adds findings from the
> 2026-06-18 source-of-truth pass. **Canonical trackers (detail lives there):**
> launch gates → `docs/PUBLISH_READINESS_CHECKLIST.md`; issues → `docs/KNOWN_ISSUES.md`;
> architecture/state → `ARCHITECTURE.md` §0.1/§4.1.

## Verification run this session
- LancerKit **app-target** sim build (XcodeBuildMCP): ✅ SUCCEEDED, 0 warnings/0 errors — the authoritative iOS build (plain `swift build` skips `#if os(iOS)` AppFeature code).
- `daemon/lancerd` `go test ./...`: ✅ pass (incl. new `approval_runid_test.go`).
- LancerKit `swift test`: running (385 tests/61 suites green per last checklist run).
- Deleted 3 verified-dead files (`ControlView.swift`, `AdaptiveRoot.swift`, `LibrarySupportViews.swift`); build stayed green.

## Dimension scorecard

| Dimension | State | Notes |
|---|---|---|
| **Functionality** | 🟢 strong / 🟡 unproven on device | Core loop (dispatch→approve→audit) works on simulator + localhost; **never proven on a physical device with APNs while app closed** (the actual product promise). |
| **Architecture** | 🟢 clean | Strict module discipline (engines no UIKit, features route through AppFeature); two transports (SSH + E2E relay) both gate policy/budget. Sidebar/New Chat IA shipped. |
| **UX/UI consistency** | 🟡 | Sidebar shell + dark/light verified; ~16 pixel-polish items open (B5); empty/error/loading + a11y sweep incomplete (B8). |
| **Performance** | 🟢 (untested at scale) | No profiling under large transcripts / many blocks; budgets defined in ARCHITECTURE §13, not measured. |
| **Reliability** | 🟡 | Reconnect/rearm logic exists; not yet covered as automated tests (C4). Offline approval queue present. |
| **Security** | 🟢 | TOFU, Keychain+BiometricGate, fail-closed hooks, audit redaction, relay key in Keychain, app-lock on background. `docs/SECURITY-REVIEW.md` triage (C6) open; semgrep triage open. |
| **Testing** | 🟡 | 385 Swift + Go suites green; gaps: real remote-host E2E (C1), device APNs (C2), IAP purchase (C5), reconnect-as-tests (C4). |
| **App Store readiness** | 🔴 not started | App Store Connect record, entitlements, IAP, privacy label, screenshots (D2) — main external gate. |
| **Deployment** | 🟡 | push-backend live on `sslip.io`; confirm APNs/Stripe secrets on running instance (D1); move to vanity domain (D4). |
| **Docs / ops** | 🟢 (post this pass) | Source of truth consolidated to `ARCHITECTURE.md`; dossier archived; root `AGENTS.md` added; skills installed. |

## Strategic direction (2026-06-24, narrowed — supersedes the broad framing)
The "mobile control plane for coding agents" category is commoditized (Codex Remote, GitHub Agent HQ,
Claude Code auto mode), and **Omnara** already ships mobile cross-provider approvals. **Narrow Lancer to
the governance wedge:** policy + hash-chained audit + emergency-stop + fleet drift for own-machine,
multi-provider agents — plus the blind-E2E privacy edge Omnara lacks. Lead the UI with policy/audit;
demote chat/terminal. This is a *conditional* continue gated on `docs/validation-cycle-v1.md`; weak
signal → open-source/SDK salvage. Full rationale + claim verification: verdict memo (plan file
`read-this-claude-code-encapsulated-blossom.md`); positioning detail → `ARCHITECTURE.md` §0.1 + §16 Q8/Q9.

## V1 scope decisions (owner, 2026-06-18)
- **Hosted-cloud execution deferred to V2; code RETAINED, not deleted** — V1 leads with SSH/self-host. The orphaned hosted-cloud UI stays in tree, unwired.
- **`continue`/follow-up is IN V1 scope** — already implemented in `dispatch.go`.
- **Artifact cards: keep both** — `InlineChatToolCard` (live tool calls) and `ChatArtifactCard` (run artifacts) are complementary; wire the latter when artifacts flow into the transcript.
- **Top V1 priority:** prove the full live loop + APNs on a real device → `docs/LIVE_LOOP_RUNBOOK.md`.

## New findings from this pass (not in the trackers)

1. **Hosted-cloud UI orphaned (~900 LOC, 0 refs):** `ProviderDetailView.swift` (298), `HostedProvisioningView.swift` (257), `HostedRunnerStatusView.swift` (204), `SelfHostVsHostedView.swift` (140). **V2 — retained, unwired** (see decision above). Do not delete.
2. **Two artifact renderers coexist:** `ChatArtifactCard` + 6 sub-cards (14 tests) vs. `NewChatTabView`'s `InlineChatToolCard`. **Decision: keep both** (complementary). `ChatArtifactCard` awaits run-artifact wiring.
3. **`FleetThreadMapper`** (4 tests) is built + tested but has **no production caller** — fleet→thread routing isn't wired into the live UI yet. V1-optional.
4. **Vestigial `enum Tab`** in `AppRoot.swift` — only `rootDestination(.inbox/.fleet)` is reached via `sidebarDetail`; `Tab.rootTabs/title/systemImage` and most `selectedTab` writes are dead navigation plumbing. Safe to simplify in a focused pass (left intact this session to avoid churn on the uncommitted WIP).
5. **Uncommitted WIP** (New Chat continuity + dispatch.go) is the **current implementation** and is unreviewed/uncommitted — checklist B1.
6. **Stale local worktrees** under `.claude/worktrees/` and `.worktrees/` (gitignored) — local scratch from prior fan-outs; prune with `git worktree remove` once confirmed idle (not done blindly — may hold other agents' work).

## Prioritized plan (severity × dependency)

### P0 — blocks a credible launch
- **Commit/reconcile the uncommitted WIP** (B1) — everything else builds on it.
- **Prove the live loop on a physical device, app closed** (C2/D3): backgrounded app → approval → APNs → lock-screen Approve → agent unblocks. Depends on **D1** (APNs secrets on running backend).
- **App Store Connect setup** (D2): record, entitlements (Push/CloudKit/App Groups), IAP `dev.lancer.mobile.pro` $14.99, privacy label, screenshots.
- **Decide the SSH-vs-cloud strategic fork** (ARCHITECTURE §16) — gates finding #1 (orphaned UI), pricing model, and positioning.

### P1 — finish before TestFlight
- Real **remote-host E2E** (C1) — sim/localhost only so far.
- **Resolve findings #2–#3 (V1-optional):** wire `ChatArtifactCard` when run artifacts flow into the transcript; wire `FleetThreadMapper`. Finding #1 (hosted-cloud UI) is **V2 — retained, not touched in V1.**
- **Release-signed app-target Release build + archive** (B3); **rebuild lancerd from Go** (B4).
- **Empty/error/loading + a11y sweep** (B8); **feature-wiring audit** (B7).
- **Security review closure + semgrep triage** (C6); reconcile push-backend security WIP (B6).
- **Vanity domain + DNS** off `sslip.io` (D4).

### P2 — polish / durability
- 16 pixel-polish items (B5); reconnect/session-loss as automated tests (C4); expand UI suite (C3: onboarding, IAP, approve-from-lockscreen).
- Simplify the vestigial `Tab` plumbing (finding #4); prune stale worktrees (finding #6).
- StoreKit IAP verified in TestFlight sandbox (C5).

### Owner-gated (one human action each)
D1 APNs secrets · D2 App Store Connect · D3 physical device · D4 DNS · D5 Archive→TestFlight→release.

## Unresolved decisions needing the owner
_All three prior open decisions were resolved 2026-06-18 (see "V1 scope decisions" above): hosted-cloud → V2/retain; artifact cards → keep both; `continue` → in scope. No blocking product decisions remain — the path to V1 is execution + the owner-gated App Store / device steps._
