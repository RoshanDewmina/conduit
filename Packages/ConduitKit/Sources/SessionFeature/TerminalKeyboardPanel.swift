#if os(iOS)
import SwiftUI
import ConduitCore
import TerminalEngine
import DesignSystem

/// The expandable terminal keyboard. Replaces the system keyboard with a full
/// key grid plus a bottom tab bar (keys / snippets / history / theme / help)
/// and an ABC button that restores the QWERTY keyboard.
///
/// Sends keys through `onBytes` — the same closure the collapsed
/// `KeyboardAccessoryRail` uses — so it works identically in block, executing
/// and raw/TUI modes. The Ctrl latch is the shared `ctrlLatched` binding so a
/// latch set on the rail still applies here; the Alt/Meta latch is panel-local.
public struct TerminalKeyboardPanel: View {

    public enum Tab: String, CaseIterable, Identifiable {
        case keys, snippets, history, theme, help
        public var id: String { rawValue }
        var label: String {
            switch self {
            case .keys: "KEYS"
            case .snippets: "SNIP"
            case .history: "HIST"
            case .theme: "THEME"
            case .help: "HELP"
            }
        }
        var symbol: String {
            switch self {
            case .keys: "square.grid.3x3"
            case .snippets: "curlybraces"
            case .history: "clock.arrow.circlepath"
            case .theme: "paintpalette"
            case .help: "questionmark.circle"
            }
        }
    }

    @Binding private var ctrlLatched: Bool
    @Binding private var selectedTab: Tab
    private let onBytes: ([UInt8]) -> Void
    private let onPaste: () -> Void
    private let onDismiss: () -> Void
    private let commandHistory: [String]
    private let onRunHistory: (String) -> Void
    private let snippets: [Snippet]
    private let onInsertSnippet: (Snippet) -> Void

    @State private var metaLatched = false
    @AppStorage("terminalTheme")          private var themeName: String = "Dark"
    @AppStorage("gestureSwipeAlternates") private var gestureSwipeAlternates: Bool = true

    @Environment(\.conduitTokens) private var t

    public init(
        selectedTab: Binding<Tab>,
        ctrlLatched: Binding<Bool>,
        commandHistory: [String] = [],
        snippets: [Snippet] = [],
        onBytes: @escaping ([UInt8]) -> Void,
        onPaste: @escaping () -> Void,
        onRunHistory: @escaping (String) -> Void = { _ in },
        onInsertSnippet: @escaping (Snippet) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self._ctrlLatched = ctrlLatched
        self.commandHistory = commandHistory
        self.snippets = snippets
        self.onBytes = onBytes
        self.onPaste = onPaste
        self.onRunHistory = onRunHistory
        self.onInsertSnippet = onInsertSnippet
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag handle — swipe down here to collapse the panel (Gesture #4).
            dismissHandle
            tabBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabBar
        }
        .background(t.termBg)
    }

    // MARK: - Drag handle (swipe-down to dismiss, Gesture #4)

