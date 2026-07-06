#if os(iOS)
import SwiftUI

/// Which visual look a Cursor-style screen renders in. Screens force one
/// specific look on purpose (e.g. Work Thread is always dark, Home is always
/// light) regardless of the device's system appearance — this is deliberately
/// separate from SwiftUI's `\.colorScheme`, which follows system dark mode.
public enum CursorScheme: Sendable {
    case light
    case dark
}

private struct CursorSchemeKey: EnvironmentKey {
    static let defaultValue: CursorScheme = .light
}

extension EnvironmentValues {
    public var cursorScheme: CursorScheme {
        get { self[CursorSchemeKey.self] }
        set { self[CursorSchemeKey.self] = newValue }
    }
}
#endif
