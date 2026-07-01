# Independent verification vs. the Cursor "Lancer UI/UX audit continuation" pass

**Purpose:** a from-scratch, code-first re-audit of all six workflows, run blind to the
Cursor session's `workflows/01-06-*.md` docs, then compared against them. Goal: catch
what either pass missed, resolve factual disagreements, and give the owner an
approve/skip/revise recommendation per workflow — clearing the gate the Cursor session
left open. See [`2026-06-30-cursor-session-recap.md`](2026-06-30-cursor-session-recap.md)
for what that session actually did, and the six `workflows/01-06-*.md` docs for its
full findings (not reproduced here except where directly relevant to a comparison).

**Method:** six subagents, one per workflow, each explicitly forbidden from reading the
Cursor docs, given only source code, `ARCHITECTURE.md`/`AGENTS.md` guardrails, and the
existing screenshots already captured today. No new simulator automation was run
(avoids 6-way contention on one shared simulator) — visual evidence is the same
screenshot set the Cursor session captured, interpreted independently.

**Headline result:** the independent pass corroborates every P0 the Cursor session
found where the two overlap, closes two "flagged but unverified" risks into confirmed
findings, and surfaces 6 new issues (including one real security gap and one dead-code
sweep) the Cursor pass didn't catch. It also surfaces one important **disagreement
about product direction** (Governance's status as a sidebar root) that both passes need
the owner to resolve explicitly, and one place where the independent pass's own claim
needed correcting after a spot-check.

---

## WF01 — Onboarding/Pairing

**Agreement:** both passes treat this as the first thing needing a decision. Both
flag QR/camera-pairing surfaces as latent risk if reachable.

**Gaps in the Cursor pass, closed by the independent pass:**
- The "Pair & continue" CTA never actually checks `client.pairingState` before
  advancing (`OnboardingRedesignGalleryView.swift:121-130, 204-211`) — screenshot-
  confirmed: `onboarding-notifications_permission-prompt_...png` shows the user
  already on Home with an empty "Connect a machine" state, i.e. onboarding completed
  with nothing paired. This is a functional drop-off risk the Cursor pass's
  value-prop-framing critique didn't touch.
- `OnboardingScanScreen`'s copy ("SCAN TO PAIR" / "terminal QR") contradicts what it
  actually accepts (`bindAccountDevice` only takes account-binding challenges,
  `OnboardingRedesignGalleryView.swift:251-257`) — a user following the on-screen
  instruction hits an error.
- A real dead-code sweep: `onAlreadyUseLancer`/`onSetupWorkspace` are wired but never
  invoked from any UI element; `ProvisioningWizard.swift` (448 lines) is unreachable;
  `BridgePairingView.swift` (365 lines) has zero callers; `OnboardingPairing.
  extractPairing`/`.renderQR` are unused. The Cursor pass's note ("QR/camera scan
  surfaces still in the tree and must stay unreachable") only spotted the tip of this —
  it's a larger cleanup than flagged, and `AGENTS.md`'s no-dead-code rule applies
  directly.

**Gaps in the independent pass:** the Cursor pass's core P0 — `OnboardingValueRows` is
abstract and never shows the real product — is a legitimate framing/trust concern the
independent pass didn't evaluate at all (it focused on functional correctness, not
value-prop persuasiveness). Treat that P0 as still standing.

**Recommendation: REVISE, not straight-approve.** The Cursor pass's redesign direction
(real product screenshot in the hero, field-adjacent pairing errors) is sound and
should proceed, but the plan needs three additions before it's complete: gate the CTA
on actual pairing success, fix or remove `OnboardingScanScreen`, and delete the four
dead files/closures above. None of these require the hero redesign to be blocked —
they can land as a fast-follow in the same PR.

---

## WF02 — Home/Attention Overview

**Agreement — both P0s independently confirmed, high confidence:**
- Split-brain attention count: the independent pass traced the exact mechanism —
  headline reads `activeInboxViewModel` (single fleet-slot, `AppRoot.swift:1528,
  715-717`), the attention section reads `fleetStore.attentionItems` (fleet-wide
  aggregate, `FleetStore.swift:152-167`) — and found `FleetStore.swift:148-150` has an
  **unused** fleet-wide `allPendingApprovals` sitting right next to the one that
  should have been wired in. Screenshot-confirmed: `home-command_pending-headline_...`
  shows "4 agents need you" with zero attention cards rendered.
