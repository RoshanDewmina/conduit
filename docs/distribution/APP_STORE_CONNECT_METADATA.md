# App Store Connect listing metadata — draft

Status: **DRAFT for owner review.** Nothing here has been entered into App Store
Connect. Character counts are approximate guides against Apple's published limits;
recount before submitting. Claims are scoped to what's implemented today (see
`docs/LIVE_LOOP_RUNBOOK.md`) — do not add claims (e.g. "works with every agent",
"instant notifications") that outrun what's been proven.

---

## App name

**Lancer**

(30-char limit. "Lancer" is 7 chars — leaves room if App Store Connect requires a
longer unique name; e.g. "Lancer — Agent Control" as a fallback if "Lancer" alone
is taken by another listing. VERIFY name availability in App Store Connect before
locking this in.)

---

## Subtitle (30-char limit)

**Govern your AI agent loops**

(29 chars. Alternative: "Approve agent actions, fast" — 28 chars.)

---

## Promotional text (170-char limit, editable without a new build)

**Lancer puts your AI coding agents on a leash. Approve or reject risky actions
from your phone, dispatch runs, and open a real terminal — all from your own
hosts.**

(167 chars.)

---

## Description

```
Lancer is a mobile control plane for the AI coding agents you already run —
Claude Code, Codex, OpenCode, and Kimi — on your own Mac or Linux machines.

You stay in control. Lancer doesn't run agents in the cloud or hold your code:
it pairs with a small daemon (lancerd) on your own host, and lets you govern
what your agents are allowed to do from your phone.

WHAT YOU CAN DO
• Approve or reject risky actions in real time — file writes, shell commands,
  anything your policy marks as needing a human in the loop. See exactly what
  the agent wants to do, the matched rule, and the blast radius before you decide.
• Dispatch a new agent run from your phone and watch it stream back, including
  tool calls, then send follow-ups to continue the conversation.
• Open a real interactive SSH terminal to any reachable host, right inside a
  chat session — run commands by hand or watch a live TUI (vim, htop, and
  friends) render inline.
• Self-host the relay yourself, or use the hosted option — your choice.

HOW IT WORKS
Install the lancerd daemon on the host you want to govern (one command), pair
your phone by scanning a QR code, and you're set. Approvals route through an
end-to-end encrypted relay; the relay forwards opaque ciphertext and never holds
a key that lets it read your commands or decisions.

WHO THIS IS FOR
Developers and small teams running autonomous or semi-autonomous coding agents
who want a human-approval gate and visibility into what those agents are doing
— without giving up control of where their code and credentials live.

Lancer Founder's Edition is a limited-time, one-time in-app purchase that supports early
adopters and is grandfathered into the future Pro subscription. The core trust loop —
approval inbox, policy, audit, emergency stop — is free. Founder's Edition unlocks
convenience surfaces (e.g. multi-host management, advanced surfaces) at launch.
```

(VERIFY: re-confirm SFTP browser and port-forwarding preview are both
user-visible/working before publishing this description — confirm against
`ARCHITECTURE.md` §0.1 current-state snapshot, which this draft did not
exhaustively cross-check feature-by-feature. Pull anything not actually shipped.)

---

## Keywords (100-char limit, comma-separated, no spaces needed around commas)

```
ssh,agent,ai,automation,terminal,devops,approval,claude,codex,remote,server,cli,bot
```

(Adjust if any of these read as trademark-adjacent in ASC review — "claude" and
"codex" name third-party products Lancer interoperates with; VERIFY this is
acceptable under App Store guidelines before submission, or soften to "ai coding
agent" generic phrasing.)

---

## Support URL

**VERIFY / placeholder** — `https://conduit.dev/support` (no live support page
confirmed in this repo). Owner must provide a real, reachable URL before
submission. A GitHub Issues URL (e.g.
`https://github.com/RoshanDewmina/lancer/issues`) is a reasonable interim value
if no dedicated support site exists yet.

---

## Marketing URL (optional)

**VERIFY / placeholder** — leave blank if no marketing site exists yet, or use the
GitHub repo README as an interim value.

---

## Privacy Policy URL (required by ASC)

**VERIFY — not found in this repo.** A privacy policy page must exist at a public
URL before submission; App Store Connect will not accept the listing without one.
See `docs/distribution/PRIVACY_ANSWERS.md` in this same directory for the data
inventory to base that policy on.

---

## Category recommendation

**Primary: Developer Tools**
**Secondary (optional): Utilities**

Rationale: the app's core function — governing CLI-based coding agents, SSH
terminal access, host management — is squarely a developer tool. "Productivity" is
a plausible secondary alternative but less precise.

---

## Age rating

Likely **4+** (no objectionable content; it's a developer utility). VERIFY against
the actual ASC age-rating questionnaire — this draft does not walk through that
questionnaire.

---

## What's New (first build / version 1.0.0)

```
Welcome to Lancer 1.0.

• Approve or reject risky AI agent actions from your phone, in real time
• Dispatch new agent runs and follow up on existing ones
• Open a real SSH terminal to any reachable host, inline in a chat session
• Pair your own self-hosted daemon via QR code
• iCloud sync for your hosts and keys (Founder's Edition)
```

(Keep "What's New" aligned to what's actually in the build being submitted — strip
any bullet not present in that specific build.)

---

## In-App Purchase listing (for `dev.lancer.mobile.pro`)

- **Reference name:** Founder's Edition
- **Type:** Non-consumable, one-time purchase (NOT a subscription — confirmed by
  `Lancer/Lancer.storekit` in this repo).
- **Price:** **$89.99** (ASC tier within the $79–99 band; supersedes the old $14.99
  draft). The local `.storekit` file mirrors this for Xcode StoreKit testing.
- **Display name:** Founder's Edition
- **Description:** Limited-time early-adopter purchase; grandfathered into future Pro
  subscription. Unlocks convenience surfaces (multi-host management, advanced surfaces).
  Core safety features (approval, policy, audit, emergency stop) remain free.
- **VERIFY:** this IAP record does not exist yet in App Store Connect — creating it
  is a human-gated step (see `HUMAN_GATED_STEPS.md`).

Note: the repo retains a Stripe-billed hosted-cloud subscription spine (`billing.go`) for
**V2 hosted execution** — it is **not offered at GA** and is **not** an Apple IAP. Do not
conflate the two in the ASC listing; only `dev.lancer.mobile.pro` needs an IAP record at GA.
