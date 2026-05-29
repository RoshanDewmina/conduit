import Foundation
import CoreText

/// Registers the bundled Bricolage Grotesque, DM Sans, and Fragment Mono fonts at app launch.
/// Call once from ConduitApp.init() before any view renders.
@MainActor
public enum DesignSystemFonts {
    private static var didRegister = false

    public static func register() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "BricolageGrotesque-Regular",
            "BricolageGrotesque-Medium",
            "BricolageGrotesque-SemiBold",
            "BricolageGrotesque-Bold",
            "BricolageGrotesque-ExtraBold",
            "DMSans-Regular",
            "DMSans-Medium",
            "DMSans-SemiBold",
            "DMSans-Bold",
            "FragmentMono-Regular",
            "FragmentMono-Italic",
        ]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
