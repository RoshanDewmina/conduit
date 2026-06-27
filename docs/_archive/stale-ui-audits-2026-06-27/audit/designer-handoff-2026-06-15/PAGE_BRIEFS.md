# Designer Page Briefs

These descriptions are functional only. They intentionally avoid direction about visual style, layout, colors, typography, motion, spacing, or component treatment. Use the screenshots as existing references, not as constraints to copy.

## Coverage Summary

- partial-or-route-gap: 40
- current-captured: 6
- future-needed: 2
- requires-live-data: 2
- decision-reference: 1

## Pages

### 01. Inbox · approval queue

- Slot: `inbox`
- Category: Core approvals
- Swift status: partial
- Board screenshot: [01-inbox-approval-queue.jpg](board-screenshots/01-inbox-approval-queue.jpg)
- Swift screenshot: [tab-inbox.png](swift-screenshots/tab-inbox.png)
- Purpose: Let the user review pending agent permission requests and decide whether work can continue.
- Primary user actions:
  - Approve or deny a request.
  - Open more detail about the requested command or file change.
  - Edit the requested command or input before running it.
  - Create a scoped allow rule when the request should not ask again.
- Required states:
  - Pending approvals
  - No pending approvals
  - Disconnected bridge
  - Policy warning or high-risk request
- Required data/content:
  - Agent name
  - Host and working directory
  - Requested tool or command
  - Risk level
  - Time waiting
  - Policy outcome
- Implementation note: Swift root exists and is populated; board is newer target composition.

### 02. Decision sheet · all 4 actions

- Slot: `sheet`
- Category: Core approvals
- Swift status: partial
- Board screenshot: [02-decision-sheet-all-4-actions.jpg](board-screenshots/02-decision-sheet-all-4-actions.jpg)
- Swift screenshot: none captured
- Purpose: Present the full decision surface for one approval request.
- Primary user actions:
  - Approve the request.
  - Deny the request.
  - Edit and run a modified request.
  - Open allow-always scope configuration.
- Required states:
  - Normal request
  - High-risk request
  - Blocked by policy
  - Submitting decision
- Required data/content:
  - Request summary
  - Exact command/input/path
  - Risk reason
  - Policy rule that applies
- Implementation note: Decision mechanics exist; this audit did not capture a stable isolated sheet route.

### 03. Critical · Face ID gate

- Slot: `critical`
- Category: Trust and safety
- Swift status: partial
- Board screenshot: [03-critical-face-id-gate.jpg](board-screenshots/03-critical-face-id-gate.jpg)
- Swift screenshot: none captured
- Purpose: Require local authentication before approving an irreversible or broad-impact request.
- Primary user actions:
  - Authenticate locally.
  - Cancel and return to the approval.
  - Review why the request is critical.
- Required states:
  - Authentication required
  - Authentication failed or canceled
  - Simulator/device without biometrics
- Required data/content:
  - Critical risk reason
  - Request details
  - Authentication result
- Implementation note: Biometric gate exists and simulator degrades gracefully; no captured Face ID prompt surface.

### 04. Decision · edit & run (3rd action)

- Slot: `editrun`
- Category: Core approvals
- Swift status: partial
- Board screenshot: [04-decision-edit-run-3rd-action.jpg](board-screenshots/04-decision-edit-run-3rd-action.jpg)
- Swift screenshot: [tab-inbox.png](swift-screenshots/tab-inbox.png)
- Purpose: Allow the user to safely modify an agent request before execution.
- Primary user actions:
  - Edit the command or input.
  - Run the edited version.
  - Cancel without sending a decision.
- Required states:
  - Valid edit
  - Invalid or empty edit
  - Submitting edited decision
- Required data/content:
  - Original request
  - Edited request
  - Host/workspace context
- Implementation note: Action is represented in the approval card; target board shows a dedicated edit sheet.

### 05. Decision · allow always → rule written

- Slot: `allowalways`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [05-decision-allow-always-rule-written.jpg](board-screenshots/05-decision-allow-always-rule-written.jpg)
- Swift screenshot: none captured
- Purpose: Confirm that an approval has been converted into a reusable scoped policy rule.
- Primary user actions:
  - Review the generated rule.
  - Undo or revoke the rule if needed.
  - Return to the approval queue.
- Required states:
  - Rule written
  - Rule write failed
  - Rule pending reload
- Required data/content:
  - Tool/action
  - Path or host scope
  - Policy effect
  - Expiration or revocation hint
- Implementation note: Scope sheet exists, but no stable automated screenshot was captured.

### 06. Inbox · first-run + demo

- Slot: `firstrun`
- Category: Onboarding and first run
- Swift status: partial
- Board screenshot: [06-inbox-first-run-demo.jpg](board-screenshots/06-inbox-first-run-demo.jpg)
- Swift screenshot: [gallery-onboarding.png](swift-screenshots/gallery-onboarding.png)
- Purpose: Explain the first useful approval loop and give the user a safe demo path.
- Primary user actions:
  - Start the first run or demo.
  - Connect a host if required.
  - Skip to the inbox if setup is already complete.
- Required states:
  - No host connected
  - Demo available
  - First approval available
- Required data/content:
  - Setup progress
  - Demo task
  - Next required action
- Implementation note: Swift onboarding exists; board combines first run and demo approval in inbox.

### 07. Inbox zero · returning user

- Slot: `empty`
- Category: Core approvals
- Swift status: partial
- Board screenshot: [07-inbox-zero-returning-user.jpg](board-screenshots/07-inbox-zero-returning-user.jpg)
- Swift screenshot: [gallery-states.jpg](swift-screenshots/gallery-states.jpg)
- Purpose: Show that there are no pending decisions while still communicating system readiness.
- Primary user actions:
  - Start a task.
  - Open fleet or activity for context.
  - Reconnect if the bridge is offline.
- Required states:
  - All caught up
  - Bridge offline
  - Waiting for first run
- Required data/content:
  - Connection state
  - Recent activity summary
  - Suggested next action
- Implementation note: State gallery covers empty/loading/error patterns; no real-app empty inbox capture in this pass.

### 08. Fleet · cross-vendor spend

- Slot: `fleet`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [08-fleet-cross-vendor-spend.jpg](board-screenshots/08-fleet-cross-vendor-spend.jpg)
- Swift screenshot: [tab-fleet.png](swift-screenshots/tab-fleet.png)
- Purpose: Show connected hosts, agents, provider usage, and operational status across the user’s control plane.
- Primary user actions:
  - Open a host or running agent.
  - Add or reconnect a host.
  - Review spend and provider status.
  - Open quota guard or host health details.
- Required states:
  - Healthy host
  - Offline host
  - Running agent
  - Provider limit warning
- Required data/content:
  - Host name
  - Agent/runtime
  - Model/provider
  - Spend/quota
  - Relay state
  - Health state
- Implementation note: Fleet root exists; board adds denser spend/privacy treatment.

### 09. Agent · run detail + stop (NEW)

- Slot: `rundetail`
- Category: Run control
- Swift status: partial
- Board screenshot: [09-agent-run-detail-stop-new.jpg](board-screenshots/09-agent-run-detail-stop-new.jpg)
- Swift screenshot: none captured
- Purpose: Show the details and controls for an active or recent agent run.
- Primary user actions:
  - Stop or pause the run.
  - Open logs, proof, or changed files.
  - Set a run budget.
  - Send a follow-up instruction when supported.
- Required states:
  - Running
  - Paused
  - Stopped
  - Completed
  - Failed
- Required data/content:
  - Goal
  - Current step
  - Elapsed time
  - Cost/budget
  - Changed files
  - Proof status
- Implementation note: Swift RunDetailView exists but has no direct gallery route captured.

### 10. Activity · while you were away

- Slot: `activity`
- Category: Audit and history
- Swift status: partial
- Board screenshot: [10-activity-while-you-were-away.jpg](board-screenshots/10-activity-while-you-were-away.jpg)
- Swift screenshot: [tab-activity.png](swift-screenshots/tab-activity.png)
- Purpose: Summarize important decisions, runs, and bridge events that happened while the user was away.
- Primary user actions:
  - Open an event detail.
  - Filter by host, agent, or risk.
  - Export or inspect audit evidence when available.
- Required states:
  - Populated activity
  - No recent activity
  - Unable to load audit feed
- Required data/content:
  - Event type
  - Timestamp
  - Host
  - Agent
  - Decision outcome
  - Audit hash or verification state
- Implementation note: Activity tab exists; populated audit data depends on daemon/live state.

### 11. Proof Card · completion attestation

- Slot: `proofcard`
- Category: Proof and completion
- Swift status: matches
- Board screenshot: [11-proof-card-completion-attestation.jpg](board-screenshots/11-proof-card-completion-attestation.jpg)
- Swift screenshot: [gallery-proof.jpg](swift-screenshots/gallery-proof.jpg)
- Purpose: Summarize what an agent completed and provide evidence that the result can be trusted.
- Primary user actions:
  - Review completed work.
  - Open changed files or CI results.
  - Share or save proof evidence.
- Required states:
  - Proof complete
  - Proof pending
  - Proof failed or missing
- Required data/content:
  - Goal
  - Changed files
  - Tests or CI outcome
  - Commit/branch
  - Evidence timestamp
- Implementation note: Dedicated gallery route captured.

### 12. Loop · goal → plan → CI → proof

- Slot: `loopdetail`
- Category: Loop supervision
- Swift status: partial
- Board screenshot: [12-loop-goal-plan-ci-proof.jpg](board-screenshots/12-loop-goal-plan-ci-proof.jpg)
- Swift screenshot: none captured
- Purpose: Show the full lifecycle of an agent loop from goal through plan, execution, CI, and proof.
- Primary user actions:
  - Review each loop stage.
  - Open CI or proof detail.
  - Stop or redirect the loop when supported.
- Required states:
  - Planning
  - Executing
  - Waiting on CI
  - Ready for proof
  - Completed
  - Failed
- Required data/content:
  - Goal
  - Plan steps
  - Current stage
  - CI events
  - Proof status
  - Policy exceptions
- Implementation note: Swift view exists with CI/proof sections; no direct screenshot route captured.

### 13. Worktrees · 3-column branch supervision

- Slot: `worktreeboard`
- Category: Branch supervision
- Swift status: partial
- Board screenshot: [13-worktrees-3-column-branch-supervision.jpg](board-screenshots/13-worktrees-3-column-branch-supervision.jpg)
- Swift screenshot: none captured
- Purpose: Compare multiple active worktrees or branches and help the user decide what should continue, merge, or stop.
- Primary user actions:
  - Open a worktree.
  - Compare progress across branches.
  - Stop or archive stale work.
  - Promote the best branch.
