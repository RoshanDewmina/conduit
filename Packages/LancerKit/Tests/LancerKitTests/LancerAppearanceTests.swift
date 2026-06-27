import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Lancer appearance preference")
struct LancerAppearanceTests {
    @Test("explicit preferences resolve to their matching color scheme")
    func explicitPreferenceResolution() {
        #expect(LancerAppearance.light.preferredColorScheme == .light)
        #expect(LancerAppearance.dark.preferredColorScheme == .dark)
    }

    @Test("system leaves the system color scheme in control")
    func systemPreferenceResolution() {
        #expect(LancerAppearance.system.preferredColorScheme == nil)
        #expect(LancerAppearance(rawValue: "invalid") == nil)
    }
}
