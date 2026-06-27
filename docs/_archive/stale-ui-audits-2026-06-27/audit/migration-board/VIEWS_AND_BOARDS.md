# Lancer — Views & Boards Catalog

A map of every screen in the app + the design boards that live in this folder, each with
a one-line description so you can get up to speed. The **design discussion** section at the
bottom is where we'll work through the V1 simplification.

Source of truth for screens: `Packages/LancerKit/Sources/`. Design boards (PNG/JSX) live
in this folder (`docs/audit/migration-board/`).

---

## The 4 tabs (the app's spine)

| Tab | File | What it does |
|---|---|---|
| **Inbox** | `InboxFeature/InboxView.swift` | The approval queue — agent permission requests (run bash, write file, etc.) land here as cards; Deny / Approve / Approve+run / scoped Allow-always. The core loop's payoff screen. |
| **Fleet** | `AppFeature/FleetView.swift` | The supervision board — connected hosts, agents, spend, active loops, host-health, quota. "What's running / blocked / costing money." Also the `+ task` dispatch entry. |
| **Activity** | `InboxFeature/ActivityView.swift` | History/audit feed — what agents did, decisions made, "while you were away." |
| **Settings** | `SettingsFeature/SettingsView.swift` | Policy, security (keys, secrets, trust), relay pairing, notifications, doctor, billing. |

## Onboarding & connect
| View | File | What it does |
|---|---|---|
| Onboarding intro | `OnboardingFeature/OnboardingView.swift` | First-run: "agents ask · you approve · work resumes" → get started. |
| Pair the bridge | `OnboardingFeature/BridgePairingView.swift` | Keyless pairing: install command + QR + 6-digit code; relay handshake. |
| QR scanner | `OnboardingFeature/QRScannerView.swift` | Camera scan of a host-shown code (the host-prints-QR direction). |
| Add host (SSH) | `WorkspacesFeature/AddHostView.swift` | Power-user fallback — SSH host + inline Ed25519 key-gen. |
| Host editor / key confirm | `WorkspacesFeature/HostEditorView.swift`, `HostKeyConfirmSheet.swift` | Edit a host; TOFU host-key trust prompt. |

## Session / terminal (depth)
| View | File | What it does |
|---|---|---|
| Session | `SessionFeature/SessionView.swift` | The live block terminal (Warp-style blocks) for a connected host. |
| Live prompt input / keyboard rail | `LivePromptInputView.swift`, `KeyboardAccessoryRail.swift`, `TerminalKeyboardPanel.swift` | Command bar + terminal key helpers (Esc/Tab/Ctrl/arrows). |
| Explain / snippet palette | `ExplainSheet.swift`, `SnippetPaletteSheet.swift` | Explain a command; run saved snippets. |
| Port forward | `PortForwardView.swift` | SSH port-forwarding controls. |

## Fleet depth / agent runs
| View | File | What it does |
|---|---|---|
| Dispatch | `AppFeature/DispatchView.swift` | Fire a headless task: pick agent + model + prompt → lancerd runs `claude -p`/`codex exec`. |
| Agent run detail | `AgentRunDetailView.swift`, `RunDetailView.swift` | A dispatched run's output/status; now includes git "Changes" + Ship-it + Proof Card. |
| Loop detail | `LoopDetailView.swift` | A supervised loop: goal, plan, blocker, files, tests, approvals, spend, PR/checks. |
| Worktree board | `WorktreeBoardView.swift` | 3-column branch/worktree board (active / review-ready / idle). |
| Agents / workspace / files / org / exec | `AgentsView`, `AgentWorkspaceView`, `AgentFilesView`, `AgentOrgView`, `AgentExecView`, `AgentDetailView` | Agent browse/manage surfaces (several are depth/secondary). |
| Quota guard | `QuotaGuardView.swift` | Per-provider spend caps, burn-rate, alerts. |
| Sessions home | `SessionsHomeView.swift` | Legacy sessions list home. |

