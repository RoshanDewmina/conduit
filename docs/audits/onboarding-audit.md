# Phase 6 — Onboarding Audit (aggressive)

> Highest-priority UX problem. Production flow = `OnboardingRedesignGalleryView` + `AccountEntryView`
> + `OnboardingPolicy` + `OnboardingSSHSetupScreen`. Legacy `OnboardingView` (7-step) is gallery-only → remove.
> Copy extracted from source; screens viewed in `screenshots/onboarding/`.

## The core problem (one line)
**The user must make an account decision laden with 4 concepts (account / recovery / device management / billing / offline pairing) and complete an auth form BEFORE they ever see what Lancer does.** Value is shown on screen 3, after the hardest step.

## Per-screen measurement

| # | Screen | ~Words | Concepts | Primary action | Required? | Repeated? | Could be visual? | Blocks value? | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Account connection choice** (`AccountEntryView`) | ~55 | 5 (Supabase account, recovery, device mgmt, billing, offline pairing) | Pick account vs offline | **No** (offline works) | — | partly | **YES** | **Move after value; default to offline** |
| 2 | **Create account / Sign in / Name** (+ reset, forgot, confirm sub-flows) | 40–90 across states | email, password ≥12, email confirmation, `lancer://auth/callback` | Submit credentials | No (optional) | — | no | **YES** | **Make optional/contextual** |
| 3 | **Value hero** ("your machines, in your pocket") | ~40 | 3 (approve / watch / policy) — well chosen | Continue | n/a (this IS the value) | — | already visual ✓ | — | **Keep — move to screen 1** |
| 4 | **Pair bridge** ("ON YOUR DESKTOP RUN `lancerd pair`" + QR/6-digit) | ~25 | 2 (run daemon, scan/enter) | Scan or enter code | **Yes** (the one required step) | — | yes | — | **Keep — this is the real setup** |
| 5 | **Policy** ("How cautious?") preset picker | ~10 | 1 (autonomy) | Pick preset | Yes (but defaultable) | also in Settings×2 | yes | — | **Keep, pre-select a default** |
| 6 | **SSH setup (optional)** — Remote Login, `scutil` commands, add machine | ~85 | 4 (Remote Login, sshd, terminal commands, add host) | Follow instructions | **No** | — | partly | — | **Remove from onboarding → contextual when adding an SSH host** |

## Principle violations
- **Show value first** — violated: value is screen 3, behind an account fork + auth form.
- **One idea per screen** — violated: account choice packs 5 concepts; SSH screen packs 4.
- **Minimal text** — violated: account choice + SSH screens are dense paragraphs.
- **Ask permission with context** — camera (QR) is requested at pairing (ok); but account/billing concepts arrive with zero context.
- **Don't make users learn the product first** — violated: device management, billing, Supabase, offline-pairing tradeoffs all surfaced pre-value.
- **Avoid unnecessary setup questions** — the account fork is an unnecessary blocker for first-run; the app supports account-free pairing.

## Real-user evidence (prior session `be82d0a1`)
> "I'm on this onboarding page where it says pair the bridge — there's **no prior steps saying we should install and run it first** on our computer." → ordering/instruction gap at the pairing step (the one step that genuinely needs guidance) while energy was spent on account screens that don't.

## Proposed minimal flow (3 screens + optional)

| # | Purpose | Minimal copy | Primary visual | Primary action | System interaction | Why necessary |
|---|---|---|---|---|---|---|
| 1 | **Show the value** | "Approve your coding agents from your phone." + 3 icon rows (Approve · Watch · Guardrails) | the editorial hero already built | **Get started** | — | Communicates the product in one glance; no decision yet |
| 2 | **Connect your machine** (the only required setup) | "On your computer run `lancerd pair`, then scan the code." | QR scanner + 6-digit field; a tiny "how to install" link | Scan / enter code | Camera permission (in context) | Pairing is the one thing the app cannot work without |
| 3 | **Set caution** (defaulted) | "How much can agents do on their own?" — Balanced pre-selected | 3 preset cards | **Done** | Notification permission prompt here (in context of approvals) | Establishes the approval posture; default means it's one tap |
| +  | **Create an account?** (optional, AFTER done) | "Save your setup for recovery, billing & multiple devices?" | small card | Create / Skip | Supabase (deferred) | Account is only needed for billing/multi-device — not for the core loop |
| +  | **SSH terminal** (contextual) | the existing Remote-Login instructions | — | shown only when user taps "Add an SSH machine" | — | Power-user path; doesn't belong in first-run |

### Net: 5–7 screens → **3 required + 2 contextual/optional.** Value moves to screen 1. Account + SSH become optional/contextual. Legacy `OnboardingView` removed.
