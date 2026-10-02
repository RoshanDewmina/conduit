# Lancer

Lancer is a native iOS app plus a small Go daemon (`lancerd`) for supervising AI coding agents
(Claude Code, Codex, OpenCode, Kimi and others) that run on your own Mac or Linux box. The agent
keeps running on the machine where the repo and toolchain live. The phone starts runs, follows them,
and answers permission prompts. When an agent wants to do something risky, `lancerd` checks it
against a local policy. If the policy says to ask, your phone gets a push notification and you can
approve or deny from the lock screen, even when the app has been force-quit. Every decision goes
into a hash-chained audit log on the host. Phone and daemon talk through a relay that only ever
sees ciphertext.

> The repo is named `conduit` because that was the project's first name. The product was renamed to
> Lancer in June 2026, and some infrastructure names (for example the `conduit-push` Fly app) still
> use the old name.

## Demo

<!-- TODO: 90-second screen recording / GIF: pair phone → dispatch an agent → lock-screen approval → audit entry -->
_A 90-second demo video is coming._

Builds have been uploaded to TestFlight for the author's own device testing. There is no public
TestFlight link.

## Architecture

```
 iPhone app (SwiftUI)                 Relay (Go, Fly.io)                 Your machine
 ┌──────────────────────┐   wss    ┌──────────────────────┐   wss    ┌──────────────────────────┐
 │ Workspaces / chat     │◀───────▶│ pairing rendezvous    │◀───────▶│ lancerd (Go, resident)    │
 │ Approvals + Live Act. │  E2E     │ forwards ciphertext   │  E2E     │  policy engine            │
 │ Siri / Watch / widgets│ frames   │ APNs + Live Activity  │ frames   │  hash-chained audit log   │
 └──────────▲───────────┘          │ push sender           │          │  agent dispatch + hooks   │
            │ APNs                  └──────────────────────┘          └────────────┬─────────────┘
            └──────────── push (redacted summary only) ◀────────────               │ hooks / argv
                                                                       Claude Code · Codex · OpenCode · Kimi
```

- **End-to-end encrypted relay.** Phone and daemon each generate an X25519 key pair at pairing time.
  They derive a session key with HKDF-SHA256 and seal every frame with ChaCha20-Poly1305 under a
  fixed AAD. The relay just forwards the frames. The Go code is in `daemon/lancerd/e2e_crypto.go`
  and the matching Swift code is in `Packages/LancerKit/Sources/SecurityKit/PairingCrypto.swift`. A
  per-generation sequence guard rejects replayed frames (see the bugs section below).
- **Policy engine** (`daemon/lancerd/policy/`). Each tool call an agent wants to make is classified
  and scored for risk, then resolved to `allow`, `deny` or `ask`. If several rules match, deny beats
  ask and ask beats allow. If nothing matches, the policy default applies, and that is
  `ask` unless configured otherwise.
  "Allow always" decisions are saved per host.
- **Hash-chained audit log** (`daemon/lancerd/audit.go`). Each entry stores the SHA-256 of the entry
  before it, and a verifier recomputes each hash and walks the chain to detect edited entries.
  Commands go through secret redaction before they're written.
- **Push.** The Go `push-backend` (`daemon/push-backend/`, deployed to Fly.io via `fly.toml`) hosts
  the relay and sends APNs alerts plus ActivityKit push updates. That lets the lock-screen Live
  Activity and Dynamic Island update while the app is closed. Alert bodies carry only a redacted
  summary. The full command is fetched in the app after unlock.
- **Accounts are optional.** Offline pairing (a short code from `lancerd pair`) needs no account.
  Supabase is used only for the optional email/password "standard account" and device binding.

There is more detail in [`ARCHITECTURE.md`](./ARCHITECTURE.md). Its §0.1 section is the current-state
snapshot.

## Key engineering decisions

- **The daemon holds the state and the phone attaches to it.** `lancerd` owns sessions, approvals
  and the conversation ledger (SQLite). The phone just reconnects, so agents keep running through
  dropped connections and app kills without any session-migration logic.
- **A relay that can't read traffic, instead of phone-to-host SSH.** Users don't have to open
  ports, and the hosted piece never sees plaintext. SSH transport still exists in code but is
  secondary.
- **Fail closed everywhere.** No matching rule means `ask`. A corrupt rule expiry means fail closed.
  A hook timeout means deny. A decision that can't be delivered is queued and retried, never assumed.
- **Hook into each vendor's own extension point.** Agents are gated through each CLI's native hooks
  or plugins. One example is OpenCode's `tool.execute.before` plugin, which replaced an earlier
  approach that OpenCode silently ignored.
- **Swift engine packages never import UIKit or SwiftUI.** They are SwiftPM libraries testable on
  the macOS CLI. Feature modules may import engines but never each other.

## Notable bugs fixed