- Required states:
  - No worktrees
  - Multiple active worktrees
  - Conflict or stale branch
- Required data/content:
  - Branch name
  - Goal
  - Status
  - Last activity
  - Changed files
  - CI/proof state
- Implementation note: Swift view exists; no direct screenshot route captured.

### 14. Nudge · mid-run instruction

- Slot: `nudge`
- Category: Run control
- Swift status: Swift empty / not built
- Board screenshot: [14-nudge-mid-run-instruction.jpg](board-screenshots/14-nudge-mid-run-instruction.jpg)
- Swift screenshot: none captured
- Purpose: Send a mid-run instruction to an agent without restarting the task.
- Primary user actions:
  - Write a follow-up instruction.
  - Choose whether the instruction is advisory or blocking.
  - Submit or cancel the nudge.
- Required states:
  - Agent can receive nudges
  - Agent cannot receive nudges
  - Submitting nudge
- Required data/content:
  - Current run
  - Current step
  - Instruction text
  - Delivery state
- Implementation note: No Swift route/view found for the board nudge composer.

### 15. Switch model · mid-run

- Slot: `switch-model`
- Category: Run control
- Swift status: Swift empty / not built
- Board screenshot: [15-switch-model-mid-run.jpg](board-screenshots/15-switch-model-mid-run.jpg)
- Swift screenshot: none captured
- Purpose: Change the model or provider used by an active run when cost, quota, privacy, or capability needs change.
- Primary user actions:
  - Select another model/provider.
  - Review impact before switching.
  - Confirm or cancel the change.
- Required states:
  - Switch available
  - Switch blocked by policy
  - Quota-limited provider
- Required data/content:
  - Current model
  - Available models
  - Provider limits
  - Privacy/data-leaving-host status
  - Estimated cost impact
- Implementation note: No Swift route/view found for mid-run model switching.

### 16. CI / PR Event Feed

- Slot: `cievents`
- Category: CI and repository events
- Swift status: partial
- Board screenshot: [16-ci-pr-event-feed.jpg](board-screenshots/16-ci-pr-event-feed.jpg)
- Swift screenshot: none captured
- Purpose: Show repository checks, pull request events, and CI status related to agent work.
- Primary user actions:
  - Open a CI event.
  - Filter by run, branch, or status.
  - Retry or inspect failed checks when supported.
- Required states:
  - Checks passing
  - Checks failing
  - Checks running
  - No CI connected
- Required data/content:
  - Repository
  - Branch/PR
  - Check name
  - Status
  - Timestamp
  - Failure reason
- Implementation note: Backend/client support exists inside loop detail, but no standalone feed route was captured.

### 17. Budget · set-run-budget overlay

- Slot: `budget-sheet`
- Category: Cost control
- Swift status: partial
- Board screenshot: [17-budget-set-run-budget-overlay.jpg](board-screenshots/17-budget-set-run-budget-overlay.jpg)
- Swift screenshot: none captured
- Purpose: Set or adjust the spend limit for one run before or during execution.
- Primary user actions:
  - Enter a run budget.
  - Review current spend.
  - Confirm or cancel the budget change.
- Required states:
  - Budget available
  - Budget exceeded
  - Budget cannot be changed
- Required data/content:
  - Current spend
  - Proposed limit
  - Remaining quota
  - Provider
- Implementation note: Budget sheet exists behind RunDetailView; no stable sheet screenshot route captured.

### 18. Run detail · control surface (v2)

- Slot: `run-detail-v2`
- Category: Run control
- Swift status: partial
- Board screenshot: [18-run-detail-control-surface-v2.jpg](board-screenshots/18-run-detail-control-surface-v2.jpg)
- Swift screenshot: none captured
- Purpose: Provide a single control surface for monitoring, stopping, budgeting, and reviewing a run.
- Primary user actions:
  - Stop/pause/resume where available.
  - Open proof, files, CI, and activity.
  - Change budget or send a nudge when available.
- Required states:
  - Running
  - Waiting for user
  - Blocked
  - Complete
  - Failed
- Required data/content:
  - Goal
  - Status
  - Cost
  - Model
  - Host
  - Recent events
  - Available controls
- Implementation note: Swift RunDetailView exists; no direct screenshot route captured.

### 19. Dispatch · start a task (NEW)

- Slot: `dispatch`
- Category: Task start
- Swift status: partial
- Board screenshot: [19-dispatch-start-a-task-new.jpg](board-screenshots/19-dispatch-start-a-task-new.jpg)
- Swift screenshot: none captured
- Purpose: Start a new agent task with the right host, repository, provider, budget, and policy context.
- Primary user actions:
  - Enter a task goal.
  - Choose host or workspace.
  - Choose agent/model if available.
  - Set optional budget or caution level.
  - Submit the task.
- Required states:
  - Ready to submit
  - Missing host/workspace
  - Policy blocks dispatch
  - Submitting
- Required data/content:
  - Goal
  - Host
  - Repository/path
  - Agent runtime
  - Model/provider
  - Budget
  - Policy preset
- Implementation note: Swift DispatchView exists and is reachable as a sheet, but was not captured by stable automation.

### 20. Policy · presets + effect chips

- Slot: `policy`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [20-policy-presets-effect-chips.jpg](board-screenshots/20-policy-presets-effect-chips.jpg)
- Swift screenshot: none captured
- Purpose: Let the user choose and understand policy presets that determine what agents can do without asking.
- Primary user actions:
  - Select a policy preset.
  - Inspect what each preset permits or blocks.
  - Open custom policy editing.
- Required states:
  - Balanced/default preset
  - Stricter preset
  - Custom policy
  - Invalid policy
- Required data/content:
  - Preset name
  - Allowed actions
  - Ask-required actions
  - Denied actions
  - Risk coverage
- Implementation note: Swift policy editor exists; no direct screenshot route captured.

### 21. Policy · edit policy.yaml + reload

- Slot: `policy-yaml`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [21-policy-edit-policy-yaml-reload.jpg](board-screenshots/21-policy-edit-policy-yaml-reload.jpg)
- Swift screenshot: none captured
- Purpose: Edit the bridge policy file and reload it on the host.
- Primary user actions:
  - View policy YAML.
  - Edit and save policy YAML.
  - Reload policy on the bridge.
  - Open policy simulation.
- Required states:
  - Saved
  - Unsaved edits
  - Reload failed
  - Invalid YAML
- Required data/content:
  - Policy file path
  - YAML body
  - Validation errors
  - Reload result
- Implementation note: Swift bridge policy editor/reload path exists; live bridge data not captured.

### 22. Settings · notifications + quiet hours

- Slot: `notifications`
- Category: Settings
- Swift status: partial
- Board screenshot: [22-settings-notifications-quiet-hours.jpg](board-screenshots/22-settings-notifications-quiet-hours.jpg)
- Swift screenshot: [tab-settings.png](swift-screenshots/tab-settings.png)
- Purpose: Configure which agent and approval events notify the user and when notifications should be quiet.
- Primary user actions:
  - Enable or disable notification classes.
  - Set quiet hours.
  - Test notification delivery when supported.
- Required states:
  - Notifications enabled
  - Notifications disabled
  - Quiet hours active
  - Permission missing
- Required data/content:
  - Notification categories
  - Quiet-hours schedule
  - Permission state
- Implementation note: Settings root captured; detailed notification controls are below/inside settings.

### 23. Settings · provider keys (multi-vendor)

- Slot: `providerkeys`
- Category: Provider setup
- Swift status: partial
- Board screenshot: [23-settings-provider-keys-multi-vendor.jpg](board-screenshots/23-settings-provider-keys-multi-vendor.jpg)
- Swift screenshot: none captured
- Purpose: Manage provider credentials and model access without exposing secrets unnecessarily.
- Primary user actions:
  - Add or update provider credentials.
  - Verify a provider connection.
  - Remove a provider credential.
- Required states:
  - Provider connected
  - Missing credential
  - Credential invalid
  - Verification pending
- Required data/content:
  - Provider name
  - Credential status
  - Available models
  - Last verified time
- Implementation note: Swift provider keys view exists; no pushed view screenshot captured.

### 24. Settings · Library dissolved

- Slot: `settings`
- Category: Settings
- Swift status: partial
- Board screenshot: [24-settings-library-dissolved.jpg](board-screenshots/24-settings-library-dissolved.jpg)
- Swift screenshot: [tab-settings.png](swift-screenshots/tab-settings.png)
- Purpose: Collect account, security, policy, notifications, billing, provider, relay, and advanced configuration entry points.
- Primary user actions:
  - Open a settings section.
  - Review app and bridge status.
  - Manage account/billing/security settings.
- Required states:
  - Connected
  - Disconnected
  - Needs setup
  - Entitlement missing
- Required data/content:
  - Account state
  - Bridge state
  - Security settings
  - Billing state
  - Provider state
- Implementation note: Settings root exists and Library is not a root tab; target board is denser.

### 25. Policy Simulator · past N days

- Slot: `policysimulator`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [25-policy-simulator-past-n-days.jpg](board-screenshots/25-policy-simulator-past-n-days.jpg)
- Swift screenshot: none captured
- Purpose: Estimate how a policy would have affected recent agent activity before applying it.
- Primary user actions:
  - Choose a time window.
  - Run a simulation.
  - Review changed outcomes.
  - Apply or revise the policy.
- Required states:
  - Ready to simulate
  - Simulation running
  - Simulation complete
  - Simulation failed
- Required data/content:
  - Policy input
  - Period
  - Allowed/asked/denied counts
  - Top affected rules
  - Representative events
- Implementation note: Swift simulator view exists from policy editor; no screenshot route captured.

### 26. Secrets · vault + pending requests

- Slot: `secrets`
- Category: Secrets and permissions
- Swift status: partial
- Board screenshot: [26-secrets-vault-pending-requests.jpg](board-screenshots/26-secrets-vault-pending-requests.jpg)
- Swift screenshot: none captured
- Purpose: Show available secret metadata and pending agent requests for secret access.
- Primary user actions:
  - Approve or deny a secret request.
  - Inspect secret metadata.
  - Revoke or rotate access where supported.
- Required states:
  - No secrets
  - Secrets available
  - Pending secret requests
  - Backend unavailable
- Required data/content:
  - Secret name/metadata
  - Requester
  - Requested scope
  - Decision history
- Implementation note: Swift secrets view exists; live secret data is owner-only/live-data.

### 27. Onboarding 1 · hero

