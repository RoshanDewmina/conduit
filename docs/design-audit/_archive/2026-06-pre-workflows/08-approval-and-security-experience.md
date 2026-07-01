# 08 — Approval and Security Experience

> Source: Wave-2 approval/security research (Apple HIG + Mobbin consequential-action corpus + repo grounding). Each recommendation: Observed → Evidence → Interpretation → Lancer rec → Confidence.

## What Lancer already has (grounding)

Lancer's **data model and correctness layer are ahead of its presentation/safeguard layer.** This workstream specifies severity/friction/safeguard rules on top of an already-good model — not new plumbing.

- **`Approval` model** — `kind` ∈ {command, patch, fileWrite, fileDelete, network, credential, browser, callMCP, askQuestion}; `risk` ∈ **low(0) / medium(1) / high(2) / critical(3)** (`Comparable` — the spine of the tier model); `decision` ∈ {approved, approvedAlways, rejected, **expired**}; carries `command`, `patch`, `cwd`, `blastRadius` (`touchesGit`, `touchesNetwork`, `files`).
- **`ApprovalSummary.derive(from:)`** — pure, on-device, plain-language headline ("Runs `git push` · touches git · network access", "Edits 3 files · +12 −4"). **Lancer's single biggest UX asset** — comprehension-first, no daemon round-trip. Keep and extend.
- **`InboxApprovalDetail`** — summary → command hero (mono `$`) → context line → collapsible Details → critical-only Face ID banner → `Deny | Approve` + `Edit & run` + `Allow always…`. Good baseline; gaps below.
- **`ApprovalRepository.decide()`** — **first-decision-wins** via `WHERE decision IS NULL`; fires wire `respond()`/audit exactly once. Backbone for anti-double-approval + already-resolved races.
- **`BiometricGate`** — `LAContext` Face ID with passcode fallback; **fails closed on `biometryLockout`**.
- **`WatchApprovalTransfer`** — Watch gets only `command, cwd, risk`; Watch→phone vocab is `decision`, `emergencyStop`, `runSnippet`. **No diff, no blast radius, no `approvedAlways`** → constrains Watch decisions.

## Risk-tier / severity model (the spine)

| Tier | `Risk` | Example actions | Badge | Confirmation friction | Biometric | Batch | Watch | Notification action |
|---|---|---|---|---|---|---|---|---|
| **Low** | `.low` | read file, `ls`, `git status`, lint | Neutral "LOW" | Single tap | No | Yes | Yes | Approve/Deny inline |
| **Medium** | `.medium` | edit in-repo, `npm install`, run tests | Accent "MED" | Single deliberate tap | No (configurable) | Yes (same-kind) | Yes | Approve/Deny inline |
| **High** | `.high` | `git push`, network egress, write outside cwd, install global, secret read | Warn "HIGH" + severity sentence | **Action-sheet confirm** or biometric | Optional (default on for push/network) | **No** | View/deny-only | **Deny inline; Approve deep-links** |
| **Critical** | `.critical` | `rm -rf`, force-push, prod deploy, credential write, `fileDelete` | Danger "CRITICAL" + caution glyph | **Explicit confirm + biometric**, fail-closed | **Mandatory** | No | **No (deny-only)** | **Review-only; no Approve in notification** |

**Friction must be proportional to blast radius, never uniform** — over-gating low-risk ops trains users to blow through dialogs and defeats the gate (Apple HIG: caution symbol "only when confirming an action that might result in unexpected loss of data"; typed-confirmation corpus: Visible/Clubhouse/Moleskine/Fabric/Tolan). Drive **all** friction off the `Risk` tier. **Confidence: High.**

**Severity-sentence library** (write once, reuse, keyed on risk×kind):
- high/network → "This sends data to the internet from `<host>`."
- critical/fileDelete → "This permanently deletes files. This cannot be undone."
- critical/command(force-push) → "This rewrites remote history on `<branch>`. This cannot be undone."
- high/command(outside cwd) → "This runs outside the project folder (`<cwd>`)."

**Risk assignment:** the daemon sets `risk`/`blastRadius`. The phone must **never down-rank**, but MAY **up-rank** on locally-detected danger tokens (`rm -rf`, `--force`, `--no-verify`, `curl … | sh`, writes to `~/.ssh`/`.env`/creds). Asymmetric: only ever increase friction. **Confidence: Medium** (needs a small client-side danger-token classifier).

## Ideal end-to-end flow

