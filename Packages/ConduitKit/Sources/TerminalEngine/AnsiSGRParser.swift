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
        // Dark-themed default palette tuned for terminal readability.
        let normal: [Color] = [
            Color(red: 0.110, green: 0.110, blue: 0.129),     // black
            Color(red: 1.000, green: 0.302, blue: 0.427),     // red
            Color(red: 0.239, green: 0.839, blue: 0.549),     // green
            Color(red: 0.961, green: 0.651, blue: 0.137),     // yellow
            Color(red: 0.302, green: 0.686, blue: 1.000),     // blue
            Color(red: 0.608, green: 0.365, blue: 0.898),     // magenta
            Color(red: 0.000, green: 0.961, blue: 0.831),     // cyan
            Color(red: 0.941, green: 0.941, blue: 0.961),     // white
        ]
        let brightP: [Color] = [
            .gray,
            Color(red: 1.000, green: 0.522, blue: 0.580),
            Color(red: 0.408, green: 0.918, blue: 0.659),
            Color(red: 1.000, green: 0.804, blue: 0.341),
            Color(red: 0.541, green: 0.808, blue: 1.000),
            Color(red: 0.776, green: 0.578, blue: 0.965),
            Color(red: 0.341, green: 1.000, blue: 0.957),
            .white,
        ]
        let table = bright ? brightP : normal
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
