import SwiftUI

public enum LancerAppearance: String, CaseIterable, Sendable {
    case light
    case dark
    case system

    public static let storageKey = "lancerAppearance"

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

// MARK: - Accent theme (user-selectable brand color)

/// The app's brand accent, chosen by the user in Settings. `terracotta` is the
/// original look and returns the base palette unchanged; the others overwrite only
/// the accent family (accent / accentInk / accentSoft / accentFg), leaving
/// surfaces, terminal, and the risk/warn ramp intact.
public enum LancerAccentTheme: String, CaseIterable, Sendable, Identifiable {
    case terracotta, indigo, emerald, violet, rose

    public var id: String { rawValue }
    public static let storageKey = "lancerAccentTheme"

    public var displayName: String {
        switch self {
        case .terracotta: "Terracotta"
        case .indigo:     "Indigo"
        case .emerald:    "Emerald"
        case .violet:     "Violet"
        case .rose:       "Rose"
        }
    }

    /// Base accent per scheme. Light/dark pairs are tuned so the accent reads with
    /// enough contrast on each background.
    public func accent(_ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .terracotta: return dark ? rgb(0.894, 0.482, 0.341) : rgb(0.753, 0.357, 0.212)
        case .indigo:     return dark ? rgb(0.506, 0.549, 0.973) : rgb(0.310, 0.275, 0.898)
        case .emerald:    return dark ? rgb(0.204, 0.827, 0.600) : rgb(0.122, 0.620, 0.431)
        case .violet:     return dark ? rgb(0.655, 0.545, 0.980) : rgb(0.486, 0.227, 0.929)
        case .rose:       return dark ? rgb(0.984, 0.443, 0.522) : rgb(0.882, 0.114, 0.282)
        }
    }