- Slot: `onb-1`
- Category: Onboarding
- Swift status: partial
- Board screenshot: [27-onboarding-1-hero.jpg](board-screenshots/27-onboarding-1-hero.jpg)
- Swift screenshot: [gallery-onboarding.png](swift-screenshots/gallery-onboarding.png)
- Purpose: Introduce the product’s primary job and start the setup flow.
- Primary user actions:
  - Continue setup.
  - Learn what needs to be connected.
- Required states:
  - First launch
  - Returning user who has not completed setup
- Required data/content:
  - Setup progress
  - Primary value proposition
  - Next setup step
- Implementation note: Swift onboarding exists but visual direction differs from the board.

### 28. Onboarding 2 · pair the bridge (no SSH)

- Slot: `onb-2`
- Category: Onboarding
- Swift status: partial
- Board screenshot: [28-onboarding-2-pair-the-bridge-no-ssh.jpg](board-screenshots/28-onboarding-2-pair-the-bridge-no-ssh.jpg)
- Swift screenshot: [gallery-onboarding-b.jpg](swift-screenshots/gallery-onboarding-b.jpg)
- Purpose: Pair the phone with the bridge or local control plane without requiring the user to understand SSH first.
- Primary user actions:
  - Start pairing.
  - Scan or enter a pairing code.
  - Handle pairing failure.
- Required states:
  - Ready to pair
  - Pairing
  - Pairing failed
  - Pairing complete
- Required data/content:
  - Pairing code/link
  - Bridge identity
  - Connection state
- Implementation note: Alternate onboarding gallery captured; exact board step not isolated.

### 29. Onboarding 3 · choose caution

- Slot: `onb-3`
- Category: Onboarding
- Swift status: partial
- Board screenshot: [29-onboarding-3-choose-caution.jpg](board-screenshots/29-onboarding-3-choose-caution.jpg)
- Swift screenshot: [gallery-onboarding-b.jpg](swift-screenshots/gallery-onboarding-b.jpg)
- Purpose: Choose the initial caution/autonomy level for agent approvals.
- Primary user actions:
  - Select a caution level.
  - Review what the level means functionally.
  - Continue setup.
- Required states:
  - Default level selected
  - Strict level selected
  - Custom level selected
- Required data/content:
  - Caution level
  - Actions that ask
  - Actions that auto-allow
  - Actions that deny
- Implementation note: Caution/autonomy exists in onboarding/settings; exact board step not isolated.

### 30. Onboarding 4 · first run + demo

- Slot: `onb-4`
- Category: Onboarding
- Swift status: partial
- Board screenshot: [30-onboarding-4-first-run-demo.jpg](board-screenshots/30-onboarding-4-first-run-demo.jpg)
- Swift screenshot: [gallery-onboarding.png](swift-screenshots/gallery-onboarding.png)
- Purpose: Guide the user into the first run or demo after basic setup is complete.
- Primary user actions:
  - Start first run.
  - Open demo approval.
  - Finish onboarding.
- Required states:
  - Ready for first run
  - Demo available
  - Setup incomplete
- Required data/content:
  - Selected host
  - Selected policy
  - Demo task
- Implementation note: First-run demo treatment is board-only as a composed artboard.

### 31. Advanced · add host over SSH

- Slot: `addhost`
- Category: Host setup
- Swift status: partial
- Board screenshot: [31-advanced-add-host-over-ssh.jpg](board-screenshots/31-advanced-add-host-over-ssh.jpg)
- Swift screenshot: none captured
- Purpose: Connect a new host that agents can use for work.
- Primary user actions:
  - Enter host details.
  - Choose authentication method.
  - Test connection.
  - Save host.
- Required states:
  - Empty form
  - Testing connection
  - Authentication needed
  - Connection failed
  - Host saved
- Required data/content:
  - Host name
  - Address
  - Port
  - Username
  - Authentication status
- Implementation note: Swift AddHostView exists; sheet capture was not stable in this pass.

### 32. Advanced · trust host key (TOFU)

- Slot: `tofu`
- Category: Host setup and trust
- Swift status: owner-only/live-data
- Board screenshot: [32-advanced-trust-host-key-tofu.jpg](board-screenshots/32-advanced-trust-host-key-tofu.jpg)
- Swift screenshot: none captured
- Purpose: Ask the user to trust or reject a host key the first time a host is connected.
- Primary user actions:
  - Review host fingerprint.
  - Trust and continue.
  - Reject and stop connection.
- Required states:
  - Unknown host key
  - Fingerprint changed
  - Trusted key stored
- Required data/content:
  - Host
  - Fingerprint
  - Previous fingerprint if changed
  - Connection target
- Implementation note: Requires live SSH host-key flow; not faked in screenshots.

### 33. Advanced · SSH keys (kept · real data)

- Slot: `sshkeys`
- Category: Credentials
- Swift status: owner-only/live-data
- Board screenshot: [33-advanced-ssh-keys-kept-real-data.jpg](board-screenshots/33-advanced-ssh-keys-kept-real-data.jpg)
- Swift screenshot: none captured
- Purpose: Show SSH key material status and keychain-backed access without exposing private key contents.
- Primary user actions:
  - Add or import a key.
  - Unlock a key when needed.
  - Remove or rotate a key.
- Required states:
  - No key
  - Key available
  - Unlock required
  - Key verification failed
- Required data/content:
  - Key label
  - Fingerprint
  - Host association
  - Unlock state
- Implementation note: Keychain/real-key state exists but was not captured with private data.

### 34. Power-user · live block session

- Slot: `terminal`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [34-power-user-live-block-session.jpg](board-screenshots/34-power-user-live-block-session.jpg)
- Swift screenshot: [gallery-session.jpg](swift-screenshots/gallery-session.jpg)
- Purpose: Provide deeper access to a live session transcript and command blocks for users who need to inspect execution.
- Primary user actions:
  - Read live output.
  - Send input when allowed.
  - Switch between block and raw session modes when supported.
- Required states:
  - Connected
  - Connecting
  - Disconnected
  - Raw full-screen program active
- Required data/content:
  - Host
  - Current directory
  - Command blocks
  - Output stream
  - Connection state
- Implementation note: Session gallery captured; live terminal data is owner-only/live-data.

### 35. Diff · approve a write

- Slot: `diff`
- Category: File change review
- Swift status: matches
- Board screenshot: [35-diff-approve-a-write.jpg](board-screenshots/35-diff-approve-a-write.jpg)
- Swift screenshot: [gallery-diff.jpg](swift-screenshots/gallery-diff.jpg)
- Purpose: Let the user inspect a proposed file change before approving an agent write.
- Primary user actions:
  - Review changed hunks.
  - Approve or deny the write.
  - Open affected file detail.
- Required states:
  - Diff available
  - Large diff
  - Binary or unsupported file
  - Write already decided
- Required data/content:
  - File path
  - Added/removed lines
  - Requesting agent
  - Decision state
- Implementation note: Dedicated diff gallery route captured.

### 36. File viewer · tap a file → drawer (NEW)

- Slot: `fileviewer`
- Category: File review
- Swift status: partial
- Board screenshot: [36-file-viewer-tap-a-file-drawer-new.jpg](board-screenshots/36-file-viewer-tap-a-file-drawer-new.jpg)
- Swift screenshot: [gallery-filepreview.jpg](swift-screenshots/gallery-filepreview.jpg)
- Purpose: Preview a file or selected changed file from an agent run.
- Primary user actions:
  - Open a file.
  - Move between files.
  - Return to run or diff context.
- Required states:
  - File loaded
  - File unavailable
  - Unsupported file type
- Required data/content:
  - File path
  - File content or preview
  - Related run/change
- Implementation note: File preview gallery captured; board drawer interaction is newer target design.

### 37. Relay pairing · E2E status

- Slot: `e2erelay`
- Category: Relay and security
- Swift status: partial
- Board screenshot: [37-relay-pairing-e2e-status.jpg](board-screenshots/37-relay-pairing-e2e-status.jpg)
- Swift screenshot: none captured
- Purpose: Pair and monitor the encrypted relay path used for approvals and status updates.
- Primary user actions:
  - Start pairing.
  - Verify relay state.
  - Disconnect or repair pairing.
- Required states:
  - Unpaired
  - Pairing
  - Paired
  - Disconnected
  - Error
- Required data/content:
  - Relay URL/state
  - Pairing state
  - Encryption/session state
- Implementation note: Swift relay pairing view exists; no pushed view screenshot captured.

### 38. Doctor · health check

- Slot: `doctor`
- Category: Diagnostics
- Swift status: partial
- Board screenshot: [38-doctor-health-check.jpg](board-screenshots/38-doctor-health-check.jpg)
- Swift screenshot: none captured
- Purpose: Run health checks that explain why setup, bridge, relay, notifications, or provider access is not working.
- Primary user actions:
  - Run checks.
  - Open fix instructions for failed checks.
  - Re-run after fixing.
- Required states:
  - All checks pass
  - Some checks fail
  - Checks running
  - Unable to run checks
- Required data/content:
  - Check name
  - Pass/fail state
  - Failure reason
  - Suggested fix
- Implementation note: Swift doctor view exists; no pushed view screenshot captured.

### 39. Allow always · scope config

- Slot: `allowalways-scope`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [39-allow-always-scope-config.jpg](board-screenshots/39-allow-always-scope-config.jpg)
- Swift screenshot: none captured
- Purpose: Define the exact scope of a reusable allow rule before it is saved.
- Primary user actions:
  - Choose tool/action scope.
  - Choose host/path/repository scope.
  - Set expiration if supported.
  - Save or cancel rule.
- Required states:
  - Safe narrow scope
  - Broad scope warning
  - Invalid scope
- Required data/content:
  - Tool/action
  - Host
  - Path/repository
  - Risk level
  - Expiration
- Implementation note: Swift scope sheet exists; no stable isolated screenshot route captured.

### 40. Trust & Privacy · what leaves your host

- Slot: `trust-privacy`
- Category: Trust and privacy
- Swift status: partial
- Board screenshot: [40-trust-privacy-what-leaves-your-host.jpg](board-screenshots/40-trust-privacy-what-leaves-your-host.jpg)
- Swift screenshot: [tab-settings.png](swift-screenshots/tab-settings.png)
- Purpose: Explain what data leaves the host and what remains local for each product capability.
- Primary user actions:
  - Review data paths.
  - Open related settings for relay, providers, or keys.
- Required states:
  - Local-only path
  - Cloud provider path
  - Relay path
  - Unknown or misconfigured path
- Required data/content:
  - Capability
  - Data sent
  - Destination
  - Control/revocation path
- Implementation note: Settings entry exists; detailed trust screen was not captured.

### 41. Fleet · model + privacy

