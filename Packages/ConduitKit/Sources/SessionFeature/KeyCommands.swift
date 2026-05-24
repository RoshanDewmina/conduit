#if os(iOS)
import UIKit

/// Keyboard shortcuts that map hardware key combos to PTY byte sequences
/// (or to app-level actions when `bytes` is empty).
public enum ShellKeyCommand {

    /// A single hardware-key → PTY-byte-sequence mapping.
    public struct KeyBinding: Sendable {
        /// The character string passed to `UIKeyCommand.input`.
        public let input: String
        /// The required modifier mask.
        public let modifiers: UIKeyModifierFlags
        /// Human-readable title shown in the discoverability HUD.
        public let title: String
        /// Bytes to write to the PTY. Empty means the action is handled
        /// at the app / navigation level (e.g. Cmd-T for new session).
        public let bytes: [UInt8]

        public init(
            input: String,
            modifiers: UIKeyModifierFlags,
            title: String,
            bytes: [UInt8]
        ) {
            self.input = input
            self.modifiers = modifiers
            self.title = title
            self.bytes = bytes
        }
    }

    /// All registered shell key bindings.
    public static let all: [KeyBinding] = [
        // --- Ctrl combos ---
        KeyBinding(input: "a", modifiers: .control, title: "Ctrl-A (line start)",  bytes: [0x01]),
        KeyBinding(input: "e", modifiers: .control, title: "Ctrl-E (line end)",    bytes: [0x05]),
        KeyBinding(input: "c", modifiers: .control, title: "Ctrl-C (interrupt)",   bytes: [0x03]),
        KeyBinding(input: "d", modifiers: .control, title: "Ctrl-D (EOF)",         bytes: [0x04]),
        KeyBinding(input: "l", modifiers: .control, title: "Ctrl-L (clear)",       bytes: [0x0C]),
        KeyBinding(input: "z", modifiers: .control, title: "Ctrl-Z (suspend)",     bytes: [0x1A]),
        KeyBinding(input: "u", modifiers: .control, title: "Ctrl-U (kill line)",   bytes: [0x15]),
        KeyBinding(input: "w", modifiers: .control, title: "Ctrl-W (erase word)",  bytes: [0x17]),

        // --- Cmd combos ---
        // Cmd-K: clear screen (same byte as Ctrl-L)
        KeyBinding(input: "k", modifiers: .command, title: "Cmd-K (clear)",        bytes: [0x0C]),
        // Cmd-T: new session — handled at app level, no PTY bytes
        KeyBinding(input: "t", modifiers: .command, title: "Cmd-T (new session)",  bytes: []),
        // Cmd-F: focus search — handled at app level
        KeyBinding(input: "f", modifiers: .command, title: "Cmd-F (search)",       bytes: []),
        // Cmd-/: help — handled at app level
        KeyBinding(input: "/", modifiers: .command, title: "Cmd-/ (help)",         bytes: []),
    ]

    /// Returns the PTY bytes for a given input + modifier combo, or `nil` if
    /// the binding is unknown or is an app-level action with no PTY bytes.
    public static func bytes(
        for input: String,
        modifiers: UIKeyModifierFlags
    ) -> [UInt8]? {
        guard let binding = all.first(where: {
            $0.input == input && $0.modifiers == modifiers
        }) else { return nil }
        return binding.bytes.isEmpty ? nil : binding.bytes
    }
}
#endif
