# M8 Existing File Patches

These are changes that MUST be applied to existing files to complete the M8 integration.
They cannot be applied by the M8 agent because file ownership rules prohibit editing existing files.

---

## Sources/PersistenceKit/AppDatabase.swift

The `snippets` table **already exists** in the `v1` migration, so **no new migration is needed**
for the base columns (`id`, `name`, `body`, `hostTags`, `tags`, `createdAt`, `lastUsedAt`).

However, the `SnippetRepository.markUsed` method documents that a `useCount` column
is desirable in the future. When that column is added, register a new migration:

```swift
m.registerMigration("v2") { db in
    try db.alter(table: "snippets") { t in
        t.add(column: "useCount", .integer).notNull().defaults(to: 0)
    }
}
```

And update `SnippetRepository.markUsed` to also run:
```sql
UPDATE snippets SET lastUsedAt = ?, useCount = useCount + 1 WHERE id = ?
```

---

## Sources/SessionFeature/SessionView.swift

Add a snippet palette button to the composer row and wire up `SnippetPaletteSheet`.

**Add at the top of `SessionView`:**
```swift
@State private var showingSnippetPalette = false
@State private var availableSnippets: [Snippet] = []
```

**In the `composer` computed property, add a button before the send button:**
```swift
Button {
    showingSnippetPalette = true
} label: {
    Image(systemName: "chevron.up.square")
        .font(.title2)
}
```

**On the outermost `VStack` in `body`, add a sheet modifier alongside the existing `.sheet(item:)` for explain:**
```swift
.sheet(isPresented: $showingSnippetPalette) {
    SnippetPaletteSheet(
        snippets: availableSnippets,
        onInsert: { snippet in
            vm.inputText += snippet.body
            showingSnippetPalette = false
        },
        onDismiss: { showingSnippetPalette = false }
    )
}
```

**In the `.task` block (or as a separate `.task`), load snippets:**
```swift
.task {
    await vm.connect()
    // Load snippets for the palette
    if let snippets = try? await SnippetRepository(db: appDatabase).all() {
        availableSnippets = snippets
    }
}
```

**Import required at top of file:**
```swift
import PersistenceKit
```

---

## Sources/AppFeature/AppRoot.swift

In the Settings tab navigation, add a link to `SnippetEditorView`:

```swift
import SettingsFeature

// Inside the Settings NavigationStack / List:
NavigationLink("Snippets") {
    SnippetEditorView()
}
```

---

## Packages/ConduitKit/Package.swift

`SessionFeature` already lists `PersistenceKit` and `AgentKit` as dependencies — no change needed.

`SettingsFeature` already lists `PersistenceKit` as a dependency — no change needed.

The test target `ConduitKitTests` already includes `PersistenceKit` and `AgentKit` — no change needed.
