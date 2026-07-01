# lancerd — Install and Pair

## One-liner (curl | sh)

```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh
```

`install.sh` is itself published as a release asset (alongside the binaries and
`SHA256SUMS`), so the one-liner above fetches the script straight from the
[latest release](https://storage.googleapis.com/conduit-dist-f1c2466d) — no
repo checkout required. It then downloads the matching `lancerd_<os>_<arch>`
binary for your OS/arch, verifies it against the release's `SHA256SUMS`,
installs it to `~/.lancer/bin/lancerd`, and optionally wires agent hooks.

### With Claude Code hooks

```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh -s -- --hooks claude
```

### From source (requires Go)

```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh -s -- --from-source
```

## Manual install

1. Download the binary for your platform and the `SHA256SUMS` file from the
   [latest release](https://storage.googleapis.com/conduit-dist-f1c2466d)
   (every release publishes four binaries + `SHA256SUMS` + `install.sh`):
   - `lancerd_darwin_amd64` (macOS Intel)
   - `lancerd_darwin_arm64` (macOS Apple Silicon)
   - `lancerd_linux_amd64` (Linux x86_64)
   - `lancerd_linux_arm64` (Linux ARM64)
   - `SHA256SUMS` (checksums for all four binaries)

2. Verify the checksum:

```bash
shasum -a 256 -c <(grep lancerd_darwin_arm64 SHA256SUMS)
# or manually: shasum -a 256 lancerd_darwin_arm64
# and compare the hash against the matching line in SHA256SUMS
```

3. Install and pair:

```bash
chmod +x lancerd_darwin_arm64
mkdir -p ~/.lancer/bin
mv lancerd_darwin_arm64 ~/.lancer/bin/lancerd
~/.lancer/bin/lancerd pair
```

4. (Optional) Install as a service:

```bash
~/.lancer/bin/lancerd install   # sets up launchd (macOS) or systemd (Linux)
```

### `APPROVAL_RELAY_SECRET` — required for approval push notifications

`lancerd install` on macOS writes a launchd job (`~/Library/LaunchAgents/dev.lancer.lancerd.plist`).
launchd jobs do **not** inherit the shell environment that ran the installer, so if
`APPROVAL_RELAY_SECRET` isn't exported *before* you run `lancerd install`, the persistent daemon
will start with no way to authenticate to push-backend's `/approval` endpoint — approval push
notifications will silently never reach your phone (visible only as `HTTP 401` in
`~/.lancer/lancerd.stderr.log`).

```bash
export APPROVAL_RELAY_SECRET=<value>
~/.lancer/bin/lancerd install
```

If you forget, `lancerd install` prints a warning to stderr explaining the gap and how to fix it
(re-run with the var exported, or hand-edit the generated plist's `EnvironmentVariables` dict and
`launchctl unload`/`load`).

See `daemon/push-backend/SELF_HOST.md` and `daemon/push-backend/DEPLOY.md` for how the operator of
a push-backend instance provisions/rotates this shared secret in the first place.

## Next steps after install

1. Run `lancerd pair` to display a QR code
2. Open the Lancer app on your phone and scan the QR code
3. The daemon connects to the relay and awaits commands

## Self-host relay

If you want to run your own relay server instead of using Lancer's hosted relay:

See [daemon/push-backend/SELF_HOST.md](../daemon/push-backend/SELF_HOST.md) for
deployment instructions.

## Pairing without the phone app

To generate a pairing code for headless or offline setup:

```bash
lancerd pair --text   # prints the pairing code as text, no QR
```

Then use `lancerd relay-attach <pairing-code>` on the host to attach.