**Relay went deaf after reconnect (replay-sequencer poisoning).** After a reconnect the app would
sometimes get stuck on "Working…" forever. Five earlier fixes had not solved it. The root cause was
that the session key comes only from the static pairing keys, so a stale frame from the *previous*
connection still decrypted. Its high sequence number got accepted right after the counter reset.
That "poisoned" the counter, and every legitimate new frame (starting at seq 0) was then rejected
as out of order. The fix tags every frame with a random generation ID, minted whenever the sender
resets its counter. The receiver rejects frames from retired generations without touching its
state. A follow-up closed a downgrade hole where an *untagged* frame could knock out the active
generation. The fix is implemented the same way in Go and Swift, and both sides have regression
tests that replay the exact failing sequence. Commits: `eeb562fa`, `aef83354`.

**Lock-screen approval lost when the app had been force-quit.** Tapping Approve on a lock-screen
notification after a force-quit looked fine on the phone, but the decision never reached the host.
iOS relaunches the app *in the background without connecting a SwiftUI scene*, and the delivery
code only ran inside the root view's `.onReceive` handler and startup task. Those never ran, so the
decision sat in an in-memory buffer and died with the process. The fix delivers the decision
directly from the notification delegate. It uses the same Keychain-hydrated, cold-launch-safe relay
path the Live Activity intent uses, wrapped in a background task. Duplicate delivery is harmless
because the database write is first-decision-wins. A physical-device retest passed for both
Approve and Reject. Write-up:
[`docs/test-runs/2026-07-08-5c-root-cause.md`](docs/test-runs/2026-07-08-5c-root-cause.md).

## Tech stack

- **iOS / watchOS / macOS:** Swift 6 (strict concurrency), SwiftUI, ActivityKit (Live Activities),
  App Intents (Siri), WidgetKit, CloudKit, StoreKit, CryptoKit, GRDB (SQLite), SwiftTerm, Citadel /
  SwiftNIO SSH. XcodeGen generates the project from `project.yml`, and fastlane handles release
  metadata.
- **Daemon and backend:** Go (`golang.org/x/crypto` for curve25519, hkdf and chacha20poly1305),
  WebSockets, APNs, Docker, Fly.io.
- **Optional services:** Supabase (accounts) and Stripe (billing code, test mode only).
- **CI:** GitHub Actions runs the SwiftPM build and tests, the iOS simulator app build, and Go
  build, test and vet.
- **Tests:** about 1,100 Swift `@Test` cases and about 770 Go test functions.

## Build and run

Requirements: Xcode 27 (beta) and the iOS 27 SDK, Swift 6.4 tools, Go 1.25+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# iOS app
xcodegen generate
open Lancer.xcodeproj            # scheme "Lancer", run on an iOS 27 simulator or device

# Swift packages (engines + features), testable without a simulator
cd Packages/LancerKit && swift build && swift test

# Daemon
cd daemon/lancerd && go build -o lancerd . && go test ./...
./lancerd pair                   # prints a pairing code to enter in the app
./lancerd install                # optional: run as a launchd/systemd service

# Relay / push backend (self-host)
cd daemon/push-backend && go test ./...   # see SELF_HOST.md and DEPLOY.md
```

To send push notifications you need your own APNs key and bundle ID. See
`daemon/push-backend/.env.example`.

## Repository layout

```
Lancer/, LancerWidgets/, LancerWatch/, LancerMac/   app targets (thin shells)
Packages/LancerKit/      all Swift code: engine packages (LancerCore, SecurityKit,
                         SSHTransport, PersistenceKit, …) and *Feature UI modules
daemon/lancerd/          resident daemon: policy, audit, dispatch, relay client
daemon/push-backend/     relay + APNs/Live Activity sender (+ deferred hosted-run code)
docs/                    architecture notes, runbooks, device test-run evidence
project.yml              XcodeGen project definition
```

## Status and limitations

- **This is a personal project, in single-user dogfooding.** I'm the only person who has used it,
  on my own machines. It has **no external users** and is not on the App Store.
- The core loop has been demonstrated on a physical iPhone: pair, dispatch, gated tool call,
  lock-screen push, approve or deny, then the agent resumes and the decision is audited. Some paths
  are still proven only in the simulator, or not re-proven since later changes. The relay
  reconnect fix, for example, has not yet been re-verified on a physical device.
  [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) tracks the open gaps.
- Emergency Stop is orchestrated by the client. It is not yet an atomic primitive on the daemon
  side.
- The hosted-cloud execution code in `push-backend` and `agent-runner` (Stripe credits, Fly/GCP
  runs) compiles but is deferred. It isn't wired into the app.
- Vendor CLI flags change often, so per-vendor dispatch argv needs re-checking as the CLIs update.

## How it was built

I (Roshan Silva) designed and directed the project. Much of the code was written by AI coding
agents working under my direction, review and on-device verification.
