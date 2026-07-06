# Lancer Final Cursor-Simple Wireframe Handoff

Date: 2026-07-05  
Status: approved product-design direction; wireframe/doc phase only

> This is a snapshot copy bundled into this report folder. For the current status (wireframe/audit/fix
> pass is now complete, plus a flagged-but-unresolved proof-to-ship pivot), see the canonical doc at
> `docs/design-audit/2026-07-05-final-cursor-wireframe-handoff.md`.

## Canonical Artifacts

- [Core wireframe board](lancer-core-wireframes-2026-07-05/index.html)
- [Board preview](lancer-core-wireframes-2026-07-05/preview.png)
- [Mobbin research log](mobbin-research-log.md)
- Workflow docs:
  - [01 Onboarding / Pairing](workflows/01-onboarding-pairing.md)
  - [02 Home / Attention Overview](workflows/02-home-attention-overview.md)
  - [03 Work Thread](workflows/03-work-thread.md)
  - [04 Review / Approvals / Diff](workflows/04-review-approvals-diff.md)
  - [05 Workspaces / Machines](workflows/05-machines.md)
  - [06 Settings](workflows/06-settings.md)

## Final Direction

Use the Cursor mobile screenshots as the primary visual target: sparse lists, direct row hierarchy, dark transcript, bottom composer, lightweight sheets, and almost no dashboard chrome.

Lancer should keep its extra power through native artifacts, not extra navigation:

- proof cards
- approval review sheets
- changed-file cards
- to-do cards
- question cards
- launch contract chips
- run target and model pickers
- agent/provider picker and capability badges
- repo playbook and readiness checks
- trusted-machine detail
- audit/export rows

## Final IA

| Visible surface | Role |
| --- | --- |
| Home | Daily ledger: Needs you, Today, Yesterday, all-clear, bottom composer. |
| Workspaces | Repo/folder list and run-target context. This is the visible replacement for Machines. |
| Settings | Account, notifications, security defaults, trusted machines, diagnostics, data/legal. |

| Contextual surface | Entry |
| --- | --- |
| Work Thread | From Home row, workspace row, search/recent, or new composer. |
| Review / Diff | From Home attention row or Work Thread approval artifact. |
| Machine detail | From Workspaces, run-target picker, or Settings trusted machines. |
| Onboarding | First run, re-pair, or Settings pairing. |
| Search / Recent | Top action or drawer overlay, not a product root. |

Remove these as visible roots: Needs Attention, Inbox, Governance, Activity, Control, Terminal, Files, Diff, Preview.

## Surface Coverage

| Surface | Approved treatment | Key states |
| --- | --- | --- |
| Onboarding | One product proof, code-only pairing, account/local choice, policy defaults, notification recovery. | Fresh start, invalid code, expired/unreachable code, paired, notification denied, local mode. |
| Home | Cursor-style daily ledger, not dashboard. | Needs you, today, yesterday, all clear, approval waiting, failed proof, offline machine, composer expanded. |
| Workspaces | Folder/repo list first; machine trust and diagnostics one level deeper. | No repos, active repo, needs-review count, add repo, pair machine, offline machine, machine detail. |
| Work Thread | Cursor-dark transcript with Lancer proof artifacts. | User prompt, agent prose, plan card, to-dos, changed files, proof passed, approval waiting, failed proof, follow-up. |
| Review / Diff | Cursor-dark review drill-in from thread; diff opens only when needed. | Low/medium/high/critical risk, biometric, approve, deny, request changes, expired, resolved, send error. |
| Settings | Native grouped list. | Account/local mode, notifications recovery, security defaults, trusted machines, diagnostics, provider keys, audit export, legal. |

## Feature Coverage Audit Against July 4 Sources

This pass checked the combined board against `/Users/roshansilva/Downloads/lancer-wireframe-2026-07-04.html` and `/Users/roshansilva/Downloads/2026-07-04-lancer-strategy-feature-source-of-truth.md`.

