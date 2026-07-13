import Foundation
import Testing
@testable import AppFeature

@Suite("DispatchModelSelection")
struct DispatchModelSelectionTests {

    @Test("default is haiku when nothing is stored")
    func defaultIsHaiku() {
        let suite = "dev.lancer.tests.dispatchModel.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DispatchModelSelection.load(from: defaults)
        #expect(model == .haiku)
        #expect(model.slug == "haiku")
        #expect(DispatchModelSelection.default == .haiku)
    }

    @Test("slug mapping covers haiku / sonnet / opus")
    func slugMapping() {
        #expect(DispatchModelSelection.haiku.slug == "haiku")
        #expect(DispatchModelSelection.sonnet.slug == "sonnet")
        #expect(DispatchModelSelection.opus.slug == "opus")
        #expect(DispatchModelSelection.haiku.displayName == "Haiku")
        #expect(DispatchModelSelection.sonnet.displayName == "Sonnet")
        #expect(DispatchModelSelection.opus.displayName == "Opus")

        #expect(DispatchModelSelection.resolve(nil) == .haiku)
        #expect(DispatchModelSelection.resolve("") == .haiku)
        #expect(DispatchModelSelection.resolve("bogus") == .haiku)
        #expect(DispatchModelSelection.resolve("haiku") == .haiku)
        #expect(DispatchModelSelection.resolve("sonnet") == .sonnet)
        #expect(DispatchModelSelection.resolve("opus") == .opus)
        #expect(DispatchModelSelection.resolve("SONNET") == .sonnet)
    }

    @Test("persists selection under lancer.dispatch.model")
    func persistenceRoundTrip() {
        let suite = "dev.lancer.tests.dispatchModel.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.string(forKey: DispatchModelSelection.storageKey) == nil)

        DispatchModelSelection.save(.sonnet, to: defaults)
        #expect(defaults.string(forKey: "lancer.dispatch.model") == "sonnet")
        #expect(DispatchModelSelection.load(from: defaults) == .sonnet)

        DispatchModelSelection.save(.opus, to: defaults)
        #expect(DispatchModelSelection.load(from: defaults) == .opus)
        #expect(DispatchModelSelection.load(from: defaults).displayName == "Opus")

        DispatchModelSelection.save(.haiku, to: defaults)
        #expect(DispatchModelSelection.load(from: defaults) == .haiku)
    }

    @Test("follow-up prefers conversation model over current picker")
    func followUpModelPreference() {
        #expect(
            DispatchModelSelection.modelForFollowUp(
                conversationModel: "sonnet",
                selected: .haiku
            ) == "sonnet"
        )
        #expect(
            DispatchModelSelection.modelForFollowUp(
                conversationModel: nil,
                selected: .opus
            ) == "opus"
        )
        #expect(
            DispatchModelSelection.modelForFollowUp(
                conversationModel: "  ",
                selected: .haiku
            ) == "haiku"
        )
    }

    @Test("dispatchSlug is Claude-only")
    func dispatchSlugClaudeOnly() {
        #expect(
            DispatchModelSelection.dispatchSlug(for: .claudeCode, selected: .sonnet) == "sonnet"
        )
        #expect(DispatchModelSelection.dispatchSlug(for: .codex, selected: .haiku) == nil)
        #expect(DispatchModelSelection.dispatchSlug(for: .opencode, selected: .opus) == nil)
        #expect(DispatchModelSelection.dispatchSlug(for: .kimi, selected: .sonnet) == nil)
    }
}
