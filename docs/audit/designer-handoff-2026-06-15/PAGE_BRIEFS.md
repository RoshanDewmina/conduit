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

### 45. Conduit Pro · paywall

- Slot: `paywall`
- Category: Billing
- Swift status: matches
- Board screenshot: [45-conduit-pro-paywall.jpg](board-screenshots/45-conduit-pro-paywall.jpg)
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

