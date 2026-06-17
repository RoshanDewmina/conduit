# M11 — Managed Compute Demo

## Prerequisites
- Fly.io account with API token (`fly tokens create`).
- Conduit app installed on device.

## Steps

### 1. New user flow
Fresh install → Onboarding screen shows two CTAs:
- "Add your first host" (existing)
- "Set up a workspace for me" (new)

Tap "Set up a workspace for me".

### 2. Provider selection
Pick **Fly.io** → Next.

### 3. Configure
Enter workspace name, Fly.io API token, select region (e.g. Singapore), pick machine size (2 GB recommended).
Tap "Next: Choose agent".

### 4. Agent selection
Select "Claude Code" → tap "Provision workspace".

### 5. Provisioning log
Progress screen shows live log:
```
> Creating Fly.io app 'conduit-my-workspace-a1b2c3d4'...
> App created.
> IP allocated.
> Machine 'abc123' starting in sin...
> Machine is running.
```
After ~90 seconds: "Workspace ready!" screen.

### 6. Auto-connect
Tap "Open session" → Face ID (if Ed25519 configured) → Session opens.
Type `claude --version` → Claude Code is on PATH.

## Pass criteria
- [ ] "Set up a workspace for me" CTA visible in onboarding.
- [ ] ProvisioningWizard 3-step flow works: provider → configure → agent.
- [ ] FlyProvisioner makes correct API calls (verify via Fly.io dashboard).
- [ ] Provisioned host is saved to HostRepository.
- [ ] BillingView shows Fly.io dashboard link.
