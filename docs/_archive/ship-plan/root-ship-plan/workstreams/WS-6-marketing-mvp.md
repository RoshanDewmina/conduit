# WS-6 — Marketing site MVP (conduit.dev on Vercel)  (covers 17-pt #10)

> Independent track. Scoped to **ship-critical MVP only**: the Stripe redirect the app depends on + the privacy-policy URL App Review requires + a download/landing page. Polish is deferred (§6 of README).

## Context
The paid-v1 billing flow routes the app → `https://conduit.dev/subscribe` → Stripe Checkout (see WS-4). So the site is **not optional** for paid v1: without `/subscribe` the external subscription path is dead, and App Store submission **requires** a privacy-policy URL. Repo `/Users/roshansilva/Documents/command-center`. Create a new top-level `marketing/` directory (Next.js 14, App Router). Coordinates with WS-5 (the backend URL) and WS-4 (the checkout route).

## Tasks
1. **Scaffold** `marketing/` — Next.js 14 + TypeScript + Tailwind, App Router, no `src/`:
   ```bash
   cd marketing && npx create-next-app@latest . --typescript --tailwind --app --no-src-dir --import-alias "@/*"
   ```
2. **MVP pages (only these for ship):**
   - `app/page.tsx` — home: hero leading with the **Warp-style agent blocks** story, a few feature rows, CTA → `/download`.
   - `app/subscribe/page.tsx` — **server component** that POSTs to `${BACKEND_URL}/billing/checkout` with `{plan}` and `redirect()`s to the returned Stripe URL:
     ```tsx
     import { redirect } from 'next/navigation'
     export default async function SubscribePage({ searchParams }: { searchParams: { plan?: string } }) {
       const plan = searchParams.plan ?? 'monthly'
       const res = await fetch(`${process.env.BACKEND_URL}/billing/checkout`, {
         method: 'POST', headers: { 'Content-Type': 'application/json' },
         body: JSON.stringify({ plan }), cache: 'no-store',
       })
       const { url } = await res.json()
       redirect(url)
     }
     ```
   - `app/privacy/page.tsx` — the privacy policy (BYO-host/BYO-key, no account, secrets stay in Keychain on-device; align with the app's actual data story — cross-check with WS-8's privacy manifest).
   - `app/download/page.tsx` — TestFlight link + an App Store button placeholder.
   - `app/layout.tsx` — metadata + OG tags; `public/og.png` (1200×630) + `public/icon.png`.
3. **Deploy** — `vercel deploy --prod`; set `BACKEND_URL` (the Cloud Run URL from WS-5) as a **server-only** Vercel env var (NOT `NEXT_PUBLIC_`); add `conduit.dev` + `www.conduit.dev` custom domains (owner does DNS at the registrar).

## Constraints
- `BACKEND_URL` is server-only — never expose it to the client. · Keep it minimal; do not build the full feature/pricing marketing site this round.

## Acceptance
- `/subscribe?plan=monthly` redirects to a real Stripe Checkout URL (works once WS-4's checkout route + WS-5's backend are live; otherwise demonstrate against a local backend). · `/privacy` exists and matches the app's data story. · Home + download render. · `npm run build` succeeds. · Deployed to Vercel; domain steps listed for the owner.

## Report Template (fill in, return)
```
## WS-6 Report
### Pages built: home <y> subscribe <y> privacy <y> download <y>
### /subscribe redirect: <tested against which backend; result>
### BACKEND_URL: <server-only confirmed?>
### Build: <npm run build green?> · Deploy: <Vercel URL or "ready, owner to deploy">
### Domain/DNS: <owner steps listed>
### Privacy policy aligned with app data story: <y/n — cross-checked WS-8?>
### Files added: <tree> · Deviations/risks:
```
