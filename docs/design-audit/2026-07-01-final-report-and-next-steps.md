# Lancer UI/UX audit — final compiled report & next steps

**Status as of 2026-07-01.** This is the single reference doc tying together
Cursor's audit, the independent verification pass, and what's now actually
fixed in code. Read this first; it points at the detail docs rather than
duplicating them.

## What happened, in order

1. **Cursor session** ("Lancer UI/UX audit continuation," 2026-06-30) produced
   a six-workflow audit — Onboarding/Pairing, Home/Attention, Work Thread,
   Review/Approvals/Diff, Machines, Settings — each with severity-rated
   issues, Mobbin competitive research, and a proposed redesign direction.
   Details: [`2026-06-30-cursor-session-recap.md`](2026-06-30-cursor-session-recap.md),
   full findings in [`2026-06-30-lancer-ui-ux-audit-packet.md`](2026-06-30-lancer-ui-ux-audit-packet.md)
   + [`workflows/01-06-*.md`](workflows/). **All six workflows ended
   "Awaiting approval" — none were approved, skipped, or revised.**
2. **Independent re-audit** — six subagents, one per workflow, blind to
   Cursor's findings, working from source code + existing screenshots. Found:
   every P0 Cursor caught, plus 6 things Cursor missed (a real security gap,
   a confirmed nav violation Cursor had only flagged as a risk, a dead-code
   sweep, and 3 mislabeled/broken screenshots). Full comparison, per-workflow
   agreement/gaps/corrections, and an approve/skip/revise recommendation for
   each workflow: [`2026-06-30-independent-verification-and-comparison.md`](2026-06-30-independent-verification-and-comparison.md).
3. **Bug-fix implementation** (this session, commits `a6a1b7b9` docs +
   `814c219c` code) — the confirmed, mechanical fixes from step 2, plus scope
   the owner added live (biometrics removed from V1 entirely, Governance
   folded back into Settings, interactive terminal unwired from nav, a new
   continue-from-phone feature for host-started sessions). **Verified**:
   XcodeBuildMCP app-target build succeeded with zero warnings, `go test
   ./...` passed fresh, `swift test` passed 477/477.

## What's done vs. what's still open

**Done — confirmed bugs, fixed and verified in code:**

| Fix | Where |
|---|---|
| Home headline/attention-list/sidebar badge share one data source | `LancerHomeView`, `AppRoot.swift` |
| Sidebar footer + Machines relay agent list compute from real state (no hardcoded "3 hosts") | `LancerSidebarView`, `AppRoot.swift` |
| Approval evidence redacted at every render site | `InboxView`, `LancerHomeView`, `NewChatTabView` |
| Onboarding CTA warns before finishing with zero machine paired | `OnboardingRedesignGalleryView` |
| `OnboardingScanScreen` copy matches actual behavior (device-binding, not generic pairing) | `OnboardingScanScreen` |
| `DarkTerminalBlockCard` no longer fabricates shell chrome for non-shell content | `DarkTranscriptComponents`, 3 call sites |
| Dead code removed (`ProvisioningWizard`, `BridgePairingView`, unused pairing helpers, orphaned `GovernanceHomeView`) | deleted |
| Biometrics removed from V1 (app-lock + all 4 approval entry points) | `AppRoot.swift`, `InboxView`, `InboxApprovalDetail`, `NewChatTabView` |
| Governance folded into Settings (no more duplicate/competing sidebar root) | `SettingsView`, `PolicyHomeView`, `LancerSidebarView` |
| Interactive terminal (`SessionView`) unwired from Work Thread + Machines nav | `AppRoot.swift`, `FleetView` |
| New: continue a host-started session from the phone | `daemon/lancerd` (`agent.observedSession.continue`), `ObservedSessionView` |

**Still open — the six per-workflow redesigns.** Neither audit's proposed
redesign direction has been implemented; both were explicitly deferred to
keep the bug-fix pass scoped and mechanical. This is the work described as
"one workflow at a time" going forward:

| Workflow | Direction (both audits agree on the shape) | Status |
|---|---|---|
| 01 Onboarding/Pairing | Real product screenshot in the hero instead of abstract value rows; field-adjacent pairing errors | **Done** — implemented + verified, commit `e0dca8a7` |
| 02 Home/Attention | Unified attention data (headline/cards/badge), all-clear module, fold Inbox into Home | **Done** — implemented + verified, commit `cc1f6aff` (owner-reviewed via rendered comparison report first, `docs/design-audit/handoff-home-2026-07-01-report/`) |
| 03 Work Thread | Phase-grouped activity-log timeline instead of chat bubbles / fake terminal | **Done** — implemented + verified, commit `64b00af8` |
| 04 Review/Approvals/Diff | One canonical approval-review anatomy reused across all entry points | **Done** — implemented + verified, commit `da3a83a9` |
| 05 Machines | Reframe as trusted-device/health surface, remove terminal drill-in | **Done** — implemented + verified, commit `490df047` |
| 06 Settings | Calm native grouped list; Governance fold already done | **Done** — implemented + verified, commit `73bd66ed` (also cut an orphaned Terminal-prefs row + view, a stale Face ID caption, and added notification-denied recovery) |

All six workflows in this redesign pass are complete as of 2026-07-01. The "Recommended order"
section below is kept for historical record of how the pass was sequenced; there is no remaining
queued work from this audit.

## One open decision before continuing

The comparison doc flagged one cross-cutting question that both Cursor and
the independent pass initially got wrong in different directions: **whether
Governance should be a sidebar root or live inside Settings.** That's now
resolved — the owner chose to fold it into Settings (done, commit
`814c219c`). No further decision needed here; noting it for the record since
workflow 02 and 06's remaining redesign work should build on this resolved
IA, not re-litigate it.

## Recommended order for the redesign pass

Matches the packet's original approval-gate order, adjusted for what's
already been de-risked by the bug fixes:

1. **Onboarding (01)** — smallest surface area, was already first in the
   queue, and the CTA/dead-code bugs are already cleared so this is now just
   the hero-image redesign.
2. **Work Thread (03)** — the audits agree this is the biggest spec-vs-code
   drift ("strongest drift in the product"); the phone→computer /
   computer→phone continuity work this session also touches this surface, so
   doing it next keeps context warm.
3. **Review/Approvals/Diff (04)** — consolidating to one canonical anatomy
   benefits from Work Thread's shape being settled first (it's one of the
   three surfaces that would reuse the canonical component).
4. **Machines (05)** — shared status component depends on Home's shape,
   already stable.
5. **Home (02) & Settings (06)** — smallest remaining deltas once the above
   land; mostly composition of finished pieces.

This is a suggestion, not a decision — say which one you want first and
I'll scope that single workflow's redesign as its own piece of work (likely
its own plan + a fresh brainstorming pass per `AGENTS.md`'s workflow, since
these are creative/design decisions, not bug fixes).
