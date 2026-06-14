# App Store Metadata — Conduit

> Current positioning: **governed approvals** (mission control for AI coding agents).
> Owner-step checklist for getting on the store: `ship-gate-owner-steps.md`.

## Listing fields

- **Name:** Conduit — Agent Approvals
- **Subtitle (30):** Approve AI agents from anywhere
- **Category:** Primary *Developer Tools* · Secondary *Productivity*
- **Privacy / Support / Marketing URLs:** `https://conduit.dev/privacy` · `https://conduit.dev/support` · `https://conduit.dev`

**Promotional text:**
> Your AI coding agents ask permission on your phone. Decide in one tap while you're away from the terminal. Safe actions auto-handle by your policy; everything's logged.

**Description:**
> Conduit is mission control for the AI coding agents running on *your own* machine. A small bridge on your host enforces the policy *you* set — auto-allowing safe actions, blocking dangerous ones, and tapping you only for the calls that genuinely need a human. When it does, you get a notification with the exact command, the files it touches, and a risk read — and you approve, deny, or edit it in seconds while the app is active or resumed from the alert. Works across Claude Code, OpenAI Codex, and opencode, with a full audit trail of every decision. Your code never leaves your host.
>
> **Decide fast** — high-risk approvals surface with command, blast radius, and risk band. Allow, deny, allow-always, or edit-then-run.
> **Stay calm** — autonomy presets (Always ask / Auto-approve reads / Critical only) and per-repo policy mean most actions never reach you.
> **See everything** — a while-you-were-away activity feed logs every autonomous decision; a fleet glance shows cross-vendor status and spend in one place.
> **Go deep when needed** — a full block-mode terminal, diff review, SFTP browser, and dev-server preview live one tap down.

- **Keywords (100):** `claude code,codex,opencode,ai agent,approvals,ssh,devops,audit,policy,governance,terminal,fleet`
- **What's New (first version):** First release. Govern Claude Code, Codex, and opencode from your phone — approve, deny, or edit agent actions in one tap, set policy, and audit every decision.

## Screenshots to capture (6.9" 1320×2868 + iPad)
Canonical set: `docs/screenshots/governed-approvals/`.
1. Inbox — high-risk approval card (command + blast radius).
2. A decision being made (Approve / Deny / Edit / Allow-always).
3. Fleet glance (cross-vendor status + spend).
4. Activity (while-you-were-away) feed.
5. Autonomy presets (Always ask / Auto-approve reads / Critical only).

## Age rating → 4+
Made for kids: No · Unrestricted web: No · Gambling/Contests: No · Violence/Sexual content: None.

## App Review notes
Conduit governs AI coding agents on the developer's own remote host. It drives a *remote* shell over SSH — it does **not** download or execute code locally (pre-empts Guideline 2.5.2). The Inbox is pre-seeded in DEBUG builds so reviewers see approval cards without a live host. The Billing screen offers a $14.99 StoreKit non-consumable (`dev.conduit.mobile.pro`); use a sandbox account.

## Privacy nutrition label
No tracking. Declare: APNs device token (push registration for approval alerts) and subscription data if Stripe billing is enabled. State plainly: **source code never leaves the device.** Verify against actual data flows before submission.

> **Copy caveat:** do not claim closed-app lock-screen approval until physical-device APNs delivery and notification actions are verified. Simulator runs can verify relay decision logic, but APNs delivery is owner-gated.

## Entitlements (observed in `project.yml`, read-only)

| Key | Value |
|-----|-------|
| `aps-environment` | `production` |
| `DEVELOPMENT_TEAM` | `39HM2X8GS6` (paid; shared by all four targets) |
| `com.apple.developer.icloud-services` | `[CloudKit]` |
| `com.apple.developer.icloud-container-identifiers` | `iCloud.dev.conduit.mobile` |
