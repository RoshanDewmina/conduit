import Foundation
import SwiftUI

/// A streaming SGR (Select Graphic Rendition) parser that turns ANSI-colored
/// text into `AttributedString` chunks suitable for SwiftUI's `Text`.
///
/// Scope:
///   - Handles SGR sequences (`ESC [ … m`) including: reset, bold, dim,
///     italic, underline; 16 standard colors; 256-color (`5;n`); truecolor
///     (`2;r;g;b`); 90-97 / 100-107 bright variants.
///   - Silently consumes other CSI sequences (cursor moves, scroll, etc.)
///     because Block mode renders linear output only.
///   - Does NOT handle alt-screen, DEC private modes, OSC; those signal a
///     TUI program → caller should escalate to Raw mode.
public struct AnsiSGRParser: Sendable {
    public init() {}

    /// Parse a snippet of text containing ANSI SGR codes into an
    /// AttributedString. The `inheriting` parameter lets streaming callers
    /// resume from the previous chunk's open style.
    public func parse(_ raw: String, inheriting state: SGRState = .init()) -> (AttributedString, SGRState) {
        var current = state
        var result = AttributedString()
        var slice = raw[...]

        while !slice.isEmpty {
            guard let escRange = slice.range(of: "\u{1B}[") else {
                var chunk = AttributedString(String(slice))
                chunk.mergeAttributes(current.attributes())
                result += chunk
                break
            }

            // Plain text before the escape.
            let plain = slice[slice.startIndex ..< escRange.lowerBound]
            if !plain.isEmpty {
                var chunk = AttributedString(String(plain))
                chunk.mergeAttributes(current.attributes())
                result += chunk
            }

            // Parse the CSI body up to the command letter.
            slice = slice[escRange.upperBound...]
            guard let cmdIdx = slice.firstIndex(where: { $0.isLetter }) else { break }
            let params = String(slice[slice.startIndex ..< cmdIdx])
            let cmd    = slice[cmdIdx]
            slice      = slice[slice.index(after: cmdIdx)...]

            if cmd == "m" {
                current.apply(params: params)
            }
            // every other CSI: silently consumed
        }

        return (result, current)
    }
}

/// Mutable accumulator for the open SGR state. Per-call value semantics so
/// streaming chunks can resume seamlessly.
public struct SGRState: Sendable, Equatable {
    public var foreground: Color? = nil
    public var background: Color? = nil
    public var bold = false
    public var italic = false
    public var underline = false
    public var dim = false

    public init() {}

    func attributes() -> AttributeContainer {
        var c = AttributeContainer()
        if let foreground { c.foregroundColor = foreground }
        if let background { c.backgroundColor = background }
        var font: Font = .system(.body, design: .monospaced)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        c.font = font
        if underline { c.underlineStyle = .single }
        if dim { c.foregroundColor = (foreground ?? .primary).opacity(0.7) }
        return c
    }

