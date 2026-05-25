# App Store Metadata — Conduit

## App Name
Conduit

## Subtitle (30 chars max)
SSH + AI Agent Control

## Category
Primary: Developer Tools
Secondary: Productivity

## Privacy Policy URL
https://conduit.dev/privacy

---

## Description (4000 chars max)

Conduit is a phone-native control plane for remote AI coding. Not just another SSH client — it is the missing mobile layer between you and the AI agents running on your servers.

**Supervise AI agents from anywhere**
When Claude Code or another AI agent wants to run a command on your server, Conduit delivers the request to your phone instantly. See exactly what it wants to do, the risk level, and the working directory. Tap Allow or Reject. No laptop required.

**Block-mode terminal**
Commands and their output appear as discrete, collapsible blocks — the way a modern terminal should work. Swipe to collapse. Long-press to copy, re-run, or ask AI to explain.

**Raw PTY for TUI apps**
vim, htop, tmux — anything that needs a real terminal is one tap away. Conduit switches automatically when it detects a TUI program and switches back when you exit.

**AI in the composer**
Type `#` before any message and Conduit translates natural language into a shell command. When a command fails, long-press the block and tap "Explain with AI" to get a clear, actionable explanation.

**Session survival**
tmux integration means your sessions stay alive when you walk away. Come back hours later, reconnect in seconds, and pick up exactly where you left off — even on a different network.

**Dev server preview**
Port-forward your running app through the SSH connection and browse it in the built-in browser, all without opening a laptop or punching holes in a firewall.

**SFTP file browser**
Browse, read, and inspect files on your remote server without leaving the app.

**Diff review**
Review unified diffs with syntax-highlighted additions and deletions. Coming: approve or reject individual hunks directly from your phone.

**Privacy by design**
Your SSH credentials and API keys never leave your device. All keys are stored in the iOS Keychain. AI requests go directly from your device to your AI provider — Conduit servers never see your prompts.

**Bring your own everything**
Your server. Your API keys. Your agents. Conduit is the control surface, not the cloud.

---

## Keywords (100 chars max — comma-separated)
SSH,terminal,AI,remote,developer,agent,Claude,server,control,PTY,SFTP,coding,automation

---

## What's New (first version)
First release. Connect to remote SSH servers, supervise AI agents, review diffs, and browse files — all from your phone.

---

## Support URL
https://conduit.dev/support

## Marketing URL
https://conduit.dev

---

## Screenshots — suggested content

### Screen 1: Workspaces list (hero)
- Show a populated list of hosts (My Dev Server, Staging, Fly.io Worker)
- Timestamp "2 minutes ago" on the first host
- Tab bar visible at bottom

### Screen 2: Session — block mode
- Show 3-4 completed command blocks
- One block with red failure bar and "Explain with AI" context menu visible
- Composer with "#" prefix showing "AI: translating…"

### Screen 3: Inbox — approval card
- Show an approval card with "HIGH RISK" badge
- Command: `rm -rf ./node_modules && npm ci`
- Allow / Reject buttons clearly visible
- Badge count "1" on tab icon

### Screen 4: Preview
- Dev server running (React or Next.js dev page visible in WKWebView)
- Port selector toolbar showing "localhost:3000"
- Viewport selector: iPhone / iPad / Desktop

### Screen 5: Diff view
- A unified diff with additions (green) and deletions (red)
- Multiple files shown
- NavigationBar title: "Diff"

---

## Age Rating Questionnaire answers
- Made For Kids: No
- Unrestricted Web Access: No
- Gambling: No
- Contests: No
- Violence: None
- Sexual Content: None

**Resulting rating: 4+**

---

## App Review Notes (include in submission)
Conduit is an SSH client and AI agent supervision tool for software developers.

To test the app:
1. Tap "Add your first host" on the Workspaces screen
2. Enter any SSH server's hostname, port, username (22, user@example.com)
3. The app will attempt to connect; for review purposes you can use a test server at:
   Host: review-test.conduit.dev | Port: 22 | Username: reviewer | Password: conduit2026

The Inbox tab shows pending AI agent approval requests (pre-seeded in DEBUG builds).
The Billing screen offers a one-time $14.99 purchase through StoreKit (use sandbox account).
