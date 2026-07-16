import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("AutonomySelection")
struct AutonomySelectionTests {

    @Test("default matches onboarding Balanced → autoSafeWrites")
    func defaultMatchesBalanced() {
        #expect(AutonomySelection.default == .autoSafeWrites)
    }

    @Test("resolve falls back for nil empty and unknown")
    func resolveFallbacks() {
        #expect(AutonomySelection.resolve(nil) == .autoSafeWrites)
        #expect(AutonomySelection.resolve("") == .autoSafeWrites)
        #expect(AutonomySelection.resolve("bogus") == .autoSafeWrites)
        #expect(AutonomySelection.resolve("alwaysAsk") == .alwaysAsk)
        #expect(AutonomySelection.resolve("bypass") == .bypass)
    }

    @Test("persists under lancer.autonomy.preset")
    func persistenceRoundTrip() {
        let suite = "dev.lancer.tests.autonomy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AutonomySelection.load(from: defaults) == .autoSafeWrites)

        AutonomySelection.save(.alwaysAsk, to: defaults)
        #expect(defaults.string(forKey: AutonomySelection.storageKey) == "alwaysAsk")
        #expect(AutonomySelection.load(from: defaults) == .alwaysAsk)

        AutonomySelection.save(.agentDecides, to: defaults)
        #expect(AutonomySelection.load(from: defaults) == .agentDecides)
    }
}
