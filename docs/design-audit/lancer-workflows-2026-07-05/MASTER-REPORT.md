# Lancer — Away Mode Design & Audit, Complete Report
**Compiled 2026-07-05**

This folder is the complete output of a multi-session design pass on Lancer's core product surfaces, plus a full audit pass checking that work for gaps, redundancy, and accuracy. Start here, then dig into `artifacts/` (the actual designs), `research/` (source material), or `audit-findings/` (what the audit found).

---

## 1. What this project was

Lancer is an iOS "mission control" app for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the user's own machines. The phone steers and approves; it doesn't replace the laptop. The product thesis is **Away Mode**: start agent work, walk away, get proof, decide.

Starting from five prior Codex/Claude Code sessions' worth of brainstorming and a Mobbin-driven wireframe board, this project:
1. Built a master feature checklist (105+ items) cross-referencing every idea ever discussed.
2. Picked up Cursor-inspired wireframe work and published the canonical bundle in this directory (`artifacts/01`–`12`).
3. Resolved a real nav-structure discrepancy in the codebase (the sidebar has 2 rows — Home, Machines — not the 5+ described in stale docs).
4. Researched iOS 27 / WWDC 2026 platform capabilities specifically to find features that make Lancer feel deeply native to the phone, not just a generic client.
5. Built 10 standalone, polished per-workflow design documents — real coded HTML/CSS phone mockups (never screenshots), each with a user-flow walkthrough, Mobbin citations with rationale, "why this shape" reasoning, and applicable iOS 27 opportunities.
6. Combined all 10 into one document and a fully tap-through interactive prototype.
7. Ran a 4-pass audit: feature completeness, a deep-dive on Onboarding specifically, whole-app IA/redundancy/logic, and a targeted re-verification of the shakiest Apple/Mobbin claims.

## 2. The 10 workflows (see `artifacts/`)

| # | Workflow | What it covers |
|---|---|---|
| 01 | Onboarding | Resequenced: pair → notifications → policy (Balanced default) → optional account |
| 02 | Home | The daily ledger — "Needs you" / "Today" / "Yesterday," the composer, run-on and model pickers |
| 03 | Workspaces | Repo-first machine management — replaces the old fleet-dashboard "Machines" model |
| 04 | Launch Setup | Pre-flight mission details — share/link intake, launch contract, mission defaults, repo playbook, readiness |
| 05 | Work Thread | The core differentiator — dark transcript, proof/annotation artifacts, the 3 Proof Suite gap screens (Device Matrix, Visual Diff, Auto Bug Replay) |
| 06 | Review & Diff | The governed approval flow — review sheet, diff drill-in, ask-for-changes |
| 07 | Fast Follows | Cross-vendor "Verify with…" second-opinion review, run comparison, time-travel/fork, Siri/widgets/Watch |
| 08 | Ship & History | Post-proof shipping — merge gate, Flight Recorder, work search, sync/account honesty |
| 09 | Platform & Gaps | 4 smaller consolidated additions — command palette, proactive signals, workspace depth, platform intelligence (on-device AI/Siri/widgets) |
| 10 | Settings | Deliberately "boring on purpose" — grouped list, no policy hero, no dashboard |
| 11 | **Combined** | All 10 in one document with a sticky jump-nav |
| 12 | **Interactive prototype** | A single tappable phone frame — 5 fully-live navigable spines (approval→diff→merge, composer→pickers→run, workspaces→machine detail, verify→two real verdicts, pair-a-new-machine) |

Every workflow artifact follows the same structure: coded phone mockups (not screenshots), a plain-language user-flow walkthrough, real Mobbin citations with the specific decision each one informed, "why this shape, not the old one" reasoning (often tied to a real, cited bug in the current codebase), and a short, curated set of applicable iOS 27/WWDC 2026 findings.

## 3. Key decisions made along the way