| Feature family | Coverage in final Cursor-simple IA | Status |
| --- | --- | --- |
| Away Launch Composer + thin launch contract | Bottom composer plus composer sheet with contract chips: repo, machine, agent, run mode, proof expected, interrupt rules. | Represented in board: Launch Setup |
| Share Sheet / Universal Link Intake | Composer attachment path; no separate intake root. | Represented in board: Launch Setup |
| Smart Default Target | Run target picker and Workspaces default row. | Covered |
| Away Mode Setup | Workspaces detail, onboarding re-pair, and per-repo setup/readiness checklist. | Represented in board: Launch Setup + Workspaces |
| Repo Playbook | Lives under Workspaces detail or Settings as per-repo defaults. | Represented in board: Launch Setup |
| Agent Readiness Check | Appears as preflight before launch and as Workspaces detail warning. | Represented in board: Launch Setup |
| Run Mode / Interruption Budget / Run Budget | One Mission Defaults sheet, launched from composer or workspace playbook. | Represented in board: Launch Setup |
| Minimal Away Status | Work Thread status/progress and Home ledger rows. | Covered |
| Question Cards + Question Ladder | Generic agent questions get their own Work Thread artifact card variant. | Represented in board: Artifact Views |
| Proof Suite base layer | Work Thread proof cards, changed files, failed proof, Review/Diff. | Covered |
| Mobile QA Annotation | Preview/proof artifact action, not a root. | Represented in board: Artifact Views |
| Error Autopsy | Failed proof card in Work Thread plus Home row. | Covered |
| Away Digest as Home | Home ledger. | Covered |
| Git / PR / Merge Actions | Work Thread hosts commit/push/PR/merge after proof passes. | Represented in board: Ship / History |
| Flight Recorder + Work Search | Search/Recent covers cross-run retrieval; per-run recorder lives as a Work Thread/history drill-in. | Represented in board: Ship / History |
| Web Preview / Preview Cockpit | Proof artifact drill-in from Work Thread. | Represented in board: Artifact Views |
| Contextual Command Cards | Rerun proof, restart preview, fix failure, remind later, pause until morning. | Represented in board: Artifact Views |
| Changed Files Review | Review/Diff and changed-file artifact cards. | Covered |
| Voice Everywhere | Mic affordances on composer, question replies, and QA annotations. | Represented in board: Artifact Views |
| Light Automations | Contextual follow-up actions such as remind later, rerun proof, notify on CI fail, pause until morning. | Represented in board: Artifact Views |
| Provider Capability Badges | Agent/vendor picker includes capability notes. | Represented in board: Artifact Views |
| Cross-Vendor Second-Agent Review | Strong fast-follow action card inside Work Thread/Review. | Represented in board: Fast Follows |
| Proof Becomes Regression / Regression Watchlist | Proof action and workspace/playbook list. | Represented in board: Fast Follows |
| Time-Travel Scrubber / Fork From Timestamp | Lives inside Flight Recorder, not as a root. | Represented in board: Fast Follows |
| Clips integration + `lancer.proof` schema | Share/attachment and proof export/import path. | Represented in board: Fast Follows |
| Run Comparison | Work Thread comparison artifact. | Represented in board: Fast Follows |
| Weekly Away Mode Digest | Retention surface from Search/Recent or notification, not Home default. | Represented in board: Ship / History |
| Siri / widgets / Watch | Platform-native extensions, not primary app roots. | Represented in board: Fast Follows |
| True Handoff | Work Thread/Review handoff action to exact Mac hunk/proof. | Represented in board: Fast Follows |
| Team/client proof layer | Proof export/share action, deferred until solo loop validates. | Represented in board: Ship / History, deferred for V1 |
| LancerMac | Separate companion surface for pairing, doctor, pause/stop; not part of mobile IA board. | Out of scope for this board |
| Billing / sync status | Settings/account and honest sync banners; safety never paywalled. | Represented in board: Ship / History + Settings |

## Implementation Order