    mutating func apply(params: String) {
        let codes = params.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0:
                self = .init()
            case 1: bold = true
            case 2: dim = true
            case 3: italic = true
            case 4: underline = true
            case 22: bold = false; dim = false
            case 23: italic = false
            case 24: underline = false
            case 30...37:
                foreground = Self.ansi16(code - 30, bright: false)
            case 38:
                if i + 1 < codes.count {
                    if codes[i + 1] == 5, i + 2 < codes.count {
                        foreground = Self.ansi256(codes[i + 2]); i += 2
                    } else if codes[i + 1] == 2, i + 4 < codes.count {
                        foreground = Color(
                            red:   Double(codes[i + 2]) / 255,
                            green: Double(codes[i + 3]) / 255,
                            blue:  Double(codes[i + 4]) / 255
                        )
                        i += 4
                    }
                }
            case 39: foreground = nil
            case 40...47:
                background = Self.ansi16(code - 40, bright: false)
            case 48:
                if i + 1 < codes.count, codes[i + 1] == 5, i + 2 < codes.count {
                    background = Self.ansi256(codes[i + 2]); i += 2
                } else if i + 1 < codes.count, codes[i + 1] == 2, i + 4 < codes.count {
                    background = Color(
                        red:   Double(codes[i + 2]) / 255,
                        green: Double(codes[i + 3]) / 255,
                        blue:  Double(codes[i + 4]) / 255
                    )
                    i += 4
                }
            case 49: background = nil
            case 90...97:
                foreground = Self.ansi16(code - 90, bright: true)
            case 100...107:
                background = Self.ansi16(code - 100, bright: true)
            default: break
            }
            i += 1
        }
    }

    private static func ansi16(_ index: Int, bright: Bool) -> Color {
        let theme = TerminalTheme.current
        let table = bright ? theme.ansiBright : theme.ansiNormal
        return table[max(0, min(index, table.count - 1))]
    }

    private static func ansi256(_ index: Int) -> Color {
        switch index {
        case 0...7:   return ansi16(index, bright: false)
        case 8...15:  return ansi16(index - 8, bright: true)
        case 16...231:
            let i = index - 16
            let r = (i / 36) * 51
            let g = ((i % 36) / 6) * 51
            let b = (i % 6) * 51
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case 232...255:
            let v = Double((index - 232) * 10 + 8) / 255
            return Color(red: v, green: v, blue: v)
        default: return .white
        }
    }
}

// MARK: - Terminal theme

/// A named 16-color ANSI palette for block-mode rendering.
public struct TerminalTheme: Sendable {
    public let name: String
    public let background: Color
    public let foreground: Color
    public let ansiNormal: [Color]   // indices 0-7
    public let ansiBright: [Color]   // indices 8-15 (bold / bright)

    /// Currently selected theme, read from UserDefaults.
    public static var current: TerminalTheme {
        let name = UserDefaults.standard.string(forKey: "terminalTheme") ?? "Dark"
        return all.first { $0.name == name } ?? .dark
    }

    public static let all: [TerminalTheme] = [.dark, .light, .solarizedDark, .dracula]

    // MARK: Presets

    public static let dark = TerminalTheme(
        name: "Dark",
        background: Color(red: 0.071, green: 0.071, blue: 0.090),
        foreground: Color(red: 0.941, green: 0.941, blue: 0.961),
        ansiNormal: [
            Color(red: 0.110, green: 0.110, blue: 0.129),
            Color(red: 1.000, green: 0.302, blue: 0.427),
            Color(red: 0.239, green: 0.839, blue: 0.549),
            Color(red: 0.961, green: 0.651, blue: 0.137),
            Color(red: 0.302, green: 0.686, blue: 1.000),
            Color(red: 0.608, green: 0.365, blue: 0.898),
            Color(red: 0.000, green: 0.961, blue: 0.831),
            Color(red: 0.941, green: 0.941, blue: 0.961),
        ],
        ansiBright: [
            .gray,
            Color(red: 1.000, green: 0.522, blue: 0.580),
            Color(red: 0.408, green: 0.918, blue: 0.659),
            Color(red: 1.000, green: 0.804, blue: 0.341),
            Color(red: 0.541, green: 0.808, blue: 1.000),
            Color(red: 0.776, green: 0.578, blue: 0.965),
            Color(red: 0.341, green: 1.000, blue: 0.957),
            .white,
        ]
    )

