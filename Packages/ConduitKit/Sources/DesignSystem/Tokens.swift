import SwiftUI

// MARK: - Design tokens for the agent-chat visual language (mother-duck-2)
// oklch → sRGB conversions pre-computed and stored as Color(.sRGB, ...) literals.
// Light palette: warm off-white surfaces (#f3f3f2 base) + dark HUD strip.
// Dark palette: near-black surfaces with the same chromatic accent.

public struct ConduitTokens: Sendable {

    // MARK: Surfaces
    public var surf0: Color   // page background
    public var surf1: Color   // card / sheet background
    public var surf2: Color   // hover / subtle elevated
    public var surf3: Color   // border / divider

    // MARK: Text
    public var text1: Color   // primary
    public var text2: Color   // secondary
    public var text3: Color   // tertiary / placeholder
    public var text4: Color   // disabled / hint

    // MARK: Semantic
    public var accent: Color
    public var ok: Color
    public var warn: Color
    public var danger: Color
    public var info: Color

    // MARK: Risk scale (0–3 → ok/warn/danger/critical)
    public func risk(_ level: Int) -> Color {
        switch level {
        case 0:     return ok
        case 1:     return warn
        case 2:     return danger
        default:    return Color(.sRGB, red: 0.80, green: 0.10, blue: 0.10, opacity: 1)
        }
    }

    // MARK: HUD (always dark regardless of scheme)
    public var hudBg: Color     // dark strip background
    public var hudText: Color   // text on HUD
    public var hudBorder: Color

    // MARK: Terminal surface (always dark)
    public var termBg: Color
    public var termText: Color
    public var termAccent: Color
    public var termGreen: Color
    public var termRed: Color
    public var termYellow: Color
    public var termBlue: Color

    // MARK: Radii
    public var radiusXS: CGFloat  = 6
    public var radiusSM: CGFloat  = 8
    public var radiusMD: CGFloat  = 12
    public var radiusLG: CGFloat  = 16
    public var radiusXL: CGFloat  = 20
    public var radiusPill: CGFloat = 999

    // MARK: Spacing
    public var sp1: CGFloat = 4
    public var sp2: CGFloat = 8
    public var sp3: CGFloat = 12
    public var sp4: CGFloat = 16
    public var sp5: CGFloat = 20
    public var sp6: CGFloat = 24
    public var sp8: CGFloat = 32

    // MARK: Prebuilt palettes

    /// Light mode — warm off-white base, dark HUD, dark terminal.
    public static let light = ConduitTokens(
        // Surfaces: oklch(97% 0.003 75) → #f3f3f2
        surf0:      Color(.sRGB, red: 0.953, green: 0.953, blue: 0.949, opacity: 1),
        surf1:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1),
        surf2:      Color(.sRGB, red: 0.929, green: 0.929, blue: 0.925, opacity: 1),
        surf3:      Color(.sRGB, red: 0.882, green: 0.882, blue: 0.878, opacity: 1),

        // Text: oklch(12% 0 0) → ~#1e1e1e … oklch(62% 0 0) → ~#9a9a9a
        text1:      Color(.sRGB, red: 0.118, green: 0.118, blue: 0.118, opacity: 1),
        text2:      Color(.sRGB, red: 0.271, green: 0.271, blue: 0.271, opacity: 1),
        text3:      Color(.sRGB, red: 0.447, green: 0.447, blue: 0.447, opacity: 1),
        text4:      Color(.sRGB, red: 0.624, green: 0.624, blue: 0.624, opacity: 1),

        // Semantic: oklch(50% 0.22 280) → #5d5ce6 (accent, purple-indigo)
        accent:     Color(.sRGB, red: 0.365, green: 0.361, blue: 0.902, opacity: 1),
        ok:         Color(.sRGB, red: 0.086, green: 0.639, blue: 0.294, opacity: 1),
        warn:       Color(.sRGB, red: 0.851, green: 0.471, blue: 0.024, opacity: 1),
        danger:     Color(.sRGB, red: 0.863, green: 0.149, blue: 0.149, opacity: 1),
        info:       Color(.sRGB, red: 0.149, green: 0.392, blue: 0.922, opacity: 1),

