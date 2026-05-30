import SwiftUI

// MARK: - Design tokens — mother-duck-2 design system
// All oklch values pre-converted to sRGB via CSS Color 4 spec.
// Light palette: warm off-white (#f3f3f2) surfaces + warm text (#15140f).
// Dark palette: near-black surfaces, same warm-orange accent hue.
// Terminal + HUD tokens are always-dark regardless of scheme.

public struct ConduitTokens: Sendable {

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
    public var termBg: Color           // #0e0f12
    public var termSurface: Color      // #16181d
    public var termSurface2: Color     // #1c1f25
    public var termBorder: Color       // #262a31
    public var termBorderStrong: Color // #2f343c
    public var termText: Color         // #d6d3cc
    public var termText2: Color        // #8e8a82
    public var termText3: Color        // #5f5b54
    public var termPrompt: Color       // oklch(0.74 0.13 165) ≈ #3fb58e
    public var termCwd: Color          // oklch(0.72 0.11 245) ≈ #5fa0d6
    public var termAccent: Color       // oklch(0.74 0.14 65) ≈ #c89a4a (amber-gold)
    public var termOk: Color           // oklch(0.74 0.16 150) ≈ #3fc06f
    public var termErr: Color          // oklch(0.70 0.18 27) ≈ #df5a4a

    // MARK: Radii
    public var r1: CGFloat = 4
    public var r2: CGFloat = 6
    public var r3: CGFloat = 8
    public var r4: CGFloat = 12
    public var r5: CGFloat = 16
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
    public func risk(_ level: Int) -> Color {
        switch level {
        case 0:  return ok
        case 1:  return warn
        case 2:  return accent
        default: return danger
        }
    }