## Settings depth
| View | File | What it does |
|---|---|---|
| Policy editor / simulator | `PolicyEditorView.swift`, `PolicySimulatorView.swift` | Edit autonomy rules + "what this policy would have done" replay. |
| Relay pairing | `E2ERelayPairingView.swift` | Configure/relay-pair from Settings (relay URL). |
| Keys / import | `KeysFeature/KeysView.swift`, `KeyImportView.swift` | SSH key gen/import/manage. |
| Secrets / provider keys | `SecretsView.swift`, `ProviderKeysView.swift` | Secrets broker; Anthropic/OpenAI provider keys. |
| Audit | `AuditView.swift` | Tamper-evident audit log + verify/export. |
| Doctor | `DoctorView.swift` | Setup/health self-check (daemon, hooks, agent auth, etc.). |
| Trust & privacy / sync / terminal | `SyncStatusView.swift`, `TerminalSettingsView.swift` | iCloud sync status; terminal prefs. |
| Billing / paywall / premium | `BillingView.swift`, `PaywallSheet.swift`, `PremiumComparisonView.swift` | Monetization surfaces. |

## Design boards in this folder
| Board (PNG) | Shows |
|---|---|
| `board-expanded-overview.png` | Full target overview/monitoring board. |
| `board-onboarding-flow.png` | Target onboarding/pairing flow. |
| `board-pairing.png` | Pair-the-bridge target screen. |
| `board-trust.png` | Trust & vendors target screen. |
| `board-backend-surfaces.png` | Backend/control-plane surfaces. |
| `cc-migration.jsx`, `cc-screens-*.jsx`, `cc-components.jsx`, `cc-platform-surfaces.jsx` | React/JSX mockups of the target design (served at localhost:4178). |

---

## Design discussion (V1 simplification) — WORKING SECTION

> This is where we talk. Goal: simplify the frontend — intuitive, nice animations, simple
> and inviting, NOT cluttered — without losing core functionality. Decide the V1 must-have
> set; everything else is paused until the core is perfect.

**Open items to decide together:**
- [ ] Remove the persistent **active-sessions / status top bar** (user: it's clutter).
- [ ] V1 must-have set — the screens that make Lancer *Lancer* (candidate: Onboarding/Pair
      → Inbox approvals → Fleet monitoring → Session → Activity → core Settings/Policy).
- [ ] What to PAUSE for V1 (candidates: worktree board, org/exec/agent-browse depth, billing/
      paywall, quota guard, secrets, sync, port-forward) — keep code, hide from V1 nav.
- [ ] Per-tab clutter pass (Inbox / Fleet / Activity / Settings) — notes added after walkthrough.

### Walkthrough notes (2026-06-15, seeded sim)

**Cross-cutting (every tab):**
- **Persistent top status bar** ("· no active session" glyph grid + "bridge offline · policy · today $0.00") appears on ALL four tabs. When nothing's connected it's pure noise. → **Remove it** (user agrees). Option: fold a single honest connection dot into Fleet only.
- Every tab repeats a **decorative breadcrumb** (`~/lancer › …`) + a **rainbow gradient strip**. Stylistic clutter repeated 4×; simplify to one quiet header.

**Inbox** — strong. Approval cards are the product: clear command, risk chip (HIGH/MED), blast radius, Deny/Approve/Edit&run/Allow-always. Keep as the hero. Minor: 4 actions per card is a lot but each is useful.

**Fleet** — saved-hosts list is core and good. But prime real estate goes to: an empty **$0.00 spend hero** (0 runs · 0 concurrent), **Quota Guard**, and **Branches & Worktrees** — all V1-pause candidates. Demote/hide; lead with hosts + "what's running".

**Activity** — clean, honest empty state gated on connection. Fine as-is.

**Settings** — comprehensive but long (~scrolls 2×): Bridge & hosts, Policy, Notification filters, Security (Face ID, redact, SSH keys, audit, health, provider keys), Trust & Privacy, Account (Pro, Billing), iCloud sync, Theme. V1-core: bridge/relay, Policy, notifications, security basics. Pause/group: Billing/Pro, iCloud sync, Quota.

**Bugs found during walkthrough:**
- "i already use lancer" routes to **Add Host**, not the app — confusing entry.
- **"lancer cloud" tab reappeared** in Add Host (the earlier gate was lost in a merge).

**Proposed V1 must-have set (the spine):**
Onboarding/Pair → **Inbox (approvals)** → **Fleet (hosts + running/blocked)** → **Session** → **Activity** → **core Settings/Policy**. Pause (keep code, hide from nav): worktree board, quota guard, agent org/exec/browse depth, billing/paywall, secrets, sync, port-forward.