- Hardcoded `"Relay connected · 3 hosts"` footer (`LancerSidebarView.swift:313,328`) —
  confirmed via `git log -p`: introduced verbatim in commit `b84decc7` (2026-06-20) and
  never wired to any state since. This exact bug was independently found a **third**
  time by the Machines (WF05) pass below — very high confidence, fix immediately.

**Gaps in the Cursor pass, closed by the independent pass:**
- `home-command_splitview_ipad-pro-11_dark.png` is stale: it shows a "WAITING ON YOU /
  N conversations blocked" banner that only exists in `InboxFeature/InboxView.swift`
  today, not in current `LancerHomeView.swift` (which uses per-approval cards). Git
  blame shows this UI predates the 2026-06-20 redesign. The screenshot needs
  recapturing, not just re-labeling — it currently misrepresents Home. It's also
  mislabeled `_dark` while showing an unambiguously light/sand theme.

**A genuine disagreement requiring an owner decision — not a bug in either pass:**
Both the Cursor WF02/WF06 docs and this verification's own WF05/WF06 briefs assumed a
"locked four-root IA (Home/Work/Machines/Settings)" and flagged Governance (and
Inbox) as roots that violate it. The independent WF02 pass checked this against actual
code and git history instead of taking the guardrail on faith: **`LancerSidebarView.
swift:185-218` renders exactly four persistent nav rows — Home, Inbox, Machines,
Governance** (Settings is reached via the profile/gear affordance, not a nav row; New
Chat is a CTA button, not a nav row). This was confirmed by directly viewing the
sidebar screenshot (see below). Git history shows this is not drift: the 2026-06-24
"Governance home + 7 wedge features" commit (`ae6590ee`) deliberately restored
Governance as a root, consistent with `ARCHITECTURE.md` §0.1's own strategic note
("Lead the product with policy/audit... one governance entry point instead of
resurrecting a Control tab"). **`ARCHITECTURE.md` §4.1's navigation table is what's
stale** — it still lists the pre-06-24 five-destination set and never mentions
Governance.

This means: the Cursor pass's WF02 recommendation ("demote Inbox," implicitly treating
Governance's presence as already-settled-wrong) and this verification's own WF05/WF06
briefs (which told agents to check against a "locked four-root IA") were both working
from a stale premise. **This is not a design defect to silently fix — it needs an
explicit owner call**: was 2026-06-24's Governance promotion the intended long-term IA
(in which case update §4.1 and stop treating it as a violation), or should it be
reverted back toward the 2026-06-20 shape (in which case Cursor's fold-into-Settings
direction for WF06 is correct after all)? Either answer is fine; leaving the doc
self-contradictory is not.

**Recommendation: PARTIAL APPROVE.** Approve and fix the two confirmed P0 bugs
immediately — they're guardrail violations (no-fake-metrics, single-source-of-truth)
independent of any IA debate. **Hold** the "demote Inbox" / Governance-as-violation
framing pending the owner's explicit IA decision above; don't implement that part of
either pass's recommendation until it's resolved.

---

## WF03 — Work Thread

**Agreement:** both passes call this the strongest drift from the V1 spec ("read-only
activity log, not a chat app").

**Gaps in the Cursor pass, closed by the independent pass — this is the most
consequential finding of the whole verification:**
- Cursor's WF03 doc flagged `SessionView` (the full interactive PTY terminal) as
  present in the tree and said it "must not surface in V1 nav (flagged P0-**if**-
  exposed, needs guardrail verification)" — i.e. a risk to check, not a confirmed bug.
  The independent pass did that verification and **confirmed it's live**: Work
  Thread's own header overflow menu ("Open workspace," `NewChatTabView.swift:604`)
  calls `AppRoot.openWorkspace(for:)` (`AppRoot.swift:731-744`), which sets
  `isShowingLiveSession = true` and presents `SessionWorkspaceContainer` →
  `SessionFeature.SessionView` for any agent backed by a live SSH fleet slot. This is
  not hidden behind a debug flag. The same path is independently reachable from
  Machines too (see WF05 below) — two live, unguarded, accessibility-labeled buttons
  into the exact pipeline `ARCHITECTURE.md` §0.1's 2026-06-30 correction says should
  not be wired into the new IA.
- A second, more specific finding than Cursor's general "reads as raw shell": the
  independent pass found `DarkTerminalBlockCard` **fabricates** shell context — its
  header hardcodes `Text("zsh — \(host)")` unconditionally (`DarkTranscriptComponents.
  swift:212`), and this card wraps **non-shell tool calls** (Read/Write/Edit/Glob get
  labeled `→ Read` inside a "zsh" window, `NewChatTabView.swift:630-641`) and **any
  failed turn regardless of whether it touched a shell at all**
  (`ChatHistoryView.swift:151-157`, confirmed by the code's own comment: "A failed
  turn keeps the dark terminal card so its error reads as terminal output"). This is
  a correctness/honesty problem (fabricating shell context that never happened), not
  just a styling-too-terminal-y taste issue.

**New, not caught by either the Cursor pass or the original verification brief:**
inconsistent composer affordance between a live thread (`inlineComposer`: `/`-
autocomplete, `@`-mentions, agent/host chips) and a resumed thread (`RunFollowUpBar`:
bare `$`-prefixed single-line field, no chips) — a user loses capability just by
navigating away and back. Also: `work-thread_sidebar-recent_...png` is a blank/broken
capture (status bar only), needs recapturing.

**Recommendation: APPROVE the phase-summary direction, but split out two P0 fast-
follows that don't need to wait for the larger redesign:** (1) resolve whether
`SessionView` should actually be reachable from Work Thread/Machines — either strip the
wiring per the §0.1 correction, or amend the doc to admit it's an intentional
power-user path (same kind of doc-vs-code tension as WF02's Governance question,
worth resolving together); (2) stop `DarkTerminalBlockCard` from rendering "zsh — host"
chrome for non-shell tool calls and non-shell failures — this is a scoped, mechanical
fix independent of the larger activity-log redesign.

---

## WF04 — Review/Approvals/Diff

**Agreement, independently confirmed and made more actionable:**
- Cursor's P0 ("evidence snippets can render command/output containing secrets;
  redaction policy not yet enforced") is real. The independent pass traced it further:
  `Redactor` exists and is used for persisted chat history, but `InboxApprovalDetail.
  pendingContent` (`InboxApprovalDetail.swift:229-235`) renders raw `args`/command
  text with `.textSelection(.enabled)` and never calls it; the daemon's own
  `redactSecrets` (`daemon/lancerd/audit.go:90`) only runs when writing the
  **post-decision** audit log, not on the payload sent to the phone for review. Fix
  location is now precise: redact once, at the point the approval payload is decoded
  from the relay/daemon response, not per-render. (Independent pass rates this **P1**,
  Cursor rated it **P0** — same bug, a severity difference worth the owner noting, not
  a factual disagreement.)

**New, not in the Cursor pass:** a real regression-risk bug — two independent
biometric gates for the same action. `InboxView.detailSheet` fires `InboxApprovalDetail`'s
own internal `LAContext` prompt (no passcode fallback, silently no-ops if biometrics
unavailable) **and then** the caller's `BiometricGate.shared.unlock()` (with proper
passcode fallback) — back-to-back Face ID prompts for one approve tap. Meanwhile
`LancerHomeView.approvalReviewSheet` relies **only** on the weaker internal gate, so a
critical approval reached from Home has no passcode escape hatch if biometrics are
locked out — inconsistent with every other approval entry point in the app. This is
the same *class* of bug PR #11 (`dff28691`) already fixed once, recurring at a
different entry point that PR didn't touch.

**A disagreement worth a quick joint recheck, not a resolved correction either way:**
Cursor's WF04 doc claims inline list-row Approve can fire without opening full detail
for non-patch approvals, skipping evidence review. The independent pass checked this
specifically and found the opposite currently in code: medium+ risk approvals require
an explicit "I've reviewed this action" checkbox before Approve un-disables
(`InboxApprovalDetail.swift:314,354+`), and `InboxView.pendingCard` routes through
`BiometricGate` correctly. Both audits ran the same day; it's possible this was already
fixed between the two passes, or one pass is looking at a different code path. Don't
resolve this unilaterally — a 5-minute joint check of `InboxView.pendingCard`'s exact
tap target settles it.

**Recommendation: APPROVE the canonical-anatomy direction**, and add two must-fix
items regardless of that larger consolidation: redact approval evidence at decode time,
and collapse the two overlapping biometric gates down to the one canonical
`BiometricGate` call (delete `InboxApprovalDetail`'s internal `LAContext` gate). Also
resolve the inline-approve-bypass disagreement before treating WF04 as fully verified.

---

## WF05 — Machines

**Agreement, independently confirmed a third time:** the hardcoded sidebar footer (see
WF02) — same bug, same fix, now confirmed by two independent code traces plus the
original Cursor pass. Treat as settled, fix immediately.

**Corroborates and sharpens WF03's SessionView finding:** `FleetView` has **four**
separate tap targets (`openTerminalRow`, `agentRow`'s fallback, `runningNowBand`,
`pendingApprovalAction`) that all call `onOpenTerminal` → the same
`isShowingLiveSession` → `SessionView` path as Work Thread. `ARCHITECTURE.md` §0.1 and
§4.1 actually **contradict each other** on this point: §0.1's 2026-06-30 correction
says don't wire the terminal into Machines; §4.1 still describes "Machine detail opens
a slot's live block terminal as an intentional drill-in." The code currently matches
the older, still-uncorrected §4.1 section. Same category of doc-vs-code tension as
WF02/WF03 above — needs one owner decision that then resolves all three at once.

**New, not in the Cursor pass:** the relay machine card's agent list is hardcoded
(`["Claude Code", "Codex", "OpenCode", "Kimi"]`, `AppRoot.swift:1357`) even though the
composer's own picker one call away already has a real `installedAgentVendors` source
with a documented temporary-fallback pattern (`AppRoot.swift:917-941`) — the Machines
card never checks it. Same fake-data guardrail violation as the footer, smaller blast
radius.

**Screenshot evidence gap:** `machines-fleet_seeded-relay_iphone-17-pro_dark.png` does
not actually show `FleetView` content — it shows the sidebar drawer open over a
partially-visible Inbox. There is currently no real screenshot of the Machines screen
body (header, agent rows, stat cards, terminal row) in the set.

**Recommendation: APPROVE the shared-status-component direction**, add the
relay-agent-list fix as a line item, and don't mark this workflow "verified" until a
real Machines-body screenshot is captured — the current one is evidence for a
different screen. Resolve the SessionView-in-Machines question jointly with WF02/WF03's
IA question, not in isolation.

---

## WF06 — Settings

**Agreement, escalated:** Cursor's P1 ("Governance exists as both a sidebar root and a
Settings section — dual entry point") is confirmed and, on inspection, worse than
flagged: `SettingsView.swift:625-709`'s `policyGovernanceSection` is explicitly
commented "folded in from the former Governance root" and re-renders the *same*
concerns (autonomy preset, enforcement log/audit, Emergency Stop) that `GovernanceHomeView`
also owns via its own Policy/Audit cards and header STOP button — two different places
to check audit history or trigger an emergency stop, with no cross-linking. This
duplication is real and worth fixing **regardless** of which way the WF02 IA question
above resolves (see next point) — even if Governance-as-a-root turns out to be the
correct long-term direction, the Settings-side duplicate should still go.

**Same open IA question as WF02, restated here because it directly determines this
workflow's direction:** Cursor's WF06 chosen direction ("demote Governance from a
sidebar root into a Settings section") assumes the 2026-06-20 IA is still current. The
independent WF02 pass's git-history check (2026-06-24 commit `ae6590ee`) suggests the
opposite may now be true. **Don't implement Cursor's fold-down direction until the
owner has made the call** — it would silently revert a 6-day-old deliberate decision if
that decision was in fact intentional.

**Verifies and closes a Cursor-flagged risk — good news, worth noting explicitly:**
Cursor's WF06 P0 said safety/approval defaults "must never be gated behind the
upgrade/Pro affordance... not yet verified as enforced." The independent pass traced
every Pro/paywall touchpoint (`PaywallSheet` is present-but-dead — `showingPaywall` is
never set `true` anywhere; `isPro` only gates cosmetic badge/copy and `BillingView`;
zero "Pro" references anywhere in `PolicyPresetsView`, `PolicyMatrixView`, `AuditView`,
`TeamRolesView`) and confirms **this guardrail holds — no safety control is
paywall-gated today.** This converts an open launch-blocker risk into a closed,
verified non-issue; the owner can drop it from the launch checklist.

**New, not in the Cursor pass:** the Governance dashboard shows hardcoded status —
`policyActive: true` and `roleLabel: "owner"` are unconditional literals
(`AppRoot.swift:1390-1399`), and Settings' own "POLICY BRIDGE / All clear" card is pure
decorative copy, not bound to any real policy/approval state. Smaller-blast-radius
version of the same fake-metrics guardrail issue as WF02/WF05's footer bug.

**A claim that needed correcting after a spot-check — noted here in the interest of
holding the independent pass to the same rigor as the Cursor pass:** the independent
WF06 agent reported `settings-root_seeded_...`, `governance-home_policy-audit_...`, and
`sidebar-drawer_open_...` as "byte-for-byte the same image." A direct MD5 check
disproves that literal claim — all three have different checksums. Viewing the
images directly, however, confirms the **substance** of the finding: all three
screenshots depict the identical scene (the sidebar drawer open over a
partially-visible Inbox), not the Settings screen body or the Governance dashboard
body. So: not byte-identical, but functionally the same capture repeated under three
names — the underlying gap (no real screenshot of either screen's actual content)
stands. This also independently confirms Governance renders as a persistent 4th
primary nav row (Home/Inbox/Machines/Governance, visible in all three images),
corroborating WF02's IA finding above.

**Recommendation: REVISE.** Don't implement the "fold Governance into Settings"
direction until the WF02 IA question is resolved by the owner. Regardless of that
outcome: remove the Settings/Governance content duplication (pick one canonical home
for policy/audit/emergency-stop), replace the hardcoded `policyActive`/`roleLabel`/"All
clear" values with real state, and recapture both the Settings-root and
Governance-home screenshots — the current ones aren't evidence of either screen.

---

## Cross-cutting themes

1. **One IA question blocks three workflows' final direction.** WF02, WF03/WF05
   (SessionView-in-nav), and WF06 all have a Cursor-recommended direction that
   presumes a doc (`ARCHITECTURE.md` §4.1, or the 2026-06-30 §0.1 terminal-scope
   correction) is authoritative over what the code and recent commit history actually
   show. Resolve these together, in one owner conversation, rather than three separate
   workflow approvals — the answers are probably related (if Governance-as-root was
   intentional on 2026-06-24, the terminal-scope correction from the same period may
   have a similar "intentional exception for Machines" the doc never spelled out).
2. **The hardcoded-metrics pattern is systemic, not a one-off.** Found in four places
   independently: sidebar host count (WF02/WF05, found 3×), relay agent list (WF05),
   Governance `policyActive`/`roleLabel` (WF06), Settings "All clear" card (WF06). Worth
   a single pass across all of `AppRoot.swift`'s destination-builder functions for any
   other literal that should be computed, rather than fixing these four in isolation.
3. **Screenshot evidence is weaker than either audit doc implies.** At least 4 of the
   23 current screenshots don't show what their filename claims: Machines (shows
   sidebar, not FleetView), Settings root and Governance home (both show sidebar, not
   their own content), Work Thread sidebar-recent (blank), and the iPad Home splitview
   (stale pre-06-20 UI). Recapturing these should happen before either audit's
   "Verified: Partial" status is upgraded further.
4. **Two guardrails were checked and found to genuinely hold** — worth stating
   positively so they don't get re-litigated: risk is never color-only anywhere checked
   (WF02, WF04), and no safety/approval control is paywall-gated anywhere in Settings
   or the approval surfaces (WF04, WF06).

## What to do next

This doc plus the six workflow docs together are what the owner needs to make the
approve/skip/revise call the Cursor session was waiting on. Suggested order: (1) settle
the Governance/terminal-scope IA question, since it gates three workflows' final shape;
(2) approve the P0 bug fixes that don't depend on that question (split-brain attention,
hardcoded metrics ×4, redaction-at-decode-time, biometric-gate consolidation,
onboarding CTA-gating, dead-code sweep) — these can start immediately; (3) approve the
larger per-workflow redesign directions once (1) is settled; (4) recapture the four
broken/mislabeled screenshots as part of whichever implementation PR touches that
screen. No SwiftUI implementation has started as part of this verification pass — this
remains doc-only, per the original packet's guardrail.
