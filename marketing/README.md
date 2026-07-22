# Lancer marketing site (static)

Minimal static assets for public-facing pages — separate from the `web/` fleet/inbox app.

## Pages

| Path | Purpose |
|------|---------|
| `index.html` | Pricing — Free / Founder's Edition / subscription later |

## Local preview

```bash
cd marketing
python3 -m http.server 8080
# open http://localhost:8080
```

Or with any static file server:

```bash
npx --yes serve marketing -p 8080
```

## Deploy (later)

Host the `marketing/` directory on any static host (Vercel, Netlify, Cloudflare Pages, S3+CloudFront, GitHub Pages). Point the App Store Connect **Marketing URL** at the deployed pricing page when ready.

No build step required — plain HTML/CSS.
