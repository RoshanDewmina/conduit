# App Store listing copy — Lancer (`dev.lancer.mobile`)

Status: **draft for owner review**, nothing entered into App Store Connect.
Supersedes `docs/distribution/APP_STORE_CONNECT_METADATA.md` where the two
disagree — that draft describes a QR-code pairing flow that no longer
exists (`docs/legal/SECURITY_ARCHITECTURE.md` §2.1: pairing is code-only,
6-digit, since before this session) and predates the interactive-terminal
and governance-first positioning in `ARCHITECTURE.md` §0.1. Character
counts below are approximate — recount in App Store Connect before locking.

---

## App name

**Lancer** (7 chars, fits App Store Connect's 30-char limit with room to
spare). App record is already named **"Lancer — Agent Control"** per the
owner's brief — use that as the App Store Connect record display name if
plain "Lancer" is unavailable as a unique listing name (verify availability
at submission time).

## Subtitle (30-char limit)

**Approve your agents, on the go** (32 chars — too long, trim).

Recommended: **Govern your coding agents** (27 chars).

Alternative: **Approve agent actions fast** (28 chars).

## Promotional text (170-char limit, editable without a new build)

Lancer is your mission control for AI coding agents running on your own
Mac or server. Review, approve, and audit every risky action — from
anywhere, in seconds.

(155 chars.)

## Description

```
Lancer is mobile mission control for the AI coding agents you already run
— Claude Code, Codex, OpenCode, and Kimi — on your own Mac or Linux
machine. Your code and credentials never leave your own infrastructure.

GOVERN YOUR AGENTS
Every risky action your agent proposes — a shell command, a file write —
can be gated behind a human decision. See the exact command, the policy
rule it matched, and its blast radius before you approve, deny, or edit
it. High-risk actions always wait for you; low-risk actions can proceed
on their own under a policy you set.

STAY IN THE LOOP FROM ANYWHERE
Get a notification the moment your agent needs a decision, including on
the lock screen. Approve without opening the app. Keep working from your
phone, on a walk, or away from your desk — the agent on your host keeps
running while you're disconnected, and picks back up the moment you
decide.

DISPATCH AND FOLLOW UP
Start a new agent run from your phone and watch it stream back in real
time, including every tool call it makes. Send follow-ups to keep the
conversation going, on the same host, without touching a keyboard.

A REAL TERMINAL WHEN YOU NEED ONE
Open a live, interactive SSH terminal to any host you've paired — run
commands by hand, or watch a live TUI (vim, htop, and friends) render
inline, right inside your chat session.

YOUR INFRASTRUCTURE, YOUR RULES
Lancer pairs with a small daemon on your own host with a one-time 6-digit
code — no QR scan, no cloud execution. Approvals route through an
end-to-end encrypted relay that only ever sees ciphertext; you can also
self-host the relay yourself.

Lancer Pro unlocks the full governance surface, plus iCloud sync of your
conversation history across your own Apple devices.

WHO THIS IS FOR
Developers and small teams running autonomous or semi-autonomous coding
agents who want a real approval gate and audit trail — without giving up
control of where their code, credentials, and compute live.
```

**VERIFY before publishing:** cross-check every capability named above
against `ARCHITECTURE.md` §0.1's Implemented list for the specific build
being archived — this draft intentionally drops SFTP browser and
port-forwarding preview (both listed as roadmap/gap items in §3.4's feature
matrix, not shipped V1 surfaces) to avoid a repeat of the prior draft's
overclaim flagged in `docs/appstore/REVIEWER_NOTES.md` §3.

## Keywords (100-char limit)

```
agent,ai,ssh,terminal,approval,governance,claude,codex,devops,automation,remote,audit,policy
```

(94 chars.) Note: "claude" and "codex" name third-party products Lancer
interoperates with — flagged in the prior draft as a VERIFY item; confirm
this is acceptable under current App Store guidelines, or soften to
"ai coding agent" generic phrasing if App Review pushes back.

## Support URL

