# Lancer Workflow Cross-Check — Whole-App IA & Redundancy Findings

Read all 10 workflow HTML artifacts in full plus the canonical IA doc (`docs/design-audit/2026-07-05-final-cursor-wireframe-handoff.md`). Findings below are grounded in exact panel/copy text; file paths are under `artifacts/` unless noted.

## 1. Cross-workflow redundancy

**Finding A — "Export audit log" is drawn twice, verbatim, as if two different screens own it.**
`artifacts/10-settings.html` (Data group, panel A) has the row `Export audit log / Decisions and proof history`. `artifacts/08-ship-history.html` panel E ("Sync, billing, proof share," screen titled **Account**) has the identical row, same label, same subtitle. The canonical IA table assigns "Account, notifications, security defaults, trusted machines, diagnostics" to Settings alone, yet Ship & History quietly rebuilds a second full "Account" screen (sync state, plan row, share-proof-link, export) that overlaps Settings almost completely. The master handoff doc's own Feature Coverage Audit acknowledges the split ("Billing / sync status … Represented in board: Ship / History + Settings") but doesn't say which one is canonical.
*Recommendation:* pick one canonical Account/billing home (Settings); let Ship & History's panel E be a single contextual "Share this mission's proof" action that deep-links into Settings for everything else, not a parallel Account screen.

