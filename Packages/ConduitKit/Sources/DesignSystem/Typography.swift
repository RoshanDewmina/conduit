import SwiftUI

public extension Font {
    /// SF Pro (system) at a given text style with weight override.
    static func dsSans(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// System monospaced at a given text style with weight override.
    static func dsMono(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}
