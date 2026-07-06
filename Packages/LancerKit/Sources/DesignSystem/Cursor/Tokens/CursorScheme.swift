#if os(iOS)
import SwiftUI

/// Which visual look a Cursor-style screen renders in. Follows the app's
/// `LancerAppearance` setting via `AppRoot`'s `cursorResolvedScheme` env
/// injection; individual screens may still override when product requires it.
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
