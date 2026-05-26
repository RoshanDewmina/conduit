#if os(iOS)
import SwiftUI
import UIKit

public struct TerminalSettingsView: View {
    @AppStorage("terminalFontSize")    private var fontSize: Double = 13
    @AppStorage("terminalKeepAlive")   private var keepAlive: Int = 60
    @AppStorage("terminalPreventSleep") private var preventSleep: Bool = true
    @AppStorage("terminalHapticFeedback") private var hapticFeedback: Bool = true
    @AppStorage("terminalScrollback")  private var scrollback: Int = 1000
    @AppStorage("terminalTheme")       private var themeName: String = "Dark"

    private let fontSizes: [(label: String, value: Double)] = [
        ("Small",  10), ("Medium", 12), ("Default", 13),
        ("Large",  15), ("XLarge", 18),
    ]
    private let keepAliveOptions: [(label: String, value: Int)] = [
        ("Off", 0), ("30 sec", 30), ("60 sec", 60), ("2 min", 120),
    ]
    private let scrollbackOptions: [(label: String, value: Int)] = [
        ("500",    500), ("1 000", 1000), ("5 000", 5000), ("Unlimited", 0),
    ]
    private let themes = ["Dark", "Light", "Solarized Dark", "Dracula"]

    public init() {}

    public var body: some View {
        Form {
            Section("Display") {
                fontPicker
                themePicker
                scrollbackPicker
            }

            Section("Behaviour") {
                keepAlivePicker
                Toggle("Prevent Screen Sleep", isOn: $preventSleep)
                Toggle("Haptic Feedback on Keys", isOn: $hapticFeedback)
            }

            Section {
                Text("Font size and theme changes take effect in the next session.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Terminal")
    }

    // MARK: - Sub-pickers

    private var fontPicker: some View {
        Picker("Font Size", selection: $fontSize) {
            ForEach(fontSizes, id: \.value) { item in
                Text(item.label).tag(item.value)
            }
        }
    }

    private var themePicker: some View {
        Picker("Theme", selection: $themeName) {
            ForEach(themes, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private var keepAlivePicker: some View {
        Picker("Keep-Alive Interval", selection: $keepAlive) {
            ForEach(keepAliveOptions, id: \.value) { item in
                Text(item.label).tag(item.value)
            }
        }
    }

    private var scrollbackPicker: some View {
        Picker("Scrollback Lines", selection: $scrollback) {
            ForEach(scrollbackOptions, id: \.value) { item in
                Text(item.label).tag(item.value)
            }
        }
    }
}

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
