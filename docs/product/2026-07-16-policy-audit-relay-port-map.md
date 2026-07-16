# Policy + audit over relay — port map (Orca / Happier / Omnara → Lancer)

Date: 2026-07-16. Sources studied read-only in `research-repos/{orca,happier,omnara}`; all
competitor paths below are relative to those clone roots. `research-repos/lfg` was skipped (no
mobile/relay client — desktop-only, not relevant to this question).

**Licenses.** Orca: MIT (`research-repos/orca/LICENSE`, Lovecast Inc.) — patterns and code portable
with attribution. Happier: MIT (`research-repos/happier/LICENCE`, "Happy Coder Contributors") —
same. Omnara: Apache-2.0 (`research-repos/omnara/LICENSE`) — portable with attribution + NOTICE.
No verbatim code is reproduced below beyond short cited excerpts; anything ported to Lancer must
carry a source-repo + file comment per `AGENTS.md`.

## The gap

Lancer's Settings advertises a **Policy editor** (allow/ask/deny rules in `~/.lancer/policy.yaml`)
and an **Audit feed** (`~/.lancer/audit.log` tail) — both wired only to the SSH `DaemonChannel`
(`Packages/LancerKit/Sources/AppFeature/Settings/GovernanceHostActions.swift:36-55`). A
relay-only phone (no SSH session open) gets `Failure.sshRequired` ("Policy requires an SSH host
session. Relay-only pairings cannot reach this RPC yet.") for both `fetchPolicy`/`savePolicyYAML`
and `tailAudit`. `emergencyStop` (same file, line 26-34) is the one governance action that DOES
have a relay fallback (`bridge.sendEmergencyStop()`), proving the daemon already has a relay-arm
pattern to copy — see `daemon/lancerd/e2e_router.go:433-443` (`agentEmergencyStop` case) and
`:441-453` (`agentStatusQuery`, a read-only relay mirror of an SSH RPC using the same underlying
`s.queryAgentStatus`).

The owner directive: find the dominant competitor pattern for policy editing + audit/activity
over their cloud/relay channel (not a direct host session), and follow it.

---

## 1. Orca (stablyai/orca) — MIT

**Does it expose permission/approval POLICY editing from the client?** No separate policy-rules
concept exists at all. Orca has no allow/ask/deny rule file analogous to `policy.yaml`. The only
persistent "trust" state is a one-time setup-hook content-hash trust
(`mobile/src/tasks/setup-hook-trust.ts:8-22`, `trustedOrcaHooksWithSetupApproval`) — "did the user
already approve this exact setup script" — not a general permission-policy editor. Per-tool-call
approval is delegated entirely to the underlying CLI vendor's own permission system (e.g. Claude
Code's built-in prompts); Orca's client never models or edits rules, it only renders whatever the
CLI printed.

**Channel:** The approval UI (`src/renderer/src/components/native-chat/NativeChatApprovalCard.tsx:16-49`)
is a "Native renderer for an agent tool-approval (PermissionRequest) as an Allow/Deny card" whose
buttons literally "write the option's literal `send` string back to the agent" — i.e. it writes
raw keystrokes (a number to allow, ESC to deny) back onto the **same PTY channel** the terminal
output came over (`src/relay/pty-handler.ts`). There is no separate policy RPC on client or
server/daemon side — `src/relay/` contains only PTY, git, and fs handlers
(`src/relay/pty-handler.ts`, `src/relay/agent-exec-handler.ts`, `src/relay/git-handler.ts`), no
`policy.get`/`policy.save`-shaped message.

**Does it expose an audit/activity/decision log?** No. `grep -ril audit` across `mobile/src` and
`src/relay` returns nothing resembling a decision log. Session/worktree "activity" in the sidebar
(`src/renderer/src/components/sidebar/worktree-section-activity.ts`,
`worktree-agent-activity-summary.ts`) is live/ephemeral run-state (running/idle/waiting), not a
persisted history of past approve/deny decisions.

**What they do instead:** hide the concept entirely. There is no remote policy or audit UI —
approvals are ephemeral, parsed out of terminal text per-session, and forgotten once the pane
scrolls past. **Policy writes reach the host:** N/A — there is no policy to write; the "decision"
is a keystroke sent down the existing PTY relay channel, consumed directly by the CLI process's
own permission prompt.

## 2. Happier (happier-dev/happier) — MIT

**Does it expose permission POLICY editing from the client?** Yes, but as a **default permission
MODE picker**, not an allow/ask/deny rules engine. `packages/protocol/src/sessionMetadata/sessionPermissionModes.ts:3-11`
defines the fixed enum `SESSION_PERMISSION_MODES = ['default','acceptEdits','bypassPermissions',
'plan','read-only','safe-yolo','yolo']`. The client UI is
`apps/ui/sources/components/settings/session/PermissionsSettingsView.tsx:41,224-264` — a
per-provider (Claude/Codex/Gemini/...) dropdown that writes a locally-persisted setting
(`useSettingMutable('sessionDefaultPermissionModeByTargetKey')`, line 41) with an apply-timing
choice (immediate vs. next-prompt, lines 27, 101-112). This is a client preference, not a
server-pushed rules document.

**Channel:** The chosen mode is sent to the server/daemon **as a field on the session-start
request** — `packages/protocol/src/executionRunStartRequest.ts:113`: `permissionMode:
z.string().min(1)`. That request travels over Happier's normal cloud sync/relay channel (the same
one used to start any session), not a direct host-only session — confirmed by
`apps/cli/src/settings/permissions/permissionModeSeed.ts:9` (`normalizePermissionModeToIntent`)
and `apps/cli/src/backends/gemini/runGemini.ts:51` (`resolvePermissionModeSeedForAgentStart`)
consuming that same seeded value CLI-side to gate the spawned agent process. Per-call approval
decisions themselves are still rendered as interactive prompt cards
(`apps/ui/sources/components/tools/shell/permissions/PermissionPromptCard.tsx`) whose
allow/deny choice is auto-resolved when the mode implies it
(`apps/cli/src/settings/notifications/permissionRequestPush.ts:164-167`,
`isAutoApprovedByMode` — `yolo`/`bypassPermissions` always auto-approve; `safe-yolo` auto-approves
non-write-like tools) and otherwise pushed to the phone as a notification/prompt over the same
cloud channel.

