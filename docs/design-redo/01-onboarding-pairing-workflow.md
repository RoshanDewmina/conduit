# 01 — Onboarding & pairing workflow

> First Mobbin workflow pass of the design redo. Ground truth pulled directly from
> `OnboardingRedesignGalleryView.swift` (the live `OnboardingRedesignView`, confirmed wired in
> `AppRoot.swift`'s `readyRoot`), not from screenshots or the earlier Codex audit — that audit's own
> onboarding screenshots were of the wrong screen (see `findings-log.md`). Per the brief, this stops
> after onboarding/pairing for sign-off before the next workflow.

## 1. Current state — verbatim, from source

Four steps, shared terracotta hero + dot progress + single CTA footer:

**Step 1 — "value"** (eyebrow "your machines," title "in your pocket.")
> "Lancer is mission control for the coding agents running on your own machines. Here's what you get:"
- "Approve actions from afar" / "Allow or deny risky steps in a tap"
- "Watch the terminal stream live" / "Every command, as it runs"
- "Policy guardrails per host" / "Rules enforce on every machine"
- CTA: "Continue →"

**Step 2 — "pair"** (eyebrow "step one," title "Pair the bridge.")
> "End-to-end encrypted — your code never leaves your machines."
- Mono label: "ON YOUR DESKTOP, RUN  lancerd pair"
- **Primary action, large bordered card: "Scan the QR on your desktop" / "Point your camera at the code in your terminal"**
- Divider: "or enter the 6-digit code"
- Numeric field, placeholder "000000"
- Status text cycles: "Enter or scan your desktop code to pair" → "Connecting…" → "Waiting for your desktop…" → "Paired ✓" / "Pairing failed — re-scan or re-enter the code"
- QR-scan failure: "That QR isn't a Lancer pairing code. Run `lancerd pair` on your machine."
- Optional account-device binding: "bind this daemon to my account" / "Scans a one-time daemon challenge. Lancer never asks for your account password on the host."
- CTA: "Pair & continue"

**Step 3 — "policy"** (eyebrow "almost there," title "How much rope?")
> "Set how freely agents act. You can fine-tune this per host later."
- Three radio cards (caution levels), CTA "Continue →"

**Step 4 — "sshSetup"**, optional, own chrome (eyebrow "optional," title "Enable SSH.")
> "Turn on a live terminal on your Mac. You can skip this — approvals and agent runs already work without it."

### Findings

1. **QR scanning is the primary pairing method today, not code-only.** `docs/V1_IMPLEMENTATION_PLAN.md` says QR was dropped in favor of code-only entry — the live code contradicts that. The pairing screen leads with a large bordered "Scan the QR on your desktop" card; manual 6-digit entry is the secondary path below a divider. This is the single biggest current-state/plan mismatch in this workflow and should be resolved as a product decision before any redesign, not papered over.
2. **Vocabulary violations** (style-guide §2 — banned in default user-facing surfaces): "bind this daemon to my **account**" and "Scans a one-time **daemon** challenge... password on the **host**" expose "daemon"/"host" directly in first-run copy, the worst offenders since this is the very first thing a non-technical user reads. "Set how freely agents act... per **host** later" — same. The `lancerd pair` CLI mentions are arguably unavoidable (the user must literally type that command) but appear twice with zero framing for someone who's never opened a terminal.
3. **Grammar bug** (already in style guide): "Rules enforce on every machine" → "Rules apply to every machine."
4. **"How much rope?"** is a cute idiom for a safety-critical setting (how cautious the agent is allowed to be). Cursor's launch copy and Raycast's onboarding (below) never lean on idiom for a mechanic the user needs to literally understand — worth reconsidering against the style guide's "concrete verb, plain sentence" principle, not because it's unclever, but because a first-time non-technical user has to parse a metaphor to understand what they're choosing.
5. **No code-expiry messaging.** The pairing code has a real 10-minute confirm window server-side (the relay-hardening work from this session) but nothing on this screen tells the user that — see Brave's pattern below.
6. **Four screens (plus the optional 5th) for first run** is more than the brief's "smallest sensible IA" goal, and more than the closest direct comparable (Raycast: one welcome screen, then auth — see below).

## 2. Mobbin research

**Pairing / connect-a-device:**

- [Signal — Link New Device](https://mobbin.com/screens/3807c71d-6541-4169-9c18-f0437911cba0): camera viewfinder fills the screen immediately, one line of instruction below, near-zero chrome. Does well: trust-by-simplicity — a security-serious app (directly comparable positioning to Lancer) doesn't decorate the moment of pairing. Adapt: get out of the way visually once scanning starts; don't compete with the QR target for attention.
- [X — Scan the QR code to link the app](https://mobbin.com/screens/ceb1bed4-2ba1-4dc8-8921-aa9e80233b2a): QR is the visual anchor, but **three** clearly labeled fallback affordances coexist without clutter: "Can't scan the QR code?" (link), "Enter code" (button), "Use this device instead." Adapt exactly: Lancer's manual-code fallback today is a plain divider + field, easy to skim past; X proves a fallback can be just as discoverable as the primary without fighting it for hierarchy.
- [Meta Quest — 5-digit code entry](https://mobbin.com/screens/599405f7-6102-4ed5-a213-c68d6ec5b339): "Look in your headset for a 5-digit code and enter it here," big legible digit boxes, full numeric keypad. Adapt: this is the right model for Lancer's manual-entry sub-screen specifically — large, unambiguous, one job.
- [Paired — invite/enter code](https://mobbin.com/screens/9db90a5d-e0ae-4c48-b3a9-5811753d5eb6): two color-coded blocks ("Invite your partner" / "Enter partner's code") separated by "or," each with its own boxed-digit treatment. Don't copy: Lancer's pairing is asymmetric (desktop generates, phone enters — or vice versa depending on flow direction), not symmetric like this app's mutual pairing, so the two-block layout doesn't map directly. Adapt only the visual idea: a code rendered as separated boxes reads as more "this is a real, temporary credential" than a plain text string.
- [Brave Browser — Sync Chain QR Code](https://mobbin.com/screens/53c3fdf5-a622-4484-aa67-8ed340ca85c0): explicit security framing in plain language — *"Treat this code like a password. If someone gets hold of it, they can read and modify your synced data"* — plus a live countdown, *"This temporary code is valid for the next 0 hour 29 min 48 seconds."* Adapt directly: Lancer's relay now has a real, server-enforced 10-minute expiry on unconfirmed codes (shipped this session) and zero UI communicates it. This is the single most directly portable pattern found.

**Value-prop economy (first-run screen count):**

- [Raycast — Welcome to Raycast](https://mobbin.com/screens/76d2a569-05bd-4694-8d1a-7dff72ff768f): "A collection of powerful productivity tools in your pocket" — one screen, then straight to Log in / Create Account. No feature-by-feature carousel. Worth noting: Raycast independently arrived at "in your pocket" as the value-prop phrase, the same anchor Lancer's current copy already uses — good signal that phrase is doing real work and should stay. Adapt: a comparable developer tool gets the user oriented in **one** screen, not three feature rows on a dedicated step. Don't copy: Raycast's product doesn't need a safety/policy decision before first use; Lancer's does, so step 3 (policy) earns its place in a way a pure marketing carousel wouldn't.

## 3. Recommended pattern for Lancer

**Collapse four screens to two**, and resolve the QR-vs-code product question before redesigning around it:

1. **Decide QR vs. code-only as a product call, not a copy fix.** Given the relay's pairing-code protections (key pinning, expiry, rate limiting — all shipped) were explicitly designed around a short human-typed code, and per the V1 constraint to "hide networking details... every screen one clear primary purpose," recommend: **make the 6-digit code the primary path, QR the secondary** (the inverse of what's shipped today) — typing a code requires no camera permission, works identically whether the desktop terminal is visible or not, and matches what the relay hardening work already assumes is the normal case. QR stays available (X's pattern: a clearly-labeled link, not removed) for when both devices are in hand and faster.
2. **Merge "value" and "pair" into one screen**, following Raycast: keep the three value rows (they're short and earn their place — Lancer's safety pitch needs more than a one-liner, unlike Raycast), but put the pairing code entry directly below them on the same screen instead of a forced "Continue" tap between two screens that are really one job ("here's what this does, now connect it"). This also removes one full screen transition from the critical path.
3. **Keep "policy" as its own screen** — it's a real decision, not value-prop filler, and deserves focus. Rename "How much rope?" to something literal per the style guide, e.g. **"How cautious should agents be?"** — keeps the same friendly register without requiring the user to decode a metaphor for a safety setting.
4. **Add the Brave-style expiry/security framing** to the pairing code itself: a short line under the code field stating it expires shortly and shouldn't be shared, using the relay's real `pairConfirmWindow`. This is a copy-only addition, not new engineering — the constraint already exists server-side.
5. **Fix the vocabulary leaks** per the rewrite table below before anything else ships — these are the worst-positioned instances of banned terms in the whole app, since they're the first thing a new user reads.
6. **SSH step stays optional and last**, unchanged in spirit — it already does the right thing (clearly skippable, explains what's gained).

## 4. Proposed page structure (onboarding/pairing only)

| Today (4-5 screens) | Proposed (3 screens) |
|---|---|
| 1. Value carousel | **1. Value + connect** — three value rows + code-entry (primary) / QR (secondary link), merged |
| 2. Pair the bridge | *(merged into 1)* |
| 3. Policy ("How much rope?") | **2. Caution level** ("How cautious should agents be?") |
| 4. Optional SSH | **3. Optional: enable SSH** — unchanged |

Net: one fewer mandatory screen before the user reaches the app, same information, no capability removed.

## 5. States to cover

- **Loading**: pairing in progress ("Connecting…") — already exists, keep.
- **Empty**: N/A (this flow has no empty state of its own).
- **Offline**: no current copy for "phone has no network during pairing" — relay dial will simply fail silently into the generic `pairingFailed` state today. Needs an explicit offline message, not the same text as a wrong/expired code.
- **Error**: QR-mismatch and generic pairing-failed both exist; needs a **distinct** message for "code expired" (now a real server-side state per the relay hardening) vs. "wrong code"/"key mismatch" (a hijack-attempt rejection) vs. generic network failure — right now all three likely collapse into the same "Pairing failed — re-scan or re-enter the code" text, which doesn't tell the user which of three very different problems occurred.
- **Expired code**: not distinguished today (see above) — should be, given it's now a real, intentional server behavior (`pairConfirmWindow`), not a bug.
- **Permission-denied**: camera permission denial for QR scanning falls back to manual entry already (`onUnavailable`) — keep, this is the right pattern.

## 6. Copy rewrite

| Current | Rewritten | Why |
|---|---|---|
| "Policy guardrails per host" / "Rules enforce on every machine" | "Policy guardrails per machine" / "Rules apply to every machine" | drops "host" (banned), fixes grammar bug |
| "bind this daemon to my account" | "link this machine to my account" | drops "daemon" |
| "Scans a one-time daemon challenge. Lancer never asks for your account password on the host." | "Scans a one-time security code. Lancer never asks for your account password on this machine." | drops "daemon"/"host," keeps the actual security claim intact |
| "Set how freely agents act. You can fine-tune this per host later." | "Set how freely agents act. You can fine-tune this per machine later." | drops "host" |
| "How much rope?" | "How cautious should agents be?" | literal, no idiom to decode for a safety setting (§1 voice principle) |
| "Pairing failed — re-scan or re-enter the code" (used for all failure types) | distinct per cause: "That code's expired — get a new one from your machine." / "That code didn't match — check it and try again." / "Can't reach the relay — check your connection." | one error message currently covers three different causes the user should react to differently |
| *(none today)* | Under the code field: "This code expires in a few minutes and works once — don't share it." | Brave-pattern: states the real `pairConfirmWindow` behavior in plain language, sets expectation before it fails |

---

## Summary

Pulled the real onboarding/pairing flow straight from source (faster and more reliable than fighting
simulator state) and found the biggest issue isn't copy — it's that the shipped flow still leads with
QR scanning, contradicting the project's own "code-only" plan doc. Recommend flipping the hierarchy
(code primary, QR secondary), merging the value and pairing screens into one (Raycast gets a
comparable dev-tool user oriented in a single screen), keeping policy as its own screen but renaming
"How much rope?" to something literal, and adding Brave's plain-language code-expiry framing since the
relay already enforces real expiry server-side with nothing telling the user. Five vocabulary leaks
("daemon," "host" ×2) found in first-run copy — the worst-positioned instances in the app since
they're the first thing a new user reads. Net page count: 4-5 mandatory screens down to 3. Full detail,
Mobbin citations, and the complete copy rewrite table are in the doc above — stopping here per the
brief for sign-off before moving to the next workflow (home / attention overview).
