# Lancer — core→extra build sequence, with the hands-free (Siri/App Intents) layer folded in

2026-07-07 · Claude Fable 5 · Companion to `2026-07-07-lancer-differentiation-verdict-and-roadmap.md`
Evidence: master plan (`2026-07-05-lancer-feature-master-plan.md`), the SDK-grepped WWDC26 audit (`docs/wwdc26-lancer-opportunity-audit/`, which greps the shipped iOS 27 SDK swiftinterfaces — stronger evidence than any web summary), the Siri plan (`docs/plans/2026-07-03-siri-primary-ios27-fast-follow-plan.md`), git state through `54a31915`, and fresh web verification (2026-07-07).

---

## 0. The two facts that decide the whole sequence

**Fact 1 — the calendar.** iOS 27 beta 3 shipped **yesterday** (2026-07-06); public beta is imminent; GA is ~**September 14, 2026**. An App Store/TestFlight build cannot require iOS 27 until then. Lancer's deployment target is iOS 26.0 (`project.yml`, `Package.swift`) and must stay there through the validation period. So every feature below is tagged **[26-safe]** (buildable and shippable now) or **[27-gated]** (cannot reach a real user before mid-September — automatically post-validation, no matter how attractive).

**Fact 2 — the clock.** The validation gate is 2026-07-21. Anything not needed to (a) pass Tier 0 on a physical device or (b) make the proof-wedge pitch demoable in interviews is post-gate by definition.

And one framing correction, so this doc doesn't inherit a stale premise: master plan §3 says "governance… is what's structurally hard to copy" and weights every feature by it. The 07-07 verdict retired that weighting — the wedge is *proof + decision + hands-free trust*, with governance as invisible load-bearing infrastructure. The sequence below re-weights accordingly, which is why a few master-plan "Post-MVP" items move up and several "V1 core" items move down.

**On your Siri instinct:** you're right, with one sharpening. The research says the real "acts on the agent's behalf without opening the app" edge in the next two months is **mostly not Siri** — it's the push/Live-Activity/lock-screen loop, which is iOS-26-safe, half-built, and demoable by 07-21. Siri (App Intents) is the second act: the iOS-26-safe slice is worth building right after the gate, and the genuinely magical parts (semantic search, onscreen awareness, long-running dispatch) are 27-gated whether we like it or not. "It just works" is part of the pitch — and the version of it you can actually show a prospect this month is a lock-screen approval that works with the phone in your pocket, not a Siri conversation.

---

## 1. What's actually possible without opening the app — the research answer

### The mechanics, disambiguated (this is the App Intent vs. Shortcut vs. Live Activity question)

**App Intent** is the primitive. One `AppIntent` type = one action the *system* can invoke. Every other surface — Siri, the Shortcuts app, Spotlight, widgets, Live Activity buttons, Control Center controls — is a different *front end onto the same intent*. Build the intent + entity layer once; the surfaces come nearly free after that. Lancer already has 5 basic App Shortcuts (status, pending approvals, pause, stop, deny-latest) but **zero production `AppEntity`/`EntityQuery`** — which is why "deny the migration approval on the mac studio" can't work today: Siri has no way to *refer to things*. The entity model is the highest-leverage single piece of hands-free work.

**App Shortcut** (via `AppShortcutsProvider`) is just Siri-phrase packaging around an intent — it's what makes "Hey Siri, Lancer status" work with zero user setup. Known sharp edge, already hit twice in production here: the provider must be compiled into the app target's own binary, not a shared package, or registration silently fails (confirmed unchanged in iOS 27 — the new `IntentExecutionTargets` API fixes runtime dispatch ambiguity for shared *intents*, but not the provider placement rule).

**Shortcuts-app automations** are user-composed chains of your intents. You don't build these; you *enable* them by shipping good intents. This is where several brief-§8 ideas (geofenced dispatch, event triggers) become free instead of features: "when I leave the office, run Lancer status and notify me" is a user automation over a status intent, not code you write.

