import Foundation
import CoreText

/// Registers the bundled editorial, UI, and technical typefaces at app launch.
@MainActor
public enum DesignSystemFonts {
    private static var didRegister = false

    public static func register() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "BricolageGrotesque",
            "HankenGrotesk",
            "InstrumentSerif-Regular",
            "InstrumentSerif-Italic",
            "JetBrainsMono",
        ]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
