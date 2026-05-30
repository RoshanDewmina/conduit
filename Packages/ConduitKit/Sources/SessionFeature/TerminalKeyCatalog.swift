#if os(iOS)
import Foundation

// MARK: - Terminal key catalog
//
// Single source of truth for the byte sequences emitted by both the collapsed
// `KeyboardAccessoryRail` and the expanded `TerminalKeyboardPanel`. Nav-key
// sequences mirror `HardwareInputHandler` exactly so a software key and the
// equivalent hardware key produce identical bytes.

/// A keystroke the expanded panel can emit. `swipeUp` is **reserved** for the
/// later gesture phase (per-key swipe alternates) and is unused today.
public struct GridKey: Identifiable, Hashable, Sendable {

    /// What pressing the key does. Modelled explicitly rather than via empty
    /// byte arrays so latch/paste keys can't be mistaken for "send nothing".
    public enum Action: Hashable, Sendable {
        case send([UInt8])   // write these bytes to the PTY
        case ctrlLatch       // toggle the shared Ctrl latch
        case metaLatch       // toggle the Alt/Meta latch (ESC-prefixes next key)
        case paste           // paste the clipboard via bracketed paste
    }

    public let id: String
    public let label: String
    public let action: Action
    public var accent: Bool
    public var wide: Bool
    /// Reserved for the gesture phase (swipe-up alternate). Unused in phase 1.
    public var swipeUp: KeyStroke?

    public init(
        id: String,
        label: String,
        action: Action,
        accent: Bool = false,
        wide: Bool = false,
        swipeUp: KeyStroke? = nil
    ) {
        self.id = id
        self.label = label
        self.action = action
        self.accent = accent
        self.wide = wide
        self.swipeUp = swipeUp
    }

    /// Convenience for the common "send literal bytes" key.
    public static func send(
        _ id: String,
        _ label: String,
        _ bytes: [UInt8],
        accent: Bool = false,
        wide: Bool = false
    ) -> GridKey {
        GridKey(id: id, label: label, action: .send(bytes), accent: accent, wide: wide)
    }
}

/// A label + bytes pair. Used for the reserved `swipeUp` alternate.
public struct KeyStroke: Hashable, Sendable {
    public let label: String
    public let bytes: [UInt8]
    public init(label: String, bytes: [UInt8]) {
        self.label = label
        self.bytes = bytes
    }
}

/// A titled group of keys rendered as one section in the grid tab.
public struct KeyCluster: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let keys: [GridKey]
    /// Number of columns to lay this cluster out in (symbols are denser).
    public let columns: Int
    public init(id: String, title: String, keys: [GridKey], columns: Int = 4) {
        self.id = id
        self.title = title
        self.keys = keys
        self.columns = columns
    }
}

public enum TerminalKeyCatalog {

    // MARK: Byte sequences (centralised — also consumed by the UIKit rail)

    public enum Bytes {
        public static let esc: [UInt8]   = [0x1B]
        public static let tab: [UInt8]   = [0x09]
        public static let up: [UInt8]    = [0x1B, 0x5B, 0x41]          // ESC [ A
        public static let down: [UInt8]  = [0x1B, 0x5B, 0x42]          // ESC [ B
        public static let right: [UInt8] = [0x1B, 0x5B, 0x43]          // ESC [ C
        public static let left: [UInt8]  = [0x1B, 0x5B, 0x44]          // ESC [ D

        // Navigation — identical to HardwareInputHandler.
        public static let home: [UInt8]   = [0x1B, 0x5B, 0x48]         // ESC [ H
        public static let end: [UInt8]     = [0x1B, 0x5B, 0x46]        // ESC [ F
        public static let pageUp: [UInt8]   = [0x1B, 0x5B, 0x35, 0x7E] // ESC [ 5 ~
        public static let pageDown: [UInt8] = [0x1B, 0x5B, 0x36, 0x7E] // ESC [ 6 ~
        public static let insert: [UInt8]   = [0x1B, 0x5B, 0x32, 0x7E] // ESC [ 2 ~
        public static let forwardDelete: [UInt8] = [0x1B, 0x5B, 0x33, 0x7E] // ESC [ 3 ~

        /// Ctrl+letter control code (0x01–0x1A).
        public static func ctrl(_ ascii: UInt8) -> [UInt8] { [ascii & 0x1F] }

        public static func ascii(_ ch: Character) -> [UInt8] { Array(String(ch).utf8) }