**Live Activity buttons** (`LiveActivityIntent`) are the sharpest tool and the most constrained. The button's `perform()` executes **inside the widget-extension process** — no host-app round trip, no access to the app's in-memory relay session, and **no supported way to show a Face ID prompt from inside the extension** (SDK-verified: no biometric API was added anywhere in the iOS 27 ActivityKit/WidgetKit/AppIntents diff). Every action on a Live Activity/widget is therefore *unauthenticated beyond device unlock*, full stop. That constraint draws the trust line for you — see below.

**Notification actions** (the path Lancer already proved app-closed on 2026-06-23) remain the workhorse: APNs arrives, user long-presses, taps Approve/Deny, the system gives the app brief background runtime to execute. iOS-26-safe, already working, already the demo.

### The trust/safety line — what can run unattended vs. what must open the app

Derived from the constraint above plus the repo's own (correct) safety classification, restated as the standing rule:

**Safe fully hands-free** (Siri / Shortcut / widget / Live Activity, no app open, no confirmation beyond the tap or utterance): anything **read-only** — status, pending-approvals count and summaries, "what finished," find/open a run or conversation. Also **pause** (reversible by design).

**Hands-free with explicit confirmation dialog:** **stop** a run; **deny** an approval (deny is fail-safe — the worst outcome of a wrong deny is a re-ask); **answering an agent's Question Card by voice** — this is your "answering a question" case, and it's genuinely possible today as an iOS-26 App Intent: Siri reads the question, takes a dictated answer, reads it back, and sends on confirm. The one real risk is dictation corrupting a technical answer ("use la crosse dot json"), which the read-back confirmation mitigates. Free-text answers to *blocking* questions should stay confirmation-gated; multiple-choice Question Ladder answers ("option 2") are lower-risk and could eventually skip it.

**Hands-free only with compensating controls, and only for policy-classified low risk:** **approving a low-risk change** from a Live Activity button or notification action. Since biometrics are impossible in the extension (and the app removed Face ID entirely on 07-07 — a decision this doc takes as given but flags: device unlock is now the *only* human-presence check anywhere), the compensating controls must be protocol-level, and both already have specs in the repo's own ranking (items #1–#2): **approval content-hash binding** (the daemon computes a hash of the exact command/diff at approval creation; the phone echoes it back; the daemon re-verifies before executing — kills TOCTOU where the action mutates between glance and tap) and **risk-tiered fail-closed policy** (only low-risk kinds may be approved from an unauthenticated surface; the daemon enforces this server-side, so a compromised or buggy client can't over-approve). Until both land, inline approve buttons on Live Activities should render only for the lowest policy tier, or stage-don't-execute.

