import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("AutonomyPreset coarse permission mode")
struct AutonomyPresetPermissionModeTests {

    @Test("bypass maps to allow; all other presets map to ask (fail-closed)")
    func presetToCoarseMode() {
        #expect(AutonomyPreset.bypass.coarsePermissionMode == .allow)
        #expect(AutonomyPreset.autoSafeWrites.coarsePermissionMode == .ask)
        #expect(AutonomyPreset.autoReads.coarsePermissionMode == .ask)
        #expect(AutonomyPreset.alwaysAsk.coarsePermissionMode == .ask)
        #expect(AutonomyPreset.agentDecides.coarsePermissionMode == .ask)
    }

    @Test("every AutonomyPreset maps to a valid coarse mode")
    func allCasesCovered() {
        for preset in AutonomyPreset.allCases {
            let mode = preset.coarsePermissionMode
            #expect(mode == .ask || mode == .allow)
            // No UI preset writes deny — that surface is Settings-only.
            #expect(mode != .deny)
        }
    }

    @Test("reflecting allow always yields bypass")
    func reflectingAllow() {
        #expect(AutonomyPreset.reflecting(coarseMode: .allow, preferred: .autoSafeWrites) == .bypass)
        #expect(AutonomyPreset.reflecting(coarseMode: .allow, preferred: .alwaysAsk) == .bypass)
        #expect(AutonomyPreset.reflecting(coarseMode: .allow, preferred: .bypass) == .bypass)
    }

    @Test("reflecting ask preserves preferred when it already maps to ask")
    func reflectingAskPreservesPreferred() {
        #expect(AutonomyPreset.reflecting(coarseMode: .ask, preferred: .alwaysAsk) == .alwaysAsk)
        #expect(AutonomyPreset.reflecting(coarseMode: .ask, preferred: .autoReads) == .autoReads)
        #expect(AutonomyPreset.reflecting(coarseMode: .ask, preferred: .autoSafeWrites) == .autoSafeWrites)
        #expect(AutonomyPreset.reflecting(coarseMode: .ask, preferred: .agentDecides) == .agentDecides)
    }

    @Test("reflecting ask replaces preferred bypass with balanced default")
    func reflectingAskReplacesBypass() {
        #expect(AutonomyPreset.reflecting(coarseMode: .ask, preferred: .bypass) == .autoSafeWrites)
    }

    @Test("reflecting deny fail-closes to alwaysAsk")
    func reflectingDeny() {
        #expect(AutonomyPreset.reflecting(coarseMode: .deny, preferred: .bypass) == .alwaysAsk)
        #expect(AutonomyPreset.reflecting(coarseMode: .deny, preferred: .autoSafeWrites) == .alwaysAsk)
    }

    @Test("AutonomySelection.coarsePermissionMode(forRaw:) uses resolve fail-closed")
    func selectionHelper() {
        #expect(AutonomySelection.coarsePermissionMode(forRaw: "bypass") == .allow)
        #expect(AutonomySelection.coarsePermissionMode(forRaw: "autoSafeWrites") == .ask)
        #expect(AutonomySelection.coarsePermissionMode(forRaw: nil) == .ask)
        #expect(AutonomySelection.coarsePermissionMode(forRaw: "bogus") == .ask)
    }

    @Test("PermissionModeScope: empty/~ are document default; repo cwd is per-chat")
    func permissionModeScope() {
        #expect(PermissionModeScope.isDocumentDefault(""))
        #expect(PermissionModeScope.isDocumentDefault("~"))
        #expect(PermissionModeScope.isDocumentDefault("  ~  "))
        #expect(!PermissionModeScope.isDocumentDefault("/tmp/repoA"))
        #expect(!PermissionModeScope.isDocumentDefault("~/Documents/app"))
    }
}
