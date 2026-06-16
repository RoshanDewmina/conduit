# Conduit UI/UX Designer Handoff - 2026-06-15

This folder is a self-contained handoff for designing every current board page and the proposed/future product surfaces represented on the board.

## What Is Included

- `PAGE_BRIEFS.md`: functional-only description for all 122 board views.
- `FEATURE_INVENTORY.md`: current, partial, future-needed, live-data, and reference-only design scope.
- `board-screenshots/`: every board artboard plus the full board image.
- `swift-screenshots/`: screenshots from the current built Swift app and debug galleries.
- `reference/swift-web-comparison.md`: original Swift/Web coverage matrix.
- `reference/*-source.md`: source docs used to ground current functionality and backend coverage.
- `data/page-briefs.json` and `data/page-briefs.csv`: structured version of the page briefs.
- `migration-board/`: JSX artboard source files and HTML viewer.

## Designer Instructions

Design all 122 board views. Treat `PAGE_BRIEFS.md` as the functional requirements. Do not treat the written descriptions as visual direction; they deliberately avoid style guidance. Screenshots are included only to show existing scope and product intent.

## Board Sections

The board now has 7 new sections beyond the original 51 views:

- Live Session & Transcript (SessionView, ChatTranscriptView, ToolCardView, ChatInputBar, KeyboardAccessoryRail)
- QR & SSH Pairing (QRScannerView, BridgePairingView, SSHConnectOverlay, WorkspacesView, HostEditorView, HostKeyConfirmSheet)
- Settings Sub-Pages (14 screens: TerminalSettings, E2ERelayPairing, TrustPrivacy, PremiumComparison, Billing, ProviderKeys, ShortcutBarEditor, SnippetEditor, SyncStatus, PolicyEditor, Secrets, Audit, Doctor, Keys)
- Agent & Cloud Features (13: AgentsView, AgentDetail, AgentRunDetail, AgentFiles, AgentWorkspace, AgentOrg, AgentExec, CreateAgent, AgentBilling, EditSchedule, LoopDetail, RunDetail, QuotaGuard)
- Git/Files/Preview (8: WorktreeBoard, RunShipSheet, ShipItSheet, FilesView/SFTP, FilePreview, DiffView, PreviewSurface, PreviewToolbar)
- Design System Component Gallery (25: all DSButtonGallery through HostHealthBadgeGallery)

## JSX Viewer

The JSX artboard files are served via index.html at:
`file:///Users/roshansilva/Documents/command-center/docs/audit/migration-board/index.html`

Run `python3 -m http.server 4179` from the `migration-board/` directory to view the rendered artboards.

## Counts

- Board views: 122
- Board screenshots: 51 (no new board shots taken — views are live JSX)
- Swift screenshots: 28 (no new Swift captures in this batch)
- JSX artboard components: ~212 artboards across 12 JSX files in migration-board/
- New JSX files created: cc-screens-4.jsx (Session/QR/SSH), cc-screens-5.jsx (14 settings), cc-screens-6.jsx (21 agent/cloud/git), cc-design-system.jsx (25 component galleries), cc-mount.jsx (board render)
- PAGE_BRIEFS.md entries: 122 views documented
- FEATURE_INVENTORY.md entries: expanded with new feature categories
- Covered production views: ~110
- Design system components documented: 25 gallery screens
- Missing from price handoff (still need real Swift screenshots): noted as future work