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

    // MARK: Radii — BLOCKS identity is the square corner (r0). Only sheets round slightly;
    // dots / avatars / pings use `pill`.
    public var r1: CGFloat = 0   // cards / blocks
    public var r2: CGFloat = 2   // chips / tags
    public var r3: CGFloat = 0   // buttons / inputs
    public var r4: CGFloat = 0   // block cards
    public var r5: CGFloat = 4   // sheets / overlays
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

    // MARK: Famicom spectrum (M-THEORY cartridge) — the signature device.
    // Drives the spectrum bar, dot-matrix loaders, logo and the risk ramp. Same in both schemes.
    public static let spectrumColors: [Color] = [
        Color(.sRGB, red: 0.784, green: 0.259, blue: 0.231, opacity: 1), // #C8423B
        Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1), // #E2662C
        Color(.sRGB, red: 0.941, green: 0.573, blue: 0.180, opacity: 1), // #F0922E
        Color(.sRGB, red: 0.949, green: 0.757, blue: 0.306, opacity: 1), // #F2C14E
        Color(.sRGB, red: 0.780, green: 0.482, blue: 0.651, opacity: 1), // #C77BA6
        Color(.sRGB, red: 0.494, green: 0.310, blue: 0.710, opacity: 1), // #7E4FB5
        Color(.sRGB, red: 0.329, green: 0.376, blue: 0.784, opacity: 1), // #5460C8
    ]
    public var spectrum: [Color] { Self.spectrumColors }

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

    /// Light palette — clean light surfaces, cool near-black text, electric-blue accent, square corners.
    /// Secondary to the dark BLOCKS theme; terminal + HUD stay always-dark.
    public static let light = ConduitTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.957, green: 0.957, blue: 0.949, opacity: 1), // #f4f4f2
        bgTint:        Color(.sRGB, red: 0.925, green: 0.929, blue: 0.918, opacity: 1), // #ecedea
        surface:       Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff
        surface2:      Color(.sRGB, red: 0.965, green: 0.965, blue: 0.957, opacity: 1), // #f6f6f4
        surfaceSunk:   Color(.sRGB, red: 0.925, green: 0.933, blue: 0.941, opacity: 1), // #eceef0
        border:        Color(.sRGB, red: 0.886, green: 0.890, blue: 0.878, opacity: 1), // #e2e3e0
        borderStrong:  Color(.sRGB, red: 0.824, green: 0.831, blue: 0.816, opacity: 1), // #d2d4d0
        divider:       Color(.sRGB, red: 0.925, green: 0.925, blue: 0.918, opacity: 1), // #ececea

        // Text — cool near-black
        text:          Color(.sRGB, red: 0.078, green: 0.086, blue: 0.106, opacity: 1), // #14161b
        text2:         Color(.sRGB, red: 0.290, green: 0.302, blue: 0.333, opacity: 1), // #4a4d55
        text3:         Color(.sRGB, red: 0.502, green: 0.514, blue: 0.549, opacity: 1), // #80838c
        text4:         Color(.sRGB, red: 0.682, green: 0.694, blue: 0.722, opacity: 1), // #aeb1b8
        textOnDark:    Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2

        // Accent — electric blue
        accent:        Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        accentInk:     Color(.sRGB, red: 0.114, green: 0.169, blue: 0.722, opacity: 1), // #1d2bb8
        accentSoft:    Color(.sRGB, red: 0.906, green: 0.914, blue: 1.000, opacity: 1), // #e7e9ff
        accentFg:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff

        // Semantic
        ok:            Color(.sRGB, red: 0.122, green: 0.616, blue: 0.341, opacity: 1), // #1f9d57
        okSoft:        Color(.sRGB, red: 0.882, green: 0.953, blue: 0.910, opacity: 1), // #e1f3e8
        warn:          Color(.sRGB, red: 0.725, green: 0.514, blue: 0.102, opacity: 1), // #b9831a
        warnSoft:      Color(.sRGB, red: 0.965, green: 0.933, blue: 0.827, opacity: 1), // #f6eed3
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
        termBg:           Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1), // #0a0b0d
        termSurface:      Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        termSurface2:     Color(.sRGB, red: 0.082, green: 0.090, blue: 0.110, opacity: 1), // #15171c
        termBorder:       Color(.sRGB, red: 0.137, green: 0.149, blue: 0.176, opacity: 1), // #23262d
        termBorderStrong: Color(.sRGB, red: 0.184, green: 0.204, blue: 0.235, opacity: 1), // #2f343c
        termText:         Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2
        termText2:        Color(.sRGB, red: 0.541, green: 0.553, blue: 0.588, opacity: 1), // #8a8d96
        termText3:        Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1), // #565963
        termPrompt:       Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        termCwd:          Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1), // #565963
        termAccent:       Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1), // #f0a93b
        termOk:           Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1), // #36c26b
        termErr:          Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1)  // #e0533f
    )

    /// Dark palette — the primary BLOCKS theme: near-black surfaces, warm-grey ink, electric-blue accent.
    public static let dark = ConduitTokens(
        // Surfaces
        bg:            Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1), // #0a0b0d
        bgTint:        Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        surface:       Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12 bg-block
        surface2:      Color(.sRGB, red: 0.067, green: 0.075, blue: 0.090, opacity: 1), // #111317 bg-raised
        surfaceSunk:   Color(.sRGB, red: 0.082, green: 0.090, blue: 0.110, opacity: 1), // #15171c bg-input
        border:        Color(.sRGB, red: 0.137, green: 0.149, blue: 0.176, opacity: 1), // #23262d line
        borderStrong:  Color(.sRGB, red: 0.184, green: 0.204, blue: 0.235, opacity: 1), // #2f343c
        divider:       Color(.sRGB, red: 0.094, green: 0.102, blue: 0.122, opacity: 1), // #181a1f line-soft

        // Text
        text:          Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2 fg
        text2:         Color(.sRGB, red: 0.541, green: 0.553, blue: 0.588, opacity: 1), // #8a8d96 fg-dim
        text3:         Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1), // #565963 fg-faint
        text4:         Color(.sRGB, red: 0.204, green: 0.216, blue: 0.243, opacity: 1), // #34373e fg-ghost
        textOnDark:    Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2

        // Accent — electric blue
        accent:        Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        accentInk:     Color(.sRGB, red: 0.353, green: 0.408, blue: 1.000, opacity: 1), // #5a68ff (legible on dark)
        accentSoft:    Color(.sRGB, red: 0.102, green: 0.122, blue: 0.302, opacity: 1), // #1a1f4d accent-dim
        accentFg:      Color(.sRGB, red: 1.000, green: 1.000, blue: 1.000, opacity: 1), // #ffffff

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
        termBg:           Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1), // #0a0b0d
        termSurface:      Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1), // #0e0f12
        termSurface2:     Color(.sRGB, red: 0.082, green: 0.090, blue: 0.110, opacity: 1), // #15171c
        termBorder:       Color(.sRGB, red: 0.137, green: 0.149, blue: 0.176, opacity: 1), // #23262d
        termBorderStrong: Color(.sRGB, red: 0.184, green: 0.204, blue: 0.235, opacity: 1), // #2f343c
        termText:         Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1), // #e9e9e2
        termText2:        Color(.sRGB, red: 0.541, green: 0.553, blue: 0.588, opacity: 1), // #8a8d96
        termText3:        Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1), // #565963
        termPrompt:       Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1), // #2f43ff
        termCwd:          Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1), // #565963
        termAccent:       Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1), // #f0a93b
        termOk:           Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1), // #36c26b
        termErr:          Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1)  // #e0533f
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

