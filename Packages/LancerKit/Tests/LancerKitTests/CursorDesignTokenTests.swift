import Testing
import SwiftUI
@testable import DesignSystem

#if os(iOS)
@Suite("Cursor design tokens")
struct CursorDesignTokenTests {
    @Test("green and red diff semantics match across light and dark")
    func diffSemanticParity() {
        let light = CursorColors.light
        let dark = CursorColors.dark
        #expect(light.successGreen == dark.successGreen)
        #expect(light.dangerRed == dark.dangerRed)
    }

    @Test("appearance resolves cursor scheme for explicit and system modes")
    func schemeResolution() {
        #expect(CursorScheme.resolve(.light, systemScheme: .dark) == .light)
        #expect(CursorScheme.resolve(.dark, systemScheme: .light) == .dark)
        #expect(CursorScheme.resolve(.system, systemScheme: .dark) == .dark)
        #expect(CursorScheme.resolve(.system, systemScheme: .light) == .light)
        #expect(CursorScheme.resolve(.dark) == .dark)
        #expect(CursorScheme.resolve(.light) == .light)
    }

    @Test("dark canvas uses near-black background and elevated sheet surface")
    func darkSurfaceRoles() {
        let dark = CursorColors.dark
        #expect(dark.background != dark.sheetBackground)
        #expect(dark.sheetBackground != dark.composerBackground)
    }

    @Test("orange accent is distinct from primary text in both schemes")
    func orangeAccentPreserved() {
        let light = CursorColors.light
        let dark = CursorColors.dark
        #expect(light.orangeAccent != light.primaryText)
        #expect(dark.orangeAccent != dark.primaryText)
        #expect(light.orangeAccent != dark.orangeAccent)
    }
}
#endif
