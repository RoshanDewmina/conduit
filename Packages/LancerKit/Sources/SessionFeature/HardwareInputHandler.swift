#if os(iOS)
import UIKit

/// Translates `UIKey` events from a hardware keyboard into PTY byte sequences.
///
/// Mapping rules
/// -------------
/// - **Ctrl + letter** : 0x01–0x1A (standard POSIX control codes)
/// - **Arrow keys (plain)** : VT100 sequences `\x1b[A/B/C/D`
/// - **Arrow keys + Option** : xterm extended sequences `\x1b[1;3A/B/C/D`
///   plus word-jump variants (`\x1bb` / `\x1bf`) for Option-←/→
/// - **Esc** : 0x1B
/// - **Tab** : 0x09
/// - **Return / Enter** : 0x0D
/// - **Backspace / Delete** : 0x7F
public enum HardwareInputHandler {

    // MARK: - Public API

    /// Maps a `UIKey` to the byte sequence that should be written to the PTY.
    /// Returns `nil` when the key press should not be forwarded (e.g. pure
    /// modifier keys, or keys handled entirely at the app / navigation level).
    @MainActor public static func bytes(for key: UIKey) -> [UInt8]? {
        let chars = key.charactersIgnoringModifiers
        let mods  = key.modifierFlags

        // --- Escape -------------------------------------------------------
        if key.keyCode == .keyboardEscape { return [0x1B] }

        // --- Tab ----------------------------------------------------------
        if key.keyCode == .keyboardTab    { return [0x09] }

        // --- Return / Enter -----------------------------------------------
        if key.keyCode == .keyboardReturnOrEnter ||
           key.keyCode == .keypadEnter             { return [0x0D] }

        // --- Backspace / Delete -------------------------------------------
        if key.keyCode == .keyboardDeleteOrBackspace { return [0x7F] }
        if key.keyCode == .keyboardDeleteForward     {
            // Forward-delete: \x1b[3~
            return [0x1B, 0x5B, 0x33, 0x7E]
        }

        // --- Arrow keys ---------------------------------------------------
        if let arrowBytes = arrowBytes(for: key) { return arrowBytes }

        // --- Ctrl + letter ------------------------------------------------
        if mods.contains(.control), let ctrlBytes = ctrlLetterBytes(chars: chars) {
            return ctrlBytes
        }

        // --- Option / Alt + printable ------------------------------------
        // Option key alone produces special Unicode glyphs on iOS keyboards.
        // We convert them to ESC-prefixed sequences for readline / vi usage.
        if mods.contains(.alternate) && !mods.contains(.control) {
            if let ascii = singleAscii(chars) {
                return [0x1B, ascii]
            }
        }

        return nil
    }

    // MARK: - Private helpers

    /// Ctrl+letter → 0x01–0x1A
    private static func ctrlLetterBytes(chars: String) -> [UInt8]? {
        guard let scalar = chars.unicodeScalars.first,
              scalar.value >= 96 && scalar.value <= 122   // a–z in lowercase
                || scalar.value >= 64 && scalar.value <= 90  // A–Z / @ etc.
        else {
            // Try direct lookup table for non-alpha Ctrl combos
            return nil
        }
        // Normalise to lowercase a–z range (0x61–0x7A) then subtract 0x60
        let lower = scalar.value >= 65 && scalar.value <= 90
            ? scalar.value + 32   // A-Z → a-z
            : scalar.value
        if lower >= 0x61 && lower <= 0x7A {
            return [UInt8(lower - 0x60)]
        }
        return nil
    }

    /// Arrow key → VT100 / xterm extended sequences.
    @MainActor private static func arrowBytes(for key: UIKey) -> [UInt8]? {
        let mods = key.modifierFlags
        let hasOption  = mods.contains(.alternate)
        let hasControl = mods.contains(.control)
        let hasShift   = mods.contains(.shift)

        switch key.keyCode {
        case .keyboardUpArrow:
            if hasOption  { return csi("1;3A") }
            if hasControl { return csi("1;5A") }
            if hasShift   { return csi("1;2A") }
            return [0x1B, 0x5B, 0x41]  // \x1b[A

        case .keyboardDownArrow:
            if hasOption  { return csi("1;3B") }
            if hasControl { return csi("1;5B") }
            if hasShift   { return csi("1;2B") }
            return [0x1B, 0x5B, 0x42]  // \x1b[B

        case .keyboardRightArrow:
            if hasOption  {
                // Word-jump forward: both common sequences for compatibility
                return [0x1B, 0x66]    // \x1bf  (readline)
            }
            if hasControl { return csi("1;5C") }
            if hasShift   { return csi("1;2C") }
            return [0x1B, 0x5B, 0x43]  // \x1b[C

        case .keyboardLeftArrow:
            if hasOption  {
                // Word-jump backward
                return [0x1B, 0x62]    // \x1bb  (readline)
            }
            if hasControl { return csi("1;5D") }
            if hasShift   { return csi("1;2D") }
            return [0x1B, 0x5B, 0x44]  // \x1b[D

        case .keyboardHome:
            return [0x1B, 0x5B, 0x48]  // \x1b[H
        case .keyboardEnd:
            return [0x1B, 0x5B, 0x46]  // \x1b[F
        case .keyboardPageUp:
            return [0x1B, 0x5B, 0x35, 0x7E]  // \x1b[5~
        case .keyboardPageDown:
            return [0x1B, 0x5B, 0x36, 0x7E]  // \x1b[6~

        default:
            return nil
        }
    }

    /// Builds a CSI sequence: ESC [ <suffix>
    private static func csi(_ suffix: String) -> [UInt8] {
        [0x1B, 0x5B] + suffix.utf8.map { UInt8($0) }
    }

    /// Returns the single ASCII code point if `str` contains exactly one
    /// ASCII-printable character.
    private static func singleAscii(_ str: String) -> UInt8? {
        guard str.count == 1,
              let scalar = str.unicodeScalars.first,
              scalar.value < 128
        else { return nil }
        return UInt8(scalar.value)
    }
}

// MARK: - Full Ctrl-A…Z lookup table (for documentation / exhaustiveness)
// The ctrlLetterBytes helper above handles all 26 letters algebraically,
// but the table below documents the mapping explicitly for readers.
//
// Ctrl-A → 0x01   Ctrl-B → 0x02   Ctrl-C → 0x03   Ctrl-D → 0x04
// Ctrl-E → 0x05   Ctrl-F → 0x06   Ctrl-G → 0x07   Ctrl-H → 0x08
// Ctrl-I → 0x09   Ctrl-J → 0x0A   Ctrl-K → 0x0B   Ctrl-L → 0x0C
// Ctrl-M → 0x0D   Ctrl-N → 0x0E   Ctrl-O → 0x0F   Ctrl-P → 0x10
// Ctrl-Q → 0x11   Ctrl-R → 0x12   Ctrl-S → 0x13   Ctrl-T → 0x14
// Ctrl-U → 0x15   Ctrl-V → 0x16   Ctrl-W → 0x17   Ctrl-X → 0x18
// Ctrl-Y → 0x19   Ctrl-Z → 0x1A

#endif
