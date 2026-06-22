# Lancer IA Board Map

Use this reference for Lancer interactive board and IA prototype work.

## Board Paths

Two boards are easy to confuse:

- Repo migration board source: `/Users/roshansilva/Documents/command-center/docs/audit/migration-board/index.html`
- Exported interactive board Roshan usually views: `/Users/roshansilva/Downloads/Lancer GitHub repo/Lancer Board.dc.html`

When the user says the new designs are not shown, treat it as a rendered-board debugging task. Static source changes are not enough.

## Active IA

Root destinations:

- Inbox
- Fleet
- Control
- Settings

Fold Activity/history into:

- Recent Threads
- Needs Attention
- per-thread or per-run audit/history details

## Verification

After edits:

1. Serve or open the exact board file the user will view.
2. Inspect live DOM after hydration for the new visible labels.
3. Screenshot desktop and mobile widths when layout changed.
4. Confirm the requested design appears near the top if the user asked to see it first.
5. Confirm interactive controls respond if the request included "interactive."

## UX Rules For This Board

- Preserve the existing visual language unless the user asks for a redesign.
- Prefer plain-English labels.
- Keep tester flows directly mapped to visible tabs.
- Avoid reintroducing a root Activity tab.
- Do not bury the main prototype below audit/reference sections.

