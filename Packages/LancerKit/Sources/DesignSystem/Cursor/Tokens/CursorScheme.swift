#if os(iOS)
import SwiftUI

/// Which visual look a Cursor-style screen renders in. Follows the app's
/// `LancerAppearance` setting via `cursorTheme()` or `AppRoot`'s env injection.
public enum CursorScheme: Sendable {
    case light
    case dark

    /// Resolve from an explicit `LancerAppearance` plus the live system scheme
    /// (used when appearance is `.system`).
    public static func resolve(_ appearance: LancerAppearance, systemScheme: ColorScheme) -> CursorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme == .dark ? .dark : .light
        }
    }

    public static func resolve(_ colorScheme: ColorScheme) -> CursorScheme {
        colorScheme == .dark ? .dark : .light
    }
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

// MARK: - Theme provider

/// Injects `cursorScheme` from `LancerAppearance` (Settings) and/or the live
/// `ColorScheme`. Screens can call this at the root instead of hand-rolling env
/// injection; `AppRoot` continues to set the env directly for the live shell.
public extension View {
    func cursorTheme(appearance: LancerAppearance? = nil) -> some View {
        modifier(CursorThemeModifier(appearance: appearance))
    }
}

private struct CursorThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(LancerAppearance.storageKey) private var appearancePref = LancerAppearance.light.rawValue

    let appearance: LancerAppearance?

    func body(content: Content) -> some View {
        let resolvedAppearance = appearance ?? (LancerAppearance(rawValue: appearancePref) ?? .light)
        let scheme = CursorScheme.resolve(resolvedAppearance, systemScheme: colorScheme)
        content.environment(\.cursorScheme, scheme)
    }
}
#endif
