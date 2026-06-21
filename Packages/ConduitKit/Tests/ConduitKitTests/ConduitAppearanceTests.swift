import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Conduit appearance preference")
struct ConduitAppearanceTests {
    @Test("explicit preferences resolve to their matching color scheme")
    func explicitPreferenceResolution() {
        #expect(ConduitAppearance.light.preferredColorScheme == .light)
        #expect(ConduitAppearance.dark.preferredColorScheme == .dark)
    }

    @Test("system leaves the system color scheme in control")
    func systemPreferenceResolution() {
        #expect(ConduitAppearance.system.preferredColorScheme == nil)
        #expect(ConduitAppearance(rawValue: "invalid") == nil)
    }
}