- **Sidebar nav is already resolved, just not documented**: the real code (`LancerSidebarView.swift`) has exactly 2 nav rows (Home, Machines) plus a New Chat CTA and a gear-icon-only Settings — Inbox folded into Home (2026-07-01), Governance folded into Settings (2026-06-30). `ARCHITECTURE.md §4.1` still describes an older 5-destination sidebar and should be updated to match.
- **Workspaces replaces Machines as a concept**: repo-first (a list of workspaces, each with its machines) instead of host-first (a fleet dashboard). This is flagged as a real, not-yet-decided data-model change — see the Workspaces artifact and Finding in §4 below.
- **Cross-vendor "Verify with…" is the sharpest differentiator against Codex/Claude Code mobile apps** — a different vendor critiques a result without re-solving it, structurally impossible for a single-vendor mobile client. This only surfaces as a rail action when a mission's own risk score is high.
- **Video-timeline/annotation/proof is genuinely differentiated** (the feature family explicitly praised at the start of this project) — it spans two workflows: Work Thread owns real-time annotation (Preview Cockpit, Tap-to-Isolate Annotation, Auto Bug Replay), Ship & History's Flight Recorder owns the scrubbable historical timeline.
- **No fake metrics, anywhere** — this rule appears repeatedly because it's grounded in a real, confirmed bug: the sidebar footer hardcodes "Relay connected · 3 hosts" regardless of truth. Every workflow that touches sync/billing/connection state was designed to avoid repeating that mistake.

## 4. Audit findings — full detail in `audit-findings/`, summarized here

Four audits ran in parallel; **fixes applied 2026-07-05** (see §7 below).

