#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

public struct TerminalSettingsView: View {
    @AppStorage("terminalFontSize")       private var fontSize: Double = 13
    @AppStorage("terminalKeepAlive")      private var keepAlive: Int = 60
    @AppStorage("terminalPreventSleep")   private var preventSleep: Bool = true
    @AppStorage("terminalHapticFeedback") private var hapticFeedback: Bool = true
    @AppStorage("terminalScrollback")     private var scrollback: Int = 1000
    @AppStorage("terminalTheme")          private var themeName: String = "Dark"

    private let fontSizes: [(label: String, value: Double)] = [
        ("Small", 10), ("Medium", 12), ("Default", 13), ("Large", 15), ("XLarge", 18),
    ]
    private let keepAliveOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("30 sec", 30), ("60 sec", 60), ("2 min", 120),
    ]
    private let scrollbackOptions: [(label: String, value: Int)] = [
        ("500", 500), ("1 000", 1000), ("5 000", 5000), ("Unlimited", 0),
    ]
    private let themes = ["Dark", "Light", "Solarized Dark", "Dracula"]

    public init() {}

    @Environment(\.conduitTokens) private var t

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Display
                    sectionHead("Display")
                    settingsCard {
                        pickerRow(label: "Font Size", options: fontSizes.map { ($0.label, $0.value) }, value: $fontSize)
                        cardDivider
                        stringPickerRow(label: "Theme", options: themes, value: $themeName)
                        cardDivider
                        pickerRow(label: "Scrollback", options: scrollbackOptions.map { ($0.label, $0.value) }, value: $scrollback)
                    }
                    .padding(.bottom, 16)

                    // ── Behaviour
                    sectionHead("Behaviour")
                    settingsCard {
                        pickerRow(label: "Keep-Alive", options: keepAliveOptions.map { ($0.label, $0.value) }, value: $keepAlive)
                        cardDivider
                        toggleRow(label: "Prevent Screen Sleep", isOn: $preventSleep)
                        cardDivider
                        toggleRow(label: "Haptic Feedback on Keys", isOn: $hapticFeedback)
                    }
                    .padding(.bottom, 16)

                    // ── Shortcut Bar
                    sectionHead("Shortcut Bar")
                    settingsCard {
                        NavigationLink {
                            ShortcutBarEditor()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Customize keyboard rail")
                                        .font(.dsSansPt(15))
                                        .foregroundStyle(t.text)
                                    Text("Reorder or hide keys above the keyboard.")
                                        .font(.dsSansPt(12))
                                        .foregroundStyle(t.text3)
                                }
                                Spacer()
                                DSIconView(.chevronRight, size: 14, color: t.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 16)

                    // ── Shell Integration
                    sectionHead("Shell Integration")
                    settingsCard {
                        ShellIntegrationDiagnosticsRow()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 16)

                    Text("Font size and theme changes take effect in the next session.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    #if DEBUG
                    sectionHead("Debug")
                    settingsCard {
                        DebugProBypassToggle()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 16)
                    #endif

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Layout helpers

    private func sectionHead(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 0.5).padding(.horizontal, 16)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(t.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pickerRow<V: Hashable>(label: String, options: [(String, V)], value: Binding<V>) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
            Spacer()
            Picker("", selection: value) {
                ForEach(options, id: \.0) { item in
                    Text(item.0).tag(item.1)
                }
            }
            .pickerStyle(.menu)
            .tint(t.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stringPickerRow(label: String, options: [String], value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
            Spacer()
            Picker("", selection: value) {
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .tint(t.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        return stored > 0 ? stored : 13
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
