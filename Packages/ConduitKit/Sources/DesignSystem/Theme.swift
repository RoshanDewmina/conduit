import SwiftUI

/// Conduit uses the system color palette by user request ("default Swift").
/// Theme provides only enough vocabulary to keep typography and layout
/// consistent without imposing a custom visual identity.
public struct ConduitTheme: Sendable {
    public var monoFont: Font
    public var monoFontUI: Font
    public var smallMono: Font
    public var headlineColor: Color
    public var subtleColor: Color
    public var successColor: Color
    public var warningColor: Color
    public var errorColor: Color
    public var accentColor: Color
    public var inputBackground: Color

    public init(
        monoFont: Font   = .system(.body, design: .monospaced),
        monoFontUI: Font = .system(.callout, design: .monospaced),
        smallMono: Font  = .system(.footnote, design: .monospaced),
        headlineColor: Color = .primary,
        subtleColor: Color   = .secondary,
        successColor: Color  = .green,
        warningColor: Color  = .orange,
        errorColor: Color    = .red,
        accentColor: Color   = .accentColor,
        inputBackground: Color = Self.platformBackground
    ) {
        self.monoFont = monoFont
        self.monoFontUI = monoFontUI
        self.smallMono = smallMono
        self.headlineColor = headlineColor
        self.subtleColor = subtleColor
        self.successColor = successColor
        self.warningColor = warningColor
        self.errorColor = errorColor
        self.accentColor = accentColor
        self.inputBackground = inputBackground
    }

    public static let `default` = ConduitTheme()

    public static var platformBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.1)
        #endif
    }
}

private struct ConduitThemeKey: EnvironmentKey {
    static let defaultValue: ConduitTheme = .default
}

public extension EnvironmentValues {
    var conduitTheme: ConduitTheme {
        get { self[ConduitThemeKey.self] }
        set { self[ConduitThemeKey.self] = newValue }
    }
}

/// Map an approval risk to a visual tint.
public enum RiskTint {
    public static func color(for risk: Int) -> Color {
        switch risk {
        case ...0:  .green
        case 1:     .yellow
        case 2:     .orange
        default:    .red
        }
    }
}