    /// Foreground drawn on top of an accent fill.
    func accentFg(_ scheme: ColorScheme) -> Color {
        // Terracotta keeps its original dark-mode ink; the saturated themes read
        // best with white on top in both schemes.
        if self == .terracotta && scheme == .dark { return rgb(0.075, 0.063, 0.051) }
        return scheme == .dark ? .white : .white
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

public extension LancerTokens {
    /// Returns a copy with the accent family swapped to `theme`. Terracotta is the
    /// baseline and returns self unchanged so the default look is byte-for-byte the
    /// same; other themes derive `accentSoft`/`accentInk` from the base accent so a
    /// single hue drives the whole accent family.
    func withAccent(_ theme: LancerAccentTheme, scheme: ColorScheme) -> LancerTokens {
        guard theme != .terracotta else { return self }
        var copy = self
        let a = theme.accent(scheme)
        copy.accent = a
        copy.accentInk = a
        copy.accentSoft = a.opacity(scheme == .dark ? 0.22 : 0.14)
        copy.accentFg = theme.accentFg(scheme)
        return copy
    }
}

// MARK: - Design tokens — Lancer editorial system
// The sand palette is the approved light shell. Dark adapts the same semantic
// roles while the terminal remains an intentionally darker working surface.
// Terminal + HUD tokens are always-dark regardless of scheme.

public struct LancerTokens: Sendable {

    // MARK: Surfaces (scheme-adaptive)
    public var bg: Color           // page background (#f3f3f2 light)
    public var bgTint: Color       // subtle tint (#ecebe9 light)
    public var surface: Color      // card / sheet (#ffffff light)
    public var surface2: Color     // hover / subtle elevated (#f7f7f6 light)
    public var surfaceSunk: Color  // recessed / input (#ededeb light)
    public var border: Color       // default border (#e3e2df light)
    public var borderStrong: Color // strong border (#d4d3cf light)
    public var divider: Color      // hairline divider (#ecebe8 light)

    // MARK: Text (scheme-adaptive)
    public var text: Color         // primary (#15140f light)
    public var text2: Color        // secondary (#4b4945 light)
    public var text3: Color        // tertiary / placeholder (#8a8782 light)
    public var text4: Color        // disabled / hint (#b3b0aa light)
    public var textOnDark: Color   // text on always-dark surfaces (#f1eee8)

    // MARK: Accent + semantic (scheme-adaptive)
    public var accent: Color       // warm orange oklch(0.66 0.17 38) ≈ #d1702f
    public var accentInk: Color    // dark accent for text oklch(0.46 0.15 38) ≈ #8f4a1e
    public var accentSoft: Color   // accent tint background oklch(0.95 0.04 50) ≈ #f6ece1
    public var accentFg: Color     // fg on accent bg (#ffffff)
    public var ok: Color           // oklch(0.62 0.14 150) ≈ #2c9b59
    public var okSoft: Color       // oklch(0.94 0.05 150) ≈ #e2f3e8
    public var warn: Color         // oklch(0.74 0.14 75) ≈ #c79528
    public var warnSoft: Color     // oklch(0.95 0.06 80) ≈ #f6eed3
    public var danger: Color       // oklch(0.58 0.18 27) ≈ #c33a31
    public var dangerSoft: Color   // oklch(0.95 0.04 27) ≈ #f8e7e3
    public var info: Color         // oklch(0.62 0.13 245) ≈ #3c7fc3
    public var infoSoft: Color     // oklch(0.95 0.03 245) ≈ #e6eef6
    public var neutralSoft: Color  // #eeede9

    // MARK: HUD (always dark — agent-status strip)
    public var hudBg: Color        // #0e0f12
    public var hudText: Color      // #dde1e7
    public var hudBorder: Color    // #1c1f25

    // MARK: Terminal (always dark — the "hero" context)
    public var termBg: Color           // #100e0c
    public var termSurface: Color      // #191613
    public var termSurface2: Color     // #211d18
    public var termBorder: Color       // #332c25
    public var termBorderStrong: Color // #483d33
    public var termText: Color         // #f1ede5
    public var termText2: Color        // #b4aa9f
    public var termText3: Color        // #776d63
    public var termPrompt: Color       // #e07a4f
    public var termCwd: Color          // #d6c4b3
    public var termAccent: Color       // #c8843c
    public var termOk: Color           // #89aa78
    public var termErr: Color          // #e06a55

    // MARK: Radii — chat shell chrome is soft and tactile; terminal/code surfaces can still
    // opt into tighter geometry locally when they need a stronger technical read.
    public var r1: CGFloat = 10  // compact cards / blocks
    public var r2: CGFloat = 12  // chips / tags
    public var r3: CGFloat = 16  // buttons / inputs
    public var r4: CGFloat = 20  // cards
    public var r5: CGFloat = 30  // sheets / overlays
    public var pill: CGFloat = 999

    // MARK: Spacing
    public var s0: CGFloat = 2
    public var s1: CGFloat = 4
    public var s2: CGFloat = 6
    public var s3: CGFloat = 8
    public var s4: CGFloat = 12
    public var s5: CGFloat = 16
    public var s6: CGFloat = 20
    public var s7: CGFloat = 24
    public var s8: CGFloat = 32
    public var s9: CGFloat = 48

    // MARK: Risk scale
    // The risk ramp is independent of the brand/CTA `accent` (R5.1/R5.2): green → amber →
    // orange → red, monotonic. Level 2 uses a dedicated orange — never `accent` — so a
    // medium-risk badge can't be mistaken for an affirmative CTA.
    public static let riskOrange = Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1) // #E2662C
    public func risk(_ level: Int) -> Color {
        switch level {
        case 0:  return ok
        case 1:  return warn
        case 2:  return Self.riskOrange
        default: return danger
        }
    }

    public func riskSoft(_ level: Int) -> Color {
        switch level {
        case 0:  return okSoft
        case 1:  return warnSoft
        case 2:  return Self.riskOrange.opacity(0.16)
        default: return dangerSoft
        }
    }

    // MARK: Backward-compat aliases
    public var surf0: Color { bg }
    public var surf1: Color { surface }
    public var surf2: Color { surface2 }
    public var surf3: Color { border }
    public var text1: Color { text }
    public var termGreen: Color  { termOk }
    public var termRed: Color    { termErr }
    public var termYellow: Color { termAccent }
    public var termBlue: Color   { termCwd }

    public var radiusXS: CGFloat  { r2 }  // 2
    public var radiusSM: CGFloat  { r3 }  // 0
    public var radiusMD: CGFloat  { r4 }  // 0
    public var radiusLG: CGFloat  { r5 }  // 4
    public var radiusXL: CGFloat  { r5 }  // 4 (sheets/overlays cap)
    public var radiusPill: CGFloat { pill }

    public var sp1: CGFloat { s1 }   // 4
    public var sp2: CGFloat { s3 }   // 8
    public var sp3: CGFloat { s4 }   // 12
    public var sp4: CGFloat { s5 }   // 16
    public var sp5: CGFloat { s6 }   // 20
    public var sp6: CGFloat { s7 }   // 24
    public var sp8: CGFloat { s8 }   // 32

    // MARK: Prebuilt palettes

    /// Light palette — the board's sand canvas, paper cards, and terracotta CTA.
    public static let light = LancerTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.945, green: 0.929, blue: 0.898, opacity: 1), // #f1ede5
        bgTint:        Color(.sRGB, red: 0.918, green: 0.898, blue: 0.859, opacity: 1), // #eae5db
        surface:       Color(.sRGB, red: 0.988, green: 0.984, blue: 0.973, opacity: 1), // #fcfbf8
        surface2:      Color(.sRGB, red: 0.957, green: 0.945, blue: 0.918, opacity: 1), // #f4f1ea
        surfaceSunk:   Color(.sRGB, red: 0.938, green: 0.914, blue: 0.875, opacity: 1), // #efe9df
        border:        Color(.sRGB, red: 0.925, green: 0.902, blue: 0.855, opacity: 1), // #ece6da
        borderStrong:  Color(.sRGB, red: 0.886, green: 0.859, blue: 0.808, opacity: 1), // #e2dbce
        divider:       Color(.sRGB, red: 0.941, green: 0.922, blue: 0.882, opacity: 1), // #f0ebe1