        /// Function-key sequences (xterm).
        public static let functionKeys: [[UInt8]] = [
            [0x1B, 0x4F, 0x50],                   // F1  ESC O P
            [0x1B, 0x4F, 0x51],                   // F2  ESC O Q
            [0x1B, 0x4F, 0x52],                   // F3  ESC O R
            [0x1B, 0x4F, 0x53],                   // F4  ESC O S
            [0x1B, 0x5B, 0x31, 0x35, 0x7E],       // F5  ESC [ 1 5 ~
            [0x1B, 0x5B, 0x31, 0x37, 0x7E],       // F6  ESC [ 1 7 ~
            [0x1B, 0x5B, 0x31, 0x38, 0x7E],       // F7  ESC [ 1 8 ~
            [0x1B, 0x5B, 0x31, 0x39, 0x7E],       // F8  ESC [ 1 9 ~
            [0x1B, 0x5B, 0x32, 0x30, 0x7E],       // F9  ESC [ 2 0 ~
            [0x1B, 0x5B, 0x32, 0x31, 0x7E],       // F10 ESC [ 2 1 ~
            [0x1B, 0x5B, 0x32, 0x33, 0x7E],       // F11 ESC [ 2 3 ~
            [0x1B, 0x5B, 0x32, 0x34, 0x7E],       // F12 ESC [ 2 4 ~
        ]
    }

    // MARK: Clusters (mirror the reference screenshots)

    /// Control + modifier cluster.
    public static let control = KeyCluster(
        id: "control",
        title: "CONTROL",
        keys: [
            .send("ctrlC", "^C", Bytes.ctrl(UInt8(ascii: "c")), accent: true),
            .send("ctrlI", "^I", Bytes.tab),
            .send("ctrlS", "^S", Bytes.ctrl(UInt8(ascii: "s"))),
            .send("ctrlZ", "^Z", Bytes.ctrl(UInt8(ascii: "z"))),
            .send("esc", "esc", Bytes.esc),
            .send("tab", "tab", Bytes.tab),
            GridKey(id: "ctrl", label: "ctrl", action: .ctrlLatch),
            GridKey(id: "alt", label: "alt", action: .metaLatch),
        ]
    )

    /// Navigation cluster: paging + arrows.
    public static let navigation = KeyCluster(
        id: "navigation",
        title: "NAVIGATION",
        keys: [
            .send("home", "home", Bytes.home),
            .send("pgUp", "pgUp", Bytes.pageUp),
            .send("pgDn", "pgDn", Bytes.pageDown),
            .send("end", "end", Bytes.end),
            .send("up", "↑", Bytes.up),
            .send("down", "↓", Bytes.down),
            .send("left", "←", Bytes.left),
            .send("right", "→", Bytes.right),
        ]
    )

    /// Action cluster: paste / delete / insert.
    public static let actions = KeyCluster(
        id: "actions",
        title: "EDIT",
        keys: [
            GridKey(id: "paste", label: "paste", action: .paste, wide: true),
            .send("del", "del", Bytes.forwardDelete),
            .send("ins", "ins", Bytes.insert),
        ],
        columns: 3
    )

    /// Symbol cluster — dense grid.
    ///
    /// Swipe-up alternates (Phase 2 gestures):
    ///   "-" → "_"   (dash → underscore)
    ///   "/" → "\"   (slash → backslash)
    ///   "~" → "`"   (tilde → backtick)
    ///   "=" → "+"   (equals → plus)
    ///   ";" → ":"   (semicolon → colon)
    ///   "!" → "?"   (bang → question mark)
    public static let symbols: KeyCluster = {
        let swipeUps: [Character: KeyStroke] = [
            "-": KeyStroke(label: "_",  bytes: [0x5f]),
            "/": KeyStroke(label: "\\", bytes: [0x5c]),
            "~": KeyStroke(label: "`",  bytes: [0x60]),
            "=": KeyStroke(label: "+",  bytes: [0x2b]),
            ";": KeyStroke(label: ":",  bytes: [0x3a]),
            "!": KeyStroke(label: "?",  bytes: [0x3f]),
        ]
        let chars: [Character] = [
            "~", "-", "=", ":", ";", "!", "*", "$",
            "%", "^", "<", ">", "(", ")", "{", "}",
            "[", "]", "@", "/", "|",
        ]
        return KeyCluster(
            id: "symbols",
            title: "SYMBOLS",
            keys: chars.map { ch in
                GridKey(
                    id: "sym-\(ch)",
                    label: String(ch),
                    action: .send(Bytes.ascii(ch)),
                    swipeUp: swipeUps[ch]
                )
            },
            columns: 8
        )
    }()

    /// Function-key row F1–F12.
    public static let functionRow = KeyCluster(
        id: "function",
        title: "FUNCTION",
        keys: Bytes.functionKeys.enumerated().map { idx, bytes in
            GridKey(id: "f\(idx + 1)", label: "F\(idx + 1)", action: .send(bytes))
        },
        columns: 6
    )

    /// Every cluster, top-to-bottom, as shown in the expanded grid tab.
    public static let allClusters: [KeyCluster] = [
        control, navigation, actions, symbols, functionRow,
    ]
}
#endif
