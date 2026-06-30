# Lancer copy style guide

> Working reference for the copy redo (2026-06 design-redo pass). Apply this screen-by-screen as we
> go through each Mobbin workflow — don't blind-sweep the whole app against it before we've
> sanity-checked it on a real screen. Sources: Cursor's iOS launch copy (cursor.com/changelog/ios-mobile-app,
> 2026-06-29), Mobbin research on Wise/Notion/Replika confirmation patterns, Lancer's own onboarding
> carousel (the best copy currently in the app — use it as the bar, not the audit).

## North star

**A non-technical developer's manager should be able to read any screen in this app and know what
it's asking of them.** Not "understand the architecture" — just know what's happening and what
happens if they tap the button. If a sentence needs the reader to already know what a daemon, relay,
or shell is, rewrite it.

---

## 1. Voice principles

**Concrete verb, plain sentence, one product noun per clause.**
Cursor's launch copy is the model: *"Open the Cursor mobile app, choose a repo, and launch an
agent the same way you would on the desktop app."* Three clauses, three plain verbs (open, choose,
launch), each clause carries exactly one noun the reader needs (app / repo / agent). It never says
"orchestrate your repository's agent runtime environment."

- **Active voice, subject does the verb.** "Approve this," not "This requires approval."
- **Anchor new concepts to a familiar mental model**, don't define them in the abstract. Cursor:
  "the same way you would on the desktop app." Lancer's onboarding already does this well: "your
  machines, in your pocket" — phone-in-pocket is the familiar anchor, not "remote session
  management."
- **Short sentences. One idea per sentence.** If you need a semicolon, it's two sentences.
- **Say what the user can DO, not how the system works.** "Watch the terminal stream live" (user
  action), not "Output is streamed via the unified PTY pipeline" (system internals).
- It's fine to use real product nouns confidently (agent, machine, run, approval) — the rule is
  density, not avoidance. One unfamiliar noun per sentence is fine. Three is jargon.

## 2. Vocabulary — what's hidden, what's allowed

Per the project's own working rules: hide networking/infra implementation details from normal
users. This is a copy rule, not just an architecture rule — the words leak the architecture.

| Banned in user-facing copy | Why | Use instead |
|---|---|---|
| relay, WebSocket, blind relay | transport implementation detail | (usually: say nothing — the connection just works) or "connection" if it must be named |
| daemon, daemon process, `lancerd` | process-model detail | "Lancer on your machine" / just "your machine" |
| dispatch, dispatched | ops jargon | "send," "start," "run" |
| SSH (when avoidable), shell, PTY | protocol/terminal internals | "terminal," "live session," or omit |
| host (as a noun for the machine) | infra noun | "machine" |
| VPS, Tailscale, LAN, IP address | networking specifics | omit, or "your network" if it must be named |
| bridge, channel, socket | transport internals | omit |
| policy engine, blast radius (as raw jargon) | internal system names | "rules," "what this could affect" |

**Exception:** Settings → Advanced and any screen explicitly for technical users *can* use precise
terms (SSH key, relay URL) — that's where the technical user goes looking for them. The default
surfaces (Home, Inbox, onboarding, approval review) stay in the hidden-vocabulary list above.

