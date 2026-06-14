# Frontend Simplification Report - Governed Approvals v1

**Date:** 2026-06-13
**Context:** Conduit shifted from a broader SSH cockpit / agent-management app toward a governed-approvals product. This report captures which frontend surfaces still feel like pre-pivot weight, which capabilities should remain, and what the next simplification pass should try to achieve.

## What I Was Trying To Do

I was trying to judge the app against the current product thesis, not the old one.

The current thesis is: **a coding agent asks permission, the user approves from the phone, and the remote host resumes safely.** Anything that helps a first-time user understand and trust that loop should stay close to the surface. Anything that mainly supports generic SSH management, hosted-agent operations, snippets, workflows, file browsing, scheduling, or billing should either move behind Advanced, be hidden until production-ready, or be deferred.

The goal was not to make Conduit less capable. It was to make the first-use experience simpler, so the real capability is easier to understand.

## Core Product Spine To Keep

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

## Frontend Surface That Feels Too Heavy For v1

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

## Capabilities To Add Or Surface

The app can become simpler without becoming weaker by adding better guidance around the core loop:

- **How approvals work:** a three-step explainer: agent pauses, you decide, host resumes.
- **First-run checklist:** connect host, trust host key, wait for first approval.
- **Demo approval:** a safe local sample approval so users understand the card before a real agent event.
- **Trust/security panel:** explain host-key trust, Keychain storage, what leaves the device, and what stays local.
- **Better allow-always management:** make revoke behavior and scope explicit, especially local-only vs bridge policy behavior.

## Recommended Information Architecture

Use this as the target v1 shape:

| Level | Surface | Purpose |
|---|---|---|
| Primary | Inbox | Decide agent requests. |
| Primary | Fleet | Connect and monitor hosts. |
| Primary | Activity | Review what happened. |
| Primary | Settings | Security, keys, notifications, policy. |
| Secondary | Advanced | Snippets, SSH keys, terminal settings, billing, Cloud, preview/SFTP, workflows. |

This keeps the product capable while protecting the first-run mental model.

## Simplification Principle

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

## Practical Next Pass

1. Move Library behind an **Advanced** row in Settings, or reduce the header icon prominence.
2. Hide incomplete snippet/workflow actions.
3. Remove mock SSH key host counts.
4. Keep Cloud/hosted-agent management gated and visually secondary.
5. Add a first-run checklist or demo approval to make the core loop tangible.
6. Re-review App Store screenshots so none feature owner-only or partial surfaces.

