# Standard accounts and daemon device binding

Lancer V1 supports two deliberate modes:

- **Lancer account:** Supabase email/password auth with confirmed email, recovery links that return to `lancer://auth/callback`, authenticated billing identity, and registered daemons.
- **Self-hosted offline:** the existing account-free E2E relay pairing. It does not contact Supabase and intentionally has no recovery, device list, or hosted billing.

## Configuration

Set the iOS build settings, separately for each configuration, rather than committing values:

```text
LANCER_SUPABASE_URL=https://<project-ref>.supabase.co
LANCER_SUPABASE_PUBLISHABLE_KEY=<publishable-or-anon-key>
```

The app reads these as `LANCER_SUPABASE_URL` and `LANCER_SUPABASE_PUBLISHABLE_KEY` from `Info.plist`. They are client configuration, not service-role credentials. Empty values keep account sign-in unavailable while offline pairing remains available.

On `push-backend`, configure only server-side values:

```text
SUPABASE_JWT_SECRET=<Supabase Auth JWT secret>
SUPABASE_JWT_ISSUER=https://<project-ref>.supabase.co/auth/v1   # recommended
```

Use the production Supabase SMTP configuration before enabling sign-up. Do not ship the default development mailer or any service-role key in the app.

Apply [`supabase/migrations/202606200001_account_devices.sql`](../supabase/migrations/202606200001_account_devices.sql) with the Supabase migration runner. It creates `profiles`, `daemon_devices`, and private pairing challenges with RLS and ownership indexes.

## Daemon bind contract

1. `lancerd pair` creates a short-lived QR challenge containing a random one-time secret and daemon public-key fingerprint.
2. A signed-in phone approves the challenge through `POST /v1/devices/bind` with its Supabase JWT.
3. The daemon calls `POST /v1/devices/redeem` using only the challenge ID and secret; it receives an opaque device credential once.
4. The backend stores hashes, never the account password or raw device credential. The owner can revoke through `POST /v1/devices/{id}/revoke`.

The backend endpoints have deterministic coverage. A real device QR scan and a production Supabase deployment remain owner-gated until the project URL, SMTP, and deployment secrets are provisioned.
