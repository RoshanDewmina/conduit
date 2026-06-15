# Feature Inventory and Design Scope

This inventory separates current captured surfaces from board concepts that need more Swift implementation, routing, or live-data capture. Descriptions here are functional only.

## Current or Partially Implemented Surfaces

- Inbox · approval queue (`inbox`): Let the user review pending agent permission requests and decide whether work can continue.
- Decision sheet · all 4 actions (`sheet`): Present the full decision surface for one approval request.
- Critical · Face ID gate (`critical`): Require local authentication before approving an irreversible or broad-impact request.
- Decision · edit & run (3rd action) (`editrun`): Allow the user to safely modify an agent request before execution.
- Decision · allow always → rule written (`allowalways`): Confirm that an approval has been converted into a reusable scoped policy rule.
- Inbox · first-run + demo (`firstrun`): Explain the first useful approval loop and give the user a safe demo path.
- Inbox zero · returning user (`empty`): Show that there are no pending decisions while still communicating system readiness.
- Fleet · cross-vendor spend (`fleet`): Show connected hosts, agents, provider usage, and operational status across the user’s control plane.
- Agent · run detail + stop (NEW) (`rundetail`): Show the details and controls for an active or recent agent run.
- Activity · while you were away (`activity`): Summarize important decisions, runs, and bridge events that happened while the user was away.
- Proof Card · completion attestation (`proofcard`): Summarize what an agent completed and provide evidence that the result can be trusted.
- Loop · goal → plan → CI → proof (`loopdetail`): Show the full lifecycle of an agent loop from goal through plan, execution, CI, and proof.
- Worktrees · 3-column branch supervision (`worktreeboard`): Compare multiple active worktrees or branches and help the user decide what should continue, merge, or stop.
- CI / PR Event Feed (`cievents`): Show repository checks, pull request events, and CI status related to agent work.
- Budget · set-run-budget overlay (`budget-sheet`): Set or adjust the spend limit for one run before or during execution.
- Run detail · control surface (v2) (`run-detail-v2`): Provide a single control surface for monitoring, stopping, budgeting, and reviewing a run.
- Dispatch · start a task (NEW) (`dispatch`): Start a new agent task with the right host, repository, provider, budget, and policy context.
- Policy · presets + effect chips (`policy`): Let the user choose and understand policy presets that determine what agents can do without asking.
- Policy · edit policy.yaml + reload (`policy-yaml`): Edit the bridge policy file and reload it on the host.
- Settings · notifications + quiet hours (`notifications`): Configure which agent and approval events notify the user and when notifications should be quiet.
- Settings · provider keys (multi-vendor) (`providerkeys`): Manage provider credentials and model access without exposing secrets unnecessarily.
- Settings · Library dissolved (`settings`): Collect account, security, policy, notifications, billing, provider, relay, and advanced configuration entry points.
- Policy Simulator · past N days (`policysimulator`): Estimate how a policy would have affected recent agent activity before applying it.
- Secrets · vault + pending requests (`secrets`): Show available secret metadata and pending agent requests for secret access.
- Onboarding 1 · hero (`onb-1`): Introduce the product’s primary job and start the setup flow.
- Onboarding 2 · pair the bridge (no SSH) (`onb-2`): Pair the phone with the bridge or local control plane without requiring the user to understand SSH first.
- Onboarding 3 · choose caution (`onb-3`): Choose the initial caution/autonomy level for agent approvals.
- Onboarding 4 · first run + demo (`onb-4`): Guide the user into the first run or demo after basic setup is complete.
- Advanced · add host over SSH (`addhost`): Connect a new host that agents can use for work.
- Power-user · live block session (`terminal`): Provide deeper access to a live session transcript and command blocks for users who need to inspect execution.
- Diff · approve a write (`diff`): Let the user inspect a proposed file change before approving an agent write.
- File viewer · tap a file → drawer (NEW) (`fileviewer`): Preview a file or selected changed file from an agent run.
- Relay pairing · E2E status (`e2erelay`): Pair and monitor the encrypted relay path used for approvals and status updates.
- Doctor · health check (`doctor`): Run health checks that explain why setup, bridge, relay, notifications, or provider access is not working.
- Allow always · scope config (`allowalways-scope`): Define the exact scope of a reusable allow rule before it is saved.
- Trust & Privacy · what leaves your host (`trust-privacy`): Explain what data leaves the host and what remains local for each product capability.
- Fleet · model + privacy (`fleet-privacy`): Show model, provider, and privacy state per host or active agent.
- Audit · tamper-evident chain (`auditchain`): Show tamper-evident audit records and verification status for decisions and bridge events.
- Host health · daemon detail (`hosthealth`): Show detailed daemon and host health for one connected machine.
- Billing · spend + quota remaining (`usage`): Show spend, quota, usage, and billing state across providers or the app account.
- Conduit Pro · paywall (`paywall`): Explain why a paid capability is unavailable and let the user upgrade or compare plans.
- Quota · per-provider dashboard (`quotaguard`): Show per-provider quota and spend guardrails so users can prevent unexpected cost or blocked runs.
- Library hub → dissolved (`rm-lib`): Document that Library should not be a primary app destination and its useful pieces should move into more relevant flows.
- Session surface switcher → deleted (`rm-shell`): Document that a session surface switcher should not be a primary navigation model.
- Mock SSH host counts → fixed (real data) (`rm-keys`): Document that host and key counts should reflect real data rather than placeholder counts.
- Risk ramp · independent of brand (`ramp`): Define how risk levels should map to approval behavior independent of provider branding.