**Does it expose an audit/activity/decision log?** Not as a distinct "audit" surface — grep for
`audit` across the whole repo turns up only test/tooling files
(`packages/cli-common/src/update/index.ts`, theme-token audit tests), nothing product-facing.
Instead, the **session transcript itself is the audit trail**: every tool call, permission prompt,
and decision is a message in the synced, cloud-persisted (optionally E2E-encrypted per
`docs/encryption.md` / AGENTS.md "Encryption storage modes" section) transcript, rendered by
`apps/ui/sources/components/sessions/transcript/**` (e.g. `ChatList`, `TranscriptEventRow.tsx`).
The client reads history back over the same sync channel as everything else, scrolled as chat, not
a separate log viewer.

**Policy writes reach the host:** pushed down through the normal cloud session-start/update RPC
(`executionRunStartRequest`), stored server-side, and read by the CLI daemon at session-start /
next-prompt boundary (`permissionModeSeed.ts`, `permissionModeApplyTiming` setting).

## 3. Omnara (omnara-ai/omnara) — Apache-2.0

**Does it expose permission POLICY editing from the client?** No. `grep -ril
"permission|policy|approv"` across `src/relay_server`, `apps/mobile`, `src/backend` returns
notification-permission and subscription-tier screens only
(`apps/mobile/src/screens/dashboard/NotificationSettingsScreen.tsx`,
`SubscriptionScreen.tsx`) — no agent tool-permission policy concept whatsoever. The one match in
`src/relay_server/sessions.py:129` (`history_policy`) is transcript-retention metadata, unrelated
to tool approval.

**Channel / mechanism:** Omnara's control surface is a structured `ask_question` MCP tool the
agent calls explicitly when it wants human input; the mobile app answers via the normal cloud
REST/websocket API (`src/relay_server/routes.py`, `websocket.py`). There is no allow/ask/deny rule
engine — the agent code itself decides when to pause and ask, and the client only answers
free-form questions, same channel as everything else (no direct-host-only path exists in this
architecture at all; Omnara is cloud-relay-only end to end).

**Does it expose an audit/activity/decision log?** Yes, but as **instance/session history**, not a
governance decision log: `src/backend/db/queries.py:381-396` sorts agent "instances" by
`last_activity`/`started_at`; the mobile `InstanceDetailScreen.tsx`
(`apps/mobile/src/screens/dashboard/InstanceDetailScreen.tsx`) shows that instance's full message
history, backed by a server-authoritative Postgres table the client reads via API — a
cloud-persisted mirror, read-only from the client's perspective, no local-file-only option.

**Policy writes reach the host:** N/A (no policy exists); question/answer round-trips are
server-mediated REST calls the agent process polls/receives via its own SDK connection to the
relay server.

---

## Dominant pattern across all three

None of the three competitors ship a Lancer-style **allow/ask/deny rules-file policy editor**
reachable from the client. The dominant pattern instead is:

