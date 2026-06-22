# Lancer Security Posture (Self-Host)

> ⚠️ **SUPERSEDED (2026-06-17)** by [`docs/legal/SECURITY_ARCHITECTURE.md`](legal/SECURITY_ARCHITECTURE.md)
> (fuller, newer threat model, 2026-06-15) and [`docs/KNOWN_ISSUES.md`](KNOWN_ISSUES.md) §2 (current
> verified security posture: GO). This file is retained for its self-host posture notes only — for
> current security state use those two documents.

This document describes the end-to-end security model for Lancer and the `lancerd` bridge when used in self-host mode.

## Threat Model (Practical Scope)

Lancer optimizes for:
- secure phone-to-host control of agent decisions
- auditable approvals and denials
- minimizing cloud exposure of code and tool payloads

Lancer does not claim:
- remote host hardening for your infrastructure
- malware protection on compromised developer machines
- complete prevention of dangerous commands if you approve them

## Data Flow and Trust Boundaries

1. iPhone connects to your host over SSH.
2. `lancerd serve` runs on the host and bridges:
   - iOS app (SSH stdio, framed JSON-RPC)
   - agent hooks (local unix socket)
3. Hook events become approval cards on-device.
4. Decision is returned to the host hook process.

Primary trust boundaries:
- network boundary: SSH transport
- local host boundary: unix socket at `~/.lancer/lancerd.sock`
- user decision boundary: explicit approve/deny action on iPhone

## Key Security Controls

### TOFU host verification
- First SSH connect is trust-on-first-use (TOFU).
- Fingerprint mismatch should be treated as a possible MITM event.

### Key handling
- Credentials are stored in platform secure storage (Keychain on iOS side).
- No API keys or agent credentials are embedded in `lancerd` source.

### Approval gating
- Hooks block pre-tool execution until a decision is returned.
- Decisions include deny / approve / approveAlways (rule-based).
- Timeout defaults to deny in active request path.

### Auditability
- Approval events carry timestamp, command summary, risk band, and tool metadata.
- Codex hook can append local JSONL event telemetry (`~/.lancer/codex-hook-events.jsonl`).

## On-Prem / Self-Host Architecture

`lancerd` is designed for on-prem operation:
- runs on your own host/VM
- no mandatory managed relay in the approval loop
- hook-to-daemon transport is local unix socket

Optional push notifications route through your configured push backend URL. This is operationally optional and can be disabled by not registering a push backend.

## What Lancer Does NOT Send To Cloud

In self-host mode, Lancer does not require sending your repository contents to a Lancer-managed cloud service for approvals.

Lancer does not automatically upload:
- your git repository
- full terminal transcript history
- secret manager values
- private keys from your local keychain

Note: your chosen agent vendor (for example Claude or Codex) may still send prompts/tool context to their own service per that vendor's policy. Lancer does not override vendor behavior.

## Operator Checklist

For hardened deployments:
- run `lancerd` under a non-root user
- restrict SSH access with keys and host firewall rules
- protect `~/.lancer` permissions (`0700`)
- rotate host credentials regularly
- keep host OS and CLI agents patched

## Known Limits

- If the host is fully compromised, an attacker can tamper with local hook execution.
- `approveAlways` rules trade friction for speed; use sparingly on high-risk tools.
- TOFU requires user vigilance on first connect and on any host key change.