**Owner-gated placeholder.** No live support page confirmed in this repo.
Interim options if no dedicated site exists: a GitHub Issues URL, or a
simple static page. App Store Connect will not accept the listing without
a reachable URL here — this is a required field, not optional.

## Marketing URL (optional)

**Owner-gated placeholder — and an open naming decision.** `ARCHITECTURE.md`
and `docs/STATUS_LEDGER.md` both reference the still-open
`*.conduit.dev` vs. `lancer.dev` domain-copy decision (see
`docs/product/2026-07-16-policy-audit-relay-port-map.md` for the latest
context) — do not pick a marketing URL that bakes in the wrong domain
before that decision lands. Leave blank if undecided at submission time.

## Privacy Policy URL (required by App Store Connect)

**Not found live in this repo as of 2026-07-17.** Base the policy content
on `docs/appstore/PRIVACY_NUTRITION_LABEL.md` (this pack) once a public URL
exists; App Store Connect rejects submission without one.

## Category

**Primary: Developer Tools.** **Secondary (optional): Utilities.**
Rationale unchanged from the prior draft — the core function (agent
governance, SSH terminal, host management) is squarely a developer tool.

## Age rating

Likely **4+** — no objectionable content, developer utility. Walk the
actual ASC age-rating questionnaire at submission time; this doc does not
substitute for it.

## What's New — first TestFlight build (version 1.0.0)

```
Welcome to Lancer.

• Governed approvals — review risky agent actions with policy match and
  blast radius, approve or deny from the lock screen
• Dispatch new agent runs and follow up on existing ones, with live
  streaming tool calls
• A real interactive SSH terminal, inline in your chat session
• Pair your own host with a one-time 6-digit code — no cloud execution
• iCloud sync for your conversation history (Lancer Pro)
```

Keep this aligned to what's actually in the archived build — strip any
bullet the current build doesn't support, per `ARCHITECTURE.md` §0.1's
Implemented/Partial split (e.g. do not claim cross-device CloudKit sync is
fully proven if `docs/appstore/CLOUDKIT_SCHEMA_PROMOTION.md`'s two-device
gate (C7) hasn't been closed yet — say "sync your conversation history"
without the word "seamlessly" or similar over-claim language until C7 is
verified).

## In-App Purchase listing — `dev.lancer.mobile.pro`

- **Reference name:** Lancer Pro
- **Type:** Non-Consumable, one-time purchase (confirmed by
  `Lancer/Lancer.storekit` — `"type" : "NonConsumable"`)
- **Price:** $14.99 — confirm this is the intended **live** ASC price tier;
  the `.storekit` file is a local StoreKit-testing config only.
- **Display name:** Lancer Pro
- **Description:** "Full access to Lancer Pro features: the agent approval
  inbox, policy & governance controls, and iCloud sync across your Apple
  devices." (Trimmed vs. the prior draft's `Lancer.storekit` copy — removed
  the SFTP-browser and port-forwarding-preview claims per the VERIFY note
  above; restore them only once those surfaces are confirmed shipped.)
- **VERIFY:** confirm this IAP record doesn't already exist in App Store
  Connect from an earlier session before creating a duplicate — creating it
  is owner-gated (see `SUBMISSION_CHECKLIST.md`).

Note: the "Managed AI Credits" Stripe subscription
(`docs/product/2026-07-16-managed-ai-credits-design.md`) is a **separate,
externally billed** product, not an Apple IAP — do not conflate the two in
the App Store listing. Only `dev.lancer.mobile.pro` needs an ASC IAP
record. If any external-payment language appears in the listing or in-app,
verify against current App Store guidelines whether Apple's External
Purchase Link entitlement/disclosure applies.

## Sources read this session

- `ARCHITECTURE.md` §0.1, §3.4 (feature matrix, SFTP/port-forwarding gap)
- `docs/legal/SECURITY_ARCHITECTURE.md` §2.1 (pairing is code-only)
- `docs/distribution/APP_STORE_CONNECT_METADATA.md` (superseded draft)
- `docs/STATUS_LEDGER.md` (domain-copy open decision, managed-credits product)
- `Lancer/Lancer.storekit`