        // Text — cool near-black
        text:          Color(.sRGB, red: 0.137, green: 0.125, blue: 0.110, opacity: 1), // #23201c
        text2:         Color(.sRGB, red: 0.247, green: 0.227, blue: 0.196, opacity: 1), // #3f3a32
        text3:         Color(.sRGB, red: 0.365, green: 0.337, blue: 0.294, opacity: 1), // #5d564b
        text4:         Color(.sRGB, red: 0.604, green: 0.569, blue: 0.510, opacity: 1), // #9a9182
        textOnDark:    Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2

        // Accent — warm primary action
        accent:        Color(.sRGB, red: 0.753, green: 0.357, blue: 0.212, opacity: 1), // #c05b36
        accentInk:     Color(.sRGB, red: 0.639, green: 0.290, blue: 0.173, opacity: 1), // #a34a2c
        accentSoft:    Color(.sRGB, red: 0.965, green: 0.906, blue: 0.847, opacity: 1), // #f6e7d8
        accentFg:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff

        // Semantic
        ok:            Color(.sRGB, red: 0.357, green: 0.478, blue: 0.357, opacity: 1), // #5b7a5b
        okSoft:        Color(.sRGB, red: 0.933, green: 0.941, blue: 0.918, opacity: 1), // #eef0ea
        warn:          Color(.sRGB, red: 0.784, green: 0.518, blue: 0.235, opacity: 1), // #c8843c
        warnSoft:      Color(.sRGB, red: 0.965, green: 0.906, blue: 0.824, opacity: 1), // #f6e7d2
        danger:        Color(.sRGB, red: 0.812, green: 0.231, blue: 0.173, opacity: 1), // #cf3b2c
        dangerSoft:    Color(.sRGB, red: 0.973, green: 0.906, blue: 0.890, opacity: 1), // #f8e7e3
        info:          Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        infoSoft:      Color(.sRGB, red: 0.906, green: 0.914, blue: 1.000, opacity: 1), // #e7e9ff
        neutralSoft:   Color(.sRGB, red: 0.929, green: 0.929, blue: 0.918, opacity: 1), // #ededea

        // HUD (always dark)
        hudBg:         Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        hudText:       Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2
        hudBorder:     Color(.sRGB, red: 0.137, green: 0.149, blue: 0.176, opacity: 1), // #23262d