```
Entry: push (closed) · lock-screen/Live Activity · Apple Watch (low/med) · in-app Needs Attention
  ▼
1. INBOX        grouped newest-first, pending pinned; row = RiskBadge + AgentBadge + summary + host/cwd + age + expiry; CRITICAL sorts first; batch only same-kind low/med
  ▼ tap
2. DETAIL       ① plain summary ② risk badge + severity sentence ③ HERO command/diff ④ scope (cwd/host/#files/chips) ⑤ collapsed Details ⑥ critical → Face ID banner before buttons
  ▼
3. REVIEW       command: full argv, mono, selectable, never silently truncated. patch: file list → expandable hunks (Diff/Original/Modified). askQuestion: render question + choices.
  ▼
4. DECIDE       primary Approve · Deny; secondary Edit & run · Allow always… · Defer. low/med → deliberate tap; high → action-sheet/biometric; critical → mandatory BiometricGate, fail-closed. "Allow always…" always opens a scope sheet.
  ▼
5. CONFIRM      optimistic change + haptic; transient toast; brief Undo ONLY for still-interceptable approves (no fake undo); row collapses to resolved with who/when.
  ▼
6. AUDIT        append-only entry: {id, kind, risk, summary, decision, decidedBy, biometricConfirmed, matchedRule, host, cwd, timestamp}; reachable from Inbox History + Governance; read-only, exportable.
```

**Structural principles:** summary before raw · one primary decision per screen · friction scales with blast radius · resolution is terminal and visible everywhere.

## Permission duration: once / session / always

Lancer has once (`approved`) + always (`approvedAlways`). **The missing, highest-value addition is a session scope** — "Allow for this session" keyed on `agentSessionID`, auto-expiring when the session ends. It's the pressure-relief valve for repeated same-tool approvals without a permanent rule.

- `approvedAlways` ("Allow always…") **must** open a scope sheet (this command / this command in this repo / this tool anywhere) — never one-tap.
- **Repeated-approval nudge:** after the same `(toolName, commandVerb, cwd)` is approved N× in a session → "Approved `npm test` 4× — Allow for this session?"
- **Critical exception:** critical kinds are never eligible for "always" without biometric, and arguably never bulk-rule-able. **Confidence: High** (once/session/always); **Medium** (nudge heuristic).

## Destructive ops, defaults, undo

- **Destructive confirm:** for critical, the destructive button is **not** the default, uses a specific verb ("Delete & run", "Force push"), shows the consequence sentence, and is biometric-gated. **Typed confirmation reserved for the truly irreversible** (mass delete / prod) — not routine high ops.
- **Safe default:** Deny/Cancel carries the visual + return default on high/critical; Approve is reachable but not the path of least resistance (HIG: "make Cancel the default"). Low/medium may make Approve primary (throughput; small blast radius).
- **⚠️ Current-code gap:** `InboxApprovalDetail` makes high/critical **Approve a single `.primary` tap** alongside Deny — under-gated. High → action-sheet confirm; critical → mandatory biometric; Deny becomes the default.
- **Undo:** short toast (~4s) ONLY for approvals the daemon can still intercept before execution. No undo for anything irreversible — a fake undo is worse than none. **Confidence: Medium** (depends on pre-exec hold window).

## Expiration & already-resolved

- **Freshness on every surface:** relative age + staleness state (>5 min → "Still waiting?", >TTL → `expired`, greyed, non-actionable, "Agent stopped waiting").
- **Already-resolved is terminal & instant:** if `decide()` returns false (row already decided) or a push arrives for a resolved id → "Already handled — Approved 1 min ago (on Watch)", not a dead button.
- **Expired never silently approves** — fail-closed, audited as `expired`. First-decision-wins already prevents a stale notification tap from flipping a resolved gate. **Confidence: High.**

## Batch

Allow batch Approve/Deny **only for low+medium, within a same-kind group** ("Approve all 6 `git status`"). **Hard rule: high/critical are never batch-approvable** (one Face ID for ten `rm -rf` is the mass-accidental-approval failure mode). Provide a satisfying "Inbox clear" zero-state (YNAB/Monarch pattern). **Confidence: High.**

## Notifications, lock screen & Apple Watch