1. **"Policy" flattens to a permission MODE, not a rules engine.** Happier's `permissionMode` enum
   and Orca/Omnara's "no policy, just per-call prompts" are two points on the same spectrum: nobody
   lets you edit fine-grained allow/deny rules remotely; at most you pick a coarse mode
   (default/plan/yolo/safe-yolo/etc.) that changes how aggressively individual prompts
   auto-resolve. The rules file, if any, stays host-local and is never round-tripped to the phone.
2. **The mode/decision travels over the SAME channel as everything else** — Happier bundles
   `permissionMode` into the ordinary session-start RPC over cloud sync; Orca/Omnara have no
   separate channel at all, so approvals ride the PTY stream or the MCP question/answer API.
   Nobody stands up a dedicated "policy socket."
3. **"Audit" is never a distinct log surface — it's the transcript/session-history the client
   already syncs.** Happier: the encrypted/plain session transcript. Omnara: the Postgres-backed
   instance message history via REST. Orca: nothing at all (ephemeral PTY scrollback only). No
   competitor built or exposed a decision-only audit feed independent of chat history.

## Port to Lancer

Given the above, the closest-to-Lancer, most defensible move is **Happier's shape**, scaled down:

1. **Replace/augment the policy editor's relay story with a permission-MODE arm, not a full
   policy.yaml round-trip.** Add a relay RPC pair mirroring the existing `agentEmergencyStop` /
   `agentStatusQuery` pattern in `daemon/lancerd/e2e_router.go:433-459`:
   - `agentPermissionModeGet` / `agentPermissionModeSet` — reads/writes a single coarse mode
     (e.g. `ask` / `acceptEdits` / `bypassPermissions` / `readOnly`, mapped onto
     `daemon/lancerd/policy/load.go`'s existing `Default` field in `policy.yaml`) rather than the
     full rule list. This keeps the daemon's actual policy engine (`daemon/lancerd/policy/`)
     untouched and host-authoritative — only the coarse default travels over relay, same as
     Happier's `permissionMode` field on `executionRunStartRequest`.
   - On the iOS side, add a case to `GovernanceHostActions` alongside `emergencyStop`: try
     `ApprovalRelay.shared.channel` first (SSH), then fall back to
     `relayFleetStore.firstConnectedMachine?.bridge` for the coarse mode get/set — the same
     fallback shape `emergencyStop` already uses (`GovernanceHostActions.swift:26-34`). Full
     per-rule editing (`fetchPolicy`/`savePolicyYAML`) can keep the current
     `Failure.sshRequired` gate — that matches the "nobody ports the full rules editor" finding.
2. **Give Audit a relay mirror the same way `agentStatusQuery` already mirrors SSH `agent.status`**
   (`e2e_router.go:441-453`, comment: "mirroring the SSH agent.status RPC ... Uses the same
   `s.queryAgentStatus` so both transports report identical behavior"). Add `agentAuditTail`
   calling the same `auditLog` reader used by `daemon/lancerd/audit.go` and the SSH `tailAudit`
   path, capped to a small `limit` (matches `GovernanceHostActions.tailAudit(limit: 100)`). This
   is strictly a read-only mirror — no competitor exposes audit as anything but a read surface
   from the client, so this involves zero new daemon business logic, just a relay pass-through
   like `agentStatusQuery`'s.
3. **Do not build a dedicated audit-log UI distinct from what already exists.** Since the
   dominant pattern treats "audit" as already-synced history, Lancer's existing Audit feed UI is
   fine as-is; the fix is purely wiring `agentAuditTail` into `GovernanceHostActions.tailAudit`'s
   fallback (same shape as item 1's mode fallback), not a redesign.

Net effect: two small relay arms (`agentPermissionModeGet/Set`, `agentAuditTail`) in
`daemon/lancerd/e2e_router.go` plus two fallback branches in
`Packages/LancerKit/Sources/AppFeature/Settings/GovernanceHostActions.swift`, following the exact
pattern already proven by `emergencyStop`/`agentEmergencyStop` and `agentStatusQuery` — no new
protocol concepts, no competitor UI to port, because none of the three built a full remote
policy-rules editor to copy.

## Per-repo license notes

- **Orca** (`research-repos/orca/LICENSE`) — MIT. Patterns and short code excerpts portable with
  attribution (repo + file). No verbatim blocks reused above beyond the quoted comment string.
- **Happier** (`research-repos/happier/LICENCE`) — MIT ("Happy Coder Contributors"). Same terms;
  the `permissionMode` field name/shape is a design pattern, not copied code.
- **Omnara** (`research-repos/omnara/LICENSE`) — Apache-2.0. Portable with attribution + NOTICE;
  nothing verbatim was needed since Omnara has no policy/audit surface to borrow from.
