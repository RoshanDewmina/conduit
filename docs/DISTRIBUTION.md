# Lancer Distribution Strategy (Stage 5)

## Why Distribution Is The Main Risk

The market now has free and visible options (first-party mobile controls and popular OSS clients). Product quality alone is not enough; trust and discoverability are the bottleneck.

Lancer's initial distribution strategy is therefore:
- publish the bridge (`lancerd`) as a transparent self-host component
- win a focused beachhead first (security-conscious teams), not broad consumer adoption

## Beachhead: Security-Conscious / Enterprise-Like Users

Primary target profile:
- teams that cannot route source code through unknown relays
- regulated or policy-heavy environments
- infra-minded developers already self-hosting tools

Why this niche first:
- has clearer willingness-to-pay than casual consumers
- values auditability and deployment control
- aligns directly with Lancer's SSH-native architecture

## Open-Source `lancerd` Strategy

`lancerd` should be treated as the trust anchor and distributed as a standalone, inspectable package.

Stage 5 baseline:
- documented self-host install path (`daemon/lancerd/install.sh`)
- portable release tarballs (`scripts/release-lancerd.sh`)
- hook templates for Claude and Codex included in release artifacts
- security posture documented in `docs/SECURITY.md`

Next steps (deferred):
- public repository split or mirror for `lancerd`
- signed release artifacts and checksum publication
- package channels (Homebrew tap / apt repo) after artifact signing is in place

## Positioning Narrative

Lancer should be positioned as:

> A secure, native, cross-vendor cockpit for steering AI coding agents, designed for teams that prefer self-hosted control paths.

Messaging pillars:
- **Control path clarity:** approval loop runs through your host over SSH.
- **Operational transparency:** hook scripts and daemon are inspectable.
- **Cross-vendor portability:** Claude + Codex now; Cursor/Gemini roadmap.

## Go-To-Market Sequence

1. Ship `lancerd` install + docs + release artifacts (this stage).
2. Publish implementation walkthroughs (self-host setup, security model).
3. Recruit design partners in security-conscious teams.
4. Add enterprise features based on partner feedback (policy and audit depth).

## Success Metrics (Early)

- number of successful self-host installs
- number of active hosts using `lancerd`
- time-to-first-approval after install
- ratio of approvals handled without reconnect/notification loss
