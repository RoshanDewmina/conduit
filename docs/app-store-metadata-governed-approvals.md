# App Store metadata — Governed Approvals v1

**Name:** Conduit — Agent Approvals
**Subtitle:** Govern Claude Code, Codex & opencode from your phone

**Promotional text:**
Your AI coding agents ask permission on your phone. Decide in one tap — even when you're away. Safe actions auto-handle by your policy; everything's logged.

**Description (opening):**
Conduit is mission control for the AI coding agents running on *your own* machine. A small bridge on your host enforces the policy *you* set — auto-allowing safe actions, blocking dangerous ones, and tapping you only for the calls that genuinely need a human. When it does, you get a notification with the exact command, the files it touches, and a risk read — and you approve, deny, or edit it in seconds, even when the app was closed. Works across Claude Code, OpenAI Codex, and opencode, with a full audit trail of every decision. Your code never leaves your host.

**Keywords:** claude code, codex, opencode, ai agent, approvals, ssh, devops, audit, policy, governance

**What to capture in screenshots (6.7"/6.1"/5.5" + iPad):**
1. Inbox with a high-risk approval card (command + blast radius).
2. A decision being made (Approve/Deny/Edit/Allow-always).
3. Fleet glance (cross-vendor status + spend).
4. Activity (while-you-were-away) feed.
5. Autonomy presets (Cautious/Balanced/Bypass).

**Decision-relay copy note:** the "even when you're away / app was closed" claim is true **only with the backend decision-relay shipped** (it is, in this milestone). If that relay is ever disabled, change the promo + description to "Open and decide in a tap" and drop "even when the app was closed."

**Privacy nutrition label:** device token (for push) + crash diagnostics if enabled; **no source code leaves the device** (state this). Verify against actual data flows before submission.

## Entitlements check (observed)

Findings from `project.yml` (read-only; not modified):

| Key | Value |
|-----|-------|
| `aps-environment` | `production` |
| `DEVELOPMENT_TEAM` | `39HM2X8GS6` |
| `com.apple.developer.icloud-services` | `[CloudKit]` |
| `com.apple.developer.icloud-container-identifiers` | `iCloud.dev.conduit.mobile` |

All four targets (`Conduit`, `ConduitWatch`, `ConduitWatchWidget`, `ConduitWidget`) share `DEVELOPMENT_TEAM: 39HM2X8GS6`. This looks like a free personal team ID — TODO(owner): confirm paid-account team id and replace `39HM2X8GS6` across all four targets in `project.yml` before archiving for App Store submission. iCloud/CloudKit and Push Notifications (`aps-environment: production`) are declared in the entitlements but require a paid account to activate.
