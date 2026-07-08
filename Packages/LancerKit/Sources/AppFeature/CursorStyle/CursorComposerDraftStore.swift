#if os(iOS)
import Foundation
import LancerCore

/// UserDefaults-backed store for per-thread composer draft text and contract fields.
///
/// Keys use the scheme `cursor.composer.draft.{threadID}` (text) and
/// `cursor.composer.contract.{threadID}` (JSON) so drafts are isolated per thread
/// and survive app restarts.
public final class CursorComposerDraftStore: @unchecked Sendable {
    public static let shared = CursorComposerDraftStore()

    public struct ContractDraft: Codable, Sendable, Equatable {
        public var goal: String
        public var doneCriteria: [String]
        public var validationCommands: [String]
        public var isExpanded: Bool

        public init(
            goal: String = "",
            doneCriteria: [String] = [],
            validationCommands: [String] = [],
            isExpanded: Bool = false
        ) {
            self.goal = goal
            self.doneCriteria = doneCriteria
            self.validationCommands = validationCommands
            self.isExpanded = isExpanded
        }
    }

    private init() {}

    public func saveDraft(threadID: String, text: String) {
        UserDefaults.standard.set(text, forKey: draftKey(threadID))
    }

    public func loadDraft(threadID: String) -> String {
        UserDefaults.standard.string(forKey: draftKey(threadID)) ?? ""
    }

    public func saveContractDraft(threadID: String, contract: ContractDraft) {
        guard let data = try? JSONEncoder().encode(contract) else { return }
        UserDefaults.standard.set(data, forKey: contractKey(threadID))
    }

    public func loadContractDraft(threadID: String) -> ContractDraft {
        guard let data = UserDefaults.standard.data(forKey: contractKey(threadID)),
              let draft = try? JSONDecoder().decode(ContractDraft.self, from: data)
        else { return ContractDraft() }
        return draft
    }

    public func clearDraft(threadID: String) {
        UserDefaults.standard.removeObject(forKey: draftKey(threadID))
        UserDefaults.standard.removeObject(forKey: contractKey(threadID))
    }

    private func draftKey(_ threadID: String) -> String {
        "cursor.composer.draft.\(threadID)"
    }

    private func contractKey(_ threadID: String) -> String {
        "cursor.composer.contract.\(threadID)"
    }
}
#endif
