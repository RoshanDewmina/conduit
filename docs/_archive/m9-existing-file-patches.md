# M9 Existing File Patches

## Sources/SessionFeature/SessionView.swift

### 1. Make the session view focusable for hardware keyboard events

Add `.focusable()` to the outermost view in `SessionView.body` so UIKit
delivers `UIKey` events to the responder chain:

```swift
// Inside SessionView.body (or the terminal scroll view wrapper)
.focusable()
```

### 2. Route raw key events through HardwareInputHandler

Wrap the terminal view in a `UIViewControllerRepresentable` (or use the
`.onKeyPress` modifier available on iOS 17+). In raw mode, every key event
should be converted to PTY bytes and written to the active shell:

```swift
// iOS 17+ approach — attach to the focusable terminal view
.onKeyPress(phases: .down) { press in
    guard vm.isRaw else { return .ignored }
    #if os(iOS)
    if let bytes = HardwareInputHandler.bytes(for: press.key) {
        vm.activeShell?.send(Data(bytes))
        return .handled
    }
    #endif
    return .ignored
}
```

For iOS 16 compatibility, install `UIKeyCommand` objects via a
`UIViewControllerRepresentable` that overrides `keyCommands` and calls
`vm.activeShell?.send(Data(bytes))` in the action handler.

### 3. Wire Cmd- shortcuts from ShellKeyCommand.all

For app-level actions (bytes == []) such as Cmd-T and Cmd-F, dispatch to the
appropriate navigation or search handler rather than the PTY.

---

## Sources/AppFeature/AppRoot.swift

### Replace rootTabs with AdaptiveRoot on iPad

Import `AppFeature` already owns `AdaptiveRoot`, so no new imports are needed.

Inside `readyRoot(env:)`, wrap `rootTabs(env:)` with `AdaptiveRoot` so that on
iPad (regular size class) the app renders a NavigationSplitView:

```swift
@ViewBuilder
private func readyRoot(env: AppEnvironment) -> some View {
    Group {
        if onboardingSeen {
            AdaptiveRoot {
                // Sidebar — the full tab bar on compact, or left column on iPad
                rootTabs(env: env)
            } detail: {
                // Detail column — shown only on iPad regular size class
                NavigationStack {
                    if let vm = sessionViewModel {
                        SessionView(viewModel: vm)
                    } else {
                        ContentUnavailableView(
                            "No active session",
                            systemImage: "terminal",
                            description: Text("Pick a host from Workspaces to begin.")
                        )
                    }
                }
            }
        } else {
            OnboardingView { ... }
        }
    }
    // ... existing sheet / alert modifiers unchanged
}
```

On compact size class `AdaptiveRoot` passes through `rootTabs(env:)` unchanged,
so iPhone behaviour is unaffected.

---

## Packages/LancerKit/Package.swift

Ensure `SessionFeature` lists `DesignSystem` as a dependency if any
`DesignSystem` components (e.g. `KeyboardAccessoryRail`) are used inside new
views added in M9:

```swift
.target(
    name: "SessionFeature",
    dependencies: [
        "LancerCore",
        "SSHTransport",
        "TerminalEngine",
        "DesignSystem",   // ← add if not already present
        "PersistenceKit",
        "AgentKit",
        "NotificationsKit",
    ]
),
```