- Slot: `fleet-privacy`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [41-fleet-model-privacy.jpg](board-screenshots/41-fleet-model-privacy.jpg)
- Swift screenshot: [tab-fleet.png](swift-screenshots/tab-fleet.png)
- Purpose: Show model, provider, and privacy state per host or active agent.
- Primary user actions:
  - Inspect a host/agent.
  - Open provider settings.
  - Switch to a safer provider when supported.
- Required states:
  - Local model
  - Cloud model
  - Relay protected
  - Provider missing
- Required data/content:
  - Host
  - Agent
  - Model
  - Provider
  - Data path
  - Quota/spend
- Implementation note: Fleet has model/privacy badges; board detail is newer target design.

### 42. Audit · tamper-evident chain

- Slot: `auditchain`
- Category: Audit and compliance
- Swift status: partial
- Board screenshot: [42-audit-tamper-evident-chain.jpg](board-screenshots/42-audit-tamper-evident-chain.jpg)
- Swift screenshot: none captured
- Purpose: Show tamper-evident audit records and verification status for decisions and bridge events.
- Primary user actions:
  - Verify audit chain.
  - Export audit records.
  - Open event detail.
- Required states:
  - Verified
  - Verification failed
  - No audit records
  - Exporting
- Required data/content:
  - Audit events
  - Hash/verification state
  - Export file
  - Event metadata
- Implementation note: Audit chain view and verification model exist; no pushed view screenshot captured.

### 43. Host health · daemon detail

- Slot: `hosthealth`
- Category: Fleet diagnostics
- Swift status: partial
- Board screenshot: [43-host-health-daemon-detail.jpg](board-screenshots/43-host-health-daemon-detail.jpg)
- Swift screenshot: [tab-fleet.png](swift-screenshots/tab-fleet.png)
- Purpose: Show detailed daemon and host health for one connected machine.
- Primary user actions:
  - Refresh health.
  - Open failed check details.
  - Reconnect or run doctor.
- Required states:
  - Healthy
  - Degraded
  - Offline
  - Unknown
- Required data/content:
  - Daemon status
  - Version
  - Latency
  - Disk/process checks
  - Last heartbeat
- Implementation note: Swift has host health polling/badge; no daemon-detail screen found.

### 44. Billing · spend + quota remaining

- Slot: `usage`
- Category: Billing and quota
- Swift status: matches
- Board screenshot: [44-billing-spend-quota-remaining.jpg](board-screenshots/44-billing-spend-quota-remaining.jpg)
- Swift screenshot: [gallery-billing.jpg](swift-screenshots/gallery-billing.jpg)
- Purpose: Show spend, quota, usage, and billing state across providers or the app account.
- Primary user actions:
  - Review usage.
  - Open plan or billing management.
  - Inspect quota alerts.
- Required states:
  - Within quota
  - Near quota
  - Over quota
  - Billing unavailable
- Required data/content:
  - Current spend
  - Quota remaining
  - Billing period
  - Provider breakdown
  - Plan
- Implementation note: Dedicated billing gallery route captured.

### 45. Lancer Pro · paywall

- Slot: `paywall`
- Category: Billing
- Swift status: matches
- Board screenshot: [45-lancer-pro-paywall.jpg](board-screenshots/45-lancer-pro-paywall.jpg)
- Swift screenshot: [gallery-paywall.jpg](swift-screenshots/gallery-paywall.jpg)
- Purpose: Explain why a paid capability is unavailable and let the user upgrade or compare plans.
- Primary user actions:
  - Review locked capability.
  - Compare plan options.
  - Start upgrade or dismiss.
- Required states:
  - Feature locked
  - Already subscribed
  - Store unavailable
- Required data/content:
  - Feature name
  - Plan options
  - Entitlement state
- Implementation note: Dedicated paywall gallery route captured.

### 46. Quota · per-provider dashboard

- Slot: `quotaguard`
- Category: Cost control
- Swift status: partial
- Board screenshot: [46-quota-per-provider-dashboard.jpg](board-screenshots/46-quota-per-provider-dashboard.jpg)
- Swift screenshot: none captured
- Purpose: Show per-provider quota and spend guardrails so users can prevent unexpected cost or blocked runs.
- Primary user actions:
  - Review quota by provider.
  - Open provider detail.
  - Adjust alerts or limits where supported.
- Required states:
  - Healthy quota
  - Near limit
  - Limit reached
  - Provider unavailable
- Required data/content:
  - Provider
  - Spend
  - Quota
  - Alert threshold
  - Recent usage
- Implementation note: Swift QuotaGuardView exists; no direct screenshot route captured.

### 47. Library hub → dissolved

- Slot: `rm-lib`
- Category: Information architecture decision
- Swift status: matches
- Board screenshot: [47-library-hub-dissolved.jpg](board-screenshots/47-library-hub-dissolved.jpg)
- Swift screenshot: [tab-settings.png](swift-screenshots/tab-settings.png)
- Purpose: Document that Library should not be a primary app destination and its useful pieces should move into more relevant flows.
- Primary user actions:
  - Use this as a design constraint, not a user-facing screen.
- Required states:
  - Not a shipping screen
- Required data/content:
  - Moved features
  - Destination surfaces
- Implementation note: Swift root IA has no Library tab; library responsibilities are dissolved.

### 48. Session surface switcher → deleted

- Slot: `rm-shell`
- Category: Information architecture decision
- Swift status: matches
- Board screenshot: [48-session-surface-switcher-deleted.jpg](board-screenshots/48-session-surface-switcher-deleted.jpg)
- Swift screenshot: none captured
- Purpose: Document that a session surface switcher should not be a primary navigation model.
- Primary user actions:
  - Use this as a design constraint, not a user-facing screen.
- Required states:
  - Not a shipping screen
- Required data/content:
  - Kept deep tools
  - Removed primary navigation concept
- Implementation note: No root session surface switcher is present in captured root tabs.

### 49. Mock SSH host counts → fixed (real data)

- Slot: `rm-keys`
- Category: Data correctness decision
- Swift status: partial
- Board screenshot: [49-mock-ssh-host-counts-fixed-real-data.jpg](board-screenshots/49-mock-ssh-host-counts-fixed-real-data.jpg)
- Swift screenshot: [tab-fleet.png](swift-screenshots/tab-fleet.png)
- Purpose: Document that host and key counts should reflect real data rather than placeholder counts.
- Primary user actions:
  - Use real counts wherever this information appears.
- Required states:
  - No real data
  - Real data available
  - Unable to load data
- Required data/content:
  - Host count
  - Key count
  - Credential status
- Implementation note: Fleet uses real/debug-seeded host data; exact board note is not a product screen.

### 50. Decisions applied

- Slot: `decisions`
- Category: Design decision log
- Swift status: intentionally deferred
- Board screenshot: [50-decisions-applied.jpg](board-screenshots/50-decisions-applied.jpg)
- Swift screenshot: none captured
- Purpose: Summarize product decisions that should guide the remaining page designs.
- Primary user actions:
  - Use as designer reference.
- Required states:
  - Not a shipping screen
- Required data/content:
  - Decision
  - Reason
  - Affected surfaces
- Implementation note: Board decision card is not meant to become a Swift screen.

### 51. Risk ramp · independent of brand