**Finding B — Two independent "audit log" rows inside Settings itself.**
Within `artifacts/10-settings.html` alone: root list → Data group → `Export audit log / Decisions and proof history`; Security & Approvals subpage → Approvals group → `Policy audit log / View and export`. Nothing in the copy distinguishes what each surfaces — both describe decisions/proof history. Reads like the same feature filed under two different groups.
*Recommendation:* merge into one row (or make the Data-group row an explicit "export" action tied to the Security subpage's log, not a second independent entry point).

**Finding C — Fast Follows' "Verify with…" and Review/Diff's approval sheet use near-identical anatomy for two different jobs, with no visual distinction.**
`artifacts/07-fast-follows.html` panel C ("Verdict — disagrees") uses a `review-card` + `diff-view` + decision-bar, with copy structured as "Confirmed / Flagged / Also checked" — nearly the same component shapes (`review-kicker`, `review-title`, `diff-view`, red/green decision-bar) as `artifacts/06-review-diff.html` panel A/B's actual governance-approval sheet ("Matched rule" evidence, Deny/Approve). One is an optional post-hoc second opinion from another vendor; the other is a mandatory pre-execution policy gate. Visually they are the same "review sheet" component reused with no differentiator (color, iconography, or persistent label) marking "this is a second opinion" vs "this is the security gate."
*Recommendation:* give cross-vendor Verify a distinct accent (e.g., a "second opinion" badge/color) so users can't mistake a quality critique for a governance approval, especially since both surfaces can appear back-to-back on the same finished result.

**Finding D — Two independent timeline/scrub components for what the master doc says is one feature.**
The handoff doc explicitly states: *"Time-Travel Scrubber / Fork From Timestamp | Lives inside Flight Recorder, not as a root."* But `artifacts/08-ship-history.html` panel C (Flight Recorder) and `artifacts/07-fast-follows.html` panel F (Time travel/fork) each draw their own independent `timeline-row` list with different content (contract/questions/proof chapters vs. checkpoints/clips), in two different files, with no shared component reference or cross-link between them. As drawn, these read as two separate timeline screens, not one screen with an added Fork action.
*Recommendation:* consolidate into one Flight Recorder screen with Fork/Export as actions on the same timeline, matching the master doc's own stated intent.

**Finding E — Two search-like surfaces (Command Palette, Work Search) drawn independently, with only one named in the canonical IA.**
The Final IA table lists a single contextual surface, "Search / Recent." `artifacts/09-platform-gaps.html` panel A draws a **Command Palette** ("jump to a mission, repo, or command") and `artifacts/08-ship-history.html` panel D draws **Work Search** (status-chip filtered mission search) — both let you "find and jump to a mission," drawn in separate docs with separate visual language, and Platform & Gaps' own slot-note insists it is "distinct from Work Search" without reconciling entry point or overlap.
*Recommendation:* clarify whether these are the same "Search/Recent" surface with a command-mode toggle, or genuinely separate features — and if separate, give them separate, non-overlapping named entry points.

## 2. Proof timing

**Finding — High-risk proof lets you ship before (or instead of) using the very safeguard built for that risk tier.**
`artifacts/05-work-thread.html` panel F ("Proof ready, high risk") shows a rail with three equal-weight actions: `PR`, `Ready`, `Verify…` — and the flow text says explicitly: *"a third rail action, Verify…, appears only when the mission's own risk score is high — optional, not required."* This contradicts the "proportional friction" principle the product otherwise applies to the same risk tiers: `artifacts/06-review-diff.html` forces a full review sheet before Approve for medium+ risk ("No inline approve for medium+ risk without opening review" — Product Rules). Here, the analogous safeguard (cross-vendor Verify) for a proof marked high-risk is optional and listed last, with `Ready`/`PR` fully tappable first. A user can ship a high-risk change without ever triggering the second-opinion check the product designed specifically for this case.
*Recommendation:* apply the same proportional-friction rule used for approvals — for proof risk-scored high, make Verify the primary/first action (or require dismissing it) rather than an equal-weight optional third button.

**Finding — Proof Suite gap screens (Device Matrix, Visual Diff, Auto Bug Replay) aren't shown gating the ship rail they logically precede.**
`artifacts/05-work-thread.html`'s Proof Suite panels (A/B/C in that section) each end in a local decision (`View frame`/`Send back`, `Send back`/`Accept`, `Play before`/`Play after`) but none of them visibly feed into or block the main "Proof ready" card (panel C) that unlocks `View PR`/`Mark Ready`. Concretely: Device Matrix panel A shows **"1 of 4 failed — Large-text layout clips the primary action"** as its own screen, but the main thread's proof card and ship rail are drawn completely separately with no visible dependency. As wireframed, nothing stops a user from tapping `Mark Ready` on the main proof card while an unresolved device-matrix failure sits one tap away, unseen. This is exactly the ambiguity the requester flagged by example.
*Recommendation:* explicitly show the "Proof ready" card as a rollup that reflects Device Matrix/Visual Diff/Auto Bug Replay state (e.g., "3 of 4 checks passed, 1 needs review") rather than leaving them as parallel, disconnected drill-ins.

Everything else checked out consistent: Ship & History panel A (ship actions) is correctly gated behind a "Proof passed" card; the merge gate (panel B) correctly shows CI-green/proof-attached as prerequisite facts before the merge confirmation activates.

## 3. Feature placement sanity

**Finding — Repo Playbook: the doc's own prose disagrees with where it's filed, and there is no path to it from Workspaces.**
`artifacts/04-launch-setup.html`'s own flow text says Playbook items "live in a per-repo Playbook under Workspaces," and the master handoff doc lists it as "Lives under Workspaces detail or Settings as per-repo defaults." Yet the artifact itself is cataloged as a Launch Setup panel (panel D), and — confirmed by grep — **`artifacts/03-workspaces.html` contains zero mentions of "Playbook"** anywhere in its five panels (Workspaces list, Workspace detail, Machine detail sheet, Offline/recovery, Add repo/pair machine). There is no drawn row, chevron, or entry point in Workspaces that leads to the Playbook screen. As wireframed, Playbook is only reachable from the composer's Mission Defaults sheet, not from the repo-scoped surface everyone (including the docs) agrees it belongs under.
*Recommendation:* add an explicit "Playbook" row to Workspace Detail (`artifacts/03-workspaces.html` panel B) so the doc's own placement claim is actually true in the drawn UI.

**Finding — Inline git blame is self-described as belonging inside Work Thread's Changed Files but is filed and drawn only in Platform & Gaps.**
`artifacts/09-platform-gaps.html` panel C's own slot-note says: *"a depth-of-review gap inside Changed Files, not a new screen."* But `artifacts/05-work-thread.html`'s own "Changes" card (panel C, "Changes 5 / file-row") shows no blame affordance, and nothing in Work Thread cross-references Platform & Gaps. The feature is drawn as an isolated screen in a separate, lower-priority document rather than as a tap-target inside the file-row component it claims to extend.
*Recommendation:* either add the blame drill-in directly to Work Thread's Changed Files card spec, or explicitly cross-reference it there instead of leaving it solely in the gaps doc.

**Finding — Container/dev-service status has an ambiguous home.**
`artifacts/09-platform-gaps.html` panel B is captioned "Docker Compose service health surfaced as an **Away Status timeline**" (implying Home), but the screen itself is titled "conduit · services" (implying it's scoped under the Workspaces repo, not Home). The two descriptions point at two different roots.
*Recommendation:* pick one — if it's repo-scoped, place it under Workspace Detail; if it's Away Status, show it as a Home ledger row type instead of a separate dark-chrome screen.

## 4. Settings scope creep

One clear instance beyond what's covered in Redundancy Finding A: **Ship & History's panel E rebuilds an "Account" screen** (title literally "Account") containing sync status, plan/billing row ("Away Mode Solo"), share-proof-link, and export-audit-log — all concerns the Settings redesign explicitly claims exclusive ownership of ("push daily-work state back to Home, Workspaces, and Review, and leave Settings holding only defaults and account/trust controls"). This is the one clean violation of that stated boundary; everything else checked (notification severity, provider keys, policy defaults) is either Settings-only or an intentionally shared component per the handoff doc's own Components table (e.g., Mission Defaults sheet is explicitly reused by "Composer, Workspaces playbook, Settings security defaults" — that reuse is by design, not creep).

## 5. Navigation reachability

- **Repo Playbook** (see Finding in §3): no tap path from Workspaces exists in the drawn wireframes. **Flag.**
- **Fast Follows' 7 panels are absent from the Final IA table entirely.** The handoff doc's "Contextual surface / Entry" table lists only Work Thread, Review/Diff, Machine detail, Onboarding, Search/Recent as contextual surfaces with defined entries. Fast Follows (Verify-with, Verdict, Run comparison, Regression, Time-travel, Platform surfaces) has no corresponding IA table row — its reachability is asserted only inside its own document ("from a finished result," "same proof rail"), never cross-verified against the canonical IA. **Flag** — low severity since the doc self-labels these as deferred/fast-follow, but worth a line item before implementation.
- **Command Palette entry point is undrawn.** No Home or Workspaces panel shows a dedicated search/palette icon being tapped to open it (the small-circle glyphs in Home/Workspaces headers are ambiguous and unlabeled). **Flag**, tied to Redundancy Finding E.
- Everything else — Machine detail (from Workspaces, run-target picker, Settings trusted machines), Onboarding re-pair, Review/Diff drill-in from Work Thread — has a demonstrated, consistent tap path across artifacts. No further findings.

## Summary of citable artifact/location pairs for quick reference

| Finding | Files |
|---|---|
| Duplicate "Export audit log" row | `artifacts/10-settings.html:788`, `artifacts/08-ship-history.html:1059` |
| Duplicate audit-log rows within Settings | `artifacts/10-settings.html:788` vs `:810` |
| Verify-with vs. Review/Diff visual collision | `artifacts/07-fast-follows.html` panel C vs `artifacts/06-review-diff.html` panel A/B |
| Duplicate timeline components | `artifacts/08-ship-history.html` panel C vs `artifacts/07-fast-follows.html` panel F |
| Command Palette vs Work Search overlap | `artifacts/09-platform-gaps.html` panel A vs `artifacts/08-ship-history.html` panel D |
| High-risk proof ships without forcing Verify | `artifacts/05-work-thread.html` panel F |
| Proof Suite gaps not shown gating ship rail | `artifacts/05-work-thread.html` (Proof Suite section) vs panel C |
| Repo Playbook unreachable from Workspaces | `artifacts/04-launch-setup.html` panel D vs `artifacts/03-workspaces.html` (no "Playbook" match) |
| Git blame filed outside Work Thread | `artifacts/09-platform-gaps.html` panel C vs `artifacts/05-work-thread.html` panel C |
| Ship & History "Account" duplicates Settings | `artifacts/08-ship-history.html` panel E vs `artifacts/10-settings.html` panel A |

**Status:** report only, no fixes applied.