    public func riskSoft(_ level: Int) -> Color {
        switch level {
        case 0:  return okSoft
        case 1:  return warnSoft
        case 2:  return accentSoft
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

    public var radiusXS: CGFloat  { r2 }  // 6
    public var radiusSM: CGFloat  { r3 }  // 8
    public var radiusMD: CGFloat  { r4 }  // 12
    public var radiusLG: CGFloat  { r5 }  // 16
    public var radiusXL: CGFloat  { 20 }
    public var radiusPill: CGFloat { pill }

    public var sp1: CGFloat { s1 }   // 4
    public var sp2: CGFloat { s3 }   // 8
    public var sp3: CGFloat { s4 }   // 12
    public var sp4: CGFloat { s5 }   // 16
    public var sp5: CGFloat { s6 }   // 20
    public var sp6: CGFloat { s7 }   // 24
    public var sp8: CGFloat { s8 }   // 32

    // MARK: Prebuilt palettes

    /// Light palette — warm off-white surfaces, warm-tinted text, orange accent.
    public static let light = ConduitTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.953, green: 0.953, blue: 0.949, opacity: 1), // #f3f3f2
        bgTint:        Color(.sRGB, red: 0.925, green: 0.922, blue: 0.914, opacity: 1), // #ecebe9
        surface:       Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff
        surface2:      Color(.sRGB, red: 0.969, green: 0.969, blue: 0.965, opacity: 1), // #f7f7f6
        surfaceSunk:   Color(.sRGB, red: 0.929, green: 0.929, blue: 0.922, opacity: 1), // #ededeb
        border:        Color(.sRGB, red: 0.890, green: 0.886, blue: 0.875, opacity: 1), // #e3e2df
        borderStrong:  Color(.sRGB, red: 0.831, green: 0.827, blue: 0.812, opacity: 1), // #d4d3cf
        divider:       Color(.sRGB, red: 0.925, green: 0.922, blue: 0.910, opacity: 1), // #ecebe8

        // Text — warm-tinted (not neutral grey)
        text:          Color(.sRGB, red: 0.082, green: 0.078, blue: 0.059, opacity: 1), // #15140f
        text2:         Color(.sRGB, red: 0.294, green: 0.286, blue: 0.271, opacity: 1), // #4b4945
        text3:         Color(.sRGB, red: 0.541, green: 0.529, blue: 0.510, opacity: 1), // #8a8782
        text4:         Color(.sRGB, red: 0.702, green: 0.690, blue: 0.667, opacity: 1), // #b3b0aa
        textOnDark:    Color(.sRGB, red: 0.945, green: 0.933, blue: 0.910, opacity: 1), // #f1eee8

        // Accent — warm orange oklch(0.66 0.17 38)
        accent:        Color(.sRGB, red: 0.820, green: 0.439, blue: 0.184, opacity: 1), // #d1702f
        accentInk:     Color(.sRGB, red: 0.561, green: 0.290, blue: 0.118, opacity: 1), // #8f4a1e
        accentSoft:    Color(.sRGB, red: 0.965, green: 0.925, blue: 0.882, opacity: 1), // #f6ece1
        accentFg:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff

        // Semantic
        ok:            Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1), // #2c9b59
        okSoft:        Color(.sRGB, red: 0.886, green: 0.953, blue: 0.910, opacity: 1), // #e2f3e8
        warn:          Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1), // #c79528
        warnSoft:      Color(.sRGB, red: 0.965, green: 0.933, blue: 0.827, opacity: 1), // #f6eed3
        danger:        Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1), // #c33a31
        dangerSoft:    Color(.sRGB, red: 0.973, green: 0.906, blue: 0.890, opacity: 1), // #f8e7e3
        info:          Color(.sRGB, red: 0.235, green: 0.498, blue: 0.765, opacity: 1), // #3c7fc3
        infoSoft:      Color(.sRGB, red: 0.902, green: 0.933, blue: 0.965, opacity: 1), // #e6eef6
        neutralSoft:   Color(.sRGB, red: 0.933, green: 0.929, blue: 0.914, opacity: 1), // #eeede9

        // HUD (always dark)
        hudBg:         Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        hudText:       Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1), // #dde1e7
        hudBorder:     Color(.sRGB, red: 0.110, green: 0.122, blue: 0.145, opacity: 1), // #1c1f25

        // Terminal (always dark)
        termBg:           Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        termSurface:      Color(.sRGB, red: 0.086, green: 0.094, blue: 0.114, opacity: 1), // #16181d
        termSurface2:     Color(.sRGB, red: 0.110, green: 0.122, blue: 0.145, opacity: 1), // #1c1f25
        termBorder:       Color(.sRGB, red: 0.149, green: 0.165, blue: 0.192, opacity: 1), // #262a31
        termBorderStrong: Color(.sRGB, red: 0.184, green: 0.204, blue: 0.235, opacity: 1), // #2f343c
        termText:         Color(.sRGB, red: 0.839, green: 0.827, blue: 0.800, opacity: 1), // #d6d3cc
        termText2:        Color(.sRGB, red: 0.557, green: 0.541, blue: 0.510, opacity: 1), // #8e8a82
        termText3:        Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1), // #5f5b54
        termPrompt:       Color(.sRGB, red: 0.247, green: 0.710, blue: 0.557, opacity: 1), // #3fb58e
        termCwd:          Color(.sRGB, red: 0.373, green: 0.627, blue: 0.839, opacity: 1), // #5fa0d6
        termAccent:       Color(.sRGB, red: 0.784, green: 0.604, blue: 0.290, opacity: 1), // #c89a4a
        termOk:           Color(.sRGB, red: 0.247, green: 0.753, blue: 0.435, opacity: 1), // #3fc06f
        termErr:          Color(.sRGB, red: 0.875, green: 0.353, blue: 0.290, opacity: 1)  // #df5a4a
    )

    /// Dark palette — near-black surfaces, same warm-orange accent hue.
    public static let dark = ConduitTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.059, green: 0.059, blue: 0.067, opacity: 1), // #0f0f11
        bgTint:        Color(.sRGB, red: 0.078, green: 0.078, blue: 0.086, opacity: 1), // #141416
        surface:       Color(.sRGB, red: 0.090, green: 0.094, blue: 0.106, opacity: 1), // #17181b
        surface2:      Color(.sRGB, red: 0.118, green: 0.122, blue: 0.137, opacity: 1), // #1e1f23
        surfaceSunk:   Color(.sRGB, red: 0.047, green: 0.047, blue: 0.059, opacity: 1), // #0c0c0f
        border:        Color(.sRGB, red: 0.149, green: 0.153, blue: 0.184, opacity: 1), // #262730
        borderStrong:  Color(.sRGB, red: 0.184, green: 0.188, blue: 0.259, opacity: 1), // #2f3042
        divider:       Color(.sRGB, red: 0.102, green: 0.106, blue: 0.125, opacity: 1), // #1a1b20

        // Text
        text:          Color(.sRGB, red: 0.941, green: 0.941, blue: 0.949, opacity: 1), // #f0f0f2
        text2:         Color(.sRGB, red: 0.722, green: 0.722, blue: 0.745, opacity: 1), // #b8b8be
        text3:         Color(.sRGB, red: 0.498, green: 0.498, blue: 0.541, opacity: 1), // #7f7f8a
        text4:         Color(.sRGB, red: 0.314, green: 0.314, blue: 0.376, opacity: 1), // #505060
        textOnDark:    Color(.sRGB, red: 0.945, green: 0.933, blue: 0.910, opacity: 1), // #f1eee8

        // Accent — warm orange, brighter for dark bg oklch(0.70 0.17 38) ≈ #da7f38
        accent:        Color(.sRGB, red: 0.855, green: 0.498, blue: 0.220, opacity: 1), // #da7f38
        accentInk:     Color(.sRGB, red: 0.910, green: 0.576, blue: 0.310, opacity: 1), // #e8934f
        accentSoft:    Color(.sRGB, red: 0.165, green: 0.086, blue: 0.031, opacity: 1), // #2a1608
        accentFg:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1),

        // Semantic
        ok:            Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369, opacity: 1), // #22c55e
        okSoft:        Color(.sRGB, red: 0.051, green: 0.137, blue: 0.094, opacity: 1), // #0d2318
        warn:          Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1), // #f59e0b
        warnSoft:      Color(.sRGB, red: 0.141, green: 0.102, blue: 0.027, opacity: 1), // #241a07
        danger:        Color(.sRGB, red: 0.973, green: 0.529, blue: 0.529, opacity: 1), // #f87171
        dangerSoft:    Color(.sRGB, red: 0.145, green: 0.051, blue: 0.051, opacity: 1), // #250d0d
        info:          Color(.sRGB, red: 0.376, green: 0.647, blue: 0.980, opacity: 1), // #60a5fa
        infoSoft:      Color(.sRGB, red: 0.055, green: 0.102, blue: 0.157, opacity: 1), // #0e1a28
        neutralSoft:   Color(.sRGB, red: 0.118, green: 0.122, blue: 0.118, opacity: 1), // #1e1f1e

        // HUD (always dark — same in both modes)
        hudBg:         Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        hudText:       Color(.sRGB, red: 0.867, green: 0.882, blue: 0.906, opacity: 1), // #dde1e7
        hudBorder:     Color(.sRGB, red: 0.110, green: 0.122, blue: 0.145, opacity: 1), // #1c1f25

        // Terminal (always dark — same in both modes)
        termBg:           Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1),
        termSurface:      Color(.sRGB, red: 0.086, green: 0.094, blue: 0.114, opacity: 1),
        termSurface2:     Color(.sRGB, red: 0.110, green: 0.122, blue: 0.145, opacity: 1),
        termBorder:       Color(.sRGB, red: 0.149, green: 0.165, blue: 0.192, opacity: 1),
        termBorderStrong: Color(.sRGB, red: 0.184, green: 0.204, blue: 0.235, opacity: 1),
        termText:         Color(.sRGB, red: 0.839, green: 0.827, blue: 0.800, opacity: 1),
        termText2:        Color(.sRGB, red: 0.557, green: 0.541, blue: 0.510, opacity: 1),
        termText3:        Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1),
        termPrompt:       Color(.sRGB, red: 0.247, green: 0.710, blue: 0.557, opacity: 1),
        termCwd:          Color(.sRGB, red: 0.373, green: 0.627, blue: 0.839, opacity: 1),
        termAccent:       Color(.sRGB, red: 0.784, green: 0.604, blue: 0.290, opacity: 1),
        termOk:           Color(.sRGB, red: 0.247, green: 0.753, blue: 0.435, opacity: 1),
        termErr:          Color(.sRGB, red: 0.875, green: 0.353, blue: 0.290, opacity: 1)
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

// MARK: - View helper

public extension View {
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

// MARK: - DI — always-dark Island palette
// Shared by AgentIsland and AgentStatusHeader. Never scheme-adaptive — the island is always dark.

#if os(iOS)
enum DI {
    static let ink  = Color(.sRGB, red: 0.957, green: 0.949, blue: 0.933, opacity: 1) // #f4f2ee
    static let ink2 = Color(.sRGB, red: 0.608, green: 0.588, blue: 0.553, opacity: 1) // #9b968d
    static let ink3 = Color(.sRGB, red: 0.400, green: 0.384, blue: 0.357, opacity: 1) // #66625b
    static let approval  = Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1)
    static let streaming = Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1)

    static func bg(approval: Bool) -> Color {
        approval ? Color(.sRGB, red: 0.110, green: 0.075, blue: 0.020, opacity: 1) // #1c1305
                 : .black
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .dsMonoPt(size, weight: weight)
    }
}
#endif

