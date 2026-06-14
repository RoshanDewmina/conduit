# Frontend Simplification — Report + Independent Review

**Date:** 2026-06-13
**Subject:** Conduit iOS, governed-approvals v1 simplification
**Contents:** Part 1 is Codex's original *Frontend Simplification Report* (verbatim). Part 2 is an independent review by Claude (Opus 4.8) that verified each claim against the shipping code in `Packages/ConduitKit/Sources/` and the design handoff (`PAGES.md` + screenshots), then gives an opinionated ADD / REMOVE / KEEP recommendation.

---
---

# Part 1 — Codex's Frontend Simplification Report (verbatim)

## Frontend Simplification Report - Governed Approvals v1

**Date:** 2026-06-13
**Context:** Conduit shifted from a broader SSH cockpit / agent-management app toward a governed-approvals product. This report captures which frontend surfaces still feel like pre-pivot weight, which capabilities should remain, and what the next simplification pass should try to achieve.

### What I Was Trying To Do

I was trying to judge the app against the current product thesis, not the old one.

The current thesis is: **a coding agent asks permission, the user approves from the phone, and the remote host resumes safely.** Anything that helps a first-time user understand and trust that loop should stay close to the surface. Anything that mainly supports generic SSH management, hosted-agent operations, snippets, workflows, file browsing, scheduling, or billing should either move behind Advanced, be hidden until production-ready, or be deferred.

The goal was not to make Conduit less capable. It was to make the first-use experience simpler, so the real capability is easier to understand.

### Core Product Spine To Keep

Keep the four-tab shape:

- **Inbox:** approval requests and decisions.
- **Fleet:** saved hosts and connection health.
- **Activity:** audit trail / while-you-were-away history.
- **Settings:** security, keys, notifications, policy, and advanced configuration.

Keep these as v1 core capabilities:

- Live SSH connection with real TOFU host-key prompt.
- Password and Ed25519 authentication.
- Approval cards: approve, deny, edit/run, allow-always.
- Local relay fallback and notification plumbing, with production APNs still owner-only.
- Policy editor and Activity feed as secondary trust surfaces.

### Frontend Surface That Feels Too Heavy For v1

These features are useful, but they distract from governed approvals if they are too prominent:

| Surface | Current concern | Recommendation |
|---|---|---|
| Library | Opens snippets, keys, agents, and other toolkit concepts from a prominent Settings header icon. | Move under **Advanced** or rename to **Tools** and keep it visually secondary. |
| Snippets | Snippet run/new paths are not fully wired. | Hide run/new affordances until complete, or make snippets read-only/import-only for v1. |
| SSH key management | Host counts are mocked. | Remove host-count chips or wire real host associations. |
| Workflows | Reads like an automation product, not governed approvals. | Hide for v1 unless fully implemented and clearly scoped. |
| SFTP / file browser / preview | Implemented or partially implemented, but not a verified normal route. | Keep internal/pro-later; do not market for v1. |
| SessionShellView surfaces | Preview/files/diff/inbox switcher creates a second app inside session. | Keep the shipping session focused on terminal + approvals. |
| Hosted agents / schedules / runs / artifacts / team invites | Powerful but pulls the product back toward agent management. | Keep behind Cloud entitlement and Advanced; do not make it a first-run concept. |
| Billing / Cloud | Owner-only production checks remain. | Keep present but quiet; avoid making Cloud feel required for BYO-host approvals. |

### Capabilities To Add Or Surface

The app can become simpler without becoming weaker by adding better guidance around the core loop:

- **How approvals work:** a three-step explainer: agent pauses, you decide, host resumes.
- **First-run checklist:** connect host, trust host key, wait for first approval.
- **Demo approval:** a safe local sample approval so users understand the card before a real agent event.
- **Trust/security panel:** explain host-key trust, Keychain storage, what leaves the device, and what stays local.
- **Better allow-always management:** make revoke behavior and scope explicit, especially local-only vs bridge policy behavior.

### Recommended Information Architecture

Use this as the target v1 shape:

| Level | Surface | Purpose |
|---|---|---|
| Primary | Inbox | Decide agent requests. |
| Primary | Fleet | Connect and monitor hosts. |
| Primary | Activity | Review what happened. |
| Primary | Settings | Security, keys, notifications, policy. |
| Secondary | Advanced | Snippets, SSH keys, terminal settings, billing, Cloud, preview/SFTP, workflows. |

