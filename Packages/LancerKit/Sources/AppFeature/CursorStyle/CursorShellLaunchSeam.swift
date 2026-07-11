import Foundation

/// DEBUG launch-env rules for the Cursor shell.
///
/// `LANCER_CURSOR_SHELL=1` alone → mock shell (UITests / design review).
/// `LANCER_CURSOR_SHELL_LIVE=1` → live bridge (real pairing / Settings).
/// When both are set, LIVE wins — a dual launch previously shipped the mock
/// Trusted machines list (Mac Mini Studio / Home Server) with Remove and
/// Clear-all hidden, which looked like a missing product feature (2026-07-09).
public enum CursorShellLaunchSeam {
    /// Whether `AppRoot` should present the mock `CursorAppShell()` (no live bridge).
    public static func usesMockCursorShell(
        cursorShell: String?,
        cursorShellLive: String?
    ) -> Bool {
        if cursorShellLive == "1" { return false }
        return cursorShell == "1"
    }

    /// Convenience over `ProcessInfo` environment.
    public static func usesMockCursorShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        usesMockCursorShell(
            cursorShell: environment["LANCER_CURSOR_SHELL"],
            cursorShellLive: environment["LANCER_CURSOR_SHELL_LIVE"]
        )
    }
}