    public static let light = TerminalTheme(
        name: "Light",
        background: Color(red: 0.980, green: 0.980, blue: 0.980),
        foreground: Color(red: 0.133, green: 0.133, blue: 0.133),
        ansiNormal: [
            Color(red: 0.200, green: 0.200, blue: 0.200),
            Color(red: 0.820, green: 0.098, blue: 0.216),
            Color(red: 0.110, green: 0.620, blue: 0.282),
            Color(red: 0.690, green: 0.490, blue: 0.000),
            Color(red: 0.149, green: 0.420, blue: 0.827),
            Color(red: 0.580, green: 0.200, blue: 0.710),
            Color(red: 0.000, green: 0.565, blue: 0.565),
            Color(red: 0.800, green: 0.800, blue: 0.800),
        ],
        ansiBright: [
            Color(red: 0.400, green: 0.400, blue: 0.400),
            Color(red: 0.937, green: 0.227, blue: 0.255),
            Color(red: 0.200, green: 0.780, blue: 0.349),
            Color(red: 0.851, green: 0.620, blue: 0.000),
            Color(red: 0.290, green: 0.565, blue: 0.886),
            Color(red: 0.773, green: 0.357, blue: 0.929),
            Color(red: 0.098, green: 0.729, blue: 0.729),
            Color(red: 0.133, green: 0.133, blue: 0.133),
        ]
    )

    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        background: Color(red: 0.000, green: 0.169, blue: 0.212),
        foreground: Color(red: 0.514, green: 0.580, blue: 0.588),
        ansiNormal: [
            Color(red: 0.027, green: 0.212, blue: 0.259),
            Color(red: 0.863, green: 0.196, blue: 0.184),
            Color(red: 0.522, green: 0.600, blue: 0.000),
            Color(red: 0.710, green: 0.537, blue: 0.000),
            Color(red: 0.149, green: 0.545, blue: 0.824),
            Color(red: 0.424, green: 0.443, blue: 0.769),
            Color(red: 0.165, green: 0.631, blue: 0.596),
            Color(red: 0.933, green: 0.910, blue: 0.835),
        ],
        ansiBright: [
            Color(red: 0.000, green: 0.169, blue: 0.212),
            Color(red: 0.796, green: 0.294, blue: 0.086),
            Color(red: 0.345, green: 0.431, blue: 0.459),
            Color(red: 0.396, green: 0.482, blue: 0.514),
            Color(red: 0.514, green: 0.580, blue: 0.588),
            Color(red: 0.576, green: 0.631, blue: 0.631),
            Color(red: 0.933, green: 0.910, blue: 0.835),
            Color(red: 0.992, green: 0.965, blue: 0.890),
        ]
    )

    public static let dracula = TerminalTheme(
        name: "Dracula",
        background: Color(red: 0.157, green: 0.165, blue: 0.212),
        foreground: Color(red: 0.973, green: 0.973, blue: 0.949),
        ansiNormal: [
            Color(red: 0.298, green: 0.306, blue: 0.424),
            Color(red: 1.000, green: 0.333, blue: 0.333),
            Color(red: 0.314, green: 0.980, blue: 0.482),
            Color(red: 0.949, green: 0.980, blue: 0.404),
            Color(red: 0.741, green: 0.576, blue: 0.976),
            Color(red: 1.000, green: 0.475, blue: 0.776),
            Color(red: 0.545, green: 0.914, blue: 0.992),
            Color(red: 0.973, green: 0.973, blue: 0.949),
        ],
        ansiBright: [
            Color(red: 0.420, green: 0.443, blue: 0.592),
            Color(red: 1.000, green: 0.573, blue: 0.573),
            Color(red: 0.573, green: 0.988, blue: 0.639),
            Color(red: 0.988, green: 1.000, blue: 0.651),
            Color(red: 0.843, green: 0.722, blue: 0.988),
            Color(red: 1.000, green: 0.647, blue: 0.843),
            Color(red: 0.722, green: 0.953, blue: 0.996),
            .white,
        ]
    )
}

// MARK: - TUI heuristic

public enum TUIDetector {
    /// Returns true if the data fragment looks like a TUI / alt-screen
    /// program took over the terminal. Used to escalate from Block to Raw
    /// mode. Heuristic, intentionally conservative.
    public static func shouldEscalate(to data: Data) -> Bool {
        guard let s = String(data: data, encoding: .utf8) else { return false }
        // \x1b[?1049h = enter alternate screen buffer (xterm)
        // \x1b[?47h   = older alt screen
        // \x1b[?1h    = application cursor keys
        return s.contains("\u{1B}[?1049h")
            || s.contains("\u{1B}[?47h")
            || s.contains("\u{1B}[?1h")
    }
}