    private var dismissHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(t.termBorder)
                .frame(width: 36, height: 4)
            Spacer()
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    let dy = value.translation.height
                    let dx = value.translation.width
                    if dy > 40, abs(dy) > abs(dx) {
                        Haptics.light()
                        onDismiss()
                    }
                }
        )
    }

    // MARK: - Tab body

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .keys:     keysGrid
        case .snippets: snippetsList
        case .history:  historyList
        case .theme:    themeList
        case .help:     helpBody
        }
    }

    // MARK: Keys grid

    private var keysGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(TerminalKeyCatalog.allClusters) { cluster in
                    clusterSection(cluster)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func clusterSection(_ cluster: KeyCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cluster.title)
                .font(.dsMonoPt(9, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.termText.opacity(0.45))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: cluster.columns
                ),
                spacing: 8
            ) {
                ForEach(cluster.keys) { key in
                    keyButton(key)
                }
            }
        }
    }

    // MARK: Key button (Gesture #3 — swipe-up alternates)

    @ViewBuilder
    private func keyButton(_ key: GridKey) -> some View {
        if key.swipeUp != nil && gestureSwipeAlternates {
            keyButtonBase(key)
                // highPriorityGesture: if finger moves 20pt+ the drag wins and
                // cancels the button tap; short taps fall through to Button.
                .highPriorityGesture(swipeUpGesture(for: key))
        } else {
            keyButtonBase(key)
        }
    }

    private func keyButtonBase(_ key: GridKey) -> some View {
        let active = isLatchActive(key)
        return Button {
            press(key)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(key.label)
                    .font(.dsMonoPt(13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(keyForeground(key, active: active))
                    .frame(maxWidth: .infinity, minHeight: 40)
                // Superscript hint for keys that have a swipe-up alternate.
                if let alt = key.swipeUp, gestureSwipeAlternates {
                    Text(alt.label)
                        .font(.dsMonoPt(8, weight: .medium))
                        .foregroundStyle(t.termAccent.opacity(0.7))
                        .padding(.top, 3)
                        .padding(.trailing, 4)
                }
            }
            .background(active ? t.termAccent : t.termSurface2)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(active ? t.termAccent : t.termBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func swipeUpGesture(for key: GridKey) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard let alt = key.swipeUp, dy < -20, abs(dy) > abs(dx) else { return }
                onBytes(alt.bytes)
                Haptics.light()
            }
    }

    private func keyForeground(_ key: GridKey, active: Bool) -> Color {
        if active { return t.termBg }
        return key.accent ? t.termAccent : t.termText
    }

    private func isLatchActive(_ key: GridKey) -> Bool {
        switch key.action {
        case .ctrlLatch: return ctrlLatched
        case .metaLatch: return metaLatched
        default: return false
        }
    }

    // MARK: Snippets

    @ViewBuilder
    private var snippetsList: some View {
        if snippets.isEmpty {
            emptyState("No snippets yet", symbol: "curlybraces")
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(snippets) { snippet in
                        Button {
                            Haptics.light()
                            onInsertSnippet(snippet)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snippet.name)
                                    .font(.dsMonoPt(13, weight: .medium))
                                    .foregroundStyle(t.termText)
                                Text(snippet.body)
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.termText.opacity(0.5))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(t.termSurface2)
                            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        if commandHistory.isEmpty {
            emptyState("No command history", symbol: "clock")
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(commandHistory.suffix(60).reversed().enumerated()), id: \.offset) { _, cmd in
                        Button {
                            Haptics.light()
                            onRunHistory(cmd)
                        } label: {
                            Text(cmd)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.termText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(t.termSurface2)
                                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: Theme

    private var themeList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(TerminalTheme.all, id: \.name) { theme in
                    Button {
                        Haptics.selection()
                        themeName = theme.name
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.background)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text("$")
                                        .font(.dsMonoPt(13, weight: .medium))
                                        .foregroundStyle(theme.foreground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(t.termBorder, lineWidth: 1)
                                )
                            Text(theme.name)
                                .font(.dsMonoPt(13, weight: .medium))
                                .foregroundStyle(t.termText)
                            Spacer()
                            if theme.name == themeName {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(t.termAccent)
                            }
                        }
                        .padding(10)
                        .background(t.termSurface2)
                        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    // MARK: Help

    private var helpBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                helpRow("ctrl", "Latch Ctrl — next key sent as Ctrl+key")
                helpRow("alt", "Latch Alt/Meta — ESC-prefixes the next key")
                helpRow("^C ^S ^Z", "Interrupt / pause output / suspend")
                helpRow("↑ ↓ ← →", "Arrow keys (history, cursor)")
                helpRow("home end", "Start / end of line")
                helpRow("pgUp pgDn", "Page up / down")
                helpRow("F1–F12", "Function keys")
                helpRow("paste", "Paste clipboard (bracketed)")
                helpRow("⌨ ABC", "Return to the system keyboard")
            }
            .padding(14)
        }
    }

    private func helpRow(_ key: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.termAccent)
                .frame(width: 84, alignment: .leading)
            Text(desc)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emptyState(_ message: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(t.termText.opacity(0.3))
            Text(message)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                tabBarButton(tab)
            }
            Divider().frame(height: 28).overlay(t.termBorder)
            abcButton
        }
        .frame(height: 56)
        .background(t.termSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(t.termBorder).frame(height: 1)
        }
    }

    private func tabBarButton(_ tab: Tab) -> some View {
        let isActive = tab == selectedTab
        return Button {
            Haptics.selection()
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17))
                Text(tab.label)
                    .font(.dsMonoPt(8, weight: .medium))
                    .tracking(0.5)
            }
            .foregroundStyle(isActive ? t.termAccent : t.termText.opacity(0.5))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var abcButton: some View {
        Button {
            Haptics.light()
            onDismiss()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "keyboard")
                    .font(.system(size: 17))
                Text("ABC")
                    .font(.dsMonoPt(8, weight: .medium))
                    .tracking(0.5)
            }
            .foregroundStyle(t.termText.opacity(0.8))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key dispatch

    private func press(_ key: GridKey) {
        switch key.action {
        case .ctrlLatch:
            ctrlLatched.toggle()
            Haptics.medium()
        case .metaLatch:
            metaLatched.toggle()
            Haptics.medium()
        case .paste:
            onPaste()
            Haptics.light()
        case .send(let bytes):
            var out = bytes
            if ctrlLatched, let first = out.first, isAlpha(first) {
                out[0] = first & 0x1F
                ctrlLatched = false
            }
            if metaLatched {
                out = [0x1B] + out
                metaLatched = false
            }
            onBytes(out)
            Haptics.light()
        }
    }

    private func isAlpha(_ b: UInt8) -> Bool {
        (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
    }
}
#endif
