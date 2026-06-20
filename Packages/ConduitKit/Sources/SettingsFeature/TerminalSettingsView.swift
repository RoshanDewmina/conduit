#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

public struct TerminalSettingsView: View {
    @AppStorage("terminalFontSize")         private var fontSize: Double = 11
    @AppStorage("terminalKeepAlive")        private var keepAlive: Int = 60
    @AppStorage("terminalPreventSleep")     private var preventSleep: Bool = true
    @AppStorage("terminalHapticFeedback")   private var hapticFeedback: Bool = true
    @AppStorage("terminalScrollback")       private var scrollback: Int = 1000
    @AppStorage("terminalTheme")            private var themeName: String = "Dark"

    @AppStorage("gestureTrackpadEnabled")   private var gestureTrackpadEnabled: Bool = true
    @AppStorage("gestureDoubleTapTab")      private var gestureDoubleTapTab: Bool = true
    @AppStorage("gestureSwipeAlternates")   private var gestureSwipeAlternates: Bool = true
    @AppStorage("gestureCursorSensitivity") private var gestureCursorSensitivity: Double = 12

    private let fontSizes: [(label: String, value: Double)] = [
        ("Small", 10), ("Default", 11), ("Medium", 13), ("Large", 15), ("XLarge", 18),
    ]
    private let keepAliveOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("30 sec", 30), ("60 sec", 60), ("2 min", 120),
    ]
    private let scrollbackOptions: [(label: String, value: Int)] = [
        ("500", 500), ("1 000", 1000), ("5 000", 5000), ("Unlimited", 0),
    ]
    private let themes = ["Dark", "Light", "Solarized Dark", "Dracula"]
    // Low=18 pt dead-zone (least sensitive), Medium=12, High=8 (most sensitive).
    private let sensitivityOptions: [(label: String, value: Double)] = [
        ("Low", 18), ("Medium", 12), ("High", 8),
    ]

    public init() {}

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("terminal", onBack: { dismiss() })

                    // ── Display
                    sectionHead("DISPLAY")
                    settingsCard {
                        menuRow(label: "Font Size", options: fontSizes.map { ($0.label, $0.value) }, value: $fontSize, mono: true)
                        cardDivider
                        menuRow(label: "Theme", options: themes.map { ($0, $0) }, value: $themeName)
                        cardDivider
                        menuRow(label: "Scrollback", options: scrollbackOptions.map { ($0.label, $0.value) }, value: $scrollback, mono: true)
                    }

                    // ── Behaviour
                    sectionHead("BEHAVIOUR")
                    settingsCard {
                        menuRow(label: "Keep-Alive", options: keepAliveOptions.map { ($0.label, $0.value) }, value: $keepAlive)
                        cardDivider
                        toggleRow(label: "Prevent Screen Sleep", isOn: $preventSleep)
                        cardDivider
                        toggleRow(label: "Haptic Feedback on Keys", isOn: $hapticFeedback)
                    }

                    // ── Gestures
                    sectionHead("GESTURES")
                    settingsCard {
                        toggleRow(label: "Trackpad cursor (long-press + drag)", isOn: $gestureTrackpadEnabled)
                        cardDivider
                        toggleRow(label: "Double-tap for Tab", isOn: $gestureDoubleTapTab)
                        cardDivider
                        toggleRow(label: "Swipe up for alternate keys", isOn: $gestureSwipeAlternates)
                        cardDivider
                        menuRow(
                            label: "Cursor Sensitivity",
                            options: sensitivityOptions.map { ($0.label, $0.value) },
                            value: $gestureCursorSensitivity
                        )
                    }

                    // ── Shortcut Bar
                    sectionHead("SHORTCUT BAR")
                    settingsCard {
                        NavigationLink {
                            ShortcutBarEditor()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Customize keyboard rail")
                                        .font(.dsSansPt(16, weight: .medium))
                                        .foregroundStyle(t.text)
                                    Text("Reorder or hide keys above the keyboard.")
                                        .font(.dsSansPt(12))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(t.text4)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Shell Integration
                    sectionHead("SHELL INTEGRATION")
                    settingsCard {
                        ShellIntegrationDiagnosticsRow()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }

                    Text("Theme changes take effect in the next session.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                    #if DEBUG
                    sectionHead("DEBUG")
                    settingsCard {
                        DebugProBypassToggle()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    #endif

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Layout helpers

    private func sectionHead(_ label: String) -> some View {
        Text(label)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var cardDivider: some View {
        DSDivider(.soft, leadingInset: 16)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(16))
                .foregroundStyle(t.text)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(t.accent)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    /// A labeled row whose trailing control is a `Menu` showing the current value + chevron,
    /// replacing the stock `.pickerStyle(.menu)` look. `mono` renders the value in the mono face
    /// (used for numeric font-size / scrollback values).
    private func menuRow<V: Hashable>(
        label: String,
        options: [(String, V)],
        value: Binding<V>,
        mono: Bool = false
    ) -> some View {
        let current = options.first { $0.1 == value.wrappedValue }?.0 ?? ""
        return Menu {
            ForEach(options, id: \.0) { item in
                Button {
                    value.wrappedValue = item.1
                } label: {
                    if item.1 == value.wrappedValue {
                        Label(item.0, systemImage: "checkmark")
                    } else {
                        Text(item.0)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.dsSansPt(16))
                    .foregroundStyle(t.text)
                Spacer()
                Text(current)
                    .font(mono ? .dsMonoPt(13) : .dsSansPt(13))
                    .foregroundStyle(t.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}

// MARK: - Shell integration diagnostics row

private struct ShellIntegrationDiagnosticsRow: View {
    @AppStorage("conduitShellDetected")  private var shellDetected: String = ""
    @AppStorage("conduitMarkersActive")  private var markersActive: Bool = false
    @AppStorage("conduitLastMarkerTime") private var lastMarkerTime: Double = 0
    @Environment(\.conduitTokens) private var t

    private var isFish: Bool { shellDetected == "fish" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DSStatusDot(tone: isFish ? .warn : (markersActive ? .ok : .off))
                Text(statusLabel)
                    .font(.dsSansPt(14))
                    .foregroundStyle(markersActive && !isFish ? t.text : t.text3)
            }
            if !shellDetected.isEmpty {
                Text("Shell: \(shellDetected)")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }
            if isFish {
                Text("Fish shell detected — structured blocks unavailable. Terminal view works normally.")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            } else if lastMarkerTime > 0 {
                let d = Date(timeIntervalSince1970: lastMarkerTime)
                Text("Last marker: \(d.formatted(date: .omitted, time: .standard))")
                    .font(.dsSansPt(11))
                    .foregroundStyle(t.text4)
            }
        }
    }

    private var statusLabel: String {
        if isFish { return "Shell integration unavailable" }
        return markersActive ? "Shell integration active" : "Awaiting first prompt"
    }
}

// MARK: - Debug pro-bypass toggle

#if DEBUG
private struct DebugProBypassToggle: View {
    @State private var isOn: Bool = UserDefaults.standard.bool(forKey: "conduitDebugProBypass")
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Unlock all features (debug)", isOn: $isOn)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
                .tint(t.accent)
                .onChange(of: isOn) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "conduitDebugProBypass")
                }
            Text("Bypasses the StoreKit paywall. Only visible in Debug builds.")
                .font(.dsSansPt(12))
                .foregroundStyle(t.text3)
        }
    }
}
#endif

// MARK: - Shared terminal preference helpers

public enum TerminalPrefs {
    public static var fontSize: Double {
        let stored = UserDefaults.standard.double(forKey: "terminalFontSize")
        return stored > 0 ? stored : 11
    }

    public static var hapticFeedbackEnabled: Bool {
        let val = UserDefaults.standard.object(forKey: "terminalHapticFeedback")
        return val == nil ? true : UserDefaults.standard.bool(forKey: "terminalHapticFeedback")
    }

    public static var preventSleep: Bool {
        let val = UserDefaults.standard.object(forKey: "terminalPreventSleep")
        return val == nil ? true : UserDefaults.standard.bool(forKey: "terminalPreventSleep")
    }

    public static var keepAliveInterval: Int {
        let val = UserDefaults.standard.integer(forKey: "terminalKeepAlive")
        return val > 0 ? val : 60
    }

    public static var themeName: String {
        UserDefaults.standard.string(forKey: "terminalTheme") ?? "Dark"
    }
}

#endif