        // Terminal (always dark — BLOCKS)
        termBg:           Color(.sRGB, red: 0.063, green: 0.055, blue: 0.047, opacity: 1), // #100e0c
        termSurface:      Color(.sRGB, red: 0.098, green: 0.086, blue: 0.075, opacity: 1), // #191613
        termSurface2:     Color(.sRGB, red: 0.129, green: 0.114, blue: 0.094, opacity: 1), // #211d18
        termBorder:       Color(.sRGB, red: 0.200, green: 0.173, blue: 0.145, opacity: 1), // #332c25
        termBorderStrong: Color(.sRGB, red: 0.282, green: 0.239, blue: 0.200, opacity: 1), // #483d33
        termText:         Color(.sRGB, red: 0.945, green: 0.929, blue: 0.898, opacity: 1), // #f1ede5
        termText2:        Color(.sRGB, red: 0.706, green: 0.667, blue: 0.624, opacity: 1), // #b4aa9f
        termText3:        Color(.sRGB, red: 0.467, green: 0.427, blue: 0.388, opacity: 1), // #776d63
        termPrompt:       Color(.sRGB, red: 0.878, green: 0.478, blue: 0.310, opacity: 1), // #e07a4f
        termCwd:          Color(.sRGB, red: 0.839, green: 0.769, blue: 0.702, opacity: 1), // #d6c4b3
        termAccent:       Color(.sRGB, red: 0.784, green: 0.518, blue: 0.235, opacity: 1), // #c8843c
        termOk:           Color(.sRGB, red: 0.537, green: 0.667, blue: 0.471, opacity: 1), // #89aa78
        termErr:          Color(.sRGB, red: 0.878, green: 0.416, blue: 0.333, opacity: 1)  // #e06a55
    )

    /// Dark palette — calm chat shell surfaces, warm-grey ink, warm primary accent.
    public static let dark = LancerTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.098, green: 0.098, blue: 0.090, opacity: 1), // #191917
        bgTint:        Color(.sRGB, red: 0.121, green: 0.118, blue: 0.106, opacity: 1), // #1f1e1b
        surface:       Color(.sRGB, red: 0.145, green: 0.141, blue: 0.125, opacity: 1), // #252420
        surface2:      Color(.sRGB, red: 0.180, green: 0.176, blue: 0.157, opacity: 1), // #2e2d28
        surfaceSunk:   Color(.sRGB, red: 0.071, green: 0.071, blue: 0.063, opacity: 1), // #121210
        border:        Color(.sRGB, red: 0.235, green: 0.231, blue: 0.204, opacity: 1), // #3c3b34
        borderStrong:  Color(.sRGB, red: 0.318, green: 0.306, blue: 0.267, opacity: 1), // #514e44
        divider:       Color(.sRGB, red: 0.180, green: 0.176, blue: 0.157, opacity: 1), // #2e2d28

        // Text
        text:          Color(.sRGB, red: 0.918, green: 0.906, blue: 0.867, opacity: 1), // #eae7dd
        text2:         Color(.sRGB, red: 0.690, green: 0.671, blue: 0.612, opacity: 1), // #b0ab9c
        text3:         Color(.sRGB, red: 0.494, green: 0.478, blue: 0.431, opacity: 1), // #7e7a6e
        text4:         Color(.sRGB, red: 0.341, green: 0.329, blue: 0.294, opacity: 1), // #57544b
        textOnDark:    Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2

        // Accent — warm primary action. Blue remains in `info` and terminal progress states.
        accent:        Color(.sRGB, red: 0.894, green: 0.482, blue: 0.341, opacity: 1), // #e47b57
        accentInk:     Color(.sRGB, red: 1.000, green: 0.702, blue: 0.573, opacity: 1), // #ffb392
        accentSoft:    Color(.sRGB, red: 0.239, green: 0.129, blue: 0.086, opacity: 1), // #3d2116
        accentFg:      Color(.sRGB, red: 0.075, green: 0.063, blue: 0.051, opacity: 1), // #13100d

        // Semantic
        ok:            Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1), // #36c26b
        okSoft:        Color(.sRGB, red: 0.063, green: 0.149, blue: 0.102, opacity: 1), // #10261a
        warn:          Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1), // #f0a93b
        warnSoft:      Color(.sRGB, red: 0.165, green: 0.125, blue: 0.031, opacity: 1), // #2a2008
        danger:        Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1), // #e0533f
        dangerSoft:    Color(.sRGB, red: 0.165, green: 0.078, blue: 0.063, opacity: 1), // #2a1410
        info:          Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        infoSoft:      Color(.sRGB, red: 0.071, green: 0.082, blue: 0.180, opacity: 1), // #12152e
        neutralSoft:   Color(.sRGB, red: 0.082, green: 0.090, blue: 0.110, opacity: 1), // #15171c

        // HUD (always dark)
        hudBg:         Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        hudText:       Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2
        hudBorder:     Color(.sRGB, red: 0.137, green: 0.149, blue: 0.176, opacity: 1), // #23262d

        // Terminal (always dark — BLOCKS)
        termBg:           Color(.sRGB, red: 0.063, green: 0.055, blue: 0.047, opacity: 1), // #100e0c
        termSurface:      Color(.sRGB, red: 0.098, green: 0.086, blue: 0.075, opacity: 1), // #191613
        termSurface2:     Color(.sRGB, red: 0.129, green: 0.114, blue: 0.094, opacity: 1), // #211d18
        termBorder:       Color(.sRGB, red: 0.200, green: 0.173, blue: 0.145, opacity: 1), // #332c25
        termBorderStrong: Color(.sRGB, red: 0.282, green: 0.239, blue: 0.200, opacity: 1), // #483d33
        termText:         Color(.sRGB, red: 0.945, green: 0.929, blue: 0.898, opacity: 1), // #f1ede5
        termText2:        Color(.sRGB, red: 0.706, green: 0.667, blue: 0.624, opacity: 1), // #b4aa9f
        termText3:        Color(.sRGB, red: 0.467, green: 0.427, blue: 0.388, opacity: 1), // #776d63
        termPrompt:       Color(.sRGB, red: 0.878, green: 0.478, blue: 0.310, opacity: 1), // #e07a4f
        termCwd:          Color(.sRGB, red: 0.839, green: 0.769, blue: 0.702, opacity: 1), // #d6c4b3
        termAccent:       Color(.sRGB, red: 0.784, green: 0.518, blue: 0.235, opacity: 1), // #c8843c
        termOk:           Color(.sRGB, red: 0.537, green: 0.667, blue: 0.471, opacity: 1), // #89aa78
        termErr:          Color(.sRGB, red: 0.878, green: 0.416, blue: 0.333, opacity: 1)  // #e06a55
    )
}

