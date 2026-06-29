# 01 — Environment & Tooling

## Toolchain (as audited)

| Item | Value | Note |
|---|---|---|
| Local Xcode | **27.0** | `xcodebuild -version` |
| CI Xcode | **26.0 / 26.0.1** | `.github/workflows/ci.yml` — **drift, see BUILD-1** |
| Swift language version | **6.2** | `project.yml` (template claimed 6.4 — incorrect) |
| iOS deployment target | **26.0** | template claimed iOS 27 — incorrect; availability checks target 26 |
| Strict concurrency | `complete` | `project.yml` (`SWIFT_STRICT_CONCURRENCY`) |
| Project generation | XcodeGen → `Lancer.xcodeproj` | `xcodegen` on PATH |

> The audit template assumed Xcode 27 beta / Swift 6.4 / iOS 27. The repo actually targets Swift 6.2
> / iOS 26 and CI is still on Xcode 26. Findings were assessed against the **repo's real settings**.

## Targets / schemes
App `Lancer`, `LancerWidget`, `LancerLiveActivityWidget` (iOS 26); `LancerWatch`/`LancerWatchWidget`
(watchOS 11); `LancerMac` (macOS 15); `LancerUITests`. Schemes: `Lancer`, `LancerMac`.

## Claude Code tooling (security review)

| Tool | Purpose | Permissions | Concern | Use for audit? |
|---|---|---|---|---|
| XcodeBuildMCP | build/run/test/screenshot app target | local Xcode | none | ✅ used (authoritative build) |
| xcode MCP | live diagnostics, previews | local Xcode | none | available, not needed |
| apple-docs MCP | Apple API/HIG/WWDC docs | read-only network | none | available |
| context7 MCP | 3rd-party lib docs | read-only network | none | available |
| ios-simulator MCP | AX-tree inspection | sim | none | not used (UI skipped) |
| `guard-secret-commit.sh` hook | blocks secret commits | pre-commit | **positive control** | n/a |

- `.claude/settings.local.json` has an `allow` list; no `.env`/signing/secret directory was found
  exposed to tools. The repo also ships a secret-commit guard hook — good hygiene.
- No unfamiliar/unvetted MCP server, plugin, or hook was enabled during this audit.

## Recommended additions (smallest trustworthy set)
- **Align CI to Xcode 27** (BUILD-1) — highest-value, zero new dependency.
- **Periphery** — *optional*, only to confirm dead-code candidates (e.g. CQ-4) before deletion; do
  not adopt as a standing gate. Verify every candidate (extensions, App Intents, previews, macros).

## Rejected / not recommended
- **SwiftLint / swift-format (new adoption):** the build is warning-clean and the codebase is
  internally consistent; a formatter migration would mix noise into behavioural diffs. Not worth it.
- **MobSF full run / certificate pinning:** static + manual review already covered the trust
  boundaries; pinning is not justified for this threat model (see 04). No new tooling needed.
