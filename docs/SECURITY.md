# Conduit Security Posture (Self-Host)

This document describes the end-to-end security model for Conduit and the `conduitd` bridge when used in self-host mode.

## Threat Model (Practical Scope)

Conduit optimizes for:
- secure phone-to-host control of agent decisions
- auditable approvals and denials
- minimizing cloud exposure of code and tool payloads

Conduit does not claim:
- remote host hardening for your infrastructure
- malware protection on compromised developer machines
- complete prevention of dangerous commands if you approve them

## Data Flow and Trust Boundaries

1. iPhone connects to your host over SSH.
2. `conduitd serve` runs on the host and bridges:
   - iOS app (SSH stdio, framed JSON-RPC)
   - agent hooks (local unix socket)
3. Hook events become approval cards on-device.
4. Decision is returned to the host hook process.

Primary trust boundaries:
- network boundary: SSH transport
- local host boundary: unix socket at `~/.conduit/conduitd.sock`
- user decision boundary: explicit approve/deny action on iPhone

## Key Security Controls

### TOFU host verification
- First SSH connect is trust-on-first-use (TOFU).
- Fingerprint mismatch should be treated as a possible MITM event.

### Key handling
- Credentials are stored in platform secure storage (Keychain on iOS side).
- No API keys or agent credentials are embedded in `conduitd` source.

### Approval gating
- Hooks block pre-tool execution until a decision is returned.
- Decisions include deny / approve / approveAlways (rule-based).
- Timeout defaults to deny in active request path.

### Auditability
- Approval events carry timestamp, command summary, risk band, and tool metadata.
- Codex hook can append local JSONL event telemetry (`~/.conduit/codex-hook-events.jsonl`).

## On-Prem / Self-Host Architecture

`conduitd` is designed for on-prem operation:
- runs on your own host/VM
- no mandatory managed relay in the approval loop
- hook-to-daemon transport is local unix socket

Optional push notifications route through your configured push backend URL. This is operationally optional and can be disabled by not registering a push backend.

## What Conduit Does NOT Send To Cloud

In self-host mode, Conduit does not require sending your repository contents to a Conduit-managed cloud service for approvals.

Conduit does not automatically upload:
- your git repository
- full terminal transcript history
- secret manager values
- private keys from your local keychain

Note: your chosen agent vendor (for example Claude or Codex) may still send prompts/tool context to their own service per that vendor's policy. Conduit does not override vendor behavior.

## Operator Checklist

For hardened deployments:
- run `conduitd` under a non-root user
- restrict SSH access with keys and host firewall rules
- protect `~/.conduit` permissions (`0700`)
- rotate host credentials regularly
- keep host OS and CLI agents patched

## Known Limits

- If the host is fully compromised, an attacker can tamper with local hook execution.
- `approveAlways` rules trade friction for speed; use sparingly on high-risk tools.
- TOFU requires user vigilance on first connect and on any host key change.