**Confirmed copy bugs already in the app** (grepped from `AppRoot.swift`, not hypothetical):
- *"Relay is the recommended path. SSH adds a live terminal."* — both banned terms, no plain-language fallback.
- *"Relay bridge not available."`* — pure infra-speak as an error message a user will actually see.
- *"Pair a host to dispatch and supervise agents."* — "host" + "dispatch" in one clause.

## 3. Button and CTA labels — name the consequence

Pattern confirmed across Wise, Notion, and Replika's confirmation screens (Mobbin): **the primary
button is labeled with the specific outcome, never a generic verb.**

| Generic (avoid) | Consequence-labeled (use) |
|---|---|
| "Confirm" | "Close your balance" (Wise) |
| "Delete" | "Yes. Delete this page" (Notion) |
| "OK" | "Delete 2 facts" (Replika, names the count) |
| "Approve" | "Run `npm install`" / "Delete 3 files" / "Allow this command" |

Applies directly to `InboxApprovalDetail` and `InboxApprovalCard`: a high or critical approval's
primary button should name what it's actually approving when the label fits (`DSButton` already
takes a string param — this is a copy change, not a new component). Generic "Approve" is
acceptable for low-risk, routine actions; it should *not* be the label for anything gated as
high/critical.

**Don't put the verbatim command on the button.** Sanity-checked this against a real Inbox screen
(2026-07-01) — real commands are compound and long (`rm -rf ./dist && npm run build:prod`,
`DROP DATABASE production`), and the full command is already shown in mono right above the
buttons. Repeating it on a `fullWidth` button is redundant and risks ugly wrapping/truncation,
which hurts scannability more than plain "Approve" does. Use a **short classified label** instead
— reuse `classifyTool()` (already exists in `push-backend/main.go`, built for the same problem:
privacy-redacted APNs notification bodies use a tool category, not the raw command). e.g. "Approve
delete + rebuild," "Approve database change" — not the literal string.

## 4. Confirmation / destructive-action structure

Three parts, in order, every time:
1. **What** — plain-language statement of the action, in the title or first line.
2. **Why it matters** — the consequence, in one sentence, in the body. Wise: "Your account details
   will stop working when you close this balance." Not buried, not omitted.
3. **Buttons** — primary names the consequence (§3); secondary is always "Cancel," never a second
   consequence-labeled option (avoid two scary buttons).

Don't use horror-movie copy ("you will lose this forever and ever") — Lancer's tone is calm and
direct, not playful-dark. State the consequence plainly and let the seriousness come from clarity,
not adjectives.

## 5. AI / agent-output trust disclaimer

WhatsApp's AI threads open with an inline system bubble: *"Messages are generated by AI. Some may
be inaccurate or inappropriate. Learn more."* Lancer doesn't have an equivalent convention for
agent-authored content in chat threads. Worth adding once we redo the conversation screen — a
single quiet system-event row (`DSSystemEvent` already exists for this slot), not a banner that
eats vertical space every session.

## 6. Tone calibration by risk level

Copy tone should track the app's own risk tiers — this is also a safety signal, not just style:

- **Low risk / routine** (a normal command, a read-only action): plain, brief, can be warm. The
  onboarding carousel's tone ("your machines, in your pocket") is the right register here.
- **Medium risk** (needs evidence review before approving): plain and a little more explicit about
  what changed. No urgency language.
- **High / critical risk** (destructive, irreversible, or biometric-gated): flattest, most literal
  register in the app. No em-dashes, no cleverness, no exclamation points. State the action and the
  consequence. This is where Face ID friction is *reinforced* by copy friction, not undercut by a
  casual button label.

## 7. Mechanics

- **Sentence case** for headings and button labels, not Title Case. ("Connect a machine," not
  "Connect A Machine.")
- **Contractions are fine** ("you'll," "it's") outside high/critical-risk copy — they read as
  human, not sloppy. Avoid them in destructive-action copy (§6).
- **Numbers**: spell out under 10 in body copy, use digits in counts/labels ("3 files," "2 agents
  need you").
- **No exclamation points** outside first-run/empty-state encouragement. Never in an error or
  confirmation.
- Fix plain grammar bugs as you find them — e.g. **"Rules enforce on every machine"** (current
  onboarding copy) should be "Rules apply to every machine" — passive-voice typo, not a style choice.
- **Pick one verb per recurring state and use it everywhere.** Found "4 agents are waiting"
  (headline) next to "4 conversations blocked" (stat card) on the same screen — two registers for
  the identical fact. "Waiting" is calmer and matches the headline; "blocked" reads as an error.
  Once a state has a verb, that verb doesn't change screen to screen.

---

## Before / after (real strings, for calibration)

| Current | Rewritten | Why |
|---|---|---|
| "Relay is the recommended path. SSH adds a live terminal." | "Connecting your machine takes a few seconds. Want a live terminal too? You can add that next." | drops banned terms, states the user-facing choice plainly |
| "Relay bridge not available." | "Can't reach your machine right now. Check it's online and try again." | error copy a non-technical user can act on |
| "Pair a host to dispatch and supervise agents." | "Connect a machine to start sending it work." | drops "host"/"dispatch," keeps the same meaning |
| "Rules enforce on every machine." | "Rules apply to every machine." | grammar fix |
| "Approve" (on a `rm -rf` command, critical risk) | "Run `rm -rf build/`" | names the actual consequence per §3 |

---

## Open question for the next pass

Do we want a "Learn more" / glossary affordance anywhere technical terms are unavoidable (Settings
→ Advanced), or just trust that surface to a technical audience entirely? Decide when we get to
Settings in the workflow order.