### 4a. Feature completeness (`01-feature-completeness-audit.md`)
**Headline finding (resolved 2026-07-05 §8):** 7 checklist items (Policy Diff Review, Cross-host policy-consistency check, On-device audit digest, Account Switcher, Vendor Performance comparison, Continuous Cross-Vendor Audit, Compliance Export) were marked "wireframed" but never drawn — now wireframed in workflow artifacts and the interactive prototype.
Also found: 7 items present but thinner than specified (mobile attachments, question-card ladder, billing's dual-mechanism distinction, light automations, etc.) — see the file for the full list.
Confirmed clean: every deliberately-cut feature really is absent as intended; no silent scope creep.

### 4b. Onboarding deep-dive (`02-onboarding-deep-dive.md`)
Not a rebuild — findings and a proposed new sequence, pending your go-ahead. Headline recommendation: **move Notifications from position 5 to position 3** (right after pairing succeeds — it's mechanism-critical, not an engagement nicety), **defer Account choice from position 2 to last** (and make it skippable — self-hosted is a real zero-account mode, forcing the choice early adds friction for exactly the persona most likely to bail), and **stop forcing a 3-way Policy preset decision** (ship "Balanced" pre-selected with a one-tap continue). Also confirmed the consumer-hardware Mobbin citations (Meta Quest, Xbox, Fitbit) were the weaker analogy, as suspected — GitHub's own device-verification flow is a stronger, more directly analogous developer-tool reference.

### 4c. Whole-app IA & redundancy (`03-whole-app-ia-redundancy-audit.md`)
The most consequential audit. Real findings, report-only:
- **5 redundancy issues**: duplicate "Export audit log" rows (Settings vs. Ship & History), a duplicate audit-log row within Settings itself, Fast Follows' "Verify with…" sharing identical visual anatomy with Review/Diff's mandatory approval sheet (risk of confusing an optional second opinion with the security gate), two independent timeline components where the IA doc says there should be one (Flight Recorder), and Command Palette vs. Work Search overlapping with no reconciliation.
- **2 proof-timing issues**: a high-risk proof's "Verify…" safeguard is drawn as optional/equal-weight rather than required, inconsistent with how the same risk tier is treated in the approval flow; and the Proof Suite gap screens (Device Matrix, Visual Diff, Auto Bug Replay) don't visibly gate the main "Mark Ready" action, so a user could ship past an unresolved failure.
- **3 placement issues**: Repo Playbook has no tap path from Workspaces despite every doc saying it belongs there; inline git blame is filed only in Platform & Gaps despite its own text saying it belongs inside Work Thread's Changed Files; Container/dev-service status contradicts itself on whether it's a Home surface or a Workspace-scoped one.
- **1 confirmed Settings scope-creep violation**: Ship & History's panel E rebuilds a full "Account" screen that duplicates what Settings claims exclusive ownership of.
- **Reachability gaps**: Repo Playbook (above), Fast Follows has no entry in the canonical IA table at all, Command Palette has no drawn entry point anywhere in the app.

### 4d. Targeted re-verification (`04-targeted-reverification-audit.md`)
Apple/iOS 27: one real issue (Platform & Gaps' own widget panel never applies the "full-screen widget → `.systemExtraLargePortrait`" correction every sibling artifact applies), one soft over-claim repeated in 3 artifacts (View Annotations presented as new-for-iOS-27 when the API itself shipped in iOS 18.4 — what's new is Apple's Siri-integration guidance around it, not the API). No hallucinated APIs found anywhere — every specific citation checked against live Apple docs came back real.
Mobbin: 3 weak citations found (one likely not actually sourced from Mobbin — Workspaces' "Tailscale & Termius" reference — plus two real-but-incompletely-linked citations in Review/Diff and Settings).

## 5. Recommended next steps (not yet actioned — for your review)

Roughly in priority order:

1. **Decide on the Workspaces data-model question**: repo-first vs. host-first is a real architecture decision, not a rename — see the Workspaces artifact's own "Open decision" section.
2. **Fix the high-risk-proof / Verify… friction inconsistency** (§4c) — this is a real product-logic bug in the current design, not just a documentation gap.
3. **Approve or adjust the proposed Onboarding resequence** (§4b) before it gets rebuilt.
4. **Reconcile the 5 redundancy findings** (§4c) — mostly quick fixes (pick one canonical Account screen, differentiate Verify-with visually from the approval sheet, merge the two timeline components).
5. ~~**Design-pass the 7 "phantom wireframed" checklist items** (§4a)~~ — **done** (see §8).
6. **Small citation cleanups**: the widget correction in Platform & Gaps, the View Annotations framing in 3 artifacts, and the 3 weak Mobbin citations (§4d).
7. **Build the actual CLI-artifact-production pipeline** (see `research/how-cli-agents-produce-artifacts.md`) — most Work Thread card types (`.diff`, `.file`, `.test`, `.preview`, and a net-new `.question`) have zero data producers today; only `.tool` and `.approval` are real.

## 7. Applied 2026-07-05 (audit fixes shipped)

All 10 workflow HTML artifacts, `11-combined-all-workflows.html`, and `12-interactive-prototype.html` were updated:

- **Onboarding:** resequenced to pair → notifications → policy (Balanced one-tap) → optional account; CLI context line; GitHub device-verification lead citation.
- **Work Thread:** high-risk Verify required first; proof rollup (3/4 checks); blame affordance on changed files.
- **Workspaces:** Playbook row on workspace detail; Starlink Mobbin citation fix.
- **Fast Follows:** second-opinion visual styling; time-travel noted as Flight Recorder action.
- **Ship & History:** panel E is contextual Share proof only (no duplicate Account/export).
- **Settings:** single policy audit log path; NYTimes Mobbin link.
- **Platform & Gaps:** `.systemExtraLargePortrait` widget correction; workspace-scoped container status; Work Search vs Command Palette clarified.
- **Review/Diff + Home + Workspaces:** View Annotations iOS 18.4 framing note; Manus diff link added.
- **Interactive prototype:** expanded navigation (onboarding flow, playbook, search, flight recorder, verify-required rail, device matrix sheet).

**Still deferred:** 7 checklist items marked wireframed but never drawn (Policy Diff Review, Cross-host policy check, On-device audit digest, Account Switcher, Vendor Performance, Continuous Cross-Vendor Audit, Compliance Export) — need a dedicated design pass.

## 7a. Interactive prototype bug-fix pass (2026-07-05)

After the audit fixes and phantom-feature wireframing above landed, the interactive prototype
(`artifacts/12-interactive-prototype.html`) was found to have real rendering bugs and was fixed in
place:

- **Encoding:** added `<!DOCTYPE html>` / `<meta charset="UTF-8">`; replaced raw emoji (folder, gear,
  mic) with CSS-drawn icons; status bar signal/WiFi marks and em dashes now use CSS/entities instead
  of raw glyphs that were rendering as mojibake.
- **Layout:** device frame corrected to native 390×848 (was 276×600 scaled 1.41×, which caused the
  clipped Review button and header overlap); header spacing tightened so the 3 right-side icons don't
  overlap; review-row grid uses `minmax(0,1fr)` so the diff pill stays on-screen; scroll/content-panel
  heights recalculated for the corrected frame size.
- **Navigation:** "Lancer app notifications" now opens `thread-running` instead of a toast; the
  device-matrix sheet's theme was fixed from light to dark.

## 8. Phantom features wireframed (2026-07-05)

The 7 checklist items that were marked "wireframed" but never drawn (§4a) now have coded phone mockup panels:

| Feature | Artifact | Panel | Interactive prototype entry |
|---|---|---|---|
| Policy Diff Review | `06-review-diff.html` | D | Settings → Security → Policy Diff Review |
| Cross-host policy-consistency check | `03-workspaces.html` | F | Workspaces → conduit detail → Policy consistency; Settings → Security |
| On-device audit digest | `10-settings.html` | E | Settings → Data → On-device audit digest |
| Account Switcher | `10-settings.html` | D | Settings → Switch account (header) |
| Vendor Performance comparison | `07-fast-follows.html` | H | Settings → Vendor performance |
| Continuous Cross-Vendor Audit | `07-fast-follows.html` | I | Settings → Security → Continuous Cross-Vendor Audit |
| Compliance Export | `08-ship-history.html` | F | Settings → Data → Compliance export |

Design decisions:
- **Policy Diff Review** reuses the Review/Diff diff-view pattern (red/green rule deltas) but lives in governance context with second-approver gate — not mixed into patch approval.
- **Cross-host policy check** surfaces as a workspace-scoped banner (not a fleet dashboard) so drift is visible where you pick run targets.
- **On-device audit digest** vs **Compliance Export**: digest is on-device FM summary for the owner; compliance export is a signed, date-ranged bundle for external auditors — explicitly distinct from panel E proof share.
- **Account Switcher** separates Lancer accounts from per-vendor CLI hot-swap rows.
- **Vendor Performance** and **Continuous Cross-Vendor Audit** stay in Fast Follows artifact but enter from Settings for prototype reachability (fast-follow by default, not sidebar roots).

## 9. Open pivot: proof-to-ship research (2026-07-05, unresolved)

The same day this bundle was finished, a separate research effort (Codex session, differentiation
brainstorm) produced a new synthesis at `docs/product/2026-07-05-lancer-feature-master-plan.md` §3
and a full package at `~/Downloads/lancer-proof-to-ship-research-2026-07-05` (start there:
`LANCER_PROOF_TO_SHIP_MASTER_REPORT.md`). Its core argument: "Away Mode with proof" as wireframed in
this bundle is necessary but not sufficient — mobile remote control/approval is now table stakes
across competitors, and the defensible wedge is a sharper judgment-and-proof loop:

```text
Mission Contract -> Away Mode Live Activity -> Needs-Me Queue ->
Decision Capsule / Risk Card -> Proof Bundle / Proof Reel -> Visual Recap -> Return-to-Desk Packet
```

That research was read and summarized (not acted on) during this bundle's fix pass, which flagged
that the wireframes here would need realignment to a **Needs-Me Queue** home (replacing the ledger
model in `02-home.html`), a **Mission Contract** launch artifact, **Decision Capsule / Risk Card**
approval UI, and a **Return-to-Desk Packet** — none of which exist in this bundle yet. This is an
open product decision for the next design pass, not something resolved by this report.

## 6. Folder contents

```
lancer-workflows-2026-07-05/
├── MASTER-REPORT.md              — this file
├── artifacts/                    — all 12 HTML files (open any in a browser)
│   ├── 01-onboarding.html  … 10-settings.html
│   ├── 11-combined-all-workflows.html
│   └── 12-interactive-prototype.html
├── research/
│   └── how-cli-agents-produce-artifacts.md   — engineering-gap research (this session)
└── audit-findings/
    ├── 01-feature-completeness-audit.md
    ├── 02-onboarding-deep-dive.md
    ├── 03-whole-app-ia-redundancy-audit.md
    └── 04-targeted-reverification-audit.md
```

Canonical parent docs live at `docs/design-audit/` (not duplicated here):

- `2026-07-05-feature-checklist-for-wireframing.md` — master 105+ item checklist
- `2026-07-05-final-cursor-wireframe-handoff.md` — IA / handoff summary