## Features To Add, Finish, or Expose With Routes

- Inbox · approval queue (`inbox`): Let the user review pending agent permission requests and decide whether work can continue.
- Decision sheet · all 4 actions (`sheet`): Present the full decision surface for one approval request.
- Critical · Face ID gate (`critical`): Require local authentication before approving an irreversible or broad-impact request.
- Decision · edit & run (3rd action) (`editrun`): Allow the user to safely modify an agent request before execution.
- Decision · allow always → rule written (`allowalways`): Confirm that an approval has been converted into a reusable scoped policy rule.
- Inbox · first-run + demo (`firstrun`): Explain the first useful approval loop and give the user a safe demo path.
- Inbox zero · returning user (`empty`): Show that there are no pending decisions while still communicating system readiness.
- Fleet · cross-vendor spend (`fleet`): Show connected hosts, agents, provider usage, and operational status across the user’s control plane.
- Agent · run detail + stop (NEW) (`rundetail`): Show the details and controls for an active or recent agent run.
- Activity · while you were away (`activity`): Summarize important decisions, runs, and bridge events that happened while the user was away.
- Loop · goal → plan → CI → proof (`loopdetail`): Show the full lifecycle of an agent loop from goal through plan, execution, CI, and proof.
- Worktrees · 3-column branch supervision (`worktreeboard`): Compare multiple active worktrees or branches and help the user decide what should continue, merge, or stop.
- Nudge · mid-run instruction (`nudge`): Send a mid-run instruction to an agent without restarting the task.
- Switch model · mid-run (`switch-model`): Change the model or provider used by an active run when cost, quota, privacy, or capability needs change.
- CI / PR Event Feed (`cievents`): Show repository checks, pull request events, and CI status related to agent work.
- Budget · set-run-budget overlay (`budget-sheet`): Set or adjust the spend limit for one run before or during execution.
- Run detail · control surface (v2) (`run-detail-v2`): Provide a single control surface for monitoring, stopping, budgeting, and reviewing a run.
- Dispatch · start a task (NEW) (`dispatch`): Start a new agent task with the right host, repository, provider, budget, and policy context.
- Policy · presets + effect chips (`policy`): Let the user choose and understand policy presets that determine what agents can do without asking.
- Policy · edit policy.yaml + reload (`policy-yaml`): Edit the bridge policy file and reload it on the host.
- Settings · notifications + quiet hours (`notifications`): Configure which agent and approval events notify the user and when notifications should be quiet.
- Settings · provider keys (multi-vendor) (`providerkeys`): Manage provider credentials and model access without exposing secrets unnecessarily.
- Settings · Library dissolved (`settings`): Collect account, security, policy, notifications, billing, provider, relay, and advanced configuration entry points.
- Policy Simulator · past N days (`policysimulator`): Estimate how a policy would have affected recent agent activity before applying it.
- Secrets · vault + pending requests (`secrets`): Show available secret metadata and pending agent requests for secret access.
- Onboarding 1 · hero (`onb-1`): Introduce the product’s primary job and start the setup flow.
- Onboarding 2 · pair the bridge (no SSH) (`onb-2`): Pair the phone with the bridge or local control plane without requiring the user to understand SSH first.
- Onboarding 3 · choose caution (`onb-3`): Choose the initial caution/autonomy level for agent approvals.
- Onboarding 4 · first run + demo (`onb-4`): Guide the user into the first run or demo after basic setup is complete.
- Advanced · add host over SSH (`addhost`): Connect a new host that agents can use for work.
- Power-user · live block session (`terminal`): Provide deeper access to a live session transcript and command blocks for users who need to inspect execution.
- File viewer · tap a file → drawer (NEW) (`fileviewer`): Preview a file or selected changed file from an agent run.
- Relay pairing · E2E status (`e2erelay`): Pair and monitor the encrypted relay path used for approvals and status updates.
- Doctor · health check (`doctor`): Run health checks that explain why setup, bridge, relay, notifications, or provider access is not working.
- Allow always · scope config (`allowalways-scope`): Define the exact scope of a reusable allow rule before it is saved.
- Trust & Privacy · what leaves your host (`trust-privacy`): Explain what data leaves the host and what remains local for each product capability.
- Fleet · model + privacy (`fleet-privacy`): Show model, provider, and privacy state per host or active agent.
- Audit · tamper-evident chain (`auditchain`): Show tamper-evident audit records and verification status for decisions and bridge events.
- Host health · daemon detail (`hosthealth`): Show detailed daemon and host health for one connected machine.
- Quota · per-provider dashboard (`quotaguard`): Show per-provider quota and spend guardrails so users can prevent unexpected cost or blocked runs.
- Mock SSH host counts → fixed (real data) (`rm-keys`): Document that host and key counts should reflect real data rather than placeholder counts.
- Risk ramp · independent of brand (`ramp`): Define how risk levels should map to approval behavior independent of provider branding.

## Requires Live Data, Owner Context, or Hardware

- Advanced · trust host key (TOFU) (`tofu`): Ask the user to trust or reject a host key the first time a host is connected.
- Advanced · SSH keys (kept · real data) (`sshkeys`): Show SSH key material status and keychain-backed access without exposing private key contents.

## Design Reference Only, Not Shipping Screens

- Decisions applied (`decisions`): Summarize product decisions that should guide the remaining page designs.

