# Phase 1 — Source-of-Truth Report

> What is actually true about Lancer's current state, and where docs/code/plans disagree.
> Evidence-based; conflicts are recorded, **product decisions are not resolved unilaterally.**
> Date 2026-06-23. Branch `rebrand/lancer`.

## 1. Canonical source hierarchy (confirmed)

Per `AGENTS.md` + `CLAUDE.md`, in priority order:

1. **Working code + recent verified commits** — override any older doc when they disagree.
2. `ARCHITECTURE.md` §0.1 (current-state snapshot) + §4.1 (navigation/IA).
3. `docs/KNOWN_ISSUES.md` (issue tracker).
4. `docs/PUBLISH_READINESS_CHECKLIST.md` (launch-state source of truth).
5. `docs/LAUNCH_AUDIT-2026-06-18.md` (readiness scorecard + V1 scope).
6. `docs/LIVE_LOOP_RUNBOOK.md` (governed-approval loop procedure).
7. `docs/_archive/**` (incl. `LANCER_PROJECT_DOSSIER.md`) — **stale, history only.**

Doc volume: ~160 markdown files (~23 already archived) — significant sprawl; archival cleanup is backlog.

## 2. Established current state (cross-confirmed)

| Area | Truth | Evidence |
|---|---|---|
| **Product** | iOS "mission control" for AI coding agents; phone steers + approves, not a phone IDE. | ARCHITECTURE.md §0.1; AGENTS.md |
| **3 layers** | iOS app (`Packages/LancerKit/`, 21 SPM targets) + `lancerd` Go daemon + `push-backend`/`agent-runner` cloud. | dir structure; Explore passes |
| **V1 transport** | **E2E relay** (phone↔push-backend↔lancerd, encrypted); phone never holds SSH in V1. SSH = legacy/power-user. | ARCHITECTURE §0.1 (corrected 2026-06-19); LIVE_LOOP_RUNBOOK |
| **IA** | **Sidebar / Command Home shell**, 6 `SidebarDestination` cases. NOT a tab bar. `enum Tab` vestigial in AppRoot.swift. | ARCHITECTURE §4.1; AppRoot.swift |
| **V1 scope (locked 2026-06-18)** | Ships: sidebar, E2E relay, governed approvals, APNs, machine detail, multi-vendor dispatch + `continue`. Deferred: hosted-cloud execution (code retained). | LAUNCH_AUDIT-2026-06-18 |
| **Build/test** | LancerKit `swift build` **SUCCEEDED 2026-06-23 (exit 0, this audit)**; docs report 385 SPM tests / 61 suites green + Go modules green. | this audit + KNOWN_ISSUES §1 |
| **Live loop** | Governed-approval loop proven on simulator; **physical-device APNs app-closed PASSED 2026-06-23 (C2)** after 5-bug fix. | PUBLISH_READINESS §C; memory |
| **TestFlight** | First build uploaded 2026-06-23 (`dev.lancer.mobile`, "Lancer — Agent Control"). | git log; memory |

## 3. Conflicts (which source is current + why)

### CONFLICT 1 — Relay URL (TESTER-1). **Code is current; doc is stale.**
- KNOWN_ISSUES §0 claims the app ships the unreachable `35.201.3.231.sslip.io` URL.
- **Actual:** `project.yml:26 LANCER_PUSH_BACKEND_URL = "https://conduit-push-y4wpy6zeva-ts.a.run.app"` (Cloud Run). Verified this audit.
- **Verdict:** the shipping config already points at the Cloud Run instance — the KNOWN_ISSUES "ships sslip.io" claim is stale. Residual real issue: the host is still named `conduit-push` (rebrand incomplete) and there's no vanity domain (D4). *Not resolved here; recorded.*

### CONFLICT 2 — lancerd installer (TESTER-2). **Open, out of audit scope.**
- Published GitHub release stale `v0.1.0`; asset-name (hyphen vs underscore) + missing SHA256SUMS/install.sh. `curl|sh` fails.
- **Verdict:** real open blocker for tester onboarding, but a release-engineering task, not a product/UX audit item. Backlog.

### CONFLICT 3 — Runbook phase ordering. **Documentation-internal drift.**
- LIVE_LOOP_RUNBOOK preamble (corrected 2026-06-19): relay (Phase 5b) is the V1 path, "do it first." Body still leads with Phase 3 SSH as the main proven path.
- **Verdict:** structure is historically-motivated; the preamble is authoritative. Low impact.

### CONFLICT 4 — IA tab-bar vs sidebar. **Resolved (sidebar shipped 2026-06-20).**
- Quarantined `TapInjectionProofTests` assert the old tab bar.
- **Verdict:** not a live contradiction — sidebar is in; old UI tests are documented debt (need sidebar rewrite). Note for Phase 8.

### CONFLICT 5 — APNs delivery. **Resolved (C2 PASSED 2026-06-23).**
- ARCHITECTURE §0.1 "Partial" line predates the device proof.
- **Verdict:** APNs app-closed is now verified; the "Partial" wording is stale and should follow the checklist. Recorded.

### CONSISTENT (no conflict)
- Hosted-cloud execution: uniformly documented as V2, code retained, ~900 LOC 0-refs, do-not-delete.
- `continue`/follow-up: in V1 scope, implemented in dispatch.go; runbook only cautions to re-verify per vendor (CLI flag drift).

## 4. Naming drift (rebrand incomplete)
The Conduit→Lancer rebrand (branch `rebrand/lancer`) is build-green but live infra still carries
`conduit-*` names (Cloud Run `conduit-push`, GCS `conduit-dist`, `*.conduit.dev`) — preserved
intentionally (migration checklist). Affects copy seen in some screens (flagged for Phase 7) and
the backend hostname. Not a code-correctness issue; a polish/branding item.

## 5. Implication for the redesign brief
The product that actually ships V1 is much smaller than the code surface suggests. The brief should
center the **core journey** (pair → dispatch → approve → continue) and treat the orphaned/deferred
surface as explicitly out-of-V1. Doc sprawl and naming drift are real but are engineering/ops debt,
not design inputs — noted, not centered.
