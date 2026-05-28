// Tier 1.5.3 — Customizable shortcut bar.
//
// `ShortcutKey` enumerates every key the SessionFeature `KeyboardAccessoryRail`
// can render. `ShortcutKeyOrder` persists the user's chosen order in
// UserDefaults. Both types live in DesignSystem so the rail (in SessionFeature)
// and the Settings reorder UI (in SettingsFeature) can share them without
// either feature depending on the other.

import Foundation

/// One key the user can pin to the shortcut bar. Add a case here + a row in
/// `RailViewController.makeButton(for:)` to register a new key — it'll appear
/// in the Settings reorder picker automatically.
public enum ShortcutKey: String, CaseIterable, Hashable, Sendable, Identifiable {
    case esc, tab
    case ctrl                  // sticky-Ctrl latch button
    case tmuxPrefix            // Ctrl-B
    case ctrlC, ctrlD, ctrlZ
    case up, down, left, right
    case pipe, semi, slash, dollar, andAnd

    public var id: String { rawValue }

    /// Label shown on the button face.
    public var label: String {
        switch self {
        case .esc: "Esc"
        case .tab: "Tab"
        case .ctrl: "Ctrl"
        case .tmuxPrefix: "Tmux"
        case .ctrlC: "C"
        case .ctrlD: "D"
        case .ctrlZ: "Z"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .pipe: "|"
        case .semi: ";"
        case .slash: "/"
        case .dollar: "$"
        case .andAnd: "&&"
        }
    }

    /// Long descriptive name used in the Settings reorder list.
    public var descriptiveName: String {
        switch self {
        case .ctrlC: "Ctrl-C"
        case .ctrlD: "Ctrl-D"
        case .ctrlZ: "Ctrl-Z"
        case .tmuxPrefix: "Tmux prefix (Ctrl-B)"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        case .pipe: "Pipe"
        case .semi: "Semicolon"
        case .slash: "Slash"
        case .dollar: "Dollar"
        case .andAnd: "AND-AND"
        default: label
        }
    }
}

/// Default key order shown when the user hasn't customized it. Mirrors the
/// previous hardcoded layout so existing users see no change.
public let kDefaultShortcutKeyOrder: [ShortcutKey] = [
    .esc, .tab, .ctrl, .tmuxPrefix,
    .ctrlC, .ctrlD, .ctrlZ,
    .up, .down, .left, .right,
    .pipe, .semi, .slash, .dollar, .andAnd,
]

/// UserDefaults storage. Typed helpers so neither the rail constructor nor
/// the Settings UI has to know the encoding.
public enum ShortcutKeyOrder {
    public static let defaultsKey = "conduitShortcutBarOrder"

    public static func load() -> [ShortcutKey] {
        guard let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] else {
            return kDefaultShortcutKeyOrder
        }
        let decoded = raw.compactMap(ShortcutKey.init(rawValue:))
        return decoded.isEmpty ? kDefaultShortcutKeyOrder : decoded
    }

    public static func save(_ keys: [ShortcutKey]) {
        UserDefaults.standard.set(keys.map(\.rawValue), forKey: defaultsKey)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
