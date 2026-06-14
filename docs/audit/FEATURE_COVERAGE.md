# Conduit Feature Coverage Matrix - Governed Approvals v1

**Date:** 2026-06-13
**Scope:** iOS app targets, ConduitKit source, push relay backend, readiness docs, and audit screenshots.
**Method:** Source review, Device Hub screenshots, XCUITest interaction proof, live localhost SSH E2E, local relay backend verification, Swift/Go tests, and archive check.

Legend:

- **Covered:** shipped UI surface exists and local verification passed.
- **Code covered:** source/tests reviewed, but a production-only external system remains.
- **Flagged:** visible partial behavior or implemented-hidden behavior needs a ship/no-ship decision.
- **Owner-only:** cannot be completed without signing, App Store Connect, physical device, production CloudKit, production APNs, or production secrets.

## Core App and Navigation

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Four-tab app shell: Inbox, Fleet, Activity, Settings | Root tabs | Covered | Tap injection proved by switching tabs in UI test. Screenshots captured light/dark. |
| Onboarding | First launch | Covered | Revised copy and light/dark screenshots captured. |
| Session full-screen cover | Fleet/Add Host/session status | Covered | Live localhost SSH E2E reaches connected session. |
| App lock / Face ID opt-in | Settings -> Security | Covered locally | UI test toggles opt-in. Hardware/biometry edge cases still require device pass. |
| Notification category setup | System notifications | Code covered | Categories register after onboarding. Physical APNs is owner-only. |
| Color scheme override | Settings -> Appearance | Covered | Light/dark screenshots captured. |

## Governed Approvals

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Pending approval list | Inbox | Covered | Screenshots plus `testApproveDecisionApplies`. |
| Approve / Deny | Approval cards | Covered | UI test taps approval and verifies pending count changes. |
| Allow always | Approval cards and Settings rules | Code covered | UI surfaced. Revoke semantics should be clarified before marketing as cross-device policy. |
| Edit and run | Approval edit sheet / diff | Code covered | Source reviewed; not part of final screenshot path. Keep claims conservative. |
| Typed question approval | Inbox card variants | Code covered | Surface exists. Needs live agent fixture before claiming broad coverage. |
| MCP call approval | Inbox card variants | Code covered | Copy improved. Needs live MCP fixture before marketing. |
| Relay fallback decision | Automatic fallback via backend | Covered locally | Local backend register -> decision -> one-time poll drain verified; Go tests pass. |
| Live SSH decision path | Session/daemon channel | Covered locally | Live localhost SSH connect/TOFU verified; approval decision UI verified against seeded data. |
| Cold-launch notification decision | Notification actions | Owner-only | Requires physical APNs delivery and app launch replay validation. |

## Host, Fleet, and SSH

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Add host | Fleet -> Add Host | Covered locally | Copy clarified. localhost seeded E2E uses real SSH. |
| Saved host reconnect | Fleet saved-host row | Covered | UI test verifies reconnect prompt path. |
| Password prompt | Connection sheet | Covered locally | E2E uses Keychain-backed local password without printing it. |
| TOFU host-key prompt | Host-key sheet | Covered locally | Live SSH test verifies Unknown Host Key -> Trust & Connect -> Connected. |
| SSH agent forwarding | Defensive error path | Flagged | Not a primary shipping path; avoid claims until implemented. |
| Host edit after creation | Host editor | Flagged | Creation path exists; edit entry point should be confirmed or surfaced deliberately. |
| Fleet bridge status | Fleet / Activity | Code covered | UI exists; live conduitd bridge status was not part of the local loopback E2E. |

## Session Tools

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Terminal/session transcript | Session | Covered locally | Live SSH reaches connected session. |
| Chat composer | Session | Code covered | Source reviewed; not all agent/provider paths exercised. |
| In-session approval banner | Session | Code covered | Keep claims tied to approval verification, not every agent variant. |
| Dictation | Session composer | Code covered | Purpose strings/build wiring present; physical mic/speech behavior still needs device pass. |
| Command history/snippets | Session sheets | Code covered | Surface exists. Snippet creation/run coverage remains flagged. |
| Port forwarding | Session sheet | Flagged | Local/remote capability surfaced more honestly; remote forwarding remains limited. |
| tmux reattach | Session sheet | Code covered | Not in final E2E path. |
| `SessionShellView` / Preview / localhost web preview | Hidden or orphaned | Flagged | Implemented but not a normal, verified submission path. Do not market yet. |
| SFTP file browser / preview | Hidden or orphaned | Flagged | Implemented but no normal route. Surface deliberately or defer. |