1. Lock visible navigation labels to Home, Workspaces, Settings while keeping route internals stable if needed.
2. Build shared row/card primitives: ledger row, workspace row, artifact card, grouped settings row, review sheet, mobile diff block.
3. Add the missing feature-preservation primitives: launch contract chips, question card, readiness warning, mission defaults sheet, preview/proof artifact, command card, and provider capability badge.
4. Convert Home to the ledger model and demote Inbox/Needs Attention into Home data.
5. Convert Work Thread to the dark transcript/artifact model and collapse raw terminal output.
6. Consolidate approval UI into one Review/Diff anatomy across Home, thread, and existing inbox code paths.
7. Rename the visible Machines surface to Workspaces and move diagnostics/trust into detail.
8. Quiet Settings into grouped native rows; fold Governance into security defaults and audit export.
9. Align onboarding to product proof plus code pairing; keep QR deferred for V1.

## Product Rules

- No fake metrics or seeded-looking production values.
- No terminal-first phone IDE route.
- No inline approve for medium+ risk without opening review.
- No hidden high-risk consequence copy.
- No safety controls behind billing or account state.
- No approval success state until the backend/daemon confirms it.
- No duplicate roots for the same job.

## Components To Build

| Component | Used by |
| --- | --- |
| Ledger row | Home, search results, workspace recent work |
| Bottom composer | Home, Work Thread |
| Composer sheet | Workspace/model/run-target pickers |
| Launch contract chips | Composer sheet, Work Thread launch artifact |
| Mission defaults sheet | Composer, Workspaces playbook, Settings security defaults |
| Workspace row | Workspaces, add/pair sheets |
| Machine detail row | Workspaces detail, Settings trusted machines |
| Thread artifact card | Work Thread plans, to-dos, proof, changed files |
| Question card | Work Thread interruptions, Siri/App Intent fast-follow |
| Preview/proof artifact | Work Thread, QA annotation, proof export |
| Contextual command card | Work Thread, failed proof, Review/Diff |
| Provider capability badge | Agent picker, run target picker |
| Approval review sheet | Home, Work Thread, existing Inbox path |
| Mobile diff block | Review / Diff |
| Grouped settings row | Settings root and subpages |
| Notification recovery row | Onboarding and Settings |

## Mobbin References

- Onboarding/pairing: [Meta Quest pairing](https://mobbin.com/screens/599405f7-6102-4ed5-a213-c68d6ec5b339), [Xbox code setup](https://mobbin.com/screens/3fb1af14-fe6a-4289-9541-ee54c3c202ac), [Fitbit code pairing](https://mobbin.com/screens/be8ade76-085a-4e3b-854e-a776073f1151), [Wise code verification](https://mobbin.com/screens/320bb9c4-7858-4a3b-8735-a2d0a9e3c14b), [ChatGPT notifications](https://mobbin.com/flows/379443da-330d-446c-8876-cc58bc9a70cd).
- Review/approval: [Airwallex approval detail](https://mobbin.com/screens/64c52224-dd85-4916-a31d-97a03c55a5c1), [Remote Global HR approval](https://mobbin.com/screens/0cbdcc18-5e9d-4678-8d0f-b8c2af3c49ab), [Revolut Business approval](https://mobbin.com/screens/9a34e3c2-65fa-49e0-9a6f-5833c749d333), [GitHub mobile review](https://mobbin.com/screens/f078a659-e648-4b5a-b312-f3be58eece15).
- Workspaces/machines: [Craft folder list](https://mobbin.com/screens/2e06ec02-f9ff-4254-b4d2-1ecb99b10909), [Apple Notes folders](https://mobbin.com/screens/51db39a6-d625-4553-82da-4131efd6ec01), [Evernote connected devices](https://mobbin.com/screens/41138583-6e7a-400f-8eba-3e2410e2bdb9), [Chime trusted devices](https://mobbin.com/screens/e7c503e7-910f-4521-8e01-a18892472901).
- Settings: [Wise settings](https://mobbin.com/screens/d527ecba-5901-4855-b8d9-20fa2aed5702), [Revolut settings](https://mobbin.com/screens/ff9a098a-d3c2-4a8f-bd86-8714c55af083), [MLS settings](https://mobbin.com/screens/5d8c6859-3a48-46a0-b27e-3373c9eb1b87).

## Next Implementation Slice

Start with Home + navigation labels. That gives the whole app the new product shape before deeper Review/Work Thread refactors begin.
