import Foundation
import Testing
@testable import AppFeature

@Suite("DispatchVendorSelection")
struct DispatchVendorSelectionTests {

    @Test("default is Claude Code")
    func defaultIsClaude() {
        let suite = "DispatchVendorSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DispatchVendorSelection.load(from: defaults) == .claudeCode)
        #expect(DispatchVendorSelection.default == .claudeCode)
    }

    @Test("wire ids and display names")
    func wireAndDisplay() {
        #expect(DispatchVendorSelection.claudeCode.wireID == "claudeCode")
        #expect(DispatchVendorSelection.codex.wireID == "codex")
        #expect(DispatchVendorSelection.opencode.wireID == "opencode")
        #expect(DispatchVendorSelection.kimi.wireID == "kimi")
        #expect(DispatchVendorSelection.cursor.wireID == "cursor")
        #expect(DispatchVendorSelection.claudeCode.displayName == "Claude Code")
        #expect(DispatchVendorSelection.codex.displayName == "Codex")
        #expect(DispatchVendorSelection.opencode.displayName == "OpenCode")
        #expect(DispatchVendorSelection.kimi.displayName == "Kimi")
        #expect(DispatchVendorSelection.cursor.displayName == "Cursor")
        #expect(DispatchVendorSelection.claudeCode.usesClaudeModelPicker)
        #expect(!DispatchVendorSelection.codex.usesClaudeModelPicker)
        #expect(!DispatchVendorSelection.opencode.usesClaudeModelPicker)
        #expect(!DispatchVendorSelection.cursor.usesClaudeModelPicker)
    }

    @Test("resolve + save round-trip")
    func resolveAndSave() {
        #expect(DispatchVendorSelection.resolve(nil) == .claudeCode)
        #expect(DispatchVendorSelection.resolve("") == .claudeCode)
        #expect(DispatchVendorSelection.resolve("bogus") == .claudeCode)
        #expect(DispatchVendorSelection.resolve("codex") == .codex)
        #expect(DispatchVendorSelection.resolve("opencode") == .opencode)

        let suite = "DispatchVendorSelectionTests.save.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DispatchVendorSelection.save(.codex, to: defaults)
        #expect(DispatchVendorSelection.load(from: defaults) == .codex)
        DispatchVendorSelection.save(.opencode, to: defaults)
        #expect(DispatchVendorSelection.load(from: defaults) == .opencode)
    }

    @Test("available filters to installed, keeps selection")
    func availableFilter() {
        let all = DispatchVendorSelection.available(installed: nil, keeping: .claudeCode)
        #expect(all == Array(DispatchVendorSelection.allCases))

        let filtered = DispatchVendorSelection.available(
            installed: ["claudeCode", "opencode"],
            keeping: .claudeCode
        )
        #expect(filtered == [.claudeCode, .opencode])

        let keepMissing = DispatchVendorSelection.available(
            installed: ["claudeCode"],
            keeping: .codex
        )
        #expect(keepMissing.first == .codex)
        #expect(keepMissing.contains(.claudeCode))
    }
}