- Slot: `ramp`
- Category: Risk model
- Swift status: partial
- Board screenshot: [51-risk-ramp-independent-of-brand.jpg](board-screenshots/51-risk-ramp-independent-of-brand.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Define how risk levels should map to approval behavior independent of provider branding.
- Primary user actions:
  - Use risk mapping when designing approval, policy, and notification flows.
- Required states:
  - Low risk
  - Medium risk
  - High risk
  - Critical risk
- Required data/content:
  - Risk level
  - Default action
  - Authentication requirement
  - Policy override
- Implementation note: Risk logic and UI states exist; board card is a product/design rationale artifact.

### 52. SessionView · full-screen block terminal

- Slot: `sessionview`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [52-session-view.jpg](board-screenshots/52-session-view.jpg)
- Swift screenshot: [gallery-session.jpg](swift-screenshots/gallery-session.jpg)
- Purpose: Provide a full-screen block terminal session showing agent work, live command blocks with status, output streaming, and a chat input bar.
- Primary user actions:
  - Read live output from running commands.
  - Send input or follow-up instructions.
  - Inspect block status (running, completed, failed).
- Required states:
  - Connected and streaming
  - Connecting
  - Disconnected
  - Idle prompt
- Required data/content:
  - Host and directory context
  - Command blocks with timestamps
  - Output stream per block
  - Connection state
- Implementation note: Session gallery route exists; board adds richer block card treatment and persistent chat input.

### 53. ChatTranscriptView · scrollable block transcript

- Slot: `chat-transcript`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [53-chat-transcript-view.jpg](board-screenshots/53-chat-transcript-view.jpg)
- Swift screenshot: [gallery-session.jpg](swift-screenshots/gallery-session.jpg)
- Purpose: Render a scrollable transcript of agent tool cards, commands, outputs, and status per block.
- Primary user actions:
  - Scroll through block history.
  - Tap a block to expand or inspect.
  - Open block action menu.
- Required states:
  - Populated transcript
  - Empty transcript
  - Streaming new blocks
- Required data/content:
  - Block list
  - Per-block status and output
  - Agent identity
- Implementation note: ChatTranscriptView exists; board adds refined block card layout.

### 54. ToolCardView · individual agent tool card

- Slot: `toolcard`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [54-tool-card-view.jpg](board-screenshots/54-tool-card-view.jpg)
- Swift screenshot: [gallery-session.jpg](swift-screenshots/gallery-session.jpg)
- Purpose: Display one agent tool invocation with its command, output, status badges, blast chips, and action buttons.
- Primary user actions:
  - View command and output.
  - Approve, deny, or edit a pending tool.
  - Inspect blast radius chips.
- Required states:
  - Running
  - Completed
  - Failed
  - Waiting for approval
- Required data/content:
  - Tool name
  - Command
  - Output
  - Blast chips (files, git, network, credentials)
  - Status badge
- Implementation note: ToolCardView exists; board adds blast chips and richer status treatment.

### 55. ChatInputBar · bottom input bar

- Slot: `chat-input`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [55-chat-input-bar.jpg](board-screenshots/55-chat-input-bar.jpg)
- Swift screenshot: [gallery-session.jpg](swift-screenshots/gallery-session.jpg)
- Purpose: Provide a persistent text input at the bottom of the session for sending commands to the agent.
- Primary user actions:
  - Type a command or message.
  - Send input.
  - Open attachments or shortcuts.
- Required states:
  - Idle
  - Typing
  - Sending
  - Disabled (disconnected)
- Required data/content:
  - Prompt prefix (›)
  - Placeholder text
  - Send button state
- Implementation note: ChatInputBar exists in the session gallery; board refines the accessory rail integration.

### 56. KeyboardAccessoryRail · shortcut rail

- Slot: `keyboard-rail`
- Category: Power-user session
- Swift status: partial
- Board screenshot: [56-keyboard-accessory-rail.jpg](board-screenshots/56-keyboard-accessory-rail.jpg)
- Swift screenshot: none captured
- Purpose: Show a horizontal rail of common command chips above the keyboard for quick input.
- Primary user actions:
  - Tap a shortcut chip to insert the command.
  - Scroll the chip list.
- Required states:
  - Default chips
  - Customized chips
  - Empty (no shortcuts configured)
- Required data/content:
  - Chip labels (git, npm, swift, curl, etc.)
  - Associated commands
- Implementation note: Keyboard rail exists as a configurable accessory; board shows default chip set.

### 57. QRScannerView · camera QR scanner

- Slot: `qr-scanner`
- Category: Onboarding and pairing
- Swift status: partial
- Board screenshot: [57-qr-scanner-view.jpg](board-screenshots/57-qr-scanner-view.jpg)
- Swift screenshot: [gallery-onboarding-b.jpg](swift-screenshots/gallery-onboarding-b.jpg)
- Purpose: Scan a bridge pairing QR code as the primary onboarding path.
- Primary user actions:
  - Scan a QR code.
  - Enter pairing code manually as fallback.
  - Handle scan failure or timeout.
- Required states:
  - Scanning
  - Code scanned
  - Scan failed
  - Permission denied
- Required data/content:
  - Camera feed
  - Viewfinder overlay
  - Manual entry link
  - Instructions
- Implementation note: QR scanning exists in onboarding; board adds refined viewfinder and instruction overlay.

### 58. BridgePairingView · bridge pairing screen

- Slot: `bridge-pairing`
- Category: Relay and security
- Swift status: partial
- Board screenshot: [58-bridge-pairing-view.jpg](board-screenshots/58-bridge-pairing-view.jpg)
- Swift screenshot: none captured
- Purpose: Show a 6-digit pairing code, QR toggle, and connection status for bridge pairing.
- Primary user actions:
  - Display pairing code to the bridge CLI.
  - Switch between code and QR display.
  - Monitor connection progress.
- Required states:
  - Waiting for pairing
  - Pairing in progress
  - Paired
  - Pairing failed
- Required data/content:
  - Pairing code
  - QR representation
  - Bridge identity
  - Connection status
- Implementation note: Bridge pairing flow exists in onboarding/relay views; board isolates the dedicated pairing card.

### 59. SSHConnectOverlay · full-screen connecting overlay

- Slot: `ssh-connect`
- Category: Host setup
- Swift status: partial
- Board screenshot: [59-ssh-connect-overlay.jpg](board-screenshots/59-ssh-connect-overlay.jpg)
- Swift screenshot: none captured
- Purpose: Show a full-screen dark overlay with animated orbital rings, PixelAvatar, and phase text during SSH connection.
- Primary user actions:
  - Cancel connection.
  - Monitor connection progress.
- Required states:
  - Connecting
  - Verifying
  - Setup
  - Done
  - Failed
- Required data/content:
  - Host identity
  - Phase label
  - PixelAvatar
  - Cancel action
- Implementation note: Connection overlay exists in live SSH flow; board adds orbital animation treatment.

### 60. WorkspacesView · saved hosts list

- Slot: `workspaces`
- Category: Host setup
- Swift status: partial
- Board screenshot: [60-workspaces-view.jpg](board-screenshots/60-workspaces-view.jpg)
- Swift screenshot: [tab-fleet.png](swift-screenshots/tab-fleet.png)
- Purpose: List saved SSH hosts with avatar, status dot, name, address, last used time, and FAB to add.
- Primary user actions:
  - Open a host.
  - Add a new host.
  - Delete or edit an existing host.
- Required states:
  - Populated list
  - Empty list
  - Offline hosts
  - Loading
- Required data/content:
  - Host name
  - PixelAvatar
  - Status dot
  - Address
  - Last used time
- Implementation note: Host list exists in fleet tab; board adds dedicated workspaces root with FAB.

### 61. HostEditorView · SSH host form

- Slot: `host-editor`
- Category: Host setup
- Swift status: partial
- Board screenshot: [61-host-editor-view.jpg](board-screenshots/61-host-editor-view.jpg)
- Swift screenshot: none captured
- Purpose: Provide a form for adding or editing SSH host configuration.
- Primary user actions:
  - Enter name, hostname, port, username.
  - Choose auth method (password or key).
  - Test connection.
  - Save host.
- Required states:
  - Empty form
  - Testing connection
  - Connection test succeeded
  - Connection test failed
  - Saving
- Required data/content:
  - Host name
  - Hostname/IP
  - Port
  - Username
  - Auth method
  - Test result
- Implementation note: AddHostView exists; board refines the form layout and test-connection UX.

### 62. HostKeyConfirmSheet · TOFU host key trust

- Slot: `host-key-confirm`
- Category: Host setup and trust
- Swift status: partial
- Board screenshot: [62-host-key-confirm-sheet.jpg](board-screenshots/62-host-key-confirm-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Present a bottom sheet for TOFU host key trust decision on first connection.
- Primary user actions:
  - Review host fingerprint.
  - Trust and connect.
  - Cancel and stop connection.
- Required states:
  - Unknown host key
  - Fingerprint changed
  - Trusted
- Required data/content:
  - Host name
  - SHA256 fingerprint visual
  - Trust and Cancel buttons
- Implementation note: TOFU sheet exists in live SSH flow; board adds fingerprint visual and refined sheet design.

### 63. TerminalSettingsView · shell and color scheme

- Slot: `terminal-settings`
- Category: Settings
- Swift status: partial
- Board screenshot: [63-terminal-settings-view.jpg](board-screenshots/63-terminal-settings-view.jpg)
- Swift screenshot: none captured
- Purpose: Configure default shell, color scheme, font size, and auto-connect toggle for the terminal.
- Primary user actions:
  - Select default shell (bash/zsh/fish).
  - Pick a color scheme.
  - Adjust font size.
  - Toggle auto-connect.
- Required states:
  - Default settings
  - Customized settings
  - Unsupported shell selected
- Required data/content:
  - Shell list
  - Color scheme list (Dark+, Solarized, Nord, Dracula, Gruvbox)
  - Font size slider
  - Auto-connect toggle
- Implementation note: Terminal settings exist; board adds curated color scheme selection.

### 64. E2ERelayPairingView · relay status and pairing

- Slot: `e2e-relay`
- Category: Relay and security
- Swift status: partial
- Board screenshot: [64-e2e-relay-pairing-view.jpg](board-screenshots/64-e2e-relay-pairing-view.jpg)
- Swift screenshot: none captured
- Purpose: Display relay connection status, E2E encryption badge, pairing QR, and disconnect option.
- Primary user actions:
  - View relay state.
  - Re-pair or disconnect.
  - Inspect encryption details.
- Required states:
  - Paired
  - Pairing
  - Unpaired
  - Disconnected
- Required data/content:
  - Relay URL/state
  - Encryption badge (X25519 + ChaCha20-Poly1305)
  - Pairing QR
  - Disconnect button
- Implementation note: Relay pairing view exists; board adds encryption algorithm badge.

### 65. TrustPrivacyView · data path explanations

- Slot: `trust-privacy-detail`
- Category: Trust and privacy
- Swift status: partial
- Board screenshot: [65-trust-privacy-view.jpg](board-screenshots/65-trust-privacy-view.jpg)
- Swift screenshot: none captured
- Purpose: Explain per-feature what data stays local, goes to provider, or goes through relay with color-coded badges.
- Primary user actions:
  - Review data paths for each capability.
  - Open related settings.
- Required states:
  - Local-only path
  - Cloud provider path
  - Relay path
  - Unknown path
- Required data/content:
  - Feature name
  - Data classification
  - Destination badge
  - Control path
- Implementation note: Settings entry exists; board adds dedicated detail view with color-coded path badges.

### 66. PremiumComparisonView · Free vs Pro

- Slot: `premium-compare`
- Category: Billing
- Swift status: partial
- Board screenshot: [66-premium-comparison-view.jpg](board-screenshots/66-premium-comparison-view.jpg)
- Swift screenshot: [gallery-paywall.jpg](swift-screenshots/gallery-paywall.jpg)
- Purpose: Compare Free and Pro plan features with check marks and plan columns.
- Primary user actions:
  - Review feature differences.
  - Start upgrade flow.
- Required states:
  - Free plan
  - Pro plan
  - Loading
- Required data/content:
  - Feature list
  - Plan columns
  - Check marks
  - Upgrade call to action
- Implementation note: Paywall gallery exists; board adds dedicated comparison view.

### 67. BillingView · plan and invoice history

- Slot: `billing-history`
- Category: Billing
- Swift status: partial
- Board screenshot: [67-billing-view.jpg](board-screenshots/67-billing-view.jpg)
- Swift screenshot: [gallery-billing.jpg](swift-screenshots/gallery-billing.jpg)
- Purpose: Show current plan, next billing date, payment method, and invoice history.
- Primary user actions:
  - View current plan.
  - Change payment method.
  - Browse invoice history.
- Required states:
  - Active subscription
  - No subscription
  - Payment method missing
  - Loading
- Required data/content:
  - Plan name
  - Next billing date
  - Payment method
  - Invoice list
- Implementation note: Billing gallery exists; board integrates plan, invoices, and payment method in one view.

### 68. ProviderKeysView · API key management

- Slot: `provider-keys-detail`
- Category: Provider setup
- Swift status: partial
- Board screenshot: [68-provider-keys-view.jpg](board-screenshots/68-provider-keys-view.jpg)
- Swift screenshot: none captured
- Purpose: Manage provider API keys with status badges for Anthropic, OpenAI, OpenRouter, Ollama, Google, Azure.
- Primary user actions:
  - Add or update a provider key.
  - Verify a key.
  - Remove a key.
- Required states:
  - Connected
  - Missing key
  - Invalid key
  - Verifying
- Required data/content:
  - Provider name
  - Key status badge
  - Available models
  - Last verified
- Implementation note: Provider keys view exists; board adds expanded provider list and status badges.

### 69. ShortcutBarEditor · customize shortcut bar

- Slot: `shortcut-editor`
- Category: Settings
- Swift status: partial
- Board screenshot: [69-shortcut-bar-editor.jpg](board-screenshots/69-shortcut-bar-editor.jpg)
- Swift screenshot: none captured
- Purpose: Provide drag-reorder and enable/disable toggles for the keyboard accessory shortcut bar.
- Primary user actions:
  - Reorder shortcuts by dragging.
  - Enable or disable individual shortcuts.
- Required states:
  - Default layout
  - Customized layout
  - Empty (all disabled)
- Required data/content:
  - Shortcut list
  - Drag handle
  - Enable toggle
- Implementation note: Shortcut bar exists; board adds dedicated editor for customization.

### 70. SnippetEditorView · snippet editing

- Slot: `snippet-editor`
- Category: Settings
- Swift status: partial
- Board screenshot: [70-snippet-editor-view.jpg](board-screenshots/70-snippet-editor-view.jpg)
- Swift screenshot: none captured
- Purpose: Edit a command snippet with name, command body, and arguments list.
- Primary user actions:
  - Edit snippet name.
  - Edit command text.
  - Add or remove arguments.
  - Save or discard changes.
- Required states:
  - Editing new snippet
  - Editing existing snippet
  - Invalid command
  - Saving
- Required data/content:
  - Snippet name
  - Command body
  - Arguments list
- Implementation note: Snippets exist in code; board adds dedicated editor view.

### 71. SyncStatusView · iCloud sync status

- Slot: `sync-status`
- Category: Settings
- Swift status: partial
- Board screenshot: [71-sync-status-view.jpg](board-screenshots/71-sync-status-view.jpg)
- Swift screenshot: none captured
- Purpose: Display iCloud sync status, last sync time, connected devices, and sync toggle.
- Primary user actions:
  - View sync state.
  - Toggle sync on or off.
  - View connected devices.
- Required states:
  - Synced
  - Syncing
  - Sync paused
  - iCloud unavailable
- Required data/content:
  - Sync status
  - Last sync time
  - Device list
  - Sync toggle
- Implementation note: iCloud sync exists; board adds dedicated status view.

### 72. PolicyEditorView · raw YAML editor

- Slot: `policy-yaml-editor`
- Category: Policy and governance
- Swift status: partial
- Board screenshot: [72-policy-editor-view.jpg](board-screenshots/72-policy-editor-view.jpg)
- Swift screenshot: none captured
- Purpose: Provide a raw YAML policy editor with syntax coloring and Save & Reload on Bridge action.
- Primary user actions:
  - Edit YAML content.
  - Save and reload on bridge.
  - Validate YAML syntax.
- Required states:
  - Valid YAML
  - Invalid YAML
  - Saving
  - Reload pending
- Required data/content:
  - YAML body
  - Syntax highlighting
  - Validation errors
  - Reload status
- Implementation note: Policy YAML editor exists; board adds syntax coloring treatment.

### 73. SecretsView · secrets vault

- Slot: `secrets-vault`
- Category: Secrets and permissions
- Swift status: partial
- Board screenshot: [73-secrets-view.jpg](board-screenshots/73-secrets-view.jpg)
- Swift screenshot: none captured
- Purpose: Display secrets vault with name, type (env/file/api-key), scope, and pending agent requests.
- Primary user actions:
  - Approve or deny a secret request.
  - View secret metadata.
  - Revoke or rotate access.
- Required states:
  - No secrets
  - Secrets available
  - Pending requests
  - Backend unavailable
- Required data/content:
  - Secret name
  - Type badge
  - Scope
  - Requester
- Implementation note: Secrets view exists; board adds type badges and request queue.

### 74. AuditView · chronological audit events

- Slot: `audit-events`
- Category: Audit and compliance
- Swift status: partial
- Board screenshot: [74-audit-view.jpg](board-screenshots/74-audit-view.jpg)
- Swift screenshot: none captured
- Purpose: Show chronological audit events grouped by time with hash verification status.
- Primary user actions:
  - Browse audit events.
  - Verify an event hash.
  - Export audit log.
- Required states:
  - Populated
  - Empty
  - Verification failed
  - Exporting
- Required data/content:
  - Event list grouped by time
  - Event type
  - Hash status
  - Timestamp
- Implementation note: Audit chain view exists; board adds time-grouped layout and hash badges.

### 75. DoctorView · health check diagnostics

- Slot: `doctor-diag`
- Category: Diagnostics
- Swift status: partial
- Board screenshot: [75-doctor-view.jpg](board-screenshots/75-doctor-view.jpg)
- Swift screenshot: none captured
- Purpose: Run health checks for daemon, hooks, keys, policy, host, and relay with pass/fail badges.
- Primary user actions:
  - Run all checks.
  - Open fix instructions.
  - Re-run individual checks.
- Required states:
  - All pass
  - Some fail
  - Running
  - Unable to run
- Required data/content:
  - Check name
  - Pass/fail badge
  - Failure reason
  - Suggested fix
- Implementation note: Doctor view exists; board adds richer per-check detail.

### 76. KeysView · SSH key management

- Slot: `ssh-keys-manage`
- Category: Credentials
- Swift status: partial
- Board screenshot: [76-keys-view.jpg](board-screenshots/76-keys-view.jpg)
- Swift screenshot: none captured
- Purpose: Manage SSH keys with fingerprints, host associations, and last-used times.
- Primary user actions:
  - View generated keys.
  - Add or import a key.
  - Remove or rotate a key.
- Required states:
  - No keys
  - Keys available
  - Key locked
- Required data/content:
  - Key label
  - Fingerprint
  - Host usage
  - Last used time
- Implementation note: SSH key management exists; board adds host usage and last-used columns.

### 77. AgentsView · cloud-hosted agent list

- Slot: `agents-list`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [77-agents-view.jpg](board-screenshots/77-agents-view.jpg)
- Swift screenshot: none captured
- Purpose: List cloud-hosted agents with status, model, and spend per agent.
- Primary user actions:
  - Open an agent detail.
  - Create a new agent.
  - Pause or resume an agent.
- Required states:
  - Populated list
  - Empty list
  - Loading
  - Offline agents
- Required data/content:
  - Agent name
  - Status badge
  - Model/provider
  - Spend
- Implementation note: Agent list exists in fleet tab; board adds dedicated agents root.

### 78. AgentDetailView · agent detail header

- Slot: `agent-detail`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [78-agent-detail-view.jpg](board-screenshots/78-agent-detail-view.jpg)
- Swift screenshot: none captured
- Purpose: Show agent detail header with run history list and controls (Pause/Resume, Schedule, Delete).
- Primary user actions:
  - View agent info.
  - Pause or resume the agent.
  - Open run history.
  - Delete agent.
- Required states:
  - Agent active
  - Agent paused
  - Agent offline
  - No run history
- Required data/content:
  - Agent name
  - Model
  - Status
  - Spend
  - Run list
- Implementation note: Agent detail exists; board adds run history and schedule controls.

### 79. AgentRunDetailView · agent run with live output

- Slot: `agent-run-detail`
- Category: Run control
- Swift status: partial
- Board screenshot: [79-agent-run-detail-view.jpg](board-screenshots/79-agent-run-detail-view.jpg)
- Swift screenshot: none captured
- Purpose: Show run detail with live output stream and controls (Stop, Pause, Budget, Ship, Diff).
- Primary user actions:
  - Monitor live output.
  - Stop or pause the run.
  - Set budget.
  - Ship or review diff.
- Required states:
  - Running
  - Paused
  - Completed
  - Failed
- Required data/content:
  - Goal
  - Live output stream
  - Controls
  - Budget progress
- Implementation note: Run detail view exists; board adds Ship/Diff action buttons.

### 80. AgentFilesView · agent workspace file browser

- Slot: `agent-files`
- Category: File review
- Swift status: partial
- Board screenshot: [80-agent-files-view.jpg](board-screenshots/80-agent-files-view.jpg)
- Swift screenshot: none captured
- Purpose: Browse agent workspace files with a directory tree.
- Primary user actions:
  - Navigate directory tree.
  - Open a file for preview.
  - Return to run context.
- Required states:
  - Files available
  - No files
  - Loading
- Required data/content:
  - Directory tree
  - File names
  - File sizes
  - Permissions
- Implementation note: File browsing exists in run context; board adds dedicated files view.

### 81. AgentWorkspaceView · repository view

- Slot: `agent-workspace`
- Category: Repository
- Swift status: partial
- Board screenshot: [81-agent-workspace-view.jpg](board-screenshots/81-agent-workspace-view.jpg)
- Swift screenshot: none captured
- Purpose: Show repository and workspace context with branch, commits, and CI status.
- Primary user actions:
  - Switch branch.
  - View commit history.
  - Inspect CI status.
- Required states:
  - Repository connected
  - No repository
  - CI passing
  - CI failing
- Required data/content:
  - Repository name
  - Branch
  - Recent commits
  - CI status badge
- Implementation note: Workspace context exists in loop detail; board adds dedicated workspace view.

### 82. AgentOrgView · org members list

- Slot: `agent-org`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [82-agent-org-view.jpg](board-screenshots/82-agent-org-view.jpg)
- Swift screenshot: none captured
- Purpose: Show organization members list with roles and status.
- Primary user actions:
  - View member roles.
  - Invite new members.
  - Remove a member.
- Required states:
  - Populated list
  - Empty list
  - Loading
- Required data/content:
  - Member name
  - Role
  - Status
- Implementation note: Org features are cloud-only; board previews the member management view.

### 83. AgentExecView · single execution detail

- Slot: `agent-exec`
- Category: Run control
- Swift status: partial
- Board screenshot: [83-agent-exec-view.jpg](board-screenshots/83-agent-exec-view.jpg)
- Swift screenshot: none captured
- Purpose: Show a single agent execution with command, arguments, environment, and output.
- Primary user actions:
  - View command and args.
  - Inspect environment.
  - Read output.
- Required states:
  - Completed
  - Running
  - Failed
- Required data/content:
  - Command
  - Arguments
  - Environment variables
  - Output
- Implementation note: Execution detail exists in run history; board isolates it as a standalone view.

### 84. CreateAgentSheet · new hosted agent form

- Slot: `create-agent`
- Category: Fleet and providers
- Swift status: partial
- Board screenshot: [84-create-agent-sheet.jpg](board-screenshots/84-create-agent-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Provide a bottom sheet form for creating a new hosted agent with name, runtime, model, and budget.
- Primary user actions:
  - Enter agent name.
  - Select runtime.
  - Choose model.
  - Set budget.
  - Create or cancel.
- Required states:
  - Empty form
  - Submitting
  - Creation failed
- Required data/content:
  - Agent name field
  - Runtime picker
  - Model picker
  - Budget input
- Implementation note: Agent creation exists; board adds a dedicated sheet form.

### 85. AgentBillingSheet · prepaid credits

- Slot: `agent-billing`
- Category: Billing
- Swift status: partial
- Board screenshot: [85-agent-billing-sheet.jpg](board-screenshots/85-agent-billing-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Show prepaid credits, per-agent spend breakdown, and top-up options.
- Primary user actions:
  - View credit balance.
  - Top up credits.
  - View spend breakdown.
- Required states:
  - Credits available
  - Credits low
  - Credits exhausted
  - Loading
- Required data/content:
  - Credit balance
  - Per-agent spend
  - Top-up options
  - Spend history
- Implementation note: Billing sheet exists behind cloud agent flows; board adds credit-focused layout.

### 86. EditScheduleSheet · schedule editor

- Slot: `edit-schedule`
- Category: Run control
- Swift status: partial
- Board screenshot: [86-edit-schedule-sheet.jpg](board-screenshots/86-edit-schedule-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Provide a schedule editor with cron expression, command, and enabled toggle.
- Primary user actions:
  - Enter or edit cron expression.
  - Set command.
  - Toggle schedule on/off.
- Required states:
  - Valid cron
  - Invalid cron
  - Schedule enabled
  - Schedule disabled
- Required data/content:
  - Cron expression
  - Command
  - Enabled toggle
  - Next run preview
- Implementation note: Scheduling exists for cloud agents; board adds dedicated editor sheet.

### 87. LoopDetailView · full agent loop lifecycle

- Slot: `loop-detail`
- Category: Loop supervision
- Swift status: partial
- Board screenshot: [87-loop-detail-view.jpg](board-screenshots/87-loop-detail-view.jpg)
- Swift screenshot: none captured
- Purpose: Show the full agent loop lifecycle: goal through plan, execution, CI, and proof with timeline stages.
- Primary user actions:
  - Review each loop stage.
  - Open CI or proof detail.
  - Stop or redirect the loop.
- Required states:
  - Planning
  - Executing
  - Waiting on CI
  - Ready for proof
  - Completed
  - Failed
- Required data/content:
  - Goal
  - Plan steps
  - Current stage
  - CI events
  - Proof status
- Implementation note: Loop detail view exists; board adds timeline stage visualization.

### 88. RunDetailView · streaming output + controls

- Slot: `run-detail`
- Category: Run control
- Swift status: partial
- Board screenshot: [88-run-detail-view.jpg](board-screenshots/88-run-detail-view.jpg)
- Swift screenshot: none captured
- Purpose: Provide streaming output view with budget progress and controls (Stop, Pause, Set Budget, Nudge).
- Primary user actions:
  - Read live output.
  - Stop or pause run.
  - Set or change budget.
  - Send a nudge.
- Required states:
  - Running
  - Paused
  - Completed
  - Failed
- Required data/content:
  - Goal
  - Output stream
  - Budget progress
  - Available controls
- Implementation note: Run detail exists; board adds budget progress bar and nudge control.

### 89. QuotaGuardView · per-provider quota dashboard

- Slot: `quota-guard`
- Category: Cost control
- Swift status: partial
- Board screenshot: [89-quota-guard-view.jpg](board-screenshots/89-quota-guard-view.jpg)
- Swift screenshot: none captured
- Purpose: Show per-provider quota dashboard with spend vs cap, time windows, and alert thresholds.
- Primary user actions:
  - Review quota by provider.
  - Adjust alert thresholds.
  - Open provider detail.
- Required states:
  - Within quota
  - Near limit
  - Limit reached
  - Provider unavailable
- Required data/content:
  - Provider name
  - Spend
  - Cap
  - Time window
  - Alert threshold
- Implementation note: QuotaGuardView exists; board adds time windows and alert threshold controls.

### 90. Git, Files & Preview · kanban and ship

- Slot: `worktree-board`
- Category: Branch supervision
- Swift status: partial
- Board screenshot: [90-worktree-board-view.jpg](board-screenshots/90-worktree-board-view.jpg)
- Swift screenshot: none captured
- Purpose: Show 3-column kanban for git worktrees: Active, Stale, Merged.
- Primary user actions:
  - Move worktree between columns.
  - Open a worktree detail.
  - Promote or archive.
- Required states:
  - Active worktrees
  - Stale worktrees
  - No worktrees
- Required data/content:
  - Worktree columns
  - Branch name
  - Status
  - Last activity
- Implementation note: Worktree board exists; board adds kanban column layout.

### 91. RunShipSheet · ship changes bottom sheet

- Slot: `run-ship`
- Category: Branch supervision
- Swift status: partial
- Board screenshot: [91-run-ship-sheet.jpg](board-screenshots/91-run-ship-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Provide a bottom sheet for shipping changes with files list, commit message, and PR toggle.
- Primary user actions:
  - Review changed files.
  - Write commit message.
  - Toggle PR creation.
  - Ship or cancel.
- Required states:
  - Ready to ship
  - Shipping
  - Ship failed
- Required data/content:
  - Changed files list
  - Commit message
  - PR toggle
  - Ship status
- Implementation note: Ship flow exists in loop/run context; board adds dedicated ship sheet.

### 92. ShipItSheet · ship from loop context

- Slot: `ship-it`
- Category: Branch supervision
- Swift status: partial
- Board screenshot: [92-ship-it-sheet.jpg](board-screenshots/92-ship-it-sheet.jpg)
- Swift screenshot: none captured
- Purpose: Ship changes from loop context with goal summary, changed files, and commit preview.
- Primary user actions:
  - Review goal and changes.
  - Write or confirm commit message.
  - Execute ship.
- Required states:
  - Changes staged
  - Shipping
  - Ship failed
- Required data/content:
  - Goal summary
  - Changed files
  - Commit message
  - Ship status
- Implementation note: Ship sheet exists; board adds goal summary context.

### 93. FilesView · SFTP file browser

- Slot: `sftp-browser`
- Category: File review
- Swift status: partial
- Board screenshot: [93-files-view.jpg](board-screenshots/93-files-view.jpg)
- Swift screenshot: none captured
- Purpose: Provide an SFTP file browser with breadcrumb navigation, permissions, sizes, and dates.
- Primary user actions:
  - Navigate directories.
  - Open a file.
  - View file metadata.
- Required states:
  - Files available
  - Directory empty
  - Loading
  - Connection lost
- Required data/content:
  - Breadcrumb trail
  - File name
  - Permissions
  - Size
  - Modification date
- Implementation note: SFTP file browser exists; board adds breadcrumb and detail columns.

### 94. FilePreviewView · monospace file preview

- Slot: `file-preview`
- Category: File review
- Swift status: partial
- Board screenshot: [94-file-preview-view.jpg](board-screenshots/94-file-preview-view.jpg)
- Swift screenshot: [gallery-filepreview.jpg](swift-screenshots/gallery-filepreview.jpg)
- Purpose: Display a monospace file preview with line numbers and language badge.
- Primary user actions:
  - Scroll file content.
  - Copy text.
  - Return to browser or run context.
- Required states:
  - File loaded
  - File unavailable
  - Unsupported type
- Required data/content:
  - File content
  - Line numbers
  - Language badge
  - File path
- Implementation note: File preview gallery exists; board adds language badge treatment.

### 95. DiffView · side-by-side git diff

- Slot: `diff-side-by-side`
- Category: File change review
- Swift status: matches
- Board screenshot: [95-diff-view.jpg](board-screenshots/95-diff-view.jpg)
- Swift screenshot: [gallery-diff.jpg](swift-screenshots/gallery-diff.jpg)
- Purpose: Show a side-by-side git diff with green/red highlighting and line numbers.
- Primary user actions:
  - Review changes.
  - Approve or deny.
  - Open file detail.
- Required states:
  - Diff available
  - Large diff
  - Binary file
- Required data/content:
  - Added lines
  - Removed lines
  - Line numbers
  - File path
- Implementation note: Diff gallery exists; board adds side-by-side layout.

### 96. PreviewSurface · WKWebView preview

- Slot: `preview-surface`
- Category: Preview and browsing
- Swift status: partial
- Board screenshot: [96-preview-surface.jpg](board-screenshots/96-preview-surface.jpg)
- Swift screenshot: none captured
- Purpose: Provide a WKWebView preview frame with URL bar for previewing served content.
- Primary user actions:
  - View rendered content.
  - Interact with the web view.
- Required states:
  - Content loaded
  - Loading
  - Content failed
- Required data/content:
  - URL
  - Web content
- Implementation note: Web preview exists; board refines the toolbar integration.

### 97. PreviewToolbar · URL bar and controls

- Slot: `preview-toolbar`
- Category: Preview and browsing
- Swift status: partial
- Board screenshot: [97-preview-toolbar.jpg](board-screenshots/97-preview-toolbar.jpg)
- Swift screenshot: none captured
- Purpose: Provide URL bar with refresh, back/forward navigation, and port selector for the preview surface.
- Primary user actions:
  - Enter or edit URL.
  - Refresh page.
  - Navigate back or forward.
  - Select port.
- Required states:
  - Page loaded
  - Loading
  - Invalid URL
- Required data/content:
  - URL text
  - Refresh button
  - Back/forward buttons
  - Port selector
- Implementation note: Preview toolbar exists in preview context; board refines port selector.

### 98. Design System · DSButtonGallery

- Slot: `ds-button-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [98-ds-button-gallery.jpg](board-screenshots/98-ds-button-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show all button variants: primary, ghost, danger, quiet in normal and disabled states.
- Primary user actions:
  - Browse variants.
  - Inspect disabled and pressed states.
- Required states:
  - All variants visible
  - None (static reference)
- Required data/content:
  - Variant labels
  - Disabled variants
- Implementation note: Button gallery exists in the component gallery; board shows all variants in one frame.

### 99. Design System · DSChipGallery

- Slot: `ds-chip-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [99-ds-chip-gallery.jpg](board-screenshots/99-ds-chip-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show all chip types: file, git, network, credentials, Pro, soon, new.
- Primary user actions:
  - Browse chip variants.
- Required states:
  - All variants visible
- Required data/content:
  - Chip labels and icons
- Implementation note: Chips exist in the component gallery; board catalogues all variants.

### 100. Design System · RiskBadgeGallery

- Slot: `ds-risk-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [100-ds-risk-badge-gallery.jpg](board-screenshots/100-ds-risk-badge-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show all 4 risk levels: low, medium, high, critical.
- Primary user actions:
  - Browse risk badges.
- Required states:
  - All levels visible
- Required data/content:
  - Risk level labels
  - Color coding
- Implementation note: Risk badges exist; board catalogues all levels.

### 101. Design System · StatusDotGallery

- Slot: `ds-statusdot-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [101-ds-status-dot-gallery.jpg](board-screenshots/101-ds-status-dot-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show all status dot variants: working, waiting, idle, error, offline, done.
- Primary user actions:
  - Browse status dots.
- Required states:
  - All variants visible
- Required data/content:
  - Status labels
  - Dot colors
- Implementation note: Status dots exist; board catalogues all states.

### 102. Design System · DSBlockCardGallery

- Slot: `ds-blockcard-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [102-ds-block-card-gallery.jpg](board-screenshots/102-ds-block-card-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show block cards in running, completed, and failed states.
- Primary user actions:
  - Browse block card states.
- Required states:
  - Running
  - Completed
  - Failed
- Required data/content:
  - Block card variants
  - State indicators
- Implementation note: Block cards exist; board catalogues all states.

### 103. Design System · DSMessageBubbleGallery

- Slot: `ds-bubble-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [103-ds-message-bubble-gallery.jpg](board-screenshots/103-ds-message-bubble-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show chat bubble variants: user, assistant, system.
- Primary user actions:
  - Browse bubble variants.
- Required states:
  - All variants visible
- Required data/content:
  - Bubble styles
- Implementation note: Message bubbles exist; board catalogues all types.

### 104. Design System · DSApprovalCardGallery

- Slot: `ds-approval-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [104-ds-approval-card-gallery.jpg](board-screenshots/104-ds-approval-card-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show approval cards with approve, deny, edit, and allow-always actions.
- Primary user actions:
  - Browse approval card variants.
- Required states:
  - All action variants visible
- Required data/content:
  - Action buttons
  - Card layout
- Implementation note: Approval cards exist; board catalogues all action variants.

### 105. Design System · DSDecisionSheetGallery

- Slot: `ds-decision-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [105-ds-decision-sheet-gallery.jpg](board-screenshots/105-ds-decision-sheet-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show the 4-action decision sheet with all action buttons.
- Primary user actions:
  - Browse decision sheet layout.
- Required states:
  - All 4 actions visible
- Required data/content:
  - Action list
- Implementation note: Decision sheet exists; board catalogues the 4-action layout.

### 106. Design System · DSBlastRadiusGallery

- Slot: `ds-blast-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [106-ds-blast-radius-gallery.jpg](board-screenshots/106-ds-blast-radius-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show blast radius inline chips and full-width banner variants.
- Primary user actions:
  - Browse blast radius variants.
- Required states:
  - Inline chips visible
  - Banner variants visible
- Required data/content:
  - Chip labels
  - Banner layouts
- Implementation note: Blast radius components exist; board catalogues all display modes.

### 107. Design System · DSSpendHeroGallery

- Slot: `ds-spend-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [107-ds-spend-hero-gallery.jpg](board-screenshots/107-ds-spend-hero-gallery.jpg)
- Swift screenshot: [gallery-billing.jpg](swift-screenshots/gallery-billing.jpg)
- Purpose: Show the spend hero card with provider breakdown.
- Primary user actions:
  - Browse spend hero layout.
- Required states:
  - Single provider
  - Multiple providers
  - No spend data
- Required data/content:
  - Spend amount
  - Provider breakdown
- Implementation note: Spend hero exists in billing gallery; board catalogues it as a component.

### 108. Design System · ProofCardViewGallery

- Slot: `ds-proof-gallery`
- Category: Design system gallery
- Swift status: matches
- Board screenshot: [108-ds-proof-card-gallery.jpg](board-screenshots/108-ds-proof-card-gallery.jpg)
- Swift screenshot: [gallery-proof.jpg](swift-screenshots/gallery-proof.jpg)
- Purpose: Show the completion proof card with CI status.
- Primary user actions:
  - Browse proof card layout.
- Required states:
  - Proof complete
  - Proof pending
  - Proof failed
- Required data/content:
  - Goal summary
  - CI status
  - Changed files
- Implementation note: Proof card gallery exists; board catalogues it as a design system component.

### 109. Design System · DSScreenHeaderGallery

- Slot: `ds-header-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [109-ds-screen-header-gallery.jpg](board-screenshots/109-ds-screen-header-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show screen header with title cursor and breadcrumb.
- Primary user actions:
  - Browse header variants.
- Required states:
  - With breadcrumb
  - Without breadcrumb
- Required data/content:
  - Title
  - Breadcrumb trail
  - Cursor indicator
- Implementation note: Screen headers exist; board catalogues cursor and breadcrumb treatments.

### 110. Design System · DSStatusHeaderGallery

- Slot: `ds-statusheader-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [110-ds-status-header-gallery.jpg](board-screenshots/110-ds-status-header-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show bridge status header variants.
- Primary user actions:
  - Browse status header variants.
- Required states:
  - Connected
  - Disconnected
  - Pairing
- Required data/content:
  - Status label
  - Connection indicator
- Implementation note: Status headers exist; board catalogues all connection states.

### 111. Design System · AgentIslandGallery

- Slot: `ds-island-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [111-ds-agent-island-gallery.jpg](board-screenshots/111-ds-agent-island-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show compact agent card with avatar, status, and inline approval.
- Primary user actions:
  - Browse island variants.
- Required states:
  - Idle
  - Working
  - Waiting for approval
- Required data/content:
  - Agent avatar
  - Status
  - Approval controls
- Implementation note: Agent island component exists; board catalogues interactive states.

### 112. Design System · DSHostRowGallery

- Slot: `ds-hostrow-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [112-ds-host-row-gallery.jpg](board-screenshots/112-ds-host-row-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show host list row variants.
- Primary user actions:
  - Browse row variants.
- Required states:
  - Online
  - Offline
  - Degraded
- Required data/content:
  - Host name
  - Status dot
  - Avatar
  - Address
- Implementation note: Host rows exist in fleet; board catalogues all row variants.

### 113. Design System · DSSessionRowGallery

- Slot: `ds-sessionrow-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [113-ds-session-row-gallery.jpg](board-screenshots/113-ds-session-row-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show session row with unread badges.
- Primary user actions:
  - Browse session row variants.
- Required states:
  - Unread
  - Read
  - Active
- Required data/content:
  - Session name
  - Unread badge
  - Timestamp
- Implementation note: Session rows exist; board catalogues badge and state variants.

### 114. Design System · DSStateGallery

- Slot: `ds-state-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [114-ds-state-gallery.jpg](board-screenshots/114-ds-state-gallery.jpg)
- Swift screenshot: [gallery-states.jpg](swift-screenshots/gallery-states.jpg)
- Purpose: Show empty, loading, error, and offline state components.
- Primary user actions:
  - Browse state variants.
- Required states:
  - Empty
  - Loading
  - Error
  - Offline
- Required data/content:
  - Illustration
  - Title
  - Description
  - Action button
- Implementation note: State gallery exists; board catalogues all state components.

### 115. Design System · DSTabBarGallery

- Slot: `ds-tabbar-gallery`
- Category: Design system gallery
- Swift status: matches
- Board screenshot: [115-ds-tab-bar-gallery.jpg](board-screenshots/115-ds-tab-bar-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show the 4-tab bar with inbox badge.
- Primary user actions:
  - Browse tab bar layout.
- Required states:
  - Badge visible
  - Badge hidden
- Required data/content:
  - Tab icons
  - Tab labels
  - Badge count
- Implementation note: Tab bar exists as the app root; board catalogues badge state.

### 116. Design System · DSSegmentedControlGallery

- Slot: `ds-segment-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [116-ds-segmented-control-gallery.jpg](board-screenshots/116-ds-segmented-control-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show segmented controls with 2, 3, and 4 segments.
- Primary user actions:
  - Browse segment variants.
- Required states:
  - 2 segments
  - 3 segments
  - 4 segments
- Required data/content:
  - Segment labels
  - Selected state
- Implementation note: Segmented controls exist; board catalogues all width variants.

### 117. Design System · DSToastGallery

- Slot: `ds-toast-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [117-ds-toast-gallery.jpg](board-screenshots/117-ds-toast-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show toast notification variants.
- Primary user actions:
  - Browse toast variants.
- Required states:
  - Success
  - Error
  - Warning
  - Info
- Required data/content:
  - Toast message
  - Icon
  - Dismiss action
- Implementation note: Toasts exist; board catalogues all severity variants.

### 118. Design System · DSSheetGallery

- Slot: `ds-sheet-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [118-ds-sheet-gallery.jpg](board-screenshots/118-ds-sheet-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show the bottom sheet pattern.
- Primary user actions:
  - Browse sheet layout.
- Required states:
  - Default height
  - Expanded height
  - With drag indicator
- Required data/content:
  - Sheet content
  - Drag handle
- Implementation note: Sheets are used throughout the app; board catalogues the pattern.

### 119. Design System · DSDividerGallery

- Slot: `ds-divider-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [119-ds-divider-gallery.jpg](board-screenshots/119-ds-divider-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show dividers, spectrum bar, and dot matrix variants.
- Primary user actions:
  - Browse divider variants.
- Required states:
  - All variants visible
- Required data/content:
  - Divider styles
  - Spectrum bar
  - Dot matrix
- Implementation note: Dividers exist; board catalogues all decorative variants.

### 120. Design System · PixelAvatarGallery

- Slot: `ds-avatar-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [120-ds-pixel-avatar-gallery.jpg](board-screenshots/120-ds-pixel-avatar-gallery.jpg)
- Swift screenshot: [gallery-features.jpg](swift-screenshots/gallery-features.jpg)
- Purpose: Show all 8 palette variants in 4 sizes.
- Primary user actions:
  - Browse avatar variants.
- Required states:
  - All sizes and palettes visible
- Required data/content:
  - Size variants
  - Palette variants
- Implementation note: PixelAvatar exists in gallery; board catalogues all palette and size combinations.

### 121. Design System · E2ERelayStatusBadge

- Slot: `ds-relay-badge-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [121-ds-e2e-relay-badge-gallery.jpg](board-screenshots/121-ds-e2e-relay-badge-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show the relay badge with paired, pairing, and disconnected states.
- Primary user actions:
  - Browse relay badge states.
- Required states:
  - Paired
  - Pairing
  - Disconnected
- Required data/content:
  - Status label
  - Icon indicator
- Implementation note: Relay badge exists; board catalogues all states.

### 122. Design System · HostHealthBadgeGallery

- Slot: `ds-health-gallery`
- Category: Design system gallery
- Swift status: partial
- Board screenshot: [122-ds-host-health-badge-gallery.jpg](board-screenshots/122-ds-host-health-badge-gallery.jpg)
- Swift screenshot: none captured
- Purpose: Show health badges with CPU, memory, and disk metrics.
- Primary user actions:
  - Browse health badge variants.
- Required states:
  - Healthy
  - Degraded
  - Critical
- Required data/content:
  - CPU metric
  - Memory metric
  - Disk metric
  - Status color
- Implementation note: Health badges exist in fleet; board catalogues all metric states.