**Must open the app, always:** approving medium/high/critical-risk actions (the Live Activity button becomes "Review in Lancer" — a deep link that stages the decision), anything that pushes/merges/rewrites git history, pairing changes, billing, policy edits. Voice-approve of any kind stays permanently rejected (repo item #25 — correct, don't revisit).

One more Apple-side reason this line sits where it does: HIG guidance says don't render sensitive content on the Lock Screen — a high-risk approval showing a full command there is the anti-pattern. This requires a `riskLevel` field in the Live Activity content state (a data-model change, currently missing) to pick which button set and how much detail renders.

### What each capability costs, honestly

| Capability | Gate | Verdict |
|---|---|---|
| Siri status / pending / find / open / pause / stop / deny (entity-aware) | **[26-safe]** — `AppEntity`+`EntityQuery`, iOS 16+ APIs | Build post-gate, week 3. Real, cheap, demoable. |
| Voice-answer a Question Card (confirmation-gated) | **[26-safe]** — custom intent + dialog | Build with Question Cards (Layer 4). |
| Lock-screen / Live Activity approve for low-risk | **[26-safe]** APIs; **gated on content-hash + risk-tier work** | The centerpiece of hands-free. Layer 3. |
| Push-to-start Live Activity with app fully closed | **[26-safe]** (iOS 17.2 API) — but relay backend has no `event:"start"` sender and registers the wrong token type today | Layer 3 daemon work. |
| Spotlight/Siri semantic search over runs ("when did we touch auth middleware") | **[27-gated]** (`IndexedEntityQuery`, `CSSearchableIndexDescription`) | September lane. Also quietly implements brief-§8's "cross-session memory search" via the OS. |
| "Pause *this* run" from what's on screen (View Annotations) | Protocol iOS 18.2, modifier's OS gate unverified | Prototype in September lane; verify gate first. |
| Siri-dispatched long-running mission (`LongRunningIntent`, >30s, auto-Live-Activity) | **[27-gated]** | September lane — this is the "tell Siri to start work" moment, and it cannot ship sooner. |
| On-device Foundation Models (advisory approval copilot, proof narration, digest) | Framework is **[26-safe]**; image input + DynamicProfile are 27; device/region-gated by Apple Intelligence availability either way | Prototype post-gate; never authoritative; always needs a fallback UX for ineligible devices. |
| Face ID before a Live Activity button executes | **Impossible** — no API exists, confirmed against the shipped SDK | Design around it (risk tiers), don't wait for it. |

---

## 2. The sequence, core → extra

Ordering rule: each layer must be independently shippable and must make the previous layer's promise more credible. iOS APIs, daemon/relay implications, and the 1–2 build risks worth flagging are per-feature. Items not listed are cut or deferred per the verdict doc's cut list (unchanged).

### Layer 0 — the gate (days 0–1) · *nothing below matters until this passes*

**Tier 0 physical-device loop** — pair → dispatch → approve → follow-up on Roshan's iPhone against real `lancerd`.
*iOS:* nothing new; exercise `CursorShellLiveBridge`, APNs registration, notification actions.
*Daemon/relay:* nothing new; exercises yesterday's never-device-tested fixes (`85f66754` approval-delivery, `9e18d679` real-data wiring).
*Risks:* (1) the owner checklist still instructs "Approve with Face ID" — it's stale against the Face-ID removal; fix the doc before running or the run will "fail" on a step that no longer exists. (2) Relay approval persistence across app kill (`ff8e290f`) has sim coverage only; device APNs timing is the classic place it breaks.

### Layer 1 — the proof slice (days 2–10) · *makes the pitch demoable*

**1a. Proof Receipt card** (deliberate subset of master-plan Proof Suite: files touched, commands/tests run with pass/fail, done-criteria checklist, accept / another-pass / open-on-desktop).
*iOS:* SwiftUI in the Cursor shell work thread — no new frameworks. Render from a typed `ProofSummary` model, not parsed text.
*Daemon/relay:* the real work. `lancerd` must emit a structured end-of-mission summary event: per-vendor adapters in `dispatch.go` normalize "commands run + exit codes" (vendors' transcript formats differ wildly); files-touched comes from git (`diff --stat` against mission-start ref — cheap, vendor-independent); new versioned relay message type (thin `lancer.proof` v0; do not build the full schema from the 07-04 spec yet). Fits within the 4KB-per-push mindset: summary in the message, evidence fetched on tap.
*Risks:* (1) vendor heterogeneity — Claude Code hooks give clean events; Codex/OpenCode/Kimi are lossier; ship with per-vendor confidence flags ("commands: complete / best-effort") rather than pretending uniformity, because a *wrong* proof card is worse than none — it's the exact trust failure the product exists to prevent. (2) Scope creep toward the Reel — the receipt is cards, not playback; hold the line for 14 days.

**1b. Away Digest needs-you-first Home ordering** (the ledger, attention-ordered, all-clear state).
*iOS:* reorder/regroup existing Home; "needs you" badge from pending-approval + blocking-question state.
*Daemon/relay:* a `needsAttention` reason enum on session state — mostly derivable client-side from data that already flows.
*Risks:* (1) this screen was mock until 07-06 — verify each row against live `lancerd` state, not the mock fixtures that fooled prior sessions. (2) Wrong "all clear" is the worst failure on this screen (user walks away believing it); bias to showing uncertainty when the relay is degraded.

**1c. Minimal launch-contract preview** (chips: repo, machine, agent, run-mode, "proof expected"). Only what makes the receipt's "done-criteria met?" line mean something.
*iOS:* composer additions; persist contract on the work thread.
*Daemon/relay:* pass contract fields through dispatch so the receipt can echo them. No enforcement yet — display-grade, honestly labeled.
*Risk:* implying enforcement that doesn't exist; copy must say "asked of the agent," not "guaranteed."

### Layer 2 — validation support (days 7–14, only as interviews demand)

Interview-driven iteration on Layer 1; screen-record the loop for outreach; **billing** = Stripe payment link (no StoreKit work). No new build items — deliberately. If an interview reveals a missing evidence type (e.g. screenshots matter more than test output), adjust 1a's cards; that's the whole point of the ordering.

### Layer 3 — the hands-free loop (weeks 3–5, post-gate) · *this is where "it just works" ships, and it's all [26-safe]*

Sequenced within the layer because each item depends on the last:

**3a. Fix the Live Activity lifecycle.** `AppRoot.swift:338` calls `.end()` on every Live Activity when backgrounding — architecturally wrong; `.end()` is terminal, so the push-driven while-closed story the architecture docs claim **cannot currently work at all**. Keep the Activity alive; drive updates via its push token.
*iOS:* remove the `.end()`-on-background call; ship `activity.pushTokenUpdates` tokens to the backend.
*Risks:* (1) 8-hour hard Activity lifetime (forum-sourced, unverified) — long missions need a refresh strategy; test on device. (2) Token lifecycle churn (new token per activity) — backend must handle re-registration, not assume one token per device.

**3b. Relay-path Live Activity tokens + push-to-start sender.** Today token forwarding only happens when a direct `daemonChannel` exists; the relay-only path (the V1-primary architecture!) registers plain APNs device tokens, and `push-backend` has no `event:"start"` sender — so a fully-closed phone can never *originate* a Live Activity.
*Daemon/relay:* register Activity + push-to-start tokens over the relay; add the `start` payload sender to `daemon/push-backend` (4KB cap; `attributes-type`/`attributes` on start).
*Risks:* (1) the payload shape in the repo audit is secondary-sourced — verify against Apple's doc page in a real browser before hard-coding server-side. (2) `NSSupportsLiveActivitiesFrequentUpdates` + user's frequent-pushes toggle gate update rates — design content updates to be sparse (stage changes, not progress ticks) so the budget never matters.

**3c. `riskLevel` in Live Activity content state + risk-gated buttons.** Low-risk: inline Approve/Deny buttons (`LiveActivityIntent`). Everything above: "Review in Lancer" deep link that stages the decision.
*iOS:* content-state schema change; button-set selection by tier; redact command detail above the threshold (HIG Lock-Screen guidance).
*Daemon/relay:* the daemon labels every approval with its policy tier (it already classifies; expose it in the payload).
*Risks:* (1) `LiveActivityIntent` runs in the widget extension — it cannot reuse the app's relay session; the approve action needs either an app-group-shared, keychain-backed minimal relay client in the extension or a stage-in-shared-storage + background-wake handoff to the main app. This is the layer's real engineering problem; solve it once, deliberately, because notification actions, widget buttons, and Watch will all reuse the answer. (2) Schema versioning — old Activities render with new widget code after an app update; version the content state now.

**3d. Approval content-hash binding + risk-tiered fail-closed** (repo ranking #1–#2). The protocol-level compensating controls that make 3c defensible — and the fix for the current 8s fail-*open* grace window, which silently approves anything when the client is unreachable.
*Daemon/relay:* hash at approval creation, echo-and-verify before execution; per-tier grace behavior (low keeps the grace window, high/critical fail closed). Pure protocol/Go work, no Apple gate.
*Risks:* (1) hash canonicalization across vendors (what exactly is hashed for a multi-file diff vs. a command?) — spec it once, version it. (2) Backward compatibility with in-flight approvals during rollout — version the approval message.

**3e. Siri Phase 1 — the [26-safe] App Intents slice** (per the existing 07-03 plan, which is correct and needs no re-derivation): `MachineEntity` / `RunEntity` / `ApprovalEntity` / `ConversationEntity` + `EntityQuery` over existing GRDB repositories; refactor the 5 existing shortcuts to be entity-aware (fixes the confirmed `DenyLatestApprovalIntent` pick-newest ambiguity bug and the empty-`hostID` audit pollution); add status/search/open/continue intents with strong confirmation dialogs; **no approve intent, ever**.
*iOS:* App Intents only — no daemon changes; queries resolve against local state.
*Risks:* (1) the `AppShortcutsProvider`-must-live-in-app-target bug class — already hit twice; the regression test that would catch it (`AppIntentsTesting`) is itself 27-gated, so until September the guard is a compiled-metadata check in CI, not a real intent-execution test. (2) Stale local state — Siri answering "status" from a dead relay cache is a trust failure; intents must surface data freshness ("as of 2 min ago; machine unreachable").

**Also in this window, small:** Watch app embedding (built, tested, reaches zero users — a packaging/CI fix; do it before adding *any* new surface, but note Watch inherits 3c's risk-gating decisions, so land it after 3c) and the deep-link routing fix (`onOpenURL` rejects the exact paths auth/billing emit — currently silently broken, and 3c's "Review in Lancer" deep link depends on this path working).

### Layer 4 — the full away loop (weeks 5–8, shaped by interview evidence)

**Question Cards + Question Ladder** — the agent-asks/user-answers structured flow. *iOS:* work-thread cards + the voice-answer App Intent (confirmation-gated, per the trust line). *Daemon:* a first-class `question` event with typed options (the Ladder), not free-text-only. *Risks:* vendor support for structured questions is uneven (Claude hooks yes; others degrade to free text) — degrade visibly; dictation-corruption on free-text answers — keep the read-back confirm.

**Return-to-Desk packet** — single recap surface: branch/worktree state, contract, receipt, open risks, copy-continuation-command / open-on-Mac. *iOS:* one screen composing Layer-1 data; Continuity/Handoff later, not now. *Daemon:* none new. *Risk:* master plan §9's open question stands — make it one real surface, not scattered rows; design check before build.

**Git/PR ship actions** (branch, commit, PR, merge from phone). *iOS:* action sheet + status. *Daemon:* `gh`/git execution with the same approval pipeline — ship actions are high-tier by definition (never on an unauthenticated surface). *Risks:* merge-from-phone is the single most dangerous action in the product — it gets the strictest gate (in-app, staged, content-hashed); repo auth states (SSH keys, `gh` login) vary per machine — preflight and surface readiness, don't fail mid-action.

**Proof Reel / timeline playback** — only if interviews said receipts weren't enough. *iOS:* timeline scrubber over Layer-1 events; frames/video later. *Daemon:* event timestamps already exist; frame capture is a new, heavy subsystem (defer). *Risk:* this is the feature with the worst charm-to-cost ratio in the repo; build the 30-second structured replay, not video, first.

### Layer 5 — the September (iOS 27) lane · *[27-gated]; prep in August, ship at GA*

The deployment-target raise is one decision + mechanical churn (`project.yml`, regenerate, `Package.swift`, all targets). Then, in value order: **AppIntentsTesting** first (cheap, regression-guards the exact two Siri bug classes already hit in production); **`IndexedEntityQuery` + Core Spotlight semantic search** over conversations/runs (this is "when did we touch the auth middleware?" answered by the OS — brief-§8's cross-session memory search, mostly for free); **View Annotations** for "pause *this* run" (verify the SwiftUI modifier's real OS gate first — unconfirmed); **`LongRunningIntent`** for Siri-dispatched missions with auto-Live-Activity progress (the genuine "tell Siri to start work and walk away" moment); **Foundation Models approval copilot** (advisory-only `RiskVerdict` via `@Generable`, evidence via `Tool` over the local GRDB/audit data; on-device; PCC `.deep` escalation for high-risk; never wired to auto-decide — and note the trap the audit caught: custom on-device adapter fine-tuning is `obsoleted: 27.0`, dead path, don't propose it). All of it device/region-gated by Apple Intelligence availability — every copilot surface needs a "not available on this device" fallback that doesn't degrade the core loop.

### Layer 6 — extras (evidence-dependent, no dates)

Cross-vendor second opinion (demo scripted in interviews first — per the verdict doc), Clips/Loom intake, team tier (policy diff review, compliance export, proof share links), StandBy/`systemExtraLargePortrait` widgets, True Handoff, Burn Switch (distinct from Emergency Stop — revokes credentials, not runs; cheap and on-brand once the hands-free surfaces multiply the credential surface).

---

## 3. Where Siri actually lands, and why — the merge, stated once

Given the 14-day clock and the engineering reality (approval screen real for one day, Live Activity lifecycle actively broken, zero entities), the hands-free work folds in as **three separate things at three different times**, not one "Siri feature":

1. **The lock-screen loop is Layer 3, immediately post-gate** — it's the highest-value hands-free surface, it's all iOS-26-safe, and its blockers are Lancer bugs (the `.end()` call, the relay token gap), not Apple gates. It — not Siri — is the "it just works" demo. If interviews before 07-21 go well enough that you want one hands-free moment in the demo, 3a alone (stop killing the Activity on background) is the only piece worth pulling forward, because it makes the *existing* notification-approve loop feel alive on the Lock Screen.
2. **Siri Phase 1 (entities + read/pause/stop/deny + voice-answer) is Layer 3e/4** — a week of work that makes the product feel native and fixes two real bugs, but it does not move a purchase decision on 07-21, so it must not compete with the proof slice for the next two weeks.
3. **The magical Siri (semantic search, onscreen awareness, Siri-dispatched missions, on-device copilot) is Layer 5 in September** because Apple says so — every one of those symbols is hard-gated to iOS 27, which GAs ~Sept 14. Prep in August, ship at GA, and by then interview evidence will say whether it's a headline or a delighter.

The trust line holds across all three: reads and reversible actions go hands-free freely; deny/stop/answers go hands-free with confirmation; low-risk approve goes hands-free only after content-hash binding and server-side risk tiers exist; everything else opens the app — and since Face ID is gone app-wide, the app-open path is now the *only* stronger check than device unlock, which makes 3d not optional if hands-free approve ships at all.

---

## Sources

In-repo (primary): `docs/wwdc26-lancer-opportunity-audit/03,04,06,08` (SDK-grepped), `docs/plans/2026-07-03-siri-primary-ios27-fast-follow-plan.md`, `docs/product/2026-07-05-lancer-feature-master-plan.md`, `docs/STATUS_LEDGER.md`.
Web (verified 2026-07-07): [iOS 27 beta 3 seeded July 6](https://www.macrumors.com/2026/07/06/apple-seeds-ios-27-beta-3/) · [iOS 27 public beta timing](https://www.macrumors.com/2026/07/02/ios-27-public-beta-release-date/) · [iOS 27 roundup / Sept release](https://www.macrumors.com/roundup/ios-27/) · [Apple: What's new in iOS](https://developer.apple.com/ios/whats-new/)
