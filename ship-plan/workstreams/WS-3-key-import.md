# WS-3 — SSH key import & management  (covers 17-pt #6)

> Depends on WS-0. Owns the untracked `KeyImportView.swift` + `OpenSSHKeyParser.swift`. Security-critical → WS-8 reviews it after.

## Context
Conduit is an iOS SSH app; users must be able to bring their own keys. Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/ConduitKit && swift build`. Read `CLAUDE.md`, `docs/agent-contract.md`.

**Confirmed state:** the feature is **half-built and untracked** (substantial, not greenfield):
- `SecurityKit/OpenSSHKeyParser.swift` — **706 lines** (parser, incomplete).
- `KeysFeature/KeyImportView.swift` — **267 lines** (UI, incomplete).
Existing infra to integrate with: `SecurityKit/KeyStore.swift` (Keychain `whenUnlockedThisDeviceOnly`, non-synced; **import API exists at ~L34–38 with no UI**; note it has uncommitted WS-0 edits), `KeysFeature/KeysView.swift` (keys list; copy-public-key at ~L88–94), and the existing Ed25519 gen/store/load/delete/list. Missing per audit: import UI wiring, **passphrase support for encrypted keys**, per-host key selection.

## Tasks
1. **Finish `OpenSSHKeyParser`** — read what's there first (706 lines may already cover a lot). Parse **OpenSSH** (`-----BEGIN OPENSSH PRIVATE KEY-----`) and **PEM/PKCS#8**; support **Ed25519 + RSA**; reject unsupported types with a clear, secret-free error.
2. **Passphrase-protected keys** — detect encryption, prompt, decrypt (bcrypt-pbkdf + the OpenSSH cipher, typically aes256-ctr). If full decryption can't be done safely, gate it behind an explicit "encrypted keys not yet supported" path rather than half-doing it — but attempt it.
3. **Wire `KeyImportView`** into the Keys flow — **paste** and **file import** (`.fileImporter`); validate via the parser; store via `KeyStore` (Keychain). Inline errors. **Never echo key material back to the screen after import.**
4. **End-to-end** — an imported key lets the user connect. If possible, verify against localhost sshd (CLAUDE.md "Block terminal" prereqs). Consider per-host key selection if cheap; otherwise note it.
5. **Tests** — parser is the well-tested core: valid Ed25519, valid RSA, OpenSSH + PEM, passphrase-protected, malformed/truncated, wrong-type, empty.

## Security constraints (HARD — WS-8 will audit)
- Key material + passphrases: **never** logged, printed, in error strings, or written to disk in plaintext. Keychain/Enclave only.
- Validate before store; never store an unparseable blob. Don't leave decrypted bytes around longer than needed.
- Keep the TOFU host-key prompt intact in prod paths.

## Acceptance
- Parser: Ed25519+RSA, OpenSSH+PEM, passphrase (or explicit clean unsupported path). · Import UI: paste + file both work, store to Keychain, inline errors, no key echo.
- Can connect with an imported key (or a clear reason the env blocked it). · Parser tests cover valid/invalid/edge, all green. · Build + suite green; light+dark screenshots of the import UI.

## Report Template (fill in, return)
```
## WS-3 Report
### Parser coverage: Ed25519 <y/n> RSA <y/n> OpenSSH <y/n> PEM <y/n> passphrase <y/n/explicit-unsupported>
### Import UI: paste <works?> file-import <works?> error handling <how> key-echo <confirmed none?>
### Storage: <Keychain attrs; confirm not UserDefaults/files>
### E2E connect with imported key: <result or why skipped>
### Tests added: <list> · Build: <green/red> · Suite: <count>
### Security self-check: <grep for print/os_log near key/passphrase — clean?>
### Screenshots: <light+dark> · Files changed/added: <list> · Deviations/risks:
```
