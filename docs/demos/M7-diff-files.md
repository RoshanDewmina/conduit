# M7 — Diff + Files Demo

## Prerequisites
- M1+M5 complete.
- Remote: `conduitd` running, agent configured with patch hook.
- iOS: Conduit app with M7 build.

## Steps

### 1. File browser via SFTP
Connect to host. In AppRoot, the Session tab's keyboard rail shows a Files button (or navigate to Files tab if implemented).

Connect to host → open Files tab → SFTP browser shows home directory.
Navigate into a project folder. Tap a `.md` file → TextPreview sheet opens with monospaced content.
Use pull-to-refresh to reload directory.

### 2. File preview
Tap a text file → preview shows content with text selection enabled.
Tap a binary file → "Binary file" placeholder shown.

### 3. Patch from agent
Run Claude Code on the remote: `claude "add a comment to main.go"`.
Claude proposes a patch → `agent.patch.proposed` event fires via conduitd.
iOS: DiffFeature sheet opens (if RecentPatch is wired) showing the unified diff.

## Pass criteria
- [ ] SFTP browser lists files with sizes formatted by ByteCountFormatter.
- [ ] Text files preview in a scrollable monospaced view.
- [ ] Binary files show placeholder instead of garbage.
- [ ] `patches` table exists in DB (PatchPersistenceTests passes).
- [ ] `swift test --filter PatchPersistence` passes.
