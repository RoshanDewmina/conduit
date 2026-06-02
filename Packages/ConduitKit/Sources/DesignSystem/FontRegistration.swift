import Foundation
import CoreText

/// Registers the bundled BLOCKS fonts — Chakra Petch (display) + Fira Code (mono) — at app launch.
/// Call once from ConduitApp.init() before any view renders.
@MainActor
public enum DesignSystemFonts {
    private static var didRegister = false

    public static func register() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "ChakraPetch-Regular",
            "ChakraPetch-Medium",
            "ChakraPetch-SemiBold",
            "ChakraPetch-Bold",
            "FiraCode-Regular",
            "FiraCode-Medium",
            "FiraCode-SemiBold",
            "FiraCode-Bold",
        ]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
