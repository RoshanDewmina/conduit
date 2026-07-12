# Design: Claude account hot-swap + agent identity badges (approved 2026-07-12)

Owner-approved brainstorm output (owner-asks #23 + new identity ask). Two features, shipped
in reverse order: identity badges first (ui), hot-swap second (sensitive). Context:
Orca precedent = swap the CLI credential JSON between stored profiles
([[project_byoa_account_switcher_gap_2026-07-04]]); Lancer's `agent` field already persists
per conversation.

## 1. Claude account hot-swap (v1: Claude Code only; auto + manual; loud)

**Job:** dodge rate limits across multiple Claude subscriptions; machine-wide swap.

**Daemon (sensitive):**
- Profile store `~/.lancer/claude-profiles/<name>.credentials.json` (0600), snapshots of
  `~/.claude/.credentials.json`. Active profile = content-hash match.
- RPCs: `account.profiles.list` / `account.profiles.capture` / `account.profiles.activate`.
  Activate = write-temp → atomic rename; REFUSED while a Claude run is active on the machine.
  Credential bytes never cross the relay — phone sees names/status only.
- Auto-swap (opt-in, default OFF): on a turn failing with a rate-limit signature, activate the
  next profile in rotation and re-dispatch that turn ONCE. Second limit → fail honestly.
  Every auto-swap: push notification + audit-log event + system line in the thread
  ("Rate-limited on *work* → swapped to *personal*, retried").
- Receipts gain `accountProfile` (per-turn executing account).

**Phone:** Settings → Claude Accounts — profile list (active checked), tap→confirm→activate;
"Capture current login as…"; auto-swap toggle. Rate-limit-failed turns get "Swap account &
retry". (Login itself stays on the Mac: `claude login` once per account, then capture.)

**Risk:** sensitive (credentials + dispatch) → Sonnet implements, Fable full-diff review.
Never log credential contents; Redactor patterns apply.

## 2. Agent identity badges (provider + account)

**Component:** `AgentIdentityBadge` in DesignSystem — vendor glyph + fixed tint per provider
(Claude/Codex/OpenCode/Kimi monograms + color tokens). Three sizes:
- glyph-only: thread-list rows (compact)
- glyph+name: thread header, Agents rows, composer confirm
- glyph+name+account: "Claude Code · personal" — thread header, receipts, Agents rows; the
  account segment renders only when profile data exists (degrades cleanly pre-hot-swap).

**Data:** provider from the conversation `agent` field; account from receipt `accountProfile`
(per-turn truth — Flight Recorder shows per-turn accounts; header shows latest).

**Risk:** ui. Ships FIRST; hot-swap receipts later light up the account segment.

## Ship order & verification
1. Badges lane (ui): swift test + app-target build + sim gate (badges on list/header/receipt).
2. Hot-swap lane (sensitive): go test + vet; live gate = capture two profiles, manual swap,
   dispatch proves active account via receipt `accountProfile`; auto-swap proven by forcing a
   rate-limit signature; audit events + push observed. Full e2e dogfood per standing done-bar.
