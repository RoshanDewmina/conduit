# Workflow 04: Review / Approvals / Diff Review

Status: **approved direction — Cursor-dark review drill-in** (doc/wireframe only; no SwiftUI implementation in this phase)  
Updated: 2026-07-05

## Locked Direction — 2026-07-05

Review / Approvals / Diff should become a **Cursor-dark review drill-in** from the Work Thread, not a separate heavyweight Inbox product.

The key decision: approval is an interruption in the thread. The user taps `Review`, gets one focused review surface, opens the diff only when needed, and returns to the same thread with the decision recorded.

The approved wireframe artifact is:

- [Core wireframe board — Review / Diff](../lancer-core-wireframes-2026-07-05/index.html#review)
- [Preview image](../lancer-core-wireframes-2026-07-05/preview.png)

### What Is Good About This Direction

- It keeps the visual language aligned with the approved Work Thread instead of introducing a new banking-style approval product.
- It preserves the trust essentials: request, consequence, scope, evidence, decision, and audit trail.
- It supports high-risk review without putting a full diff in front of every low-risk decision.
- It gives `Review`, `Deny`, and `Ask for changes` a natural home from the thread action rail.
- It maps cleanly to existing code surfaces: `InboxApprovalDetail`, `DiffView`, and `ChatApprovalArtifactCard`.

### What Needs Care

- The pinned decision bar must never cover the exact evidence the user needs to inspect.
- Medium and high risk approvals need enough friction; low risk approvals should stay quick.
- The diff view must remain readable on phone width, with file context and line changes that do not require horizontal scrolling for basic review.
- `Deny` and `Ask for changes` should be distinct actions; rejecting silently is not enough for agent steering.
- Resolved, expired, offline, biometric-blocked, and send-error states need the same calm treatment, not one-off alerts.

### Mobbin Pass — 2026-07-05

| Example | What it does well | Adapt for Lancer | Do not copy directly |
| --- | --- | --- | --- |
| [Airwallex approval detail](https://mobbin.com/screens/64c52224-dd85-4916-a31d-97a03c55a5c1) | Keeps scope and approval decision close together | Use request, scope, and decision in one review surface | Banking chrome and financial density |
| [Remote Global HR approval](https://mobbin.com/screens/0cbdcc18-5e9d-4678-8d0f-b8c2af3c49ab) | Actor, request, and status are easy to parse | Show agent, machine, repo, and age clearly | HR workflow language |
| [Revolut Business approval](https://mobbin.com/screens/9a34e3c2-65fa-49e0-9a6f-5833c749d333) | Proportional seriousness without visual panic | Use higher friction only for high/critical risk | Finance-specific visual weight |
| [GitHub mobile review](https://mobbin.com/screens/f078a659-e648-4b5a-b312-f3be58eece15) | Changed files and review state are familiar to developers | Use file summaries and diff drill-in | Full PR workflow complexity |

**Net:** borrow approval hierarchy from Airwallex/Remote/Revolut, borrow changed-files review from GitHub, but keep the screen visually in the Cursor-dark Work Thread family.

### Proposed Page Model

1. **Thread interruption** — Work Thread shows an approval artifact with `Review`, `Deny`, and follow-up composer.
2. **Review sheet** — request, consequence, scope, evidence, and pinned actions.
3. **Diff drill-in** — file summary plus readable mobile diff; approve remains contextual to the patch.
4. **Ask for changes** — send instruction back into the same thread instead of silently denying.
5. **Resolved review** — read-only decision, actor, time, audit ID, and no duplicate approve action.

### What Stays From Lancer

| Capability | Review treatment |
| --- | --- |
| Risk model | Text badge plus consequence copy; color is secondary |
| Biometric gate | Critical approvals trigger after review, before final approve |
| Diff review | Drill-in from review, not a separate root |
| Deny / request changes | Always available; request changes resumes the agent in-thread |
| Audit trail | Visible after decision and in resolved state |
| Offline / expired / already handled | Same review surface, disabled invalid actions |
| Redaction | Evidence snippets must use redacted command/env/output values |

### Open Design Decision

For medium-risk approvals, decide whether `Approve` appears immediately in the review sheet or stays disabled until the evidence area has been opened once. My recommendation: immediate approve for medium risk, forced diff/evidence open only for high and critical risk.

## Current Screenshots

### Primary path (refreshed 2026-06-30, iPhone 17 Pro, dark)

![Seeded approval inbox — list cards with inline Approve/Deny](../screenshots/current/approval-inbox_seeded-pending_iphone-17-pro_dark.png)

### Related context

![Home pending headline — repo-backed count without Home cards](../screenshots/current/home-command_pending-headline_iphone-17-pro_dark.png)

### Capture recipe

| State | Launch env | Notes |
| --- | --- | --- |
| Inbox list (seeded) | `LANCER_DESTINATION=inbox` + `LANCER_UITEST_RESEED=1` | Seeds 4 pending approvals; sidebar badge shows count |
| Approval detail sheet | Tap card body or **Review diff** on patch rows | Opens `InboxApprovalDetail` via `.sheet(item:)` |
| Home attention row | `LANCER_DESTINATION=sessions` + reseed + fleet slot (not seedable today) | `DSReviewSheet` path on Home NEEDS ATTENTION — blocked without live slot |
| Diff drill-in | From detail sheet on `.patch` kind | `DiffView` navigation from `InboxApprovalDetail` |

**Not captured (gaps):**

- **Full-screen approval detail sheet** — list capture shows inline actions; detail anatomy (`InboxApprovalDetail`) exists in code + `#Preview` fixtures but not exported to `screenshots/current/`.
- **Diff review mobile layout** — `DiffView` not screenshotted from seeded patch approval.
- **Expired / already-handled / offline decision** — no UITest seam for these states.
- **Permission-blocked biometric** — critical approve path exists in code; gate failure UI not captured.

## Current Structure

Approval Review is the most important V1 trust surface. It should convert an agent request into a clear, proportional decision: what is requested, why it matters, what evidence supports it, what can go wrong, and what the user's options are.

The locked V1 behavior uses proportional risk gates:

- Low risk: immediate review/approve path.
- Medium risk: expandable evidence.
- High risk: open/mark diff and stronger confirmation.
- Critical risk: high-risk treatment plus biometric confirmation where required.

### Implementation map (corrected paths)

| Area | File |
| --- | --- |
| Inbox list + inline cards | `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` |
| Detail sheet anatomy | `Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift` |
| Review sheet chrome | `Packages/LancerKit/Sources/DesignSystem/Components/DSReviewSheet.swift` |
| Diff drill-in | `Packages/LancerKit/Sources/DiffFeature/DiffView.swift` |
| Approval model | `Packages/LancerKit/Sources/LancerCore/Approval.swift` |
| Biometric gate | `Packages/LancerKit/Sources/LancerCore/BiometricGate.swift` |
| Home attention → review | `Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift` (attention rows) |

### What the code actually ships today

1. **Inbox** (`InboxView`) — board-style `InboxBoardCard` rows with risk band, agent initial, mono code chip, inline **Approve** / **Deny** (or **Review diff** for patches). Critical risk triggers `BiometricGate` on inline Approve.
2. **Detail sheet** — tapping card or Review diff opens `InboxApprovalDetail` with request, scope rows, evidence, decision bar, audit footer.
3. **Two review chrome paths** — `InboxApprovalDetail` (inbox sheet) vs `DSReviewSheet` wrapper (Home attention). Anatomy overlaps but is not one shared component yet.
4. **Diff** — patch approvals route secondary action to detail; diff is a drill-in, not the default list view.

## Current Issues

| Issue | Evidence | Severity |
| --- | --- | --- |
| **Dual approval designs** | `InboxBoardCard` inline triage vs `InboxApprovalDetail` sheet vs `DSReviewSheet` on Home — three presentations of the same decision | P0 IA — consolidate before launch |
| **Inbox competes with Home** | Sidebar **Inbox** root with badge duplicates attention-first Home direction (WF02) | P1 IA |
| **Risk by color weight** | `riskColor` / `riskBackground` on cards; `RiskBadge` in detail — label present but consequence copy thin on list rows | P1 trust — risk must include scope + consequence text |
| **Inline approve bypasses evidence** | List-row Approve can fire without opening detail for non-patch kinds | P1 — proportional gates may be skipped |
| **Patch vs command clarity** | Mono chip shows command fragment; patch body says "Apply a patch to" — good start, diff not visible until drill-in | P2 |
| **Deny without reply** | Secondary on non-patch is immediate `rejected`; no reply/request-changes affordance on list | P1 — spec calls for deny + reply |
| **State matrix gaps** | Expired, already-handled, offline queue, permission-blocked — designed in spec, not verified in simulator | Doc gap |
| **Secrets in evidence** | Code paths render command/output snippets — redaction policy must be enforced before launch | P0 security |

## Mobbin / Pattern References

| Example | What it does well | Adapt for Lancer | Do not copy directly |
| --- | --- | --- | --- |
| Revolut Business approval flows | Makes financial approvals feel serious without becoming unreadable. | Use proportional confirmation, clear amount/scope equivalent, and persistent approve/deny actions. | Do not copy banking visuals or imply money movement unless billing is involved. |
| Manus approval/review patterns | Frames autonomous agent actions as decisions with context. | Strong precedent for agent request, evidence, and decision history. | Do not copy another agent product's exact wording or branding. |
| Codex review/approval patterns | Technical agent decisions need evidence and visible command/output context. | Put command, files, risk reason, and outcome close together. | Do not expose full terminal interactivity in V1 review. |
| [GitHub PR review list](https://mobbin.com/screens/9be4aad3-c5b8-41a3-adc5-d60a940edccb) | Makes review state, changed files, and checks scannable. | Use file/change summaries and review state in Diff Review. | Do not import full GitHub PR workflow or comments model. |
| Typed delete confirmation patterns | Uses friction only when consequence is high. | Critical approvals can require biometric and/or typed confirmation only when justified. | Do not add typed confirmation to every high-risk action. |
| Discord destructive action sheets | Keeps destructive choices distinct and visible. | Deny/cancel/destructive actions should have clear language and spacing. | Do not use casual community-app tone. |
| Apple HIG alerts and sheets | Native confirmation patterns are predictable and accessible. | Use native sheets/alerts for destructive or permission-blocked states. | Do not overuse alerts for normal review flow. |
| Marcus security setup | Builds confidence around verification steps. | Biometric confirmation copy should explain why the gate exists. | Do not copy banking density or legal framing. |

### Fresh Mobbin Pass: 2026-06-30

Additional references reviewed:

- [Airwallex approval detail](https://mobbin.com/screens/64c52224-dd85-4916-a31d-97a03c55a5c1): strong example of scope and consequence living near the decision.
- [Remote Global HR approval](https://mobbin.com/screens/27e7a839-fea8-4c52-94a1-563816ff1bc0): useful for actor, reason, and review-state clarity.
- [Airwallex transaction approval](https://mobbin.com/screens/5678a8fc-1c54-4067-afe7-9be11682204c): useful for persistent approve/deny hierarchy.
- [Revolut Business approval](https://mobbin.com/screens/9a34e3c2-65fa-49e0-9a6f-5833c749d333): useful for high-trust proportional friction.
- [Airwallex approval state](https://mobbin.com/screens/94e0c040-22b2-4151-b2a9-029c5b2fcd54): useful for metadata rows and state clarity.

Net update: Approval Review should keep request, consequence, scope, evidence, and decision controls on one coherent surface. Diff Review is a drill-in, not a separate mental model.

## Chosen Direction

**Scope:** Targeted consolidation — one reusable Approval Review anatomy across Inbox, Home attention, and Work Thread inline blocks. Retire duplicate chrome; keep Inbox as optional deep queue until IA merges into Home.

Use a single reusable Approval Review anatomy:

1. Request: what the agent wants to do.
2. Scope: machine, repo/project, branch, files, command, environment.
3. Risk: level plus reason and consequence.
4. Evidence: command, diff, output, policy/audit signals.
5. Decision: approve, deny, reply/request change.
6. Audit: who decided, when, and resulting state.

Diff Review should be a drill-in from Approval Review with a clear return path and decision context preserved.

**Proportional friction:** list rows may show quick actions for low risk only; medium+ should default to opening the full review sheet before approve enables.

## Proposed Screen Structure

1. Header:
   - Risk badge and request title.
   - Machine, agent, and age.
   - Expiry or already-handled state if relevant.

2. Summary:
   - One-sentence plain-English request.
   - Why Lancer is asking for approval.

3. Scope:
   - Files, command, project, branch, environment.
   - Use compact rows with copyable values where appropriate.

4. Evidence:
   - Diff summary.
   - Command/output snippet.
   - Policy rule or guardrail that triggered the review.
   - Expandable raw evidence.

5. Diff Review:
   - File list with changed lines summary.
   - Inline diff with readable mobile formatting.
   - Mark/review affordance if high risk requires user inspection.

6. Decision bar:
   - Primary approve action.
   - Deny action.
   - Reply/request changes action.
   - Loading/sending state after choice.

7. Audit footer:
   - Request ID, machine, timestamp, and decision trail.

## Required States

| State | Design requirement |
| --- | --- |
| Loading | Preserve review sheet structure and show skeleton for request/evidence. |
| Low risk | Concise review with immediate approve/deny. |
| Medium risk | Evidence visible by default or one tap away. |
| High risk | Diff/evidence inspection required before approve is enabled if product rules require it. |
| Critical risk | Biometric gate after review, before final approve. |
| Expired | Disable approve, explain expiry, keep evidence/audit visible. |
| Already handled | Show decision, actor, and time. Do not allow duplicate decision. |
| Denied | Show denial reason/reply if sent. |
| Offline | Explain whether decision can queue or must wait. Hooks should remain fail-closed. |
| Permission blocked | Explain biometric/notification/security permission issue and provide Settings action. |
| Error sending decision | Keep decision visible, show retry, do not imply approval succeeded. |

## Designer Notes

- Hierarchy: request and consequence first, evidence second, raw technical detail third.
- Spacing: decision bar must remain visually separate from scrollable evidence.
- Typography: command/code/diff values should be monospaced; reasons and consequences should use readable body text.
- Iconography: risk icons should be consistent across Home, Review, and Work Thread.
- Motion: biometric/critical confirmation can use native transitions only. Avoid dramatic warning animation.
- Accessibility: action labels must include consequence, for example "Approve high-risk file write" where possible.

## Implementation Notes

- Promote `InboxApprovalDetail` into the canonical Approval Review component or merge with `DSReviewSheet` — one anatomy, one `RiskBadge`.
- Gate inline list Approve for medium+ risk behind opening full review (product rule).
- Use one approval anatomy across Home row, Review sheet, and Work Thread event.
- Ensure deny/reply actions remain enabled even when approve is gated.
- Do not log secrets in evidence snippets. Redact sensitive command/env values before rendering.
- Verify biometric, expired, offline, denied, loading, and already-handled states in simulator.

## Approval Ask

Approve a single evidence-led Approval Review anatomy with Diff Review as a drill-in, proportional friction by risk level, and consolidation of Inbox vs Home review chrome.
