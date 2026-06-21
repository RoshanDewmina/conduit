# conduitd — Install and Pair

## One-liner (curl | sh)

```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh
```

`install.sh` is itself published as a release asset (alongside the binaries and
`SHA256SUMS`), so the one-liner above fetches the script straight from the
[latest release](https://storage.googleapis.com/conduit-dist-f1c2466d) — no
repo checkout required. It then downloads the matching `conduitd_<os>_<arch>`
binary for your OS/arch, verifies it against the release's `SHA256SUMS`,
installs it to `~/.conduit/bin/conduitd`, and optionally wires agent hooks.

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
   - `conduitd_darwin_amd64` (macOS Intel)
   - `conduitd_darwin_arm64` (macOS Apple Silicon)
   - `conduitd_linux_amd64` (Linux x86_64)
   - `conduitd_linux_arm64` (Linux ARM64)
   - `SHA256SUMS` (checksums for all four binaries)

2. Verify the checksum:

```bash
shasum -a 256 -c <(grep conduitd_darwin_arm64 SHA256SUMS)
# or manually: shasum -a 256 conduitd_darwin_arm64
# and compare the hash against the matching line in SHA256SUMS
```

3. Install and pair:

```bash
chmod +x conduitd_darwin_arm64
mkdir -p ~/.conduit/bin
mv conduitd_darwin_arm64 ~/.conduit/bin/conduitd
~/.conduit/bin/conduitd pair
```

4. (Optional) Install as a service:

```bash
~/.conduit/bin/conduitd install   # sets up launchd (macOS) or systemd (Linux)
```

## Next steps after install

1. Run `conduitd pair` to display a QR code
2. Open the Conduit app on your phone and scan the QR code
3. The daemon connects to the relay and awaits commands

## Self-host relay

If you want to run your own relay server instead of using Conduit's hosted relay:

See [daemon/push-backend/SELF_HOST.md](../daemon/push-backend/SELF_HOST.md) for
deployment instructions.

## Pairing without the phone app

To generate a pairing code for headless or offline setup:

```bash
conduitd pair --text   # prints the pairing code as text, no QR
```

Then use `conduitd relay-attach <pairing-code>` on the host to attach.