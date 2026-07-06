#if os(iOS)
import Foundation

/// UserDefaults-backed store for per-thread composer draft text.
///
/// Keys use the scheme `cursor.composer.draft.{threadID}` so drafts are
/// isolated per thread and survive app restarts.
public final class CursorComposerDraftStore: @unchecked Sendable {
    public static let shared = CursorComposerDraftStore()

    private init() {}

    public func saveDraft(threadID: String, text: String) {
        UserDefaults.standard.set(text, forKey: draftKey(threadID))
    }

    public func loadDraft(threadID: String) -> String {
        UserDefaults.standard.string(forKey: draftKey(threadID)) ?? ""
    }

    public func clearDraft(threadID: String) {
        UserDefaults.standard.removeObject(forKey: draftKey(threadID))
    }

    private func draftKey(_ threadID: String) -> String {
        "cursor.composer.draft.\(threadID)"
    }
}
#endif