        // HUD — always-dark strip at top of agent chat
        hudBg:      Color(.sRGB, red: 0.039, green: 0.039, blue: 0.043, opacity: 1),
        hudText:    Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1),
        hudBorder:  Color(.sRGB, red: 0.157, green: 0.157, blue: 0.165, opacity: 1),

        // Terminal — always-dark surface (same as dark theme term)
        termBg:     Color(.sRGB, red: 0.102, green: 0.106, blue: 0.118, opacity: 1),
        termText:   Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1),
        termAccent: Color(.sRGB, red: 0.486, green: 0.416, blue: 0.969, opacity: 1),
        termGreen:  Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369, opacity: 1),
        termRed:    Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267, opacity: 1),
        termYellow: Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1),
        termBlue:   Color(.sRGB, red: 0.376, green: 0.647, blue: 0.980, opacity: 1)
    )

    /// Dark mode — near-black base.
    public static let dark = ConduitTokens(
        surf0:      Color(.sRGB, red: 0.059, green: 0.059, blue: 0.067, opacity: 1),
        surf1:      Color(.sRGB, red: 0.090, green: 0.094, blue: 0.106, opacity: 1),
        surf2:      Color(.sRGB, red: 0.118, green: 0.122, blue: 0.137, opacity: 1),
        surf3:      Color(.sRGB, red: 0.149, green: 0.153, blue: 0.173, opacity: 1),

        text1:      Color(.sRGB, red: 0.941, green: 0.941, blue: 0.949, opacity: 1),
        text2:      Color(.sRGB, red: 0.722, green: 0.722, blue: 0.745, opacity: 1),
        text3:      Color(.sRGB, red: 0.498, green: 0.498, blue: 0.541, opacity: 1),
        text4:      Color(.sRGB, red: 0.314, green: 0.314, blue: 0.376, opacity: 1),

        // Dark accent: oklch(65% 0.22 280) → #7c6af7 (lighter purple for dark bg)
        accent:     Color(.sRGB, red: 0.486, green: 0.416, blue: 0.969, opacity: 1),
        ok:         Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369, opacity: 1),
        warn:       Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1),
        danger:     Color(.sRGB, red: 0.973, green: 0.529, blue: 0.529, opacity: 1),
        info:       Color(.sRGB, red: 0.376, green: 0.647, blue: 0.980, opacity: 1),

        hudBg:      Color(.sRGB, red: 0.024, green: 0.024, blue: 0.027, opacity: 1),
        hudText:    Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1),
        hudBorder:  Color(.sRGB, red: 0.141, green: 0.141, blue: 0.157, opacity: 1),

        termBg:     Color(.sRGB, red: 0.102, green: 0.106, blue: 0.118, opacity: 1),
        termText:   Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1),
        termAccent: Color(.sRGB, red: 0.486, green: 0.416, blue: 0.969, opacity: 1),
        termGreen:  Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369, opacity: 1),
        termRed:    Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267, opacity: 1),
        termYellow: Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1),
        termBlue:   Color(.sRGB, red: 0.376, green: 0.647, blue: 0.980, opacity: 1)
    )
}

// MARK: - Environment key

private struct ConduitTokensKey: EnvironmentKey {
    static let defaultValue: ConduitTokens = .dark
}

public extension EnvironmentValues {
    var conduitTokens: ConduitTokens {
        get { self[ConduitTokensKey.self] }
        set { self[ConduitTokensKey.self] = newValue }
    }
}

// MARK: - View helper — resolve tokens for current color scheme

public extension View {
    /// Injects the correct token palette based on the current `colorScheme`.
    func conduitTokens() -> some View {
        modifier(ConduitTokensModifier())
    }
}

private struct ConduitTokensModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .environment(\.conduitTokens, colorScheme == .dark ? .dark : .light)
    }
}
