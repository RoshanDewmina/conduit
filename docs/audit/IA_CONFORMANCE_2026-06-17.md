# IA Conformance — tester flow vs current app (2026-06-17)

Target IA (from the tester flow): **Inbox** (decisions + history) · **Fleet** (live
agents) · **Control** (rules/guardrails) · **Settings** (Connection/Security/
Notifications/Account/Advanced).

Current app IA: **Inbox · Fleet · Activity · Settings** (`AppRoot.Tab`).

> Per owner: the Activity→Inbox-history merge is already understood ("activity tab
> swapped") — not re-litigated here. The substantive gap is the missing **Control** tab.

## Conformance table

| Tester expectation | Current app | Verdict |
|---|---|---|
| **Inbox** = decisions + dashboard home + history | Inbox = pending cards + `InboxEmptyState`; history present | ✅ mostly — verify empty state is a *dashboard* (running/handled-today/spend/last-decision), not just "all clear" |
| **Fleet** = live agents, task detail, new task | Fleet = agents + hosts + Quota Guard + New Task | ✅ structure right (populated state device-only) |
| **Control** tab = autonomy, budget, auto-approvals, risk rules, quiet hours, emergency stop | **No Control tab.** Pieces scattered: autonomy+policy+notification-filters → Settings; budget → Fleet QuotaGuard + Settings; emergency stop → **watch-only**, no phone UI | ❌ **missing** |
| **Settings** = Connection / Security / Notifications / Account / Advanced | Settings = Bridge&Hosts / Approvals(+notif filters) / Security(SSH keys, Secrets, Provider keys, Doctor) / Pro+Billing | ⚠️ different grouping; no **Advanced** (SSH/provider/doctor not demoted), no **Account** group |
| 4th tab = **Control** | 4th tab = **Activity** | ❌ swap intended |
| **Emergency stop** visible but not accidentally tappable | Exists only as a Watch command (`onEmergencyStop`); no phone affordance | ❌ **missing on phone** |

## Where we deviate (summary)
1. **No Control tab** — the single biggest gap. Autonomy/budget/auto-approvals/risk-rules/quiet-hours/emergency-stop are real features but live in Settings/Fleet, not a dedicated guardrails surface.
2. **No phone Emergency Stop** — watch-only today.
3. **Settings not regrouped** to Connection/Security/Notifications/Account/Advanced; technical tools (SSH keys, provider keys, doctor) sit in "Security" rather than a demoted "Advanced".
4. (Acknowledged, not actioned) Activity is still a tab vs merged into Inbox history.

## What already conforms
- Inbox decisions, approval card anatomy, Face ID on critical, edit & run, allow-always.
- Fleet as live-ops surface + New Task composer.
- Autonomy presets (`AutonomyPreset`), budget/quota (`QuotaGuard`), policy rules — all **exist**, just not consolidated under Control.
- Onboarding "agents ask / you approve / work resumes" + demo approval + connect-computer.

## Plan to conform (proposed)
**P1 — Control tab (replace Activity):** new `ControlView` consolidating: Autonomy level
(reuse `AutonomyPreset`), Budget limits (reuse `QuotaGuard`), Automatic approvals + Risk
rules (reuse Policy), Quiet hours (reuse notification filters), **Emergency Stop** (new
phone affordance → fan out the existing `onEmergencyStop` to all live `fleetStore.slots`).
Move Activity's history into Inbox.
**P2 — Settings regroup:** Connection / Security / Notifications / Account / Advanced;
demote SSH keys + provider keys + doctor + terminal customization + cloud + snippets into
**Advanced**.
**P3 — Inbox home dashboard:** ensure empty state shows running/handled-today/spend/last-decision.
