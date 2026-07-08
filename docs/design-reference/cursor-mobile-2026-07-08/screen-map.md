# A3 rebuild — screenshot → surface map (2026-07-08)

Reference folder: /Users/roshansilva/Downloads/Cursor Mobile App
IMG_2408–2422 = real Cursor iOS app (light theme) — the design source of truth.
Screenshot 11.58/12.05/12.07 = Lancer current state from D0.2 device run (evidence, incl. Review binding regression).

| # | Image(s) | Surface | Key elements |
|---|---|---|---|
| 1 | 2408 | Workspaces root | Profile avatar top-left; circular search + "+" buttons top-right; large "Workspaces" title; rows: All Repos / repo folders / Add Repo with chevrons + hairline separators; floating pill composer bottom ("Plan, ask, build…" + "+" + mic) |
| 2 | 2409 | Workspace thread list | Back chevron, search + filter buttons; repo name as large title; sections "Yesterday" / "This Week"; rows: status dot, thread title, status subtitle (✓ Checks Passed · +461 -0 / ⑂ Merged / No Changes / diff stats); same floating composer |
| 3 | 2410, 2412 | Work thread detail | Centered nav title w/ back + "…"; user message in gray bubble; "Worked 26s" caption; rich markdown answer (tables, bold); "Changes N" card w/ per-file rows + green/red diff counts; pill buttons "View PR +461 -0" and "Squash & Merge"; "Follow up…" floating composer; scroll-to-bottom chevron |
| 4 | 2411 | PR detail | Title + PR number in gray; Open badge (green tint), +461 -0 · 1 File · 2 Commits; "Ready to Merge" card: green check circle "All Checks Passed" + full-width green "Squash & Merge" button; file list rows with diff counts; link + "…" top-right |
| 5 | 2413, 2415 | New-chat composer sheet | Bottom sheet over dimmed root; grabber; "conduit master ⌄" repo/branch selector + cloud toggle ⌄; "Plan, ask, build…" placeholder; bottom row: "+" context button, model picker "Composer 2.5 ⌄", mic circle |
| 6 | 2414 | Add Repo sheet | Full sheet: X close, centered title, rounded search field "Repo…", "Workspaces" section, org/repo rows (org gray, name bold) |
| 7 | 2416 | Repo picker sheet | X + "Repo" title + search; sections Active (repo + branch selector on right), Recents, More |
| 8 | 2417 | Search sheet | X + "Search" title; search field "Agents, repos…" + clear; scope chips (All / conduit / personal-web — selected = filled); result rows like thread list w/ repo name suffix |
| 9 | 2418–2420 | Profile sheet | Grabber + X + "Profile"; big gradient avatar; email + plan tier; "Tokens" stat w/ large number + monthly bar chart (orange bars, right axis, J–D); "Local Agents"/"Cloud Agents" two-up stats + chart; "Current Streak"/"Longest" + year dot-grid (orange intensity); sections: Plan (Manage Plan), Support (Help↗, Contact Sales↗, Acknowledgements>), More (Sign out), Danger Zone (Delete Account, red); version footer "CURSOR V1.2.0 (38381)" |
| 10 | 2421, 2422 | Context sheet | X + "Context"; horizontal carousel of recent screenshots thumbnails; "Mode" list: Plan, Draft (icons); "Add" list: Photos, Screenshots>, Camera, Files, MCP Servers (count + chevron) |

Lancer current-state evidence (do NOT copy — fix):
- 11.58.53: Workspaces root w/ "Reconnecting…" amber banner — Lancer already close to #1 but check row metadata (thread counts, host subtitle).
- 12.05.34: Review screen "No pending approval" + empty Scope while footer says "Approved · Decided by You" — the CursorReviewDiffView Approval-binding regression (AppRoot.swift ~line 212 comment).
- 12.07.50: Review populated (Scope agent/kind/directory/command, Risk tier w/ colored dot, Evidence mono block + content hash, Decision Approved, "Decided by You · just now") — this is the good state to preserve.

Design language: light theme, near-white bg, dark text, hairline separators, rounded cards, circular icon buttons, pill CTAs, green for merge/pass, orange accent for charts/streaks.

OWNER DECISION (2026-07-08): pixel-close to Cursor, support BOTH light and dark. Dark reference set: /Users/roshansilva/Downloads/Cursor Mobile App/Dark/ (IMG_2423–2431).

Dark-theme tokens (from IMG_2423–2431): pure/near-black background (#0A–#0D), same layout/geometry as light; elevated surfaces (sheets, cards, composer pill, icon buttons) in dark gray (#1C–#26); primary text near-white, secondary ~40% gray; same hairline separators at low alpha; green diff/pass and red deletion colors unchanged; "Merged" badge = desaturated purple/indigo pill on dark; user chat bubble = dark gray; syntax-highlighted code on very dark green-tinted bg.

Additional surfaces only visible in dark set:
| 11 | 2428 | Commits sheet | grabber + X + "Commits" title with "2 Commits → main" subtitle; timeline dots + connector; commit title, author row (avatar + "Cursor Agent" + green/red diff counts), relative time right-aligned |
| 12 | 2425 | Code diff / file viewer | file header row (chevron, filename, ext badge, diff counts) pinned; line-numbered gutter; syntax-highlighted source; green added-line gutter markers |
| 13 | 2429, 2431 | Context menus + toast | PR "…" menu: Open in GitHub ↗, Close PR (red); thread "…" menu: Pin, Rename, Mark as Unread, Archive, then Copy ID, Share; iOS-style blurred menu cards; "Copied Link" pill toast top-center |