This keeps the product capable while protecting the first-run mental model.

### Simplification Principle

Do not ask users to understand all of these at once:

- agents
- SSH
- host keys
- snippets
- workflows
- files
- previews
- schedules
- billing
- Cloud
- widgets
- Watch
- APNs
- policy

For v1, teach one loop extremely well:

**My coding agent asks permission. I approve from my phone. The host keeps working safely.**

### Practical Next Pass

1. Move Library behind an **Advanced** row in Settings, or reduce the header icon prominence.
2. Hide incomplete snippet/workflow actions.
3. Remove mock SSH key host counts.
4. Keep Cloud/hosted-agent management gated and visually secondary.
5. Add a first-run checklist or demo approval to make the core loop tangible.
6. Re-review App Store screenshots so none feature owner-only or partial surfaces.

---
---

# Part 2 — Independent Review (Claude / Opus 4.8)

**Method:** Each claim below was checked against the shipping source in `Packages/ConduitKit/Sources/` and the handoff (`PAGES.md`, `screenshots/`). File:line references are included so findings are actionable.

**Bottom line:** I agree with the report's spirit and ~80% of its specifics. Digging changed three things materially — the in-session "second app" is already **dead code** (delete, don't reorganize), the three-step approval explainer **already ships** (so the demo + checklist matter more), and the Library should be **dissolved, not renamed**.

## What the report gets right (verified)

- **Mock SSH-key host counts are a real shipping bug.** `AppFeature/LibrarySupportViews.swift:21` → `// Mock host-count associations (TODO: wire real per-key host tracking)`, with `mockHostCounts` rendered into the live key rows (`:77`, `:112`, `:126`). Fake data in a security app destroys trust. Remove — ship-blocker.
- **Snippet "run" is unwired on the phone.** Only `AppFeature/PhoneWatchConnector.swift` / `ConduitCore/WatchApprovalTransfer.swift` implement `runSnippet`; there is no run wiring in the phone snippet views. Hiding the run affordance is correct.
- **Cloud/billing should stay quiet** — already gated behind `SettingsView.showPaidSurfaces`. Mostly done.
- **The core loop is genuinely good.** `01-inbox-populated` cards (risk chip → `$ command` → EDIT&RUN / DENY / ALLOW ALWAYS / APPROVE + the "Allow always applies to this exact tool, input, and path. Revoke rules in Settings." line) are clean and focused. Do not touch.

## Where the report is stale or wrong (the value of digging)

1. **"SessionShellView creates a second app inside the session" — that view is dead code.** `grep` finds `SessionShellView` referenced *nowhere* except its own definition (`AppFeature/SessionShellView.swift:42`). The shipping session is `SessionView`, presented via `AppRoot.isShowingLiveSession` (`AppRoot.swift:681`, `:744`). `SessionView` has **no** preview/files/diff/inbox switcher — only the block terminal plus sheets (snippet palette, port-forward, tmux, explain, raw history). The 5-way `SessionSurface` switcher (terminal/preview/files/diff/inbox) lives only in the dead `SessionShellView`, and it even Pro-gates *Diff* and *Inbox* (`SessionShellView.swift:168`, `:181`) — which would be wrong if it shipped. **Right move: delete `SessionShellView` + `SessionSurface`, don't "keep the session focused."**

2. **"Add a three-step approval explainer" — already shipped.** `00-onboarding-populated` reads **"agents ask. you approve. work resumes."** with "Coding agents pause for risky actions. Conduit sends the approval to your phone, then safely resumes the run." That recommendation is done. What's missing is the *checklist* and the *demo*, not the explainer.

3. **"Workflows reads like an automation product" — it's not surfaced.** `LibraryView.swift` shows exactly three cards: Snippets / SSH Keys / Agents. `AgentKit/WorkflowEngine.swift` exists but has no user-facing screen. Nothing to hide; don't spend effort here.

4. **Don't bury SSH keys, and don't lump Diff with the file browser.** Keys are part of the connect-trust story (Ed25519 password-less auth). Diff is part of *approvals* — you approve a write by reading its diff, and full-diff view is already free (`PAGES.md` p30: only *partial-hunk* apply is Pro). The report's IA table drops both into the "Advanced" junk drawer; that conflates a core trust step (keys) and a core approval surface (diff) with genuinely deferrable extras (SFTP/preview).