**Actionable notifications (app closed — the #1 V1 path; C2 gate already PASSED on device):**
- **low/medium:** inline Approve/Deny actions OK; Approve can run in background. Body includes `ApprovalSummary.headline` + cwd.
- **high:** Deny inline; **Approve deep-links into the app** (must see scope + confirm).
- **critical:** **no Approve action at all** — only "Review" (opens app → biometric); Deny may be inline.
- Mark all Approve actions `.authenticationRequired` so a locked/found phone can't approve from the lock screen. ([Apple actionable notifications](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)). **Confidence: High.**

**Apple Watch** is a **triage + deny + emergency-stop** device, not a full approval surface (payload can't render a diff or scope sheet):
- Approve **only low/medium command-kind**, with a two-tap confirm (beats accidental wrist-taps).
- Deny **anything** (always safe) + trigger **Emergency Stop** (already wired).
- high/critical → "Open on iPhone to approve" + Deny. **Confidence: High.**

## Anti-accidental-approval safeguards (consolidated)

1. Friction proportional to blast radius (never uniform).
2. Safe default button (Deny default on high/critical) — **fixes the under-gated Approve**.
3. Biometric on critical, fail-closed; `.authenticationRequired` on notification Approve.
4. No one-tap on consequential surfaces (row quick-approve = low/med only).
5. Separate Approve/Deny targets; brief disabled period on critical Approve after the sheet appears (prevents tap-through).
6. First-decision-wins (already enforced) → "already handled" copy, not a dead control.
7. Client-side danger up-ranking.
8. Typed confirmation for the irreversible only.
9. No fake undo.
10. Batch never includes critical.
11. Stale/expired never auto-approves.

## Audit trail

Every resolved approval appends an **append-only** entry: `{id, kind, risk, summary, decision, decidedBy (phone|watch|auto-rule:<name>), biometricConfirmed, matchedRule, host, cwd, timestamp}`. Surfaced in Inbox History + Governance home; filterable by decision/risk/agent; read-only; **exportable**. **Distinguish auto-approved-by-rule rows clearly** ("Allowed by rule: npm test in /app") — they're the most important rows because the human didn't see them live. Tie to the existing audit verify/export governance feature so entries are tamper-evident (Discord Audit Log pattern). **Confidence: High.**

## Accessibility (mandatory)

- **Never color alone for risk:** text label + glyph + color ("CRITICAL" word + caution glyph + red). `RiskBadge` must include the tier word.
- **VoiceOver hints state consequence:** Approve → hint "Runs git push force on main. This rewrites remote history."; Deny → "Rejects this action; the agent will not run it."; critical → "Requires Face ID."
- **Risk announced first** (accessibility sort priority): stakes before raw command.
- **Dynamic Type:** command/diff blocks wrap, don't clip.
- **Hit targets ≥ 44×44 pt**, Approve/Deny separated.
- **Haptics** as non-visual confirmation; distinct stronger haptic for critical-confirm.
- **Reduce Motion:** toasts/undo must not depend on animation. **Confidence: High.**

## Concrete recommendations against current code

1. Add a **severity-sentence layer** (risk×kind) between summary and command hero. *(High)*
2. **Up-gate high/critical Approve** — high → action-sheet confirm; critical → mandatory `BiometricGate.unlock()`; Deny becomes default. *(High)*
3. Build the **patch diff drill-in** (file list → hunks, Diff/Original/Modified) reusing `DiffFeature`; soft-gate critical-patch Approve until the diff was opened. *(High)*
4. Add **"Allow for this session"** scope keyed on `agentSessionID`. *(High)*
5. **Notification action gating** by tier with `.authenticationRequired`; critical = Review-only. *(High)*
6. **Constrain Watch** to low/med approve + universal deny + emergency-stop. *(High)*
7. Surface **freshness + expired**; render already-resolved as "Already handled". *(High)*
8. **Client-side danger-token up-ranker**. *(Medium)*
9. **RiskBadge includes tier word + glyph**; VoiceOver hints carry the severity sentence. *(High)*
10. **Audit records decidedBy + biometricConfirmed + matchedRule**; flag auto-rule rows; export via governance feature. *(High)*

## Evidence references

[Apple HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) · [Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets) · [Actionable notifications](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types) · [Codex agent approvals & security](https://developers.openai.com/codex/agent-approvals-security) · Mobbin: [Revolut approve-request](https://mobbin.com/flows/1ab1004a-0d7a-4b2f-bfed-8101a3c6d8a5), [Manus diff](https://mobbin.com/flows/9dc39db8-4413-4875-a9f4-88e713129a06), [YNAB batch](https://mobbin.com/flows/50808b84-7bf6-4f70-a2c5-1236186c450a), [Discord audit log](https://mobbin.com/flows/cd9e6fd7-fe6e-4545-a153-3b1338ab5773), [Visible typed-delete](https://mobbin.com/flows/ea98b39b-b91d-4c4b-8fe5-70c727fbbefb).
