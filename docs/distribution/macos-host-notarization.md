# Lancer for Mac — Developer-ID notarization runbook

> Runnable checklist to sign, notarize, and direct-distribute `Lancer.app` (the macOS menu-bar
> host companion). Closes Phase C task 3 of `docs/plans/macos-host-implementation.md`. **Direct
> distribution only** — no Mac App Store, no App Sandbox (the app reads `~/.lancer/` and connects
> to the `lancerd` Unix socket). Sparkle decision at the bottom.

## Facts (verified from the repo, 2026-06-22)
- Target/scheme: **`LancerMac`** · bundle id **`dev.lancer.mac`** · team **`39HM2X8GS6`** · macOS 15.
- `ENABLE_HARDENED_RUNTIME: YES` already set (`project.yml`); **no App Sandbox** (no `.entitlements`
  with `com.apple.security.app-sandbox`) — correct for `~/.lancer` + Unix-socket access.
- A non-sandboxed Developer-ID app needs **no special `com.apple.security.*` entitlements** for
  Unix-socket or home-dir access. Only add entitlements if a future feature requires one.

## 0. Owner-gated prerequisite (one-time) — **BLOCKER if absent**
Direct distribution requires a **Developer ID Application** certificate. The Mac currently has only
an *Apple Development* cert (`security find-identity -v -p codesigning`), which **cannot** notarize.
- In Xcode → Settings → Accounts → Manage Certificates → **+ → Developer ID Application**
  (or Apple Developer portal). Requires the paid Apple Developer account for team `39HM2X8GS6`.
- Create an App-Store-Connect **API key** (or app-specific password) for `notarytool`; store it:
  ```sh
  xcrun notarytool store-credentials lancer-notary \
    --team-id 39HM2X8GS6 --key <AuthKey_XXX.p8> --key-id <KEY_ID> --issuer <ISSUER_UUID>
  ```
  (App-specific-password alternative: `--apple-id … --team-id … --password …`.)

Confirm the cert is present before continuing:
```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## 1. Build a Release, Developer-ID-signed app
```sh
xcodebuild -project Lancer.xcodeproj -scheme LancerMac -configuration Release \
  -derivedDataPath build/DerivedData-MacRelease \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=39HM2X8GS6 \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  clean build
APP=build/DerivedData-MacRelease/Build/Products/Release/Lancer.app
```
`--options runtime` = Hardened Runtime (also on via `ENABLE_HARDENED_RUNTIME`); `--timestamp` is
required for notarization.

## 2. Verify the signature before submitting
```sh
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'   # expect Developer ID + runtime flag
```

## 3. Zip → notarize → wait
```sh
ditto -c -k --keepParent "$APP" build/Lancer.zip
xcrun notarytool submit build/Lancer.zip --keychain-profile lancer-notary --wait
```
`--wait` blocks until Apple returns `Accepted`/`Invalid`. On `Invalid`:
```sh
xcrun notarytool log <submission-id> --keychain-profile lancer-notary
```

## 4. Staple the ticket to the .app (so it validates offline)
```sh
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
```

## 5. Gatekeeper assessment — the go/no-go gate
```sh
spctl -a -vv -t exec "$APP"     # expect: accepted, source=Notarized Developer ID
```
**Acceptance:** run this on a clean Mac with no prior trust for this developer — it must say
`accepted`. That is the Phase-C distribution acceptance criterion.

## 6. Package for download
Distribute the **stapled** app. A `.dmg` is friendliest:
```sh
hdiutil create -volname Lancer -srcfolder "$APP" -ov -format UDZO build/Lancer.dmg
codesign --timestamp --options runtime -s "Developer ID Application" build/Lancer.dmg
xcrun notarytool submit build/Lancer.dmg --keychain-profile lancer-notary --wait
xcrun stapler staple build/Lancer.dmg
```
(Notarize the `.dmg` too so the container itself passes Gatekeeper on download.)

## Updates — **No Sparkle (yet)**
Ship the **manual signed-update path** first: a new signed+notarized `.dmg`/`.zip` that the user
re-downloads and drags to /Applications, replacing the old app. The resident `lancerd` keeps
running across the swap (it's a separate LaunchAgent-managed process, not owned by `Lancer.app`),
and the authed/versioned IPC handshake already negotiates app↔daemon version skew.

Defer Sparkle until there's a real cadence of releases — and before adopting it, evaluate Sparkle's
auto-update helper against the SMAppService-managed LaunchAgent model (two updaters touching the
same install is the risk). Decision recorded in `docs/plans/macos-host-implementation.md` Phase C.

## Uninstall (for parity / support)
The bundled daemon now has a first-class teardown: `lancerd uninstall` removes the LaunchAgent
plist, the PATH shim wrappers, and the installed binary (leaves `~/.lancer` config + Keychain +
Claude hook intact, printing how to wipe those by hand). The Mac app's Management view should call
this via the host-control socket when offering "Remove Lancer".