// MARK: - Environment key

private struct LancerTokensKey: EnvironmentKey {
    // Sand/light is the shipped default shell; dark is reserved for terminal/session.
    static let defaultValue: LancerTokens = .light
}

public extension EnvironmentValues {
    var lancerTokens: LancerTokens {
        get { self[LancerTokensKey.self] }
        set { self[LancerTokensKey.self] = newValue }
    }
}

// MARK: - View helper

public extension View {
    func lancerTokens() -> some View {
        modifier(LancerTokensModifier())
    }

    func lancerTokens(appearance: LancerAppearance) -> some View {
        modifier(LancerTokensModifier(appearance: appearance))
    }
}

private struct LancerTokensModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(LancerAccentTheme.storageKey) private var accentPref = LancerAccentTheme.terracotta.rawValue

    let appearance: LancerAppearance?

    init(appearance: LancerAppearance? = nil) {
        self.appearance = appearance
    }

    func body(content: Content) -> some View {
        let resolvedScheme: ColorScheme = appearance?.preferredColorScheme ?? colorScheme
        let base = resolvedScheme == .dark ? LancerTokens.dark : .light
        let theme = LancerAccentTheme(rawValue: accentPref) ?? .terracotta
        content.environment(\.lancerTokens, base.withAccent(theme, scheme: resolvedScheme))
    }
}

// MARK: - DI — always-dark Island palette
// Shared by AgentIsland and AgentStatusHeader. Never scheme-adaptive — the island is always dark.

#if os(iOS)
enum DI {
    static let ink  = Color(.sRGB, red: 0.957, green: 0.949, blue: 0.933, opacity: 1) // #f4f2ee
    static let ink2 = Color(.sRGB, red: 0.608, green: 0.588, blue: 0.553, opacity: 1) // #9b968d
    static let ink3 = Color(.sRGB, red: 0.400, green: 0.384, blue: 0.357, opacity: 1) // #66625b
    static let approval  = Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1) // warn #f0a93b
    static let streaming = Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1) // accent #2f43ff

    static func bg(approval: Bool) -> Color {
        approval ? Color(.sRGB, red: 0.110, green: 0.075, blue: 0.020, opacity: 1) // #1c1305
                 : .black
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .dsMonoPt(size, weight: weight)
    }
}
#endif
