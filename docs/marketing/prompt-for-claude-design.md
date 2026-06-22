# Claude Design prompt — Lancer website

> Paste the block below into Claude Design (claude.ai/design). Attach this brief and, optionally, a reference screenshot of the "dot." template for motion/feel.
> Full rationale, copy, and research: `docs/marketing/website-design-brief.md`.
> **Run it on Claude Fable 5** (`claude-fable-5`) — select the model in Claude Design. Fable 5's stronger vision (dense screenshots / web UIs) and first-shot accuracy fit a fully-specified page; use **high** effort, or **xhigh** for the hero. Feed it this brief + a reference screenshot of the "dot." template. Then hand the result to Claude Code (also Fable 5) to build the React site in one instruction.

---

```
You are designing the marketing website for Lancer — conduit.dev.

PURPOSE
Design a 6-page marketing site that makes Lancer feel like a serious, trustworthy developer tool — not a generic AI app. The hero must communicate the product in five seconds and show the real app on a modern iPhone.

AMBITION / QUALITY BAR
Design this to Awwwards "Site of the Day" standard — the level of craft featured on awwwards.com: confident typography, orchestrated motion, impeccable spacing, memorable detail. But it must stay a serious, fast, accessible developer tool: restraint over spectacle. Never trade clarity, load speed, or the five-second message for decoration. "Award-grade" here means the most polished possible version of calm-editorial — not a maximalist agency showreel.

WHAT THE PRODUCT IS
Lancer is a phone-first approval, policy, and audit layer for AI coding agents (Claude Code, OpenAI Codex, opencode) that run on the developer's OWN machine. A small bridge (lancerd) on the host enforces the user's policy: safe actions auto-run, dangerous ones are blocked, and ambiguous ones pause and ping the phone with the exact command, the files it touches, and a risk read. The user approves, denies, edits-then-runs, or sets an allow-always rule — in one tap, even when the app is closed. Every decision is logged. The user's source code never leaves their host.

WHO IT IS FOR
Developers and small teams running MULTIPLE agents across their OWN machines, who won't give each vendor unrestricted repo access. NOT casual single-vendor users (first-party tools serve those for free). Speak engineer-to-engineer: precise, calm, specific. No hype.

AESTHETIC DIRECTION (follow exactly — reject generic AI aesthetics)
Calm-editorial, but serious devtool. This is a deliberate counter-position: every competitor site (Linear, Vercel, Warp) is dark and code-dense, so we go warm and light to stand out and to match the product's promise of control-without-anxiety.
- Background: warm paper #F4F2EC; pure-white cards; generous whitespace.
- Ink: warm near-black #16170F.
- Type: Instrument Serif for display/headlines; Inter for body/UI; a true monospace (Geist Mono) for ALL literal commands, file paths, code, and risk pills. The serif + mono pairing is intentional and premium — do not substitute system fonts.
- Accent: one confident deep evergreen #1E4D3D as primary. Semantic state colors, used functionally: approve/green #2E9E5B, ask/amber #C8841A, deny/red #C0392B (the Approve button is green, the Deny button is red — the site should teach the product's color language).
- Depth: subtle paper grain, soft layered card shadows, a faint blueprint/grid motif for "infrastructure." NO glassmorphism, NO neon, NO purple gradients, NO robot/sparkle icons, NO dark-by-default.

PAGES TO DESIGN (6)
1. Landing (/) — the priority. Above the fold: wordmark + nav (Product, Trust, Pricing, Docs, Get the app); H1 "Approve your agents. Keep your code."; one-sentence subhead; primary CTA "Join the TestFlight beta" + secondary "See how it works"; the live iPhone approval-card hero; a vendor row "Works with Claude Code · Codex · opencode." Then sections: the problem; the approval card; policy; activity/audit; cross-vendor; local-first/trust; minimal fleet; final CTA; FAQ.
2. Product (/product) — the four concepts: Agents, the Bridge (lancerd), Approvals, Policy; plus "go deep" (terminal/diff/files as depth).
3. Trust/Security (/trust) — precise privacy story: source + credentials never leave the host; relay carries only chosen approval metadata; E2EE of the relay and open-source bridge are PLANNED (label clearly); fail-closed default; deny holds even under --dangerously-skip-permissions; audit log. No certification claims.
4. Pricing (/pricing) — Free / Lancer Pro $14.99 one-time / Team & Self-host PLANNED. Honest, no contact-sales wall.
5. Docs / Getting started (/docs) — three steps: install the bridge, point the agent's hook, pair the phone. Show real commands in monospace. "Working in ~5 minutes."
6. Download (/download) — TestFlight beta now; App Store PLANNED; "No account. Your code stays on your machine."

COPY
Use the copy in docs/marketing/website-design-brief.md §4 (landing, product, trust, pricing, docs, download) and §5 (App Store) verbatim where possible. Headline lane is locked: "Approve your agents. Keep your code." Everything marked [PLANNED] must read as future tense — never imply it ships today.

HERO — THE LIVE MOMENT (replaces an old Nokia-phone-on-a-beach mockup)
A modern iPhone (clean device frame) showing the Lancer inbox approval card. A scripted micro-animation, looping:
1) a command types into the card in monospace (e.g. `rm -rf node_modules/`),
2) a risk pill appears (amber "ask"), blast-radius lines populate (files touched),
3) a tap lands on Allow → the card resolves to a green "✓ Approved" state → the next card slides up.
The on-screen app screenshot is a PLACEHOLDER labeled "[SCREENSHOT — owner-supplied]" (the owner is providing the real captures). The animated approval-card overlay itself should be a real, designed component so the live moment works before the screenshot is dropped in.

INTERACTIONS / ANIMATION
Orchestrated, scroll-triggered reveals (fade + slight rise) per section; the looping hero approval-card animation; a typed-command effect in monospace; subtle hover states on buttons (the evergreen primary, with a soft top glint). Tasteful and fast — motion must never slow the page, and must honor prefers-reduced-motion.
Animation stack: use GSAP for the signature page motion — ScrollTrigger for orchestrated scroll reveals and any pinned sections, SplitText for the editorial headline — with a Lenis smooth-scroll layer for the buttery feel. motion/react is fine for React component micro-interactions (the approval-card sequence, hovers). Do NOT make Three.js / WebGL the centerpiece — heavy 3D reads flashy and off-brand for a calm, serious tool; at most one subtle, optional WebGL/shader accent (e.g., animated paper grain), never required.

DESKTOP / MOBILE
Desktop: centered max-width ~1024–1152px content column, asymmetric hero (text left / device right or device-centered with text above), generous margins. Mobile: single column, device hero stacks under the headline, sticky compact nav, thumb-reachable CTAs. The site must look native on a 390×844 iPhone.

ASSETS TO USE / PRODUCE
- Produce a wordmark: lowercase "lancer" in Instrument Serif (a small monospace lockup variant for footers/technical contexts).
- Produce /og.png (1200×630) and /icon.png (512×512) — they're referenced but missing.
- Use PLACEHOLDER device screenshots throughout (owner supplies finals). Reference shots exist at docs/screenshots/governed-approvals/ for layout only — do not treat as final.

WHAT TO REPLACE / AVOID
- REPLACE the old phone mockup with the modern iPhone live approval card.
- REPLACE all "SSH terminal / run agents over SSH" copy — that positioning is retired. Terminal is a depth feature, never the headline.
- AVOID: hosted-cloud / "we run your agents" messaging; generic-AI visuals (purple gradients, system fonts, glassy cards, sparkle/robot icons); fake logos, stats, testimonials, or certifications; "Download on the App Store" buttons (use TestFlight); dark-by-default theme.

IMPLEMENTATION CONSTRAINTS (from the codebase)
- Deliverable is design-first; if implemented, target the existing site: Next.js 16 App Router + React 19 + Tailwind v4, with GSAP (ScrollTrigger, SplitText) + Lenis for signature motion and motion/react for component micro-interactions. The repo warns (marketing/AGENTS.md) that Next.js 16 has breaking changes — its docs must be read before coding.
- A "dot." Vite template (single App.tsx, Instrument Serif + Inter, motion/react, a video-background hero with a typing overlay) is the reference for motion + editorial feel ONLY — adapt its structure, not its content; replace its blue (#0871E7) with the evergreen accent and its retro Nokia font with Geist Mono.
- Keep site and app visually coherent; you may read the codebase/design tokens to align colors, type, and components.
- Run this design session on Claude Fable 5 (claude-fable-5): select it as the model. Its stronger vision (dense screenshots/web UIs) and first-shot accuracy fit a fully-specified page; use high effort, or xhigh for the hero. Then hand the design to Claude Code (also Fable 5) to implement the React site in one instruction.

SCOPE / DISCIPLINE
Design exactly the 6 pages and the sections specified — do not invent extra pages, modals, or features, and don't add abstractions beyond what's asked. Do the simplest thing that looks excellent. If a choice is ambiguous, pick the option that best serves the five-second message and move on.
```
