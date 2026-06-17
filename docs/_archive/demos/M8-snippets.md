# M8 — Snippets + Workflows

Status: in progress
Created: 2026-05-24

## Goal

Frequently-used commands and multi-step workflows are first-class citizens in Conduit.
Users can save, search, and insert snippets directly from the session composer,
and execute parameterized multi-step workflows with inline prompt resolution.

## Demo Script

1. Settings → Snippets → "+" → name: "tail logs", body: `journalctl -u myservice -f` → Save.
2. In session composer, tap the snippet palette button (chevron.up.square) → search "tail" → tap → body inserts into composer.
3. Send → renders as streaming Block.
4. Create workflow "deploy" with body:
   ```
   git push origin {{branch}}
   ssh prod "cd /app && git pull && systemctl restart myapp"
   ```
5. Invoke from palette → prompted for `{{branch}}` → enter "main" → both commands run in sequence.

## New Files

| File | Purpose |
|------|---------|
| `Sources/PersistenceKit/SnippetRepository.swift` | GRDB-backed CRUD + search for Snippet records |
| `Sources/SessionFeature/SnippetPaletteSheet.swift` | Searchable sheet to pick & insert a snippet into the composer |
| `Sources/AgentKit/WorkflowEngine.swift` | Runs multi-line snippets with `{{param}}` substitution |
| `Sources/SettingsFeature/SnippetEditorView.swift` | List + add/edit/delete UI for managing snippets |
| `Tests/ConduitKitTests/SnippetRepositoryTests.swift` | Unit tests for repository operations |
| `Tests/ConduitKitTests/WorkflowEngineTests.swift` | Unit tests for engine parsing and execution |
