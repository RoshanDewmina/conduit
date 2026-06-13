# Archived ConduitKit views (dead / old-direction)

Archived **2026-06-12**. These Swift files were moved out of `Packages/ConduitKit/Sources/AppFeature/`
so they are **no longer compiled** into the app. They were all DEBUG-gallery-only — never reachable
from the shipping 4-tab app (Inbox / Fleet / Activity / Settings). They are kept here (not deleted) so
they can be restored or mined for reference.

Nothing here ships. The App Store release build never included these (`#if DEBUG` gallery routes), and
removing them does not change any shipping screen.

## What's here and why it was retired

| File | Contents | Why archived |
|---|---|---|
| `ManagementViews1.swift` | `HostDetailView`, `AgentPolicyView`, `AgentListView`, `VMListView`, `VMDetailView` | Old "SSH/VM management app" direction — superseded by the governed-approvals / loop control-plane direction. |
| `ManagementViews2-mgmt-screens.swift` | `WorkflowBuilderView`, `DiagnosticsView`, `CommandBarView` | Same old-management direction. (The live `KeysManagementView` + `SnippetsLibraryView` that shared the original file stayed in Sources as `LibrarySupportViews.swift`.) |
| `HostsView.swift` | `HostsView` | Only consumer of `HostDetailView`; not wired into AppRoot. |
| `ManagementMocks.swift` | `ManagementMocks`, `MockVM`, `MockAgent`, … | Mock data used only by the management screens above. |
| `LibraryMocks.swift` | `LibraryMocks` | Mock data used only by `WorkflowBuilderView`. |
| `CommandCenterGallery.swift` | `CCPolicyGalleryScreen`, `CCInboxGalleryScreen`, `CCUsageGalleryScreen` | Command-center prototype demos. `cc-usage` rendered an all-black/broken view. |
| `DispatchComposerView.swift` | `DispatchComposerView` | `cc-dispatch` prototype composer. |
| `PageReviewGallery.swift` | `PageReviewScreen`, `HostsReviewScreen`, `InboxReviewScreen`, `SettingsReviewScreen`, `SettingsAboutGalleryScreen`, `LibraryGalleryScreen`, `PersistentStatusBarGalleryScreen`, `AddHostGalleryScreen`, `MgmtGalleryHostDetail/Keys/Snippets` | Review-screen demos that duplicated the real tabs. |

## To restore one

1. Move the file back into `Packages/ConduitKit/Sources/AppFeature/`.
2. Re-add its `case "<route>": …` branch in `DebugGalleryView.swift`.
3. If it referenced `ManagementMocks` / `LibraryMocks`, restore those too.
4. `cd Packages/ConduitKit && swift build`.

Full history is in git — these were moved with `git mv`, so `git log --follow` works.