## Settings, Library, and Local Data

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Provider selection | Settings | Covered for Anthropic/OpenAI | OpenRouter support exists elsewhere but is not surfaced in Settings; flag. |
| API key storage/test/remove | Settings -> API Keys | Code covered | Keychain path reviewed; live provider testing not part of this pass. |
| Notification filters / quiet hours | Settings | Code covered | UI exists; APNs behavior owner-only. |
| Policy editor | Settings -> Agent approvals | Code covered | Requires connected bridge for real policy sync. |
| Cloud Sync status | Settings | Code covered | Now Info.plist-gated; production CloudKit owner-only. |
| Billing and usage | Settings | Owner-only | IAP/Stripe/App Store Connect sandbox verification remains. |
| Library home | Settings toolbar -> Library | Flagged | Entry exists, but some child actions are partial. |
| Snippets library | Library -> Snippets | Flagged | Run/new snippet paths need wiring or hiding. |
| Snippet editor | Existing sheet | Flagged | Creation/edit entry points need clear route coverage. |
| SSH keys management | Library -> SSH Keys | Flagged | Mock host counts and import coverage need cleanup. |
| Workflows | Library -> Workflows | Flagged | Add-step/mock behavior should not appear in submission screenshots. |

## Hosted Agents, Cloud, Billing, and Organizations

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Hosted agents list/create/detail | Library/Add Host cloud surfaces | Owner-only / flagged | Requires entitlement and backend credentials. Keep out of App Review claims unless provisioned. |
| Agent runs/logs/files/artifacts | Hosted agent detail | Owner-only / flagged | Backend route surface exists; production Cloud verification remains. |
| Dispatch composer | Debug gallery only | Flagged | Do not ship as a claimed user path unless routed normally and tested. |
| Org members/invites | Hosted agent org UI | Flagged | Invite email delivery is not enabled/proven. |
| Billing checkout/portal/status | Settings and backend routes | Owner-only | IAP/Stripe/App Store Connect checks remain. |
| Credits/quota/usage | Backend routes / Settings | Owner-only | Requires production account and policy decisions. |

## Widgets, Watch, Live Activity, and System Surfaces

| Capability | UI surface | Status | Evidence / recommendation |
|---|---|---|---|
| Home/Lock-screen widget | Widget extension | Code covered | Builds; real widget placement not verified in this pass. |
| Live Activity / Dynamic Island | Live Activity extension | Owner-only | Builds; physical-device APNs/action verification required. |
| App Intents approval actions | Live Activity/notification actions | Code covered | Framework wiring fixed; real action delivery still owner-only. |
| Watch app inbox/session/activity/snippets | Watch target | Code covered | Builds through project; hardware pairing/action delivery not verified. |
| Watch complication pending count | Watch widget | Flagged | Pending-count freshness needs hardware verification. |

## Push Backend and Relay

| Capability / route | Surface | Status | Evidence / recommendation |
|---|---|---|---|
| `GET /health` | Backend health | Covered locally | Returned 200 in local run. |
| `POST /register` | APNs registration | Covered locally | Requires `APPROVAL_RELAY_SECRET`; auth failure verified. |
| `POST /approval` | APNs approval push | Code covered / owner-only | Route exists; real APNs delivery requires production `.p8` and device. |
| `POST /approval/decision` | Relay decision ingress | Covered locally | Authorized decision accepted; wrong token rejected. |
| `GET /decisions` | conduitd decision polling | Covered locally | Authorized poll drains once; wrong token rejected. |
| Billing routes | Backend | Owner-only | Requires Stripe/App Store account verification. |
| Agent/run/artifact/schedule/org routes | Backend | Owner-only / flagged | Route surface exists; production Cloud behavior not part of governed-approvals local E2E. |
| Production secret fail-fast | Backend startup | Covered | New tests cover production env detection. |

## conduitd Read-Only Coverage

`daemon/conduitd` is out of direct modification scope unless it blocks governed approvals. It was not edited. Read-only verification passed:

- `go vet ./...`
- `go test ./...`

Relevant governed-approvals surfaces reviewed:

| Capability | App surface | Status |
|---|---|---|
| Approval response RPC | Inbox/session approval decisions | Code covered |
| Audit tail | Activity / while-away feed | Code covered |
| Policy get/set/reload | Settings policy editor | Code covered |
| Device register / decision poller | Notifications and relay fallback | Code covered locally via backend tests |

## Implemented But Hidden

| Capability | Recommendation |
|---|---|
| SFTP browser and file preview | Route it normally and test it, or keep it out of submission claims. |
| Preview / `SessionShellView` | Decide if this is a v1 feature. If yes, add normal navigation and screenshots. |
| Fuller keys management | Replace mock data and verify import/edit flows. |
| Snippet editor creation path | Wire from Library or remove incomplete affordances. |
| OpenRouter provider support | Add Settings support and tests only if shipping. |
| Dispatch composer | Keep debug/internal unless Cloud dispatch is submission-ready. |
| Post-onboarding provisioning | Add a normal entry point only if provisioning support is production-ready. |

## Shown But Partial

| Surface | Recommendation |
|---|---|
| Library new snippet and run actions | Wire or hide before App Review screenshots. |
| Workflows add-step/mock builder | Wire or hide. |
| Key host counts | Back with real data or remove. |
| Watch pending count | Verify on paired hardware. |
| Invite email | Enable backend email before claiming. |
| Allow-always revoke | Clarify whether revoke updates local DB only or bridge policy too. |
| Lock-screen approvals | Do not market until physical APNs proof exists. |

## Screenshot Coverage

Final June 13 screenshots are listed in `docs/audit/screens/MANIFEST.md`. They cover onboarding and all four root tabs in light and dark. Deep feature surfaces that remain partial/flagged were intentionally not promoted as final submission screenshots.