## Verdict — REMOVE

| Remove | Why | Effort |
|---|---|---|
| **Mock host-count chips** (`LibrarySupportViews.swift:21,77,112,126`) | Fake data in a shipping security app destroys trust | Trivial |
| **`SessionShellView` + `SessionSurface`** (whole file) | Dead code; the "app-inside-session" the report fears; carries a wrong Diff/Inbox Pro-gate | Trivial (delete) |
| **The Library hub as a concept** | After the cuts below it holds nothing real — dissolve it, don't rename to "Tools" | Small |
| **Snippet run/new affordances** | Unwired; snippets stay browse/import-only for v1 | Small |
| **Library folder icon in Settings header** (`SettingsView.swift:251`) | Only entry to a hub being dissolved | Trivial |

Why **dissolve** Library rather than rename: snippets are already reachable in-session (`SessionView` `showingSnippetPalette` → `SnippetPaletteSheet`), SSH keys belong in the Add-Host/connect flow, and Agents is Cloud-gated. Strip those three and the container is empty. Renaming an empty container to "Tools" just preserves dead weight behind a friendlier label.

## Verdict — ADD

| Add | Why it's the highest-leverage work | Effort |
|---|---|---|
| **Demo approval ("try it")** | For governed-approvals, the *real* first approval can take hours (set up host → run agent → hit a gate). A safe local sample card makes the product tangible on day one. The `Approval` model + `DebugSeeder.makeDebugApprovals()` (`AppFeature/DebugSeeder.swift:180`) already exist — promote that into a real, dismissible "sample" card. **Single most important addition.** | Medium |
| **First-run checklist** | "1 connect a host · 2 trust the host key · 3 wait for your first approval" as a 3-step strip on the Inbox empty state. Onboarding *explains* the loop; the checklist *gets the user into it.* | Small–Medium |
| **Move SSH-key generation into Add-Host/connect** | Keys are part of connecting, not a toolkit extra; reachable where they're needed | Small |
| **Trust/security panel** | One screen: host-key TOFU, Keychain storage, "what leaves the device" (nothing but your key → provider over TLS). `SettingsView.aboutConduitSection` already has the raw copy — promote it into a real trust surface | Small |

## KEEP exactly as-is

Four-tab shape (Inbox / Fleet / Activity / Settings) · the approval cards · the block terminal (`SessionView`) · the onboarding headline · the gated Billing/Cloud (`showPaidSurfaces`) · the policy editor and allow-always rules (these are *trust* surfaces — they belong).

## Suggested sequencing

1. **Kill mock host counts** — credibility ship-blocker; do first.
2. **Delete `SessionShellView`** — free de-risk; removes a wrong Pro-gate.
3. **Dissolve Library** — remove folder icon, hide snippet run/new, move keys into connect.
4. **Demo approval** — the activation centerpiece.
5. **First-run checklist** on the Inbox empty state.
6. **Re-shoot App Store screenshots** so none feature owner-only/partial surfaces.

## One disagreement, stated plainly

The report treats the **demo approval** as a minor "capability to add." Flip it — it's the most important item on the list, because it's the only one that lets a brand-new user *feel* the core loop before wiring up a single host.

---

## Evidence index (file:line)

- `AppFeature/LibrarySupportViews.swift:21` — mock host-count TODO; `:77,:112,:126` — rendered into key rows
- `AppFeature/SessionShellView.swift:14–37` — dead `SessionSurface` 5-way switcher; `:168,:181` — Diff/Inbox Pro-gate
- `AppFeature/AppRoot.swift:681,:744` — shipping session is `SessionView` via `isShowingLiveSession`
- `AppFeature/LibraryView.swift` — three cards only (Snippets/SSH Keys/Agents); no Workflows
- `SettingsFeature/SettingsView.swift:216–232` — Settings section order; `:251` — Library folder icon; `:412–429` — `aboutConduitSection` trust copy; `:392` — `showPaidSurfaces` gating
- `AppFeature/DebugSeeder.swift:180` — `makeDebugApprovals()` (reusable for a real demo card)
- `AgentKit/WorkflowEngine.swift` — workflow engine exists, no UI surface
- `PAGES.md` p00 (onboarding explainer ships), p30 (diff free; partial-hunk Pro)